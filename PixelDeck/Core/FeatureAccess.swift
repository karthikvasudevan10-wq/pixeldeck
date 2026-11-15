import Foundation

/// Features unlocked by the one-time "Pixel Deck Pro" purchase.
/// Display text is localised in the app layer (LocalizedTitles.swift).
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case largeCanvas
    case unlimitedFrames
    /// Eased playback timing (frames held for different lengths of time).
    case timing
    /// GIF and MP4 video.
    case gifExport
    case largeExport

    var id: String { rawValue }


}

/// What the current user may do. Every limit lives here so it can be tuned in one place.
struct FeatureAccess: Equatable, Sendable {
    /// Largest art (width and height of the drawn pixels across all frames) on the infinite canvas.
    static let freeMaxArtSide = 64
    static let proMaxArtSide = 512
    /// How many times the area Pro art can cover compared with free (64 for 512 vs 64).
    static var proAreaMultiple: Int { (proMaxArtSide * proMaxArtSide) / (freeMaxArtSide * freeMaxArtSide) }
    static let freeFrameLimit = 12
    static let freeMaxExportScale = 4
    /// Hard ceiling for everyone.
    static let absoluteFrameLimit = 999
    /// Total pixels a sprite may hold across all frames: 64 MB of RGBA in memory. Keeps big
    /// sprites from exhausting memory on older iPhones (256×256 → 256 frames, 128×128 → 999).
    static let pixelBudget = 16_777_216

    static func maxFrames(forArea area: Int) -> Int {
        min(absoluteFrameLimit, max(1, pixelBudget / max(1, area)))
    }

    var isPro: Bool

    static let free = FeatureAccess(isPro: false)
    static let pro = FeatureAccess(isPro: true)

    var maxArtSide: Int { isPro ? FeatureAccess.proMaxArtSide : FeatureAccess.freeMaxArtSide }

    func allowsArt(_ r: PixelRect) -> Bool {
        r.width <= maxArtSide && r.height <= maxArtSide
    }

    /// Frame limit for a sprite whose frames each cover `area` pixels.
    func frameLimit(forArea area: Int) -> Int {
        let cap = FeatureAccess.maxFrames(forArea: area)
        return isPro ? cap : min(FeatureAccess.freeFrameLimit, cap)
    }

    /// GIF and MP4 video.
    var allowsAnimatedExport: Bool { isPro }

    /// Playback easing other than Linear.
    var allowsEasedPlayback: Bool { isPro }

    var maxExportScale: Int { isPro ? 16 : FeatureAccess.freeMaxExportScale }
}
