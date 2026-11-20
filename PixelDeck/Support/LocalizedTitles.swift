import Foundation

// Display names for the core's enums. They live here, not in Core, because Core is
// platform-independent (it also builds on Linux for tests) and LocalizedStringResource is
// Apple-only. Xcode extracts these literals into Localizable.xcstrings.

extension Tool {
    var title: LocalizedStringResource {
        switch self {
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .eyedropper: LocalizedStringResource("Colour picker", comment: "Eyedropper tool")
        case .select: LocalizedStringResource("Select & move", comment: "Selection tool")
        case .shape: LocalizedStringResource("Shapes", comment: "Shape tools: line, rectangle, circle, triangle, hexagon and more")
        }
    }
}

extension ShapeKind {
    var title: LocalizedStringResource {
        switch self {
        case .line: "Line"
        case .rectangle: LocalizedStringResource("Rectangle", comment: "Shape tool; square with proportions locked")
        case .ellipse: LocalizedStringResource("Circle", comment: "Shape tool; ellipse when proportions aren't locked")
        case .triangle: "Triangle"
        case .diamond: LocalizedStringResource("Diamond", comment: "Shape tool: a square turned 45°")
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .octagon: "Octagon"
        case .parallelogram: "Parallelogram"
        case .star: LocalizedStringResource("Star", comment: "Shape tool: a five-pointed star")
        }
    }
}

extension Easing {
    var title: LocalizedStringResource {
        switch self {
        case .linear: LocalizedStringResource("Linear", comment: "Animation timing: constant speed")
        case .easeIn: LocalizedStringResource("Ease in", comment: "Animation timing: starts slow")
        case .easeOut: LocalizedStringResource("Ease out", comment: "Animation timing: ends slow")
        case .easeInOut: LocalizedStringResource("Ease in & out", comment: "Animation timing: slow at both ends")
        }
    }
}

extension TweenPathStyle {
    var title: LocalizedStringResource {
        switch self {
        case .traced: LocalizedStringResource("Follow my drag", comment: "Tween route option")
        case .straight: LocalizedStringResource("Straight line", comment: "Tween route option")
        }
    }
}

extension TweenMode {
    var title: LocalizedStringResource {
        switch self {
        case .insertFrames: "Insert new frames"
        case .spreadAcrossFollowing: "Use existing next frames"
        }
    }
}

extension SpriteSheetLayout {
    var title: LocalizedStringResource {
        switch self {
        case .strip: LocalizedStringResource("Row", comment: "Sprite sheet layout: all frames in one row")
        case .grid: LocalizedStringResource("Grid", comment: "Sprite sheet layout: frames wrapped into a grid")
        }
    }
}

extension ExportFormat {
    var title: LocalizedStringResource {
        switch self {
        case .gif: "Animated GIF"
        case .spriteSheet: "Sprite sheet"
        case .frames: "PNG frames"
        case .video: "Video"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .gif: "Loops anywhere you post it"
        case .spriteSheet: "All frames in one image, for game engines"
        case .frames: "One image per frame"
        case .video: "For Reels, Shorts and TikTok"
        }
    }

    /// The export button's label.
    var action: LocalizedStringResource {
        switch self {
        case .gif: "Save GIF"
        case .spriteSheet: "Save sheet"
        case .frames: "Save frames"
        case .video: "Save video"
        }
    }

    var fileExtension: String {
        switch self {
        case .gif: ".gif"
        case .spriteSheet, .frames: ".png"
        case .video: ".mp4"
        }
    }
}

extension ProFeature {
    var title: LocalizedStringResource {
        switch self {
        case .largeCanvas: "Grow your art to \(FeatureAccess.proMaxArtSide) × \(FeatureAccess.proMaxArtSide)"
        case .unlimitedFrames: "Up to \(FeatureAccess.absoluteFrameLimit) frames per sprite"
        case .largeExport: "Export up to 16× and 4K"
        case .noWatermark: "No watermark on GIFs, videos and images"
        case .artistBrushes: "Dither brush & 4-way symmetry"
        case .paletteImport: "Import palettes"
        case .timing: "Eased timing and timelapse video"
        case .photoToPixel: "Photo to pixel art"
        case .animationPresets: "Every animation preset"
        case .adjustAllFrames: "Recolour every frame at once"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .largeCanvas: "The canvas is infinite for everyone. Free art can grow to \(FeatureAccess.freeMaxArtSide) × \(FeatureAccess.freeMaxArtSide) pixels; Pro gives it \(FeatureAccess.proAreaMultiple) times the room, for detailed scenes and tilesets."
        case .unlimitedFrames: "Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames. Very large sprites have a lower limit to protect your device's memory."
        case .largeExport: "Crisp, large images and 4K videos for stores, social posts and print."
        case .noWatermark: "Free exports carry a small \"Made with Pixel Deck\" mark. Pro exports are just your art."
        case .artistBrushes: "Shade with a checkerboard dither brush, and draw with top-bottom or four-way symmetry."
        case .paletteImport: "Bring in palettes from Lospec and other apps: .hex, .gpl, .txt and palette images."
        case .timing: "Let animations speed up and slow down, in playback, GIFs, videos and sprite sheets. And save the timelapse of your drawing as a video."
        case .photoToPixel: "Turn any photo into pixel art in its own colours, your palette or a retro look, ready to tidy and animate."
        case .animationPresets: "Bounce and Blink are free. Pro adds Float, Shake, Colour cycle and Squash, drawn for you as real frames."
        case .adjustAllFrames: "Change brightness, contrast, hue and saturation across a whole animation in one go."
        }
    }
}

extension PalettePreset {
    var title: LocalizedStringResource {
        switch self {
        case .pixelDeck: LocalizedStringResource("Pixel Deck", comment: "Palette name: the app's starter colours")
        case .sunset: LocalizedStringResource("Sunset", comment: "Palette name")
        case .forest: LocalizedStringResource("Forest", comment: "Palette name")
        case .ocean: LocalizedStringResource("Ocean", comment: "Palette name")
        case .candy: LocalizedStringResource("Candy", comment: "Palette name: pastels")
        case .neon: LocalizedStringResource("Neon", comment: "Palette name")
        case .fire: LocalizedStringResource("Fire", comment: "Palette name")
        case .people: LocalizedStringResource("Skin & hair", comment: "Palette name: skin tones and hair colours for characters")
        case .pocketGreens: LocalizedStringResource("Pocket greens", comment: "Palette name: shades of green, like an old handheld screen")
        case .grayscale: LocalizedStringResource("Greys", comment: "Palette name: black to white")
        }
    }
}

extension FrameTransform {
    var title: LocalizedStringResource {
        switch self {
        case .flipHorizontal: "Flip left to right"
        case .flipVertical: "Flip upside down"
        case .rotateClockwise: "Rotate right"
        case .rotateCounterClockwise: "Rotate left"
        }
    }

    var systemImage: String {
        switch self {
        case .flipHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .flipVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .rotateClockwise: "rotate.right"
        case .rotateCounterClockwise: "rotate.left"
        }
    }
}
