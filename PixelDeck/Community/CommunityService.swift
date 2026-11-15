import CloudKit
import Foundation
import Observation

/// A shared sprite in the Community feed.
struct CommunityPost: Identifiable, Equatable {
    let id: String               // CloudKit record name
    let title: String
    let author: String           // the poster's nickname
    let authorID: String?        // CloudKit user record name (for blocking)
    let created: Date
    let art: PostArt
    let isMine: Bool
    /// Built once, for the looping previews.
    let frames: [Frame]

    static func == (l: CommunityPost, r: CommunityPost) -> Bool { l.id == r.id && l.isMine == r.isMine }
}

/// Community: sharing sprites publicly through CloudKit's public database. Apple hosts it; there's
/// no server. Anyone can browse (no iCloud account needed); posting, reporting and deleting need
/// an iCloud account.
///
/// Moderation without pre-approval (App Store guideline 1.2):
/// - titles and nicknames are filtered (`ContentFilter`), on posting and again when shown;
/// - anyone can report a post; three reports from different people hide it for everyone;
/// - anyone can block a poster (their posts disappear for them at once);
/// - posters can delete their own posts;
/// - the developer removes posts in CloudKit Console, or in the app with a moderator account
///   (`AppConfig.communityModeratorIDs`).
///
/// Record types (see AppStore/SUBMISSION_CHECKLIST.md for the indexes and security roles):
/// - `Post`: title, author, width, height, frames, fps (all plain fields) and art (an asset: the
///   PostArt JSON).
/// - `Report`: post (a reference to the Post), reason. One per person per post.
@MainActor @Observable
final class CommunityService {
    enum Feed: Hashable { case newest, mine }
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var posts: [CommunityPost] = []
    private(set) var phase: Phase = .idle
    private(set) var canLoadMore = false
    private(set) var feed: Feed = .newest
    /// This person's CloudKit user record name, once known (needs an iCloud account).
    private(set) var myUserID: String?
    private(set) var blockedAuthors: Set<String>
    private(set) var reportedByMe: Set<String>

    var isConfigured: Bool { container != nil }
    var isModerator: Bool { myUserID.map { AppConfig.communityModeratorIDs.contains($0) } ?? false }

    @ObservationIgnored private let container: CKContainer?
    @ObservationIgnored private var cursor: CKQueryOperation.Cursor?
    @ObservationIgnored private var loadToken = 0

    private static let blockedKey = "communityBlockedAuthors"
    private static let reportedKey = "communityReportedPosts"
    private static let pageSize = 24

    init() {
        // CKContainer.default() crashes when the app lacks the CloudKit entitlement, so the
        // container is named explicitly and Community stays off until it's set (AppConfig).
        container = AppConfig.cloudKitContainerID.map { CKContainer(identifier: $0) }
        let d = UserDefaults.standard
        blockedAuthors = Set(d.stringArray(forKey: Self.blockedKey) ?? [])
        reportedByMe = Set(d.stringArray(forKey: Self.reportedKey) ?? [])
    }

    private var db: CKDatabase? { container?.publicCloudDatabase }

    // MARK: Feed

    func show(_ feed: Feed) async {
        self.feed = feed
        await refresh()
    }

    func refresh() async {
        cursor = nil
        posts = []
        canLoadMore = false
        await loadPage()
    }

    func loadMore() async {
        guard canLoadMore, phase != .loading else { return }
        await loadPage()
    }

