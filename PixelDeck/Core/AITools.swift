import Foundation

/// The drawing tools an AI assistant can call (through MCP on the Mac). They are the same actions
/// a person uses, so what an assistant draws is real layers and frames: editable, undoable one
/// step at a time, and recorded in the timelapse.
///
/// Coordinates are whole canvas pixels: x grows to the right, y grows downwards, and (0, 0) is
/// the middle of a new canvas. Colours are "#RRGGBB"; "clear" (or leaving the colour out) erases.
struct AITool: Sendable {
    let name: String
    let summary: String
    /// JSON Schema for the arguments, as JSON text.
    let schema: String
}

struct AIToolError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

enum AITools {
    /// Most pixels one call may set, so a mistake can't flood the canvas.
    static let maxPixelsPerCall = 20_000

    static let all: [AITool] = [
        AITool(name: "read_canvas", summary: "Look at the current frame: its size, colours and every pixel as rows of characters. Call this first, and again after drawing, to check your work.",
               schema: #"{"type":"object","properties":{}}"#),
        AITool(name: "set_pixels", summary: "Set individual pixels. Either `pixels`: a list of [x, y, \"#RRGGBB\"] (use \"clear\" to erase), or `rows` drawn from (x, y): strings where each character is a key of `legend` and '.' leaves the pixel alone.",
               schema: #"{"type":"object","properties":{"pixels":{"type":"array","items":{"type":"array"}},"x":{"type":"integer"},"y":{"type":"integer"},"rows":{"type":"array","items":{"type":"string"}},"legend":{"type":"object"}}}"#),
        AITool(name: "line", summary: "Draw a 1-pixel line from (x1, y1) to (x2, y2).",
               schema: #"{"type":"object","properties":{"x1":{"type":"integer"},"y1":{"type":"integer"},"x2":{"type":"integer"},"y2":{"type":"integer"},"color":{"type":"string"}},"required":["x1","y1","x2","y2"]}"#),
        AITool(name: "rect", summary: "Draw a rectangle between two corners, filled or as an outline.",
               schema: #"{"type":"object","properties":{"x1":{"type":"integer"},"y1":{"type":"integer"},"x2":{"type":"integer"},"y2":{"type":"integer"},"color":{"type":"string"},"filled":{"type":"boolean"}},"required":["x1","y1","x2","y2"]}"#),
        AITool(name: "ellipse", summary: "Draw an ellipse inside the box between two corners, filled or as an outline.",
               schema: #"{"type":"object","properties":{"x1":{"type":"integer"},"y1":{"type":"integer"},"x2":{"type":"integer"},"y2":{"type":"integer"},"color":{"type":"string"},"filled":{"type":"boolean"}},"required":["x1","y1","x2","y2"]}"#),
        AITool(name: "fill", summary: "Flood-fill the area of one colour touching (x, y) on the current layer.",
               schema: #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"},"color":{"type":"string"}},"required":["x","y","color"]}"#),
        AITool(name: "set_palette", summary: "Set the sprite's colours: the first ten become its swatches, the rest are added as extra colours.",
               schema: #"{"type":"object","properties":{"colors":{"type":"array","items":{"type":"string"}}},"required":["colors"]}"#),
        AITool(name: "add_frame", summary: "Add a frame after the current one and go to it. With `copy` true it starts as a copy of the current frame; otherwise blank (the previous frame shows through faintly).",
               schema: #"{"type":"object","properties":{"copy":{"type":"boolean"}}}"#),
        AITool(name: "select_frame", summary: "Go to a frame (1 is the first).",
               schema: #"{"type":"object","properties":{"frame":{"type":"integer"}},"required":["frame"]}"#),
        AITool(name: "add_layer", summary: "Add a layer above the current one and draw on it from now on.",
               schema: #"{"type":"object","properties":{"name":{"type":"string"}}}"#),
        AITool(name: "select_layer", summary: "Draw on another layer (1 is the bottom one).",
               schema: #"{"type":"object","properties":{"layer":{"type":"integer"}},"required":["layer"]}"#),
        AITool(name: "flip", summary: "Flip the current frame's art: direction is \"horizontal\" or \"vertical\". With `all_frames` true, every frame.",
               schema: #"{"type":"object","properties":{"direction":{"type":"string","enum":["horizontal","vertical"]},"all_frames":{"type":"boolean"}},"required":["direction"]}"#),
        AITool(name: "rotate", summary: "Turn the current frame's art a quarter turn: direction is \"right\" or \"left\". With `all_frames` true, every frame.",
               schema: #"{"type":"object","properties":{"direction":{"type":"string","enum":["right","left"]},"all_frames":{"type":"boolean"}},"required":["direction"]}"#),
        AITool(name: "set_speed", summary: "Set the animation's speed in frames per second (1 to 30).",
               schema: #"{"type":"object","properties":{"fps":{"type":"integer"}},"required":["fps"]}"#),
        AITool(name: "undo", summary: "Undo the last step.", schema: #"{"type":"object","properties":{}}"#),
    ]

    // MARK: Arguments

    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double, d == d.rounded(), abs(d) < 1e9 { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }

    /// A colour argument: nil or "clear" erases. Throws on anything unreadable.
    static func color(_ any: Any?) throws -> RGBA {
        guard let s = any as? String else {
            if any == nil || any is NSNull { return .clear }
            throw AIToolError("Colours are strings like \"#FF5C8A\", or \"clear\" to erase.")
        }
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "clear" || t == "transparent" || t.isEmpty { return .clear }
        guard let c = RGBA(hexString: t) else { throw AIToolError("\"\(s)\" isn't a colour. Use \"#RRGGBB\", or \"clear\" to erase.") }
        return c
    }

    private static func point(_ args: [String: Any], _ kx: String, _ ky: String) throws -> PixelPoint {
        guard let x = int(args[kx]), let y = int(args[ky]) else { throw AIToolError("\(kx) and \(ky) must be whole numbers.") }
        guard abs(x) <= 4096, abs(y) <= 4096 else { throw AIToolError("\(kx), \(ky) is too far away.") }
        return PixelPoint(x: x, y: y)
    }

    // MARK: Calling

    /// Runs a tool on the Studio's model. Returns what to tell the assistant.
    static func call(_ name: String, _ args: [String: Any], model: EditorModel) throws -> String {
        switch name {
        case "read_canvas":
            return describe(model)
        case "set_pixels":
            var groups: [RGBA: [PixelPoint]] = [:]
            if let list = args["pixels"] as? [Any] {
                for item in list {
                    guard let triple = item as? [Any], triple.count >= 2, let x = int(triple[0]), let y = int(triple[1]) else {
                        throw AIToolError("Each pixel is [x, y, \"#RRGGBB\"].")
                    }
                    groups[try color(triple.count > 2 ? triple[2] : nil), default: []].append(PixelPoint(x: x, y: y))
                }
            }
            if let rows = args["rows"] as? [String] {
                let origin = try point(args, "x", "y")
                let legend = (args["legend"] as? [String: Any]) ?? [:]
                var colors: [Character: RGBA] = [:]
                for (k, v) in legend { if let ch = k.first, k.count == 1 { colors[ch] = try color(v) } }
                for (dy, row) in rows.enumerated() {
                    for (dx, ch) in row.enumerated() where ch != "." {
                        guard let c = colors[ch] else { throw AIToolError("'\(ch)' isn't in the legend. Use '.' to leave a pixel alone.") }
                        groups[c, default: []].append(PixelPoint(x: origin.x + dx, y: origin.y + dy))
                    }
                }
            }
            let total = groups.values.reduce(0) { $0 + $1.count }
            guard total > 0 else { throw AIToolError("Nothing to draw: give `pixels`, or `rows` with a `legend`.") }
            return try draw(groups, model: model)
        case "line":
            let a = try point(args, "x1", "y1"), b = try point(args, "x2", "y2")
            return try draw([try color(args["color"]): PixelGrid.linePoints(from: a, to: b)], model: model)
        case "rect", "ellipse":
            let a = try point(args, "x1", "y1"), b = try point(args, "x2", "y2")
            let pts = ShapeRaster.points(name == "rect" ? .rectangle : .ellipse, from: a, to: b, filled: bool(args["filled"]))
            return try draw([try color(args["color"]): pts], model: model)
        case "fill":
            let p = try point(args, "x", "y")
            let c = try color(args["color"])
            guard !c.isClear else { throw AIToolError("Fill needs a colour. To erase an area, draw over it with \"clear\".") }
            let before = model.currentGrid
            model.pickColor(c)
            model.fill(at: p)
            return model.currentGrid == before ? "Nothing changed: that area is already this colour, or it's empty space outside the art." : "Filled."
        case "set_palette":
            guard let list = args["colors"] as? [Any], !list.isEmpty else { throw AIToolError("Give `colors`: a list of \"#RRGGBB\" strings.") }
            let colors = try list.map { try color($0) }.filter { !$0.isClear }
            guard !colors.isEmpty else { throw AIToolError("Give at least one colour.") }
            guard !model.isPaletteLocked else { throw AIToolError("This is a retro canvas: its colours are fixed.") }
            var swatches = model.palette
            for (i, c) in colors.prefix(swatches.count).enumerated() { swatches[i] = c }
            model.applyPalette(swatches)
            let extra = model.addColors(Array(colors.dropFirst(swatches.count)))
            return "Palette set: \(min(colors.count, swatches.count)) swatches" + (extra > 0 ? ", \(extra) extra colours." : ".")
        case "add_frame":
            let count = model.frameCount
            if bool(args["copy"]) { model.duplicateFrame(at: model.currentIndex) } else { model.addKeyframe() }
            guard model.frameCount > count else { throw AIToolError("This sprite can't have more frames (free sprites have up to \(FeatureAccess.freeFrameLimit)).") }
            return "Now on frame \(model.currentIndex + 1) of \(model.frameCount)."
        case "select_frame":
            guard let n = int(args["frame"]), (1...model.frameCount).contains(n) else {
                throw AIToolError("There are \(model.frameCount) frames; `frame` counts from 1.")
            }
            model.selectFrame(n - 1)
            return "Now on frame \(n) of \(model.frameCount)."
        case "add_layer":
            guard model.canAddLayer else { throw AIToolError("This sprite is too big in memory for another layer (it has \(model.layers.count)). Fewer frames or a smaller canvas would make room.") }
            let raw = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            model.addLayer(named: raw.isEmpty ? nil : String(raw.prefix(24)))
            return "Drawing on new layer \(model.activeLayer + 1) of \(model.layers.count): \"\(model.layers[model.activeLayer].name)\"."
        case "select_layer":
            guard let n = int(args["layer"]), (1...model.layers.count).contains(n) else {
                throw AIToolError("There are \(model.layers.count) layers; `layer` counts from 1 at the bottom.")
            }
            model.selectLayer(n - 1)
            return "Drawing on layer \(n): \"\(model.layers[n - 1].name)\"."
        case "flip", "rotate":
            let direction = (args["direction"] as? String)?.lowercased() ?? ""
            let transform: FrameTransform
            switch (name, direction) {
            case ("flip", "horizontal"): transform = .flipHorizontal
            case ("flip", "vertical"): transform = .flipVertical
            case ("rotate", "right"): transform = .rotateClockwise
            case ("rotate", "left"): transform = .rotateCounterClockwise
            default: throw AIToolError(name == "flip" ? "direction is \"horizontal\" or \"vertical\"." : "direction is \"right\" or \"left\".")
            }
            guard model.transform(transform, allFrames: bool(args["all_frames"])) else {
                throw AIToolError("Nothing to turn, or the turned art wouldn't fit.")
            }
            return "Done."
        case "set_speed":
            guard let fps = int(args["fps"]), (1...SpriteProject.maxFPS).contains(fps) else { throw AIToolError("fps is a whole number from 1 to \(SpriteProject.maxFPS).") }
            model.setFPS(fps)
            return "Playing at \(fps) frames per second."
        case "undo":
            guard model.canUndo else { throw AIToolError("Nothing to undo.") }
            model.undo()
            return "Undone."
        default:
            throw AIToolError("There's no tool called \(name).")
        }
    }

    /// Draws groups of pixels as one undo step, refusing anything that would take the art past
    /// its size limit rather than drawing part of it.
    private static func draw(_ groups: [RGBA: [PixelPoint]], model: EditorModel) throws -> String {
        let all = groups.filter { !$0.key.isClear }.values.flatMap { $0 }
        let total = groups.values.reduce(0) { $0 + $1.count }
        guard total <= maxPixelsPerCall else { throw AIToolError("That's \(total) pixels in one call; the most is \(maxPixelsPerCall).") }
        if let first = all.first {
            var box = PixelRect(x: first.x, y: first.y, width: 1, height: 1)
            for p in all { box = box.union(p) }
            let art = model.contentBounds.map { $0.union(box) } ?? box
            guard model.access.allowsArt(art) else {
                let side = model.access.maxArtSide
                throw AIToolError("That would make the art \(art.width) × \(art.height) pixels; the most here is \(side) × \(side). Draw closer to the existing art, which covers x \(model.contentBounds?.x ?? 0)…, y \(model.contentBounds?.y ?? 0)….")
            }
        }
        model.isPlaying = false
        model.commitSelection()
        model.pushUndo()
        model.revealActiveLayer()
        // Erasing first, so a call that both clears and paints a pixel ends with it painted.
        for (c, pts) in groups.sorted(by: { $0.key.isClear && !$1.key.isClear }) { model.paintPixels(pts, color: c) }
        model.contentKnown = false
        model.finishEdit()
        return "Drew \(total) pixels on frame \(model.currentIndex + 1), layer \"\(model.layers[model.activeLayer].name)\"."
    }

    /// The current frame as text: where the art is, the colours used, and one row of characters
    /// per row of pixels.
    static func describe(_ model: EditorModel) -> String {
        var out = "Sprite \"\(model.project.name)\": frame \(model.currentIndex + 1) of \(model.frameCount), "
        out += "drawing on layer \(model.activeLayer + 1) of \(model.layers.count) (\"\(model.layers[model.activeLayer].name)\"), \(model.project.fps) fps.\n"
        let side = model.access.maxArtSide
        out += "Coordinates: x right, y down, (0, 0) is the middle of a new canvas. Art can be up to \(side) × \(side) pixels.\n"
        out += "Swatches: " + model.allColors.map(\.hexString).joined(separator: " ") + "\n"
        guard let box = model.contentBounds else { return out + "The canvas is empty." }
        out += "Art covers x \(box.x) to \(box.maxX - 1), y \(box.y) to \(box.maxY - 1) (\(box.width) × \(box.height)).\n"
        guard box.width <= 160, box.height <= 160 else {
            return out + "It's too big to list pixel by pixel here."
        }
        let keys = Array("#abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%&*+=")
        var legend: [RGBA: Character] = [:]
        var rows: [String] = []
        for y in box.y..<box.maxY {
            var row = ""
            for x in box.x..<box.maxX {
                let c = model.pixel(PixelPoint(x: x, y: y))
                if c.isClear { row.append("."); continue }
                if legend[c] == nil { legend[c] = keys[min(legend.count, keys.count - 1)] }
                row.append(legend[c]!)
            }
            rows.append(row)
        }
        out += "Legend: . = empty"
        for (c, ch) in legend.sorted(by: { $0.value < $1.value }) { out += ", \(ch) = \(c.hexString)" }
        out += "\nThis frame (all visible layers), top row first, starting at x \(box.x), y \(box.y):\n"
        return out + rows.joined(separator: "\n")
    }
}
