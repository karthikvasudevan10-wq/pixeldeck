import CloudKit
import SwiftUI
import WidgetKit

// Home Screen widget: the most-hearted Community posts of all time, a new one every hour.
// It reads Pixel Deck's public CloudKit database directly (no server, no account needed to read),
// using the small preview image each post carries (`thumb`). Tapping opens the post in the app.

private let containerID = "iCloud.karthikvasudevan.pixeldeck"
/// How many top posts to rotate through, and how often the list is refreshed.
private let topCount = 24
private let refreshHours = 6
/// Posts reported by this many people are hidden for everyone (as in the app).
private let hideAfterReports = 3

struct TopPost: Identifiable {
    let id: String
    let title: String
    let author: String
    let hearts: Int
    let image: UIImage?
}

struct TopPostsEntry: TimelineEntry {
    let date: Date
    /// The posts to show, starting with this hour's.
    let posts: [TopPost]
}

struct TopPostsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopPostsEntry {
        TopPostsEntry(date: .now, posts: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TopPostsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(TopPostsEntry(date: .now, posts: await Self.fetchTop())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopPostsEntry>) -> Void) {
        Task {
            let top = await Self.fetchTop()
            let now = Date()
            // One entry per hour, each starting one post further along the list.
            let hourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
            let entries: [TopPostsEntry] = top.isEmpty
                ? [TopPostsEntry(date: now, posts: [])]
                : (0..<refreshHours).map { h in
                    let start = (Self.hourIndex(hourStart) + h) % top.count
                    let rotated = Array(top[start...] + top[..<start])
                    return TopPostsEntry(date: h == 0 ? now : hourStart.addingTimeInterval(Double(h) * 3600), posts: rotated)
                }
            let next = hourStart.addingTimeInterval(Double(refreshHours) * 3600)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    /// Counts hours since a fixed date, so the rotation carries on across refreshes.
    private static func hourIndex(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 3600)
    }

    /// The most-hearted posts, best first, skipping ones hidden by reports. Nothing until the app
    /// has confirmed (with the age-range check) that Community is allowed on this device.
    static func fetchTop() async -> [TopPost] {
        guard UserDefaults(suiteName: "group.karthikvasudevan.pixeldeck")?.bool(forKey: "communityAllowed") == true else { return [] }
        let db = CKContainer(identifier: containerID).publicCloudDatabase
        let query = CKQuery(recordType: "HeartTally", predicate: NSPredicate(format: "count > 0"))
        query.sortDescriptors = [NSSortDescriptor(key: "count", ascending: false)]
        let tallies = ((try? await db.records(matching: query, desiredKeys: ["post", "count"], resultsLimit: topCount))?
            .matchResults.compactMap { try? $0.1.get() }) ?? []
        var ids = tallies.compactMap { ($0["post"] as? CKRecord.Reference)?.recordID }
        // Not many hearts yet (a new community): fill up with the newest posts.
        if ids.count < topCount {
            let newest = CKQuery(recordType: "Post", predicate: NSPredicate(value: true))
            newest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let recent = ((try? await db.records(matching: newest, desiredKeys: [], resultsLimit: topCount))?
                .matchResults.map(\.0)) ?? []
            let have = Set(ids)
            ids += recent.filter { !have.contains($0) }.prefix(topCount - ids.count)
        }
        guard !ids.isEmpty else { return [] }
        let hearts = Dictionary(tallies.compactMap { t -> (String, Int)? in
            guard let id = (t["post"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
            return (id, (t["count"] as? Int) ?? 0)
        }, uniquingKeysWith: max)
        let posts = (try? await db.records(for: ids, desiredKeys: ["title", "author", "thumb"])) ?? [:]
        let hidden = await reportedPosts(ids, db: db)
        return ids.compactMap { id -> TopPost? in
            guard !hidden.contains(id.recordName), case .success(let r)? = posts[id],
                  let asset = r["thumb"] as? CKAsset, let url = asset.fileURL,
                  let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return TopPost(id: id.recordName, title: (r["title"] as? String) ?? "", author: (r["author"] as? String) ?? "",
                           hearts: hearts[id.recordName] ?? 0, image: image)
        }
    }

    private static func reportedPosts(_ ids: [CKRecord.ID], db: CKDatabase) async -> Set<String> {
        let refs = ids.map { CKRecord.Reference(recordID: $0, action: .none) }
        let query = CKQuery(recordType: "Report", predicate: NSPredicate(format: "post IN %@", refs))
        guard let page = try? await db.records(matching: query, desiredKeys: ["post"], resultsLimit: 400) else { return [] }
        var reporters: [String: Set<String>] = [:]
        for case .success(let r) in page.matchResults.map(\.1) {
            guard let post = (r["post"] as? CKRecord.Reference)?.recordID.recordName,
                  let who = r.creatorUserRecordID?.recordName else { continue }
            reporters[post, default: []].insert(who)
        }
        return Set(reporters.filter { $0.value.count >= hideAfterReports }.keys)
    }
}

// MARK: Views

private enum WidgetColors {
    static let ink = Color(red: 0x12 / 255, green: 0x0E / 255, blue: 0x1F / 255)
    static let surface = Color(red: 0x1E / 255, green: 0x18 / 255, blue: 0x33 / 255)
    static let pink = Color(red: 1, green: 0x5C / 255, blue: 0x8A / 255)
    static let cream = Color(red: 1, green: 0xF6 / 255, blue: 0xE0 / 255)
    static let muted = Color(red: 0xA8 / 255, green: 0x9C / 255, blue: 0xC8 / 255)
}

private func postURL(_ post: TopPost) -> URL? { URL(string: "pixeldeck://community/\(post.id)") }

struct TopPostsWidgetView: View {
    let entry: TopPostsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.posts.isEmpty {
                empty
            } else {
                switch family {
                case .systemLarge: large
                case .systemMedium: medium(entry.posts[0])
                default: small(entry.posts[0])
                }
            }
        }
        .containerBackground(WidgetColors.ink, for: .widget)
    }

    private func art(_ post: TopPost) -> some View {
        Group {
            if let image = post.image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func hearts(_ count: Int) -> some View {
        if count > 0 {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold))
            Text(verbatim: "\(count)").font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(WidgetColors.pink)
        }
    }

    private func small(_ post: TopPost) -> some View {
        VStack(spacing: 6) {
            art(post).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(post.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetColors.cream).lineLimit(1)
                Spacer(minLength: 2)
                hearts(post.hearts)
            }
        }
        .widgetURL(postURL(post))
    }

