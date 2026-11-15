import SwiftUI

@main
struct PixelDeckApp: App {
    @State private var store = ProjectStore()
    @State private var purchases = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
                .environment(purchases)
                // Night (dark) and Paper (light) follow the system appearance.
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
        }
    }
}