    private func loadPage() async {
        guard let db else { phase = .failed(String(localized: "Community isn't set up in this build.")); return }
        loadToken += 1
        let token = loadToken
        phase = .loading
        do {
            await identify()
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await db.records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
            } else {
                let predicate: NSPredicate
                switch feed {
                case .newest:
                    predicate = NSPredicate(value: true)
                case .mine:
                    guard let me = myUserID else {
                        phase = .failed(String(localized: "Sign in to iCloud to see your posts."))
                        return
                    }
                    predicate = NSPredicate(format: "creatorUserRecordID == %@", CKRecord.ID(recordName: me))
                }
                let query = CKQuery(recordType: "Post", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                page = try await db.records(matching: query, resultsLimit: Self.pageSize)
            }
            guard token == loadToken else { return }          // a newer load started
            let records = page.matchResults.compactMap { try? $0.1.get() }
            cursor = page.queryCursor
            canLoadMore = page.queryCursor != nil
            let reporters = feed == .mine ? [:] : await reports(for: records.map(\.recordID))
            guard token == loadToken else { return }
            let known = Set(posts.map(\.id))
            for r in records {
                guard let post = makePost(r), !known.contains(post.id) else { continue }
                let visible = post.isMine || CommunityModeration.isVisible(
                    postID: post.id, authorID: post.authorID, title: post.title, author: post.author,
                    reporters: reporters[post.id] ?? [], blockedAuthors: blockedAuthors, reportedByMe: reportedByMe)
                if visible { posts.append(post) }
            }
            phase = .loaded
        } catch {
            guard token == loadToken else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    /// Who reported each of these posts (record name → reporter ids).
    private func reports(for ids: [CKRecord.ID]) async -> [String: Set<String>] {
        guard let db, !ids.isEmpty else { return [:] }
        let refs = ids.map { CKRecord.Reference(recordID: $0, action: .none) }
        let query = CKQuery(recordType: "Report", predicate: NSPredicate(format: "post IN %@", refs))
        guard let page = try? await db.records(matching: query, desiredKeys: ["post"], resultsLimit: 400) else { return [:] }
        var out: [String: Set<String>] = [:]
        for case .success(let r) in page.matchResults.map(\.1) {
            guard let post = (r["post"] as? CKRecord.Reference)?.recordID.recordName,
                  let who = r.creatorUserRecordID?.recordName else { continue }
            out[post, default: []].insert(who)
        }
        return out
    }

    private func makePost(_ r: CKRecord) -> CommunityPost? {
        guard let asset = r["art"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url), let art = PostArt.decode(data) else { return nil }
        let creator = r.creatorUserRecordID?.recordName
        // CloudKit names the current user's own records "__defaultOwner__".
        let mine = creator == CKCurrentUserDefaultName || (creator != nil && creator == myUserID)
        return CommunityPost(
            id: r.recordID.recordName,
            title: (r["title"] as? String) ?? "",
            author: (r["author"] as? String) ?? "",
            authorID: mine ? myUserID : creator,
            created: r.creationDate ?? Date(),
            art: art, isMine: mine,
            frames: art.frames.map { Frame(grid: $0) })
    }

    /// Looks up this person's CloudKit id once (nil without an iCloud account).
    private func identify() async {
        guard myUserID == nil, let container,
              (try? await container.accountStatus()) == .available,
              let id = try? await container.userRecordID() else { return }
        myUserID = id.recordName
    }

    // MARK: Posting

    enum PostError: LocalizedError {
        case notSetUp, blank, tooBig, notAllowed
        var errorDescription: String? {
            switch self {
            case .notSetUp: String(localized: "Community isn't set up in this build.")
            case .blank: String(localized: "Draw something first: this sprite is empty.")
            case .tooBig: String(localized: "This sprite is too big to share. Try fewer frames.")
            case .notAllowed: String(localized: "That title or nickname isn't allowed. Please choose another.")
            }
        }
    }

    /// Shares a sprite. Throws a readable error (no iCloud account, offline, too big, filtered).
    func publish(_ project: SpriteProject, title rawTitle: String, nickname rawNick: String) async throws {
        guard let db, let container else { throw PostError.notSetUp }
        let title = ContentFilter.tidy(rawTitle, maxLength: ContentFilter.maxTitleLength)
        let nick = ContentFilter.tidy(rawNick, maxLength: ContentFilter.nicknameLength.upperBound)
        guard !title.isEmpty, ContentFilter.nicknameLength.contains(nick.count),
              ContentFilter.isAcceptable(title), ContentFilter.isAcceptable(nick) else { throw PostError.notAllowed }
        guard let art = PostArt(project: project) else { throw PostError.blank }
        let data = try art.encoded()
        guard data.count <= PostArt.maxBytes else { throw PostError.tooBig }
        do {
            guard try await container.accountStatus() == .available else {
                throw CKError(.notAuthenticated)
            }
            await identify()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let record = CKRecord(recordType: "Post")
            record["title"] = title
            record["author"] = nick
            record["width"] = art.width
            record["height"] = art.height
            record["frames"] = art.frames.count
            record["fps"] = art.fps
            record["art"] = CKAsset(fileURL: url)
            let saved = try await db.save(record)
            if let post = makePost(saved) {
                posts.removeAll { $0.id == post.id }
                posts.insert(post, at: 0)
            }
        } catch let e as PostError {
            throw e
        } catch {
            throw NSError(domain: "Community", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.message(for: error)])
        }
    }

    // MARK: Moderation

    /// Reports a post: it's hidden for this person at once, and for everyone after enough reports.
    func report(_ post: CommunityPost, reason: String) async {
        reportedByMe.insert(post.id)
        UserDefaults.standard.set(Array(reportedByMe), forKey: Self.reportedKey)
        posts.removeAll { $0.id == post.id }
        guard let db else { return }
        await identify()
        // One report per person per post: the record name makes repeats a no-op.
        let name = "report-\(post.id)-\(myUserID ?? UUID().uuidString)"
        let r = CKRecord(recordType: "Report", recordID: CKRecord.ID(recordName: String(name.prefix(255))))
        r["post"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: post.id), action: .none)
        r["reason"] = reason
        _ = try? await db.save(r)
    }

    /// Hides everything this person posts, for this user.
    func block(_ post: CommunityPost) {
        guard let author = post.authorID else { return }
        blockedAuthors.insert(author)
        UserDefaults.standard.set(Array(blockedAuthors), forKey: Self.blockedKey)
        posts.removeAll { $0.authorID == author }
    }

    func unblockAll() {
        blockedAuthors = []
        UserDefaults.standard.removeObject(forKey: Self.blockedKey)
    }

    /// Deletes a post: your own, or any post for a moderator account.
    func delete(_ post: CommunityPost) async throws {
        guard let db else { throw PostError.notSetUp }
        do {
            _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: post.id))
            posts.removeAll { $0.id == post.id }
        } catch {
            throw NSError(domain: "Community", code: 2, userInfo: [NSLocalizedDescriptionKey: Self.message(for: error)])
        }
    }

    /// For the developer: the id to put in `AppConfig.communityModeratorIDs`.
    func myCommunityID() async -> String? {
        await identify()
        return myUserID
    }

    // MARK: Errors

    static func message(for error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud in the Settings app to post.")
        case .networkUnavailable, .networkFailure:
            return String(localized: "You're offline. Check your connection and try again.")
        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return String(localized: "Community is busy right now. Try again in a minute.")
        case .quotaExceeded:
            return String(localized: "Community is full right now. Try again later.")
        case .permissionFailure:
            return String(localized: "You can't do that to this post.")
        case .unknownItem:
            return String(localized: "Community isn't ready yet. Please try again later.")
        default:
            return ck.localizedDescription
        }
    }
}