    private func medium(_ post: TopPost) -> some View {
        HStack(spacing: 14) {
            art(post).frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.hearts > 0 ? "MOST HEARTED" : "NEW ON PIXEL DECK").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(WidgetColors.pink)
                Text(post.title).font(.system(size: 16, weight: .bold)).foregroundStyle(WidgetColors.cream).lineLimit(2)
                Text("by \(post.author)").font(.system(size: 12)).foregroundStyle(WidgetColors.muted).lineLimit(1)
                Spacer(minLength: 0)
                hearts(post.hearts)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(postURL(post))
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMUNITY FAVOURITES").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(WidgetColors.pink)
            let four = Array(entry.posts.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(four) { post in
                    Link(destination: postURL(post) ?? URL(string: "pixeldeck://community")!) {
                        VStack(spacing: 4) {
                            art(post).frame(maxWidth: .infinity, maxHeight: .infinity)
                            HStack {
                                Text(post.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetColors.cream).lineLimit(1)
                                Spacer(minLength: 2)
                                hearts(post.hearts)
                            }
                        }
                        .padding(6)
                        .background(WidgetColors.surface)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart").font(.system(size: 26, weight: .bold)).foregroundStyle(WidgetColors.pink)
            Text("Open Community in Pixel Deck to see favourites here").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetColors.cream).multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "pixeldeck://community"))
    }
}

struct TopPostsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TopPosts", provider: TopPostsProvider()) { entry in
            TopPostsWidgetView(entry: entry)
        }
        .configurationDisplayName("Community favourites")
        .description("The most-hearted pixel art on Pixel Deck, then the newest. A new one every hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PixelDeckWidgets: WidgetBundle {
    var body: some Widget {
        TopPostsWidget()
    }
}
