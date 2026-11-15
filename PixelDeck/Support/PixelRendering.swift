import SwiftUI
import UIKit

enum PixelRenderer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func cgImage(_ grid: PixelGrid, scale: Int = 1) -> CGImage? {
        let s = max(1, scale)
        return cgImage(width: grid.width * s, height: grid.height * s, rgba: grid.rgbaBytes(scale: s))
    }

    /// Pixels are either fully opaque or fully transparent (0,0,0,0), so premultiplied alpha is exact.
    static func cgImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The onion skin look: every opaque pixel becomes one flat colour.
    static func tinted(_ grid: PixelGrid, with color: RGBA) -> PixelGrid {
        var out = PixelGrid(width: grid.width, height: grid.height)
        for y in 0..<grid.height {
            for x in 0..<grid.width where !grid[x, y].isClear { out[x, y] = color }
        }
        return out
    }
}

extension RGBA {
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ui = UIColor(color)
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            ui.getWhite(&white, alpha: &a)
            r = white; g = white; b = white
        }
        func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        self.init(r: byte(r), g: byte(g), b: byte(b), a: 255)
    }
}

/// Caches frame thumbnails until the frame's pixels change. NSCache evicts under memory
/// pressure and is capped at ~48 MB.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private final class Entry {
        let version: Int
        let image: CGImage
        init(version: Int, image: CGImage) { self.version = version; self.image = image }
    }

    private let cache: NSCache<NSUUID, Entry> = {
        let c = NSCache<NSUUID, Entry>()
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    func image(for frame: Frame) -> CGImage? {
        let key = frame.id as NSUUID
        if let e = cache.object(forKey: key), e.version == frame.version { return e.image }
        guard let img = PixelRenderer.cgImage(frame.grid) else { return nil }
        cache.setObject(Entry(version: frame.version, image: img), forKey: key, cost: img.bytesPerRow * img.height)
        return img
    }
}

/// A crisp, nearest-neighbour rendering of a canvas over a checkerboard.
struct PixelImage: View {
    let image: CGImage?
    var checker = true

    init(grid: PixelGrid, checker: Bool = true) {
        self.image = PixelRenderer.cgImage(grid)
        self.checker = checker
    }

    init(frame: Frame, checker: Bool = true) {
        self.image = ThumbnailCache.shared.image(for: frame)
        self.checker = checker
    }

    /// A ready-made image (for looping previews that render their frames once).
    init(image: CGImage?, checker: Bool = false) {
        self.image = image
        self.checker = checker
    }

    var body: some View {
        ZStack {
            if checker { CheckerBackground() }
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
            }
        }
        .aspectRatio(image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 1, contentMode: .fit)
    }
}

/// Checkerboard behind thumbnails, in the design's checker colours.
struct CheckerBackground: View {
    var body: some View { Checkerboard(cell: 6) }
}

/// Looping playback that follows a sprite's (possibly eased) per-frame durations.
enum PlaybackClock {
    static func index(_ date: Date, durations: [Double]) -> Int {
        PlaybackTiming.frameIndex(at: date.timeIntervalSinceReferenceDate, durations: durations)
    }

    /// How often a looping view needs to update: often enough for the shortest frame.
    static func tick(_ durations: [Double]) -> TimeInterval {
        max(1.0 / 60, durations.min() ?? 0.125)
    }
}

/// Playback easing choices for the frame-rate menus (Pro; Linear is free).
struct TimingPicker: View {
    let model: EditorModel

    var body: some View {
        Picker(selection: Binding(get: { model.project.playbackEasing }, set: { model.setPlaybackEasing($0) })) {
            ForEach(Easing.allCases) { e in
                if e == .linear || model.access.allowsEasedPlayback {
                    Text(e.title).tag(e)
                } else {
                    Text("\(Text(e.title)) · Pro", comment: "A locked option; the placeholder is the option name").tag(e)
                }
            }
        } label: {
            Label("Timing", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .pickerStyle(.menu)
    }
}
