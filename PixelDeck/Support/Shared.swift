import Foundation

/// The app's shared objects: one of each for the whole app.
///
/// Screens read them from here rather than from SwiftUI's environment. On the Mac, screens
/// opened from the Studio (and some that are only prepared, never shown) did not receive
/// environment objects, and reading one that isn't there stops the app. Reading them here always
/// works, and SwiftUI still redraws a screen when something it read changes.
@MainActor
enum Shared {
    /// Opens where the sprites were last time (iCloud or the device), so the gallery appears at
    /// once; `cloud` then checks the account and moves things if anything changed.
    static let store = ProjectStore(directory: CloudSync.launchDirectory())
    static let cloud = CloudSync(store: store)
    static let purchases = PurchaseManager()
    static let community = CommunityService()
    static let ageGate = AgeGate()
    static let router = AppRouter()
}
