import Foundation
import Observation

/// A copied frame: every layer's pixels, trimmed to the art and kept in world coordinates, so
/// it pastes back in the same place in any frame of any sprite.
struct FrameClip: Sendable {
    /// The world rectangle the cels cover; nil for a blank frame.
    var bounds: PixelRect?
    /// One cel per layer, bottom first, each covering `bounds` (empty for a blank frame).
    var layers: [PixelGrid]
    /// The visible layers flattened, for pasting into a sprite with a different layer stack.
    var flattened: PixelGrid?
    /// How many layers the frame had when it was copied.
    var layerCount: Int

    init(frame: Frame, frameBounds: PixelRect, visible: [Bool]) {
        layerCount = frame.layers.count
        var art: PixelRect?
        for cel in frame.layers {
            guard let r = cel.opaqueBounds?.offsetBy(frameBounds.origin) else { continue }
            art = art.map { $0.union(r) } ?? r
        }
        bounds = art
        guard let rect = art else {
            layers = []
            flattened = nil
            return
        }
        let cels = frame.layers.map { $0.reframed(from: frameBounds, to: rect) }
        layers = cels
        flattened = Frame(layers: cels, visible: visible).grid
    }

    var isBlank: Bool { bounds == nil }
}

/// The app's frame clipboard. Shared, so a frame copied in one sprite can be pasted in another.
@Observable
final class FrameClipboard {
    static let shared = FrameClipboard()
    var clip: FrameClip?
}

extension EditorModel {
    /// Copies frame `index` to the app's frame clipboard.
    func copyFrameToClipboard(at index: Int) {
        if let clip = copyFrame(at: index) { FrameClipboard.shared.clip = clip }
    }

    /// Pastes the clipboard into frame `index` (replacing it), or as a new frame after it.
    @discardableResult
    func pasteClipboard(at index: Int, asNewFrame: Bool) -> Bool {
        guard let clip = FrameClipboard.shared.clip, project.frames.indices.contains(index) else { return false }
        selectFrame(index)
        return pasteFrame(clip, asNewFrame: asNewFrame)
    }
}
