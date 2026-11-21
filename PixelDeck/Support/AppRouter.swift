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

    /// A picture on its way to Photo to pixel art (dropped on the canvas or the gallery), and a
    /// level file on its way to the Playground. The screen that opens collects it from here: on
    /// the Mac a screen opened from the gallery while the Studio is in front is built from values
    /// the gallery had before, so handing it over as the screen is made arrives empty.
    @ObservationIgnored var pendingPhoto: UIImage?
    @ObservationIgnored var pendingLevel: URL?
}
