import Observation
import SwiftUI
import UIKit

/// Requests from the Studio (its sidebar, the Mac menu bar, a dropped file) for things the
/// gallery presents: the New canvas chooser, Settings, Pixel Academy, the Playground, Community,
/// starting a lesson, or opening a photo or an Aseprite file. On the Mac the Studio is the main
/// window and the gallery stays behind it, so this is how those screens are reached.
@Observable
final class AppRouter {
    enum Request: Equatable {
        case newCanvas, settings, academy, playground, community
        /// A Pixel Academy lesson, by id.
        case lesson(String)
        case photo(UIImage)
        case aseprite(URL)
    }

    var request: Request?
}
