import Foundation

/// A picture laid under every layer to trace over. Only these settings live in the sprite; the
/// image itself is stored beside it (see ImageStore). It is never drawn into frames, thumbnails,
/// the onion skin or exports.
struct TraceSettings: Codable, Equatable, Sendable {
    var opacity: Double = 0.5
    var isVisible = true
    /// Centre, in world pixels.
    var centerX: Double = 0
    var centerY: Double = 0
    /// Width in art pixels. The height follows the picture's shape.
    var width: Double = 32
    /// The picture's height ÷ width.
    var aspect: Double = 1

    static let opacityRange = 0.05...1.0
    static let widthRange = 4.0...1024.0

    var height: Double { width * aspect }
    /// (x, y, width, height) in world pixels.
    var rect: (x: Double, y: Double, width: Double, height: Double) {
        (centerX - width / 2, centerY - height / 2, width, height)
    }

    /// A newly picked picture: as wide as the art (or 32 px on a blank canvas), centred on it.
    static func placed(aspect: Double, over art: PixelRect?) -> TraceSettings {
        var t = TraceSettings()
        t.aspect = aspect.isFinite && aspect > 0 ? aspect : 1
        if let art {
            // Cover the art: fit its width, or its height if the picture is wider than the art.
            let artAspect = Double(art.height) / Double(art.width)
            t.width = t.aspect < artAspect ? Double(art.height) / t.aspect : Double(art.width)
            t.centerX = Double(art.x) + Double(art.width) / 2
            t.centerY = Double(art.y) + Double(art.height) / 2
        }
        return t.sanitized
    }

    /// Clamped into range, so a damaged file can't hide the picture or blow up its size.
    var sanitized: TraceSettings {
        var t = self
        func finite(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }
        t.opacity = min(max(finite(opacity, 0.5), Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        t.width = min(max(finite(width, 32), Self.widthRange.lowerBound), Self.widthRange.upperBound)
        t.aspect = min(max(finite(aspect, 1), 0.05), 20)
        t.centerX = min(max(finite(centerX, 0), -10_000), 10_000)
        t.centerY = min(max(finite(centerY, 0), -10_000), 10_000)
        return t
    }
}

extension EditorModel {
    var trace: TraceSettings? { project.trace }

    /// Sets (or, with nil, removes) the tracing picture's settings. Not part of undo, like the
    /// onion skin: it's a guide, not art.
    func setTrace(_ t: TraceSettings?) {
        let new = t?.sanitized
        guard new != project.trace else { return }
        updateProject { $0.trace = new }
    }
}
