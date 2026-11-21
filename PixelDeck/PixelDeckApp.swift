import SwiftUI
import UIKit

@main
struct PixelDeckApp: App {
    @State private var store: ProjectStore
    @State private var cloud: CloudSync
    @State private var purchases = PurchaseManager()
    @State private var community = CommunityService()
    @State private var ageGate = AgeGate()
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.registerBundledFonts()
        // Opens where the sprites were last time (iCloud or the device), so the gallery appears at
        // once; CloudSync then checks the account and moves things if anything changed.
        let store = ProjectStore(directory: CloudSync.launchDirectory())
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudSync(store: store))
    }

    /// On the Mac: keep the window big enough for the desk layout, and hide the title bar.
    private static func setMinimumWindowSize() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            guard let window = scene as? UIWindowScene else { continue }
            window.sizeRestrictions?.minimumSize = CGSize(width: 1080, height: 680)
            // As designed: no separate title bar. The Studio's own toolbar shares the top row
            // with the close, minimise and zoom buttons.
            window.titlebar?.titleVisibility = .hidden
            window.titlebar?.toolbar = nil
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
                .environment(purchases)
                .environment(cloud)
                .environment(community)
                .environment(ageGate)
                .environment(router)
                .task { cloud.start() }
                .task { AIBridge.shared.startIfEnabled() }
                // Night (dark) and Paper (light) follow the system appearance.
                .tint(Theme.accent)
                .onAppear { Self.setMinimumWindowSize() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            // The Mac menu bar. (On iPhone and iPad the Studio's own shortcuts are used.)
            #if targetEnvironment(macCatalyst)
            StudioCommands(router: router)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
        }
    }
}
