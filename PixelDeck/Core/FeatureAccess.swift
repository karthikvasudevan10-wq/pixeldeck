import Foundation

/// Features unlocked by the one-time "Pixel Deck Pro" purchase.
/// Display text is localised in the app layer (LocalizedTitles.swift).
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case largeCanvas
    case unlimitedFrames
    case gifExport
    case largeExport

    var id: String { rawValue }


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
    /// Hard ceiling for everyone.
    static let absoluteFrameLimit = 999
    /// Total pixels a sprite may hold across all frames: 64 MB of RGBA in memory. Keeps big
    /// canvases from exhausting memory on older iPhones (256×256 → 256 frames, 128×128 → 999).
    static let pixelBudget = 16_777_216

    static func maxFrames(forCanvas size: Int) -> Int {
        min(absoluteFrameLimit, max(1, pixelBudget / max(1, size * size)))
    }

    var isPro: Bool

    static let free = FeatureAccess(isPro: false)
    static let pro = FeatureAccess(isPro: true)

    func allowsCanvas(size: Int) -> Bool {
        isPro || FeatureAccess.freeSizes.contains(size)
    }

    func frameLimit(forCanvas size: Int) -> Int {
        let cap = FeatureAccess.maxFrames(forCanvas: size)
        return isPro ? cap : min(FeatureAccess.freeFrameLimit, cap)
    }

    var allowsGIF: Bool { isPro }

    var maxExportScale: Int { isPro ? 32 : FeatureAccess.freeMaxExportScale }
}
