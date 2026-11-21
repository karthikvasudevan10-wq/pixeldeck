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
        #if DEBUG
        titlebarExperiment()
        #endif
        #endif
    }

    #if DEBUG && targetEnvironment(macCatalyst)
    /// TEMPORARY: tries ways of hiding the title bar (launch argument -pdTitlebar N) and reports what the window looks like.
    private static func titlebarExperiment() {
        let mode = UserDefaults.standard.integer(forKey: "pdTitlebar")
        func scenes() -> [UIWindowScene] { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene } }
        func nsWindows() -> [NSObject] {
            guard let cls = NSClassFromString("NSApplication") as AnyObject?,
                  let app = cls.value(forKey: "sharedApplication") as? NSObject else { return [] }
            return app.value(forKey: "windows") as? [NSObject] ?? []
        }
        func report(_ label: String) {
            var out = "PD-DIAG mode=\(mode) \(label)\n"
            for s in scenes() {
                out += "  fullScreen=\(s.isFullScreen)\n"
                // Read by name: mentioning the title bar's type here doesn't link on the Mac.
                let bar = s.value(forKey: "titlebar") as? NSObject
                out += "  scene titlebar=\(bar == nil ? "none" : "yes") toolbar=\(String(describing: bar?.value(forKey: "toolbar"))) titleVis=\(String(describing: bar?.value(forKey: "titleVisibility"))) style=\(String(describing: bar?.value(forKey: "toolbarStyle")))\n"
                for w in s.windows { out += "    uiwindow frame=\(w.frame) safe=\(w.safeAreaInsets) root=\(type(of: w.rootViewController as Any))\n" }
            }
            for w in nsWindows() {
                out += "  nswindow \(type(of: w)) frame=\(String(describing: w.value(forKey: "frame"))) mask=\(String(describing: w.value(forKey: "styleMask"))) toolbar=\(String(describing: w.value(forKey: "toolbar"))) transparent=\(String(describing: w.value(forKey: "titlebarAppearsTransparent"))) layout=\(String(describing: w.value(forKey: "contentLayoutRect")))\n"
            }
            fputs(out, stderr)
        }
        report("at start")
        if mode == 1 {
            for delay in [0.3, 1.0, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    for s in scenes() { s.titlebar?.titleVisibility = .hidden; s.titlebar?.toolbar = nil }
                }
            }
        }
        if mode == 2 || mode == 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                for w in nsWindows() {
                    let mask = (w.value(forKey: "styleMask") as? UInt) ?? 0
                    w.setValue(mask | (1 << 15), forKey: "styleMask")          // full-size content view
                    w.setValue(true, forKey: "titlebarAppearsTransparent")
                    if mode == 3 { w.setValue(nil, forKey: "toolbar") }
                }
            }
        }
        if mode == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                for w in nsWindows() where String(describing: type(of: w)) == "UINSWindow" {
                    _ = w.perform(NSSelectorFromString("toggleFullScreen:"), with: nil)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { report("after 7s") }
    }
    #endif

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
