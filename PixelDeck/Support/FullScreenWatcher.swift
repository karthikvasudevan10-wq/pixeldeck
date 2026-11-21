import SwiftUI
import UIKit

/// Reports whether the window this view is in is full screen (on the Mac).
///
/// In full screen the Mac hides its title bar, and slides the menu bar and title bar down over
/// the top of the window when the pointer goes there. The Studio uses this to keep its own
/// toolbar clear of that strip.
struct FullScreenWatcher: UIViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeUIView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.isUserInteractionEnabled = false
        view.onChange = { value in
            if isFullScreen != value { isFullScreen = value }
        }
        return view
    }

    func updateUIView(_ view: WatcherView, context: Context) {}

    final class WatcherView: UIView {
        var onChange: ((Bool) -> Void)?

        // The window changes size when it goes in or out of full screen, which lays this view out again.
        override func layoutSubviews() {
            super.layoutSubviews()
            check()
            // And once more when the animation into (or out of) full screen has finished.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.check() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            check()
        }

        private func check() {
            guard let scene = window?.windowScene else { return }
            let full = scene.isFullScreen
            DispatchQueue.main.async { [weak self] in self?.onChange?(full) }
        }
    }
}

/// On the Mac in full screen, moves a whole-window screen down by the height of the title bar,
/// so the strip the Mac slides down over the top of the window (menu bar and title bar, when the
/// pointer goes there) never covers the screen's own Back or Close button.
struct MacTitleBarInset: ViewModifier {
    @State private var fullScreen = false

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if fullScreen { Color.clear.frame(height: EditorView.macTitleBarHeight) }
            }
            .background { FullScreenWatcher(isFullScreen: $fullScreen) }
        #else
        content
        #endif
    }
}

extension View {
    /// See `MacTitleBarInset`. For screens that fill the window (full-screen covers and the gallery).
    func clearOfMacTitleBar() -> some View { modifier(MacTitleBarInset()) }
}
