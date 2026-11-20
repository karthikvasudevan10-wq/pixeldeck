import Foundation

// v2 editing: turning and resizing selections, animation presets, colour adjustments, ramps and
// extra colours, frame holds and loop modes.

/// Which pixels a colour adjustment changes.
enum AdjustScope: String, CaseIterable, Identifiable, Sendable {
    case selection, layer, frame, allFrames
    var id: String { rawValue }
}

extension EditorModel {
    // MARK: Selection: rotate, scale, flip

    var hasSelection: Bool { floating != nil || marquee != nil }

    /// How the lifted selection is currently turned, resized and flipped.
    var selectionTransform: PatchTransform { floating?.transform ?? PatchTransform() }

    /// Turns, resizes or flips the selection around its centre (lifting it first if it's only
    /// outlined). Returns false if there's no selection or the result would not fit.
    @discardableResult
    func setSelectionTransform(_ t: PatchTransform) -> Bool {
        isPlaying = false
        if floating == nil, let m = marquee { lift(m) }
        guard let f = floating else { return false }
        var trial = f
        trial.setTransform(t)
        if let r = trial.opaqueRect(at: trial.offset) {
            promptedThisGesture = false
            guard ensureCovers(r) else { return false }
        }
        // Growing the canvas re-frames the stored selection, so start from that one.
        guard var next = floating else { return false }
        next.setTransform(t)
        floating = next
        if !t.isIdentity || t.flipH || t.flipV { floatingIsMasked = floatingIsMasked || (t.angle.truncatingRemainder(dividingBy: 90) != 0) }
        mutateCurrent { $0 = next.composited() }
        contentKnown = false
        return true
    }

    @discardableResult
    func rotateSelection(by degrees: Double) -> Bool {
        var t = selectionTransform
        t.angle = (t.angle + degrees).truncatingRemainder(dividingBy: 360)
        return setSelectionTransform(t)
    }

    @discardableResult
    func flipSelection(horizontal: Bool) -> Bool {
        var t = selectionTransform
        if horizontal { t.flipH.toggle() } else { t.flipV.toggle() }
        return setSelectionTransform(t)
    }

    /// Selects everything drawn on the active layer of this frame.
    func selectAll() {
        commitSelection()
        guard let r = currentLayerGrid.opaqueBounds else { return }
        if tool != .select { tool = .select }
        marquee = r.offsetBy(bounds.origin)
    }

    /// The selected pixels (world), whatever state the selection is in.
    var selectedMask: SelectionMask? {
        if let f = floating { return f.currentMask }
        if let m = marqueeMask { return m }
        return marquee.map { SelectionMask(rect: $0) }
    }

    // MARK: Animation presets

    /// The subject of a preset on a cel: the selected pixels, or the whole cel. Grids are local to
    /// `origin`.
    private func presetParts(cel: PixelGrid, origin: PixelPoint, mask: SelectionMask?) -> (subject: PixelGrid, background: PixelGrid) {
        guard let mask else { return (cel, PixelGrid(width: cel.width, height: cel.height)) }
        var subject = PixelGrid(width: cel.width, height: cel.height)
        var background = cel
        for p in mask.points {
            let l = p - origin
            subject[l] = cel[l]
            background[l] = .clear
        }
        return (subject, background)
    }

    /// World rectangle a preset would reach, or nil when there's nothing to animate.
    private func presetExtent(_ preset: AnimationPreset, amount: Int, mask: SelectionMask?) -> PixelRect? {
        let parts = presetParts(cel: currentLayerGrid, origin: bounds.origin, mask: mask)
        guard let art = parts.subject.opaqueBounds else { return nil }
        return AnimationPresets.extent(preset, of: art, amount: amount).offsetBy(bounds.origin)
    }

    /// What the preset would draw: every frame, with all visible layers. Changes nothing.
    func presetPreview(_ preset: AnimationPreset, frames count: Int, amount: Int) -> [PixelGrid] {
        let mask = selectedMask
        guard let reach = presetExtent(preset, amount: amount, mask: mask) else { return [] }
        let big = bounds.union(reach)
        let template = project.frames[currentIndex]
        let cels = template.layers.map { $0.reframed(from: bounds, to: big) }
        // A floating selection is already drawn into the cel at its current place.
        let parts = presetParts(cel: cels[activeLayer], origin: big.origin, mask: mask)
        let visible = project.layerVisibility
        return AnimationPresets.frames(preset, subject: parts.subject, background: parts.background, count: count, amount: amount).map { g in
            var c = cels
            c[activeLayer] = g
            return Frame(layers: c, visible: visible).grid
        }
    }

