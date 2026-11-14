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
        case .eyedropper: LocalizedStringResource("Pick colour", comment: "Eyedropper tool")
        case .select: LocalizedStringResource("Select & move", comment: "Selection tool")
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
        case .spriteSheet: "Sprite sheet"
        case .gif: LocalizedStringResource("GIF", comment: "Animated GIF file format")
        case .frames: "PNG frames"
        }
    }
}

extension ProFeature {
    var title: LocalizedStringResource {
        switch self {
        case .largeCanvas: "64, 128 & 256 px canvases"
        case .unlimitedFrames: "Up to \(FeatureAccess.absoluteFrameLimit) frames per sprite"
        case .gifExport: "Animated GIF export"
        case .largeExport: "Export up to 32× size"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .largeCanvas: "Room for detailed sprites, tiles and scenes."
        case .unlimitedFrames: "Free sprites can have up to \(FeatureAccess.freeFrameLimit) frames."
        case .gifExport: "Share looping animations anywhere."
        case .largeExport: "Crisp, large images for stores, social posts and print."
        }
    }
}
