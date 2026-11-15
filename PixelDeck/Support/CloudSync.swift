import Foundation
import Observation

/// Keeps the sprites (and their tracing and reference pictures) in the app's private iCloud
/// container, so they appear on every device signed in to the same Apple Account.
///
/// iCloud does the syncing: the store just keeps its files in the container instead of on the
/// device, writes through NSFileCoordinator, and an NSMetadataQuery reports when other devices
/// change something. Files are hidden from the Files app. With iCloud off, unavailable or signed
/// out, everything works the same on the device alone.
///
/// Needs the iCloud capability with "iCloud Documents" ticked (see README). Without it, the
/// container is nil and the app stays local.
@MainActor @Observable
final class CloudSync {
    enum Status: Equatable {
        /// Turned off in Settings.
        case off
        case checking
        /// No iCloud account on this device, iCloud Drive is off for the app, or the build lacks
        /// the iCloud capability.
        case unavailable
        /// Uploading or downloading.
        case syncing
        case upToDate
    }

    private(set) var status: Status = .checking
    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            Task { await apply() }
        }
    }

    nonisolated static let enabledKey = "iCloudSyncEnabled"
    private nonisolated static let lastCloudFolderKey = "iCloudSpritesFolder"

    private let store: ProjectStore
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var mergeScheduled = false
    @ObservationIgnored private var started = false

    init(store: ProjectStore) {
        self.store = store
        self.enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        // Plain function references (not closures made here), so they're not tied to the main
        // actor: the store calls them on its background queue.
        store.writeFile = CloudFiles.write
        store.removeFile = CloudFiles.remove
    }

    /// Where to open the store at launch: the iCloud folder used last time (so the gallery shows
    /// straight away, before iCloud has been checked), or nil for the device folder.
    nonisolated static func launchDirectory() -> URL? {
        let d = UserDefaults.standard
        guard d.object(forKey: enabledKey) as? Bool ?? true,
              let path = d.string(forKey: lastCloudFolderKey) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        ImageStore.root = url.deletingLastPathComponent()
        return url
    }

    func start() {
        guard !started else { return }
        started = true
        let account = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.apply() } }
        }
        observers.append(account)
        Task { await apply() }
    }

    /// Picks the folder (iCloud or device) for the current setting and account, moving work across.
    func apply() async {
        guard enabled else {
            stopWatching()
            moveToDevice()
            status = .off
            return
        }
        status = .checking
        // Can be slow the first time, so not on the main thread (Apple's advice).
        let container = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        guard let container, enabled else {
            stopWatching()
            moveToDevice()
            status = enabled ? .unavailable : .off
            return
        }
        let sprites = container.appendingPathComponent("Sprites", isDirectory: true)
        let wasLocal = store.directory.standardizedFileURL == ProjectStore.localDirectory.standardizedFileURL
        // Work made on this device moves into iCloud (and leaves the device folder, so an old
        // local copy can't reappear after it's been deleted on another device).
        store.relocate(to: sprites, removingOld: wasLocal)
        ImageStore.move(to: container, removingOld: wasLocal)
        UserDefaults.standard.set(sprites.path, forKey: Self.lastCloudFolderKey)
        startWatching()
    }

    /// Back to the device folder, keeping a copy of everything (the iCloud copies stay in iCloud).
    private func moveToDevice() {
        UserDefaults.standard.removeObject(forKey: Self.lastCloudFolderKey)
        guard store.directory.standardizedFileURL != ProjectStore.localDirectory.standardizedFileURL else { return }
        store.relocate(to: ProjectStore.localDirectory, removingOld: false)
        ImageStore.move(to: nil, removingOld: false)
    }

    // MARK: Watching for changes from other devices

    private func startWatching() {
        guard query == nil else { mergeSoon(); return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDataScope]   // the container, not iCloud Drive
        q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.queryChanged() }
            })
        }
        query = q
        q.start()
    }

    private func stopWatching() {
        query?.stop()
        query = nil
    }

    private func queryChanged() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var busy = false
        for case let item as NSMetadataItem in q.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let download = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if download != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                busy = true
            }
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) == true { busy = true }
            if (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) == true {
                CloudFiles.resolveConflicts(at: url)
            }
        }
        status = busy ? .syncing : .upToDate
        mergeSoon()
    }

    /// Batches bursts of updates into one reload.
    private func mergeSoon() {
        guard !mergeScheduled else { return }
        mergeScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.mergeScheduled = false
            self.store.mergeFromDisk()
        }
    }
}

/// File access that iCloud can follow: every write and delete goes through NSFileCoordinator
/// (harmless for files on the device).
enum CloudFiles {
    static func write(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    static func remove(_ url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    static func copy(from: URL, to: URL) {
        guard let data = try? Data(contentsOf: from) else { return }
        try? write(data, to: to)
    }

    /// Two devices changed the same file while apart. Sprites keep the version edited most
    /// recently (by the sprite's own `modifiedAt`); pictures keep the latest file.
    static func resolveConflicts(at url: URL) {
        guard let current = NSFileVersion.currentVersionOfItem(at: url),
              let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else { return }
        func edited(_ v: NSFileVersion) -> Date {
            if url.pathExtension == "json", let data = try? Data(contentsOf: v.url),
               let p = try? JSONDecoder().decode(SpriteProject.self, from: data) { return p.modifiedAt }
            return v.modificationDate ?? .distantPast
        }
        let winner = ([current] + others).max { edited($0) < edited($1) } ?? current
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            if winner != current { _ = try? winner.replaceItem(at: target, options: []) }
            try? NSFileVersion.removeOtherVersionsOfItem(at: target)
            for v in others { v.isResolved = true }
        }
    }
}
