import SwiftUI
import UIKit

@main
struct PixelDeckApp: App {
    @State private var store: ProjectStore
    @State private var cloud: CloudSync
    @State private var purchases = PurchaseManager()
    @State private var community = CommunityService()
    @State private var ageGate = AgeGate()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.registerBundledFonts()
        // Opens where the sprites were last time (iCloud or the device), so the gallery appears at
        // once; CloudSync then checks the account and moves things if anything changed.
        let store = ProjectStore(directory: CloudSync.launchDirectory())
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudSync(store: store))
    }

    /// On the Mac, keep the window big enough for the desk layout.
    private static func setMinimumWindowSize() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.sizeRestrictions?.minimumSize = CGSize(width: 980, height: 640)
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
                .task { cloud.start() }
                // Night (dark) and Paper (light) follow the system appearance.
                .tint(Theme.accent)
                .onAppear(perform: Self.setMinimumWindowSize)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            // The Mac menu bar. (On iPhone and iPad the Studio's own shortcuts are used.)
            #if targetEnvironment(macCatalyst)
            StudioCommands()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
        }
    }
}
