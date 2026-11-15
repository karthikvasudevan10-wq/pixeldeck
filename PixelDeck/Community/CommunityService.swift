import CloudKit
import UIKit
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
    /// Hearts from everyone, and whether this person gave one.
    var hearts = 0
    var heartedByMe = false

    static func == (l: CommunityPost, r: CommunityPost) -> Bool {
        l.id == r.id && l.isMine == r.isMine && l.hearts == r.hearts && l.heartedByMe == r.heartedByMe
    }
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
/// - `Heart`: post (reference). One per person per post (record name `heart-<post>-<user>`),
///   so a heart can't be counted twice. Only its creator can delete it.
/// - `HeartTally`: post (reference), count. One per post (record name `tally-<post>`), kept up
///   to date by the app when people heart and unheart (CloudKit can't count on the server). It's
///   what Popular and the Home Screen widget sort by, so it needs the "Authenticated: Write" role.
@MainActor @Observable
final class CommunityService {
    enum Feed: Hashable { case newest, popular, mine }
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var posts: [CommunityPost] = []
    private(set) var phase: Phase = .idle
    private(set) var canLoadMore = false
    private(set) var feed: Feed = .newest
    /// This person's CloudKit user record name, once known (needs an iCloud account).
    private(set) var myUserID: String?
    private(set) var blockedAuthors: Set<String>
    private(set) var reportedByMe: Set<String>

    var isConfigured: Bool { AppConfig.cloudKitContainerID != nil }
    var isModerator: Bool { myUserID.map { AppConfig.communityModeratorIDs.contains($0) } ?? false }

    /// Made on first use (opening Community), not at launch, so a build that's missing the CloudKit
    /// capability can still start.
    @ObservationIgnored private lazy var container: CKContainer? = AppConfig.cloudKitContainerID.map { CKContainer(identifier: $0) }
    @ObservationIgnored private var cursor: CKQueryOperation.Cursor?
    @ObservationIgnored private var loadToken = 0

    private static let blockedKey = "communityBlockedAuthors"
    private static let reportedKey = "communityReportedPosts"
    private static let pageSize = 24

    init() {
        // CKContainer.default() crashes when the app lacks the CloudKit entitlement, so the
        // container is named explicitly (AppConfig) and created lazily.
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
            if feed == .popular {
                try await loadPopularPage(db, token: token)
                return
            }
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await db.records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
            } else {
                let predicate: NSPredicate
                switch feed {
                case .newest, .popular:
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
            await append(records, token: token)
            guard token == loadToken else { return }
            phase = .loaded
        } catch {
            guard token == loadToken else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    /// Popular: the most-hearted posts of all time, from the tallies.
    private func loadPopularPage(_ db: CKDatabase, token: Int) async throws {
        let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
        if let cursor {
            page = try await db.records(continuingMatchFrom: cursor, resultsLimit: Self.pageSize)
        } else {
            let query = CKQuery(recordType: "HeartTally", predicate: NSPredicate(format: "count > 0"))
            query.sortDescriptors = [NSSortDescriptor(key: "count", ascending: false)]
            page = try await db.records(matching: query, resultsLimit: Self.pageSize)
        }
        guard token == loadToken else { return }
        cursor = page.queryCursor
        canLoadMore = page.queryCursor != nil
        let ids = page.matchResults.compactMap { try? $0.1.get() }
            .compactMap { ($0["post"] as? CKRecord.Reference)?.recordID }
        let fetched = (try? await db.records(for: ids)) ?? [:]
        let records = ids.compactMap { try? fetched[$0]?.get() }   // in tally order
        await append(records, token: token)
        guard token == loadToken else { return }
        phase = .loaded
    }

    /// Adds posts that pass moderation, then fills in their hearts.
    private func append(_ records: [CKRecord], token: Int) async {
        let reporters = feed == .mine ? [:] : await reports(for: records.map(\.recordID))
        guard token == loadToken else { return }
        var known = Set(posts.map(\.id))
        var added: [String] = []
        for r in records {
            guard let post = makePost(r), !known.contains(post.id) else { continue }
            let visible = post.isMine || CommunityModeration.isVisible(
                postID: post.id, authorID: post.authorID, title: post.title, author: post.author,
                reporters: reporters[post.id] ?? [], blockedAuthors: blockedAuthors, reportedByMe: reportedByMe)
            if visible {
                posts.append(post)
                known.insert(post.id)
                added.append(post.id)
            }
        }
        await loadHearts(for: added)
    }

    // MARK: Hearts

    private static func tallyID(_ post: String) -> CKRecord.ID { CKRecord.ID(recordName: "tally-\(post)") }
    private func heartID(_ post: String, by me: String) -> CKRecord.ID {
        CKRecord.ID(recordName: String("heart-\(post)-\(me)".prefix(255)))
    }

    /// Fetches the heart counts, and which of these posts this person hearted.
    private func loadHearts(for ids: [String]) async {
        guard let db, !ids.isEmpty else { return }
        let tallies = (try? await db.records(for: ids.map(Self.tallyID), desiredKeys: ["count"])) ?? [:]
        var mine: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        if let me = myUserID {
            mine = (try? await db.records(for: ids.map { heartID($0, by: me) }, desiredKeys: [])) ?? [:]
        }
        for id in ids {
            guard let i = posts.firstIndex(where: { $0.id == id }) else { continue }
            if case .success(let t)? = tallies[Self.tallyID(id)] { posts[i].hearts = max(0, (t["count"] as? Int) ?? 0) }
            if let me = myUserID, case .success? = mine[heartID(id, by: me)] { posts[i].heartedByMe = true }
        }
    }

    /// Hearts or unhearts someone else's post. The change shows at once; if CloudKit refuses
    /// (offline, no iCloud account), it's undone and the reason returned.
    @discardableResult
    func toggleHeart(_ post: CommunityPost) async -> String? {
        guard let db, !post.isMine else { return nil }
        await identify()
        guard let me = myUserID else { return String(localized: "Sign in to iCloud to give hearts.") }
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return nil }
        let adding = !posts[i].heartedByMe
        posts[i].heartedByMe = adding
        posts[i].hearts = max(0, posts[i].hearts + (adding ? 1 : -1))
        do {
            let hid = heartID(post.id, by: me)
            if adding {
                let heart = CKRecord(recordType: "Heart", recordID: hid)
                heart["post"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: post.id), action: .deleteSelf)
                do {
                    _ = try await db.save(heart)
                } catch let e as CKError where e.code == .serverRecordChanged {
                    return nil                                // already hearted on another device
                }
            } else {
                _ = try await db.deleteRecord(withID: hid)
            }
            try await adjustTally(post.id, by: adding ? 1 : -1, db: db)
            return nil
        } catch {
            if let j = posts.firstIndex(where: { $0.id == post.id }) {
                posts[j].heartedByMe = !adding
                posts[j].hearts = max(0, posts[j].hearts + (adding ? -1 : 1))
            }
            return Self.message(for: error)
        }
    }