    /// Draws the preset's frames: the current frame becomes the first, and the rest are inserted
    /// after it (other layers are copied, so a background stays put). One undo step.
    @discardableResult
    func applyPreset(_ preset: AnimationPreset, frames count: Int, amount: Int) -> Bool {
        isPlaying = false
        guard access.allows(preset) else {
            onProRequired?(.animationPresets)
            return false
        }
        let n = min(max(count, AnimationPreset.frameRange.lowerBound), AnimationPreset.frameRange.upperBound)
        let mask = selectedMask
        commitSelection()
        guard let reach = presetExtent(preset, amount: amount, mask: mask) else { return false }
        guard hasRoom(forFrames: n - 1) else { return false }
        promptedThisGesture = false
        guard ensureCovers(reach) else { return false }
        pushUndo()
        let parts = presetParts(cel: currentLayerGrid, origin: bounds.origin, mask: mask)
        let grids = AnimationPresets.frames(preset, subject: parts.subject, background: parts.background, count: n, amount: amount)
        let template = project.frames[currentIndex]
        let visible = project.layerVisibility
        mutateCurrent { $0 = grids[0] }
        let added = grids.dropFirst().map { g -> Frame in
            var cels = template.layers
            cels[activeLayer] = g
            return Frame(layers: cels, visible: visible)
        }
        project.frames.insert(contentsOf: added, at: currentIndex + 1)
        contentKnown = false
        finishEdit()
        return true
    }

    // MARK: Colours beyond the ten swatches

    /// The swatches plus any extra colours (ramps, photo colours, adjusted colours).
    var allColors: [RGBA] { project.palette + project.extraColors }

    /// Adds colours to the sprite's extra colours, skipping ones it already has. Returns how many
    /// were added.
    @discardableResult
    func addColors(_ colors: [RGBA]) -> Int {
        var have = Set(allColors)
        var fresh: [RGBA] = []
        for c in colors {
            let o = RGBA(r: c.r, g: c.g, b: c.b, a: 255)
            if have.insert(o).inserted { fresh.append(o) }
        }
        let room = SpriteProject.maxExtraColors - project.extraColors.count
        let adding = Array(fresh.prefix(max(0, room)))
        guard !adding.isEmpty else { return 0 }
        updateProject { $0.extraColors += adding }
        return adding.count
    }

    func removeExtraColor(_ c: RGBA) {
        guard project.extraColors.contains(c) else { return }
        updateProject { $0.extraColors.removeAll { $0 == c } }
    }

    /// Adds the ramp for `base` (with the current steps and hue shift) to the extra colours.
    @discardableResult
    func addRampToPalette(from base: RGBA) -> Int {
        addColors(ramp(for: base))
    }

    /// How many times each colour is used, across every frame and layer.
    var colorHistogram: [RGBA: Int] {
        ColorTools.histogram(project.frames.flatMap(\.layers))
    }

    /// Merges colours that look almost the same into the most-used one of each group, in every
    /// frame and layer. One undo step. Returns how many colours were merged away.
    @discardableResult
    func mergeSimilarColors() -> Int {
        let plan = ColorTools.mergePlan(colorHistogram)
        guard !plan.isEmpty else { return 0 }
        isPlaying = false
        commitSelection()
        pushUndo()
        let visible = project.layerVisibility
        for i in project.frames.indices {
            let cels = project.frames[i].layers.map { $0.mappingColors { plan[$0] ?? $0 } }
            project.frames[i].setLayers(cels, visible: visible)
        }
        finishEdit()
        return plan.count
    }

    // MARK: Adjust colours

    var isAdjusting: Bool { adjustBase != nil }

    /// Starts a colour adjustment: remembers the art, and which pixels are selected.
    func beginAdjustment() {
        isPlaying = false
        let mask = selectedMask
        commitSelection()
        adjustMask = mask
        if let mask {
            // Keep the outline on screen while adjusting.
            marqueeMask = mask
            marquee = mask.rect
        }
        adjustBase = snapshot()
    }

    /// The scopes that make sense right now ("Selection" needs a selection).
    var adjustScopes: [AdjustScope] { adjustMask == nil ? [.layer, .frame, .allFrames] : AdjustScope.allCases }

