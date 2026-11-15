import SwiftUI

@main
struct PixelDeckApp: App {
    @State private var store: ProjectStore
    @State private var cloud: CloudSync
    @State private var purchases = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.registerBundledFonts()
        // Opens where the sprites were last time (iCloud or the device), so the gallery appears at
        // once; CloudSync then checks the account and moves things if anything changed.
        let store = ProjectStore(directory: CloudSync.launchDirectory())
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudSync(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
                .environment(purchases)
                .environment(cloud)
                .task { cloud.start() }
                // Night (dark) and Paper (light) follow the system appearance.
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
        }
    }
}