    /// Adds `delta` to a post's tally, retrying if someone else changed it at the same moment.
    private func adjustTally(_ post: String, by delta: Int, db: CKDatabase) async throws {
        let id = Self.tallyID(post)
        for _ in 0..<5 {
            let record: CKRecord
            do {
                record = try await db.record(for: id)
            } catch let e as CKError where e.code == .unknownItem {
                record = CKRecord(recordType: "HeartTally", recordID: id)
                record["post"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: post), action: .deleteSelf)
            }
            record["count"] = max(0, ((record["count"] as? Int) ?? 0) + delta)
            do {
                let result = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                try result.saveResults[id]?.get()
                return
            } catch let e as CKError where e.code == .serverRecordChanged || e.code == .partialFailure {
                continue                                      // someone else hearted at the same time
            }
        }
    }

    /// One post, for opening it from the Home Screen widget.
    func fetchPost(id: String) async -> CommunityPost? {
        if let p = posts.first(where: { $0.id == id }) { return p }
        guard let db, let r = try? await db.record(for: CKRecord.ID(recordName: id)) else { return nil }
        await identify()
        guard var post = makePost(r) else { return nil }
        let reporters = await reports(for: [r.recordID])
        guard post.isMine || CommunityModeration.isVisible(
            postID: post.id, authorID: post.authorID, title: post.title, author: post.author,
            reporters: reporters[post.id] ?? [], blockedAuthors: blockedAuthors, reportedByMe: reportedByMe) else { return nil }
        if let t = try? await db.record(for: Self.tallyID(id)) { post.hearts = (t["count"] as? Int) ?? 0 }
        if let me = myUserID, (try? await db.record(for: heartID(id, by: me))) != nil { post.heartedByMe = true }
        return post
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
            // A small PNG of the first frame, for the Home Screen widget.
            let thumbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            defer { try? FileManager.default.removeItem(at: thumbURL) }
            if let thumb = Self.thumbnailPNG(art) {
                try thumb.write(to: thumbURL)
                record["thumb"] = CKAsset(fileURL: thumbURL)
            }
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

    /// The first frame at a whole-number scale, about 256 px on its long side, with crisp pixels.
    static func thumbnailPNG(_ art: PostArt) -> Data? {
        guard let first = art.frames.first else { return nil }
        let scale = max(1, 256 / max(art.width, art.height))
        guard let image = PixelRenderer.cgImage(first, scale: scale) else { return nil }
        return UIImage(cgImage: image).pngData()
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
