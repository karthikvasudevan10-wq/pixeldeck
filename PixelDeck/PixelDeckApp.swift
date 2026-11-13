import SwiftUI

@main
struct PixelDeckApp: App {
    @State private var store = ProjectStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.flush() }
        }
    }
}
