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
        case .shape: LocalizedStringResource("Shapes", comment: "Shape tools: line, rectangle, circle, triangle")
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
        case .largeCanvas: "Art up to \(FeatureAccess.proMaxArtSide) × \(FeatureAccess.proMaxArtSide)"
        case .unlimitedFrames: "Up to \(FeatureAccess.absoluteFrameLimit) frames per sprite"
        case .gifExport: "Animated GIF & video export"
        case .largeExport: "Export up to 16× size"
        case .timing: "Eased playback timing"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .largeCanvas: "Free art on the infinite canvas can be up to \(FeatureAccess.freeMaxArtSide) × \(FeatureAccess.freeMaxArtSide) pixels. Pro gives you room for detailed scenes and tilesets."
        case .unlimitedFrames: "Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames. Very large sprites have a lower limit to protect your device's memory."
        case .gifExport: "Share looping GIFs and MP4 videos for Reels, Shorts and TikTok."
        case .largeExport: "Crisp, large images for stores, social posts and print."
        case .timing: "Let animations speed up and slow down — ease in, ease out or both — in playback, GIFs, videos and sprite sheets."
        }
    }
}