    private func adjustMapping(_ adj: ColorAdjustment, snap: Bool) -> (RGBA) -> RGBA {
        let colors = allColors
        var cache: [RGBA: RGBA] = [:]
        return { c in
            if let hit = cache[c] { return hit }
            var out = adj.apply(to: c)
            if snap, !colors.isEmpty { out = out.nearest(in: colors) }
            cache[c] = out
            return out
        }
    }

    /// Applies `adj` to `frames` of the remembered art. Returns the colours that result.
    private func applyAdjustment(_ adj: ColorAdjustment, scope: AdjustScope, snap: Bool, base: Snapshot, allFrames: Bool) -> Set<RGBA> {
        project.frames = base.frames
        guard !adj.isIdentity || snap else { return [] }
        let map = adjustMapping(adj, snap: snap)
        var produced = Set<RGBA>()
        let record: (RGBA) -> RGBA = { c in
            let out = map(c)
            if out != c { produced.insert(out) }
            return out
        }
        let visible = project.layerVisibility
        let o = bounds.origin
        switch scope {
        case .selection:
            guard let mask = adjustMask else { return [] }
            mutateCurrent { g in
                for p in mask.points {
                    let c = g[p - o]
                    if !c.isClear { g[p - o] = record(c) }
                }
            }
        case .layer:
            mutateCurrent { $0 = $0.mappingColors(record) }
        case .frame, .allFrames:
            let indices = scope == .allFrames && allFrames ? Array(project.frames.indices) : [currentIndex]
            for i in indices {
                project.frames[i].setLayers(project.frames[i].layers.map { $0.mappingColors(record) }, visible: visible)
            }
        }
        return produced
    }

    /// Shows the adjustment on the canvas without saving it ("All frames" previews this frame).
    /// Returns how many colours it would add to the sprite's colours (0 when snapping).
    @discardableResult
    func previewAdjustment(_ adj: ColorAdjustment, scope: AdjustScope, snapToPalette: Bool) -> Int {
        guard let base = adjustBase else { return 0 }
        let produced = applyAdjustment(adj, scope: scope, snap: snapToPalette, base: base, allFrames: false)
        return produced.subtracting(allColors).count
    }

    /// Makes the adjustment real: one undo step. Without snapping, the new colours join the
    /// sprite's extra colours. "All frames" needs Pro.
    @discardableResult
    func commitAdjustment(_ adj: ColorAdjustment, scope: AdjustScope, snapToPalette: Bool) -> Bool {
        guard let base = adjustBase else { return false }
        if scope == .allFrames && !access.allowsAdjustAllFrames {
            project.frames = base.frames
            onProRequired?(.adjustAllFrames)
            return false
        }
        let produced = applyAdjustment(adj, scope: scope, snap: snapToPalette, base: base, allFrames: true)
        adjustBase = nil
        adjustMask = nil
        marquee = nil
        marqueeMask = nil
        guard !produced.isEmpty else { return false }
        pushUndo(base)
        if !snapToPalette {
            let fresh = produced.subtracting(allColors).sorted { $0.luminance < $1.luminance }
            let room = SpriteProject.maxExtraColors - project.extraColors.count
            project.extraColors += fresh.prefix(max(0, room))
        }
        contentKnown = false
        finishEdit()
        return true
    }

    func cancelAdjustment() {
        guard let base = adjustBase else { return }
        project.frames = base.frames
        adjustBase = nil
        adjustMask = nil
        marquee = nil
        marqueeMask = nil
    }

    // MARK: Holds and loop mode

    /// How many beats a frame stays on screen (1–8).
    func setHold(_ beats: Int, at index: Int) {
        guard project.frames.indices.contains(index) else { return }
        let h = min(max(beats, 1), Frame.maxHold)
        guard project.frames[index].hold != h else { return }
        updateProject { $0.frames[index].hold = h }
    }

    func setLoopMode(_ mode: LoopMode) {
        guard mode != project.loopMode else { return }
        updateProject { $0.loopMode = mode }
    }

    /// The frames in the order they play, and for how long.
    var playbackSequence: PlaybackSequence { project.playbackSequence }
}

extension PixelGrid {
    /// A copy with every opaque pixel's colour passed through `f`.
    func mappingColors(_ f: (RGBA) -> RGBA) -> PixelGrid {
        var out = self
        out.withUnsafeMutablePixels { px in
            for i in px.indices where px[i].a != 0 { px[i] = f(px[i]) }
        }
        return out
    }
}
