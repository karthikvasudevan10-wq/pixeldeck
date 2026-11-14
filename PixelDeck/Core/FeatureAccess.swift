import Foundation

/// Features unlocked by the one-time "Pixel Deck Pro" purchase.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case largeCanvas
    case unlimitedFrames
    case gifExport
    case largeExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeCanvas: "64, 128 & 256 px canvases"
        case .unlimitedFrames: "Up to 999 frames per sprite"
        case .gifExport: "Animated GIF export"
        case .largeExport: "Export up to 32× size"
        }
    }

    var detail: String {
        switch self {
        case .largeCanvas: "Room for detailed sprites, tiles and scenes."
        case .unlimitedFrames: "Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames."
        case .gifExport: "Share looping animations anywhere."
        case .largeExport: "Crisp, large images for stores, social posts and print."
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .largeCanvas: "square.resize.up"
        case .unlimitedFrames: "rectangle.stack.fill"
        case .gifExport: "play.square.stack"
        case .largeExport: "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// What the current user may do. Every limit lives here so it can be tuned in one place.
struct FeatureAccess: Equatable, Sendable {
    static let freeSizes: Set<Int> = [8, 16, 32]
    static let freeFrameLimit = 12
    static let freeMaxExportScale = 4
    /// Hard ceiling for everyone, to keep memory and file sizes sane.
    static let absoluteFrameLimit = 999

    var isPro: Bool

    static let free = FeatureAccess(isPro: false)
    static let pro = FeatureAccess(isPro: true)

    func allowsCanvas(size: Int) -> Bool {
        isPro || FeatureAccess.freeSizes.contains(size)
    }

    var frameLimit: Int {
        isPro ? FeatureAccess.absoluteFrameLimit : FeatureAccess.freeFrameLimit
    }

    var allowsGIF: Bool { isPro }

    var maxExportScale: Int { isPro ? 32 : FeatureAccess.freeMaxExportScale }
}
