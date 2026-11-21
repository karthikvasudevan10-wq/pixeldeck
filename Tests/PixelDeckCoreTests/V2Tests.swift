import XCTest
@testable import PixelDeckCore

private func makeModel(access: FeatureAccess = .free) -> EditorModel {
    let m = EditorModel(project: SpriteProject(name: "T"))
    m.access = access
    m.pickColor(.black)
    return m
}

private func tap(_ m: EditorModel, _ x: Double, _ y: Double) {
    m.touchBegan(at: Vec2(x: x, y: y))
    m.touchEnded()
}

private func stroke(_ m: EditorModel, _ points: [(Double, Double)]) {
    m.touchBegan(at: Vec2(x: points[0].0, y: points[0].1))
    for p in points.dropFirst() { m.touchMoved(to: Vec2(x: p.0, y: p.1)) }
    m.touchEnded()
}

private func P(_ x: Int, _ y: Int) -> PixelPoint { PixelPoint(x: x, y: y) }

private func opaqueCount(_ g: PixelGrid) -> Int { g.pixels.filter { !$0.isClear }.count }

/// A filled square of `color` from (x, y), `side` pixels wide, drawn with the shape tool on the
/// model's active layer.
private func drawBlock(_ m: EditorModel, x: Int, y: Int, side: Int, color: RGBA) {
    m.pickColor(color)
    m.pixelPerfect = false
    for row in 0..<side {
        stroke(m, [(Double(x) + 0.5, Double(y + row) + 0.5), (Double(x + side - 1) + 0.5, Double(y + row) + 0.5)])
    }
    m.pixelPerfect = true
}

final class ColorMathTests: XCTestCase {
    func testHSLRoundTrip() {
        for hex: UInt32 in [0xFF5C8A, 0x3A86FF, 0x7BE07B, 0x1B1530, 0xFFFFFF, 0x000000, 0x808080] {
            let c = RGBA(hex: hex)
            let back = RGBA(hsl: c.hsl)
            XCTAssertLessThanOrEqual(abs(Int(back.r) - Int(c.r)), 1)
            XCTAssertLessThanOrEqual(abs(Int(back.g) - Int(c.g)), 1)
            XCTAssertLessThanOrEqual(abs(Int(back.b) - Int(c.b)), 1)
        }
    }

    func testRampRunsDarkToLightAndKeepsTheBase() {
        let base = RGBA(hex: 0x3A86FF)
        for steps in ColorRamp.stepRange {
            let ramp = ColorRamp.make(from: base, steps: steps)
            XCTAssertEqual(ramp.count, steps)
            XCTAssertTrue(ramp.contains(base))
            XCTAssertEqual(Set(ramp).count, steps, "no repeated colours")
            for i in 1..<ramp.count { XCTAssertLessThan(ramp[i - 1].luminance, ramp[i].luminance) }
        }
    }

    func testRampShiftsHue() {
        let base = RGBA(hex: 0x3A86FF)
        let flat = ColorRamp.make(from: base, steps: 5, hueShift: 0)
        let shifted = ColorRamp.make(from: base, steps: 5, hueShift: 30)
        XCTAssertEqual(flat.first!.hsl.h, base.hsl.h, accuracy: 0.02)
        XCTAssertNotEqual(shifted.first!.hsl.h, base.hsl.h, accuracy: 0.02)
    }

    func testAdjustmentKeepsRelationships() {
        let dark = RGBA(hex: 0x224466), light = RGBA(hex: 0x88AACC)
        // A hue turn doesn't change how light each pixel is.
        let hue = ColorAdjustment(hue: 120)
        XCTAssertEqual(hue.apply(to: dark).hsl.l, dark.hsl.l, accuracy: 0.02)
        XCTAssertEqual(hue.apply(to: light).hsl.l, light.hsl.l, accuracy: 0.02)
        XCTAssertNotEqual(hue.apply(to: dark), dark)
        // Brightening keeps the order and the hue.
        let bright = ColorAdjustment(brightness: 30)
        XCTAssertLessThan(bright.apply(to: dark).luminance, bright.apply(to: light).luminance)
        XCTAssertGreaterThan(bright.apply(to: dark).luminance, dark.luminance)
        XCTAssertEqual(bright.apply(to: dark).hsl.h, dark.hsl.h, accuracy: 0.02)
        // Nothing changes transparent pixels, and no change is no change.
        XCTAssertEqual(bright.apply(to: .clear), .clear)
        XCTAssertEqual(ColorAdjustment().apply(to: dark), dark)
        // Saturation down to nothing is grey.
        let grey = ColorAdjustment(saturation: -100).apply(to: dark)
        XCTAssertEqual(grey.r, grey.g)
        XCTAssertEqual(grey.g, grey.b)
    }

    func testMergePlanFoldsNearDuplicatesIntoTheMostUsed() {
        let a = RGBA(hex: 0x3A86FF), nearA = RGBA(hex: 0x3B87FE), other = RGBA(hex: 0xFF5C8A)
        let plan = ColorTools.mergePlan([a: 10, nearA: 2, other: 5])
        XCTAssertEqual(plan, [nearA: a])
    }
}

final class PixelPerfectTests: XCTestCase {
    func testCornerDetection() {
        XCTAssertTrue(PixelPerfect.isCorner(P(0, 0), P(1, 0), P(1, 1)))
        XCTAssertFalse(PixelPerfect.isCorner(P(0, 0), P(1, 0), P(2, 0)))
        XCTAssertFalse(PixelPerfect.isCorner(P(0, 0), P(1, 1), P(2, 2)))
        XCTAssertEqual(PixelPerfect.clean([P(0, 0), P(1, 0), P(1, 1), P(2, 1), P(2, 2)]), [P(0, 0), P(1, 1), P(2, 2)])
    }

    func testStaircaseStrokeBecomesADiagonal() {
        let m = makeModel()
        XCTAssertTrue(m.pixelPerfect, "on by default")
        stroke(m, [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5), (2.5, 1.5), (2.5, 2.5)])
        XCTAssertEqual(opaqueCount(m.currentGrid), 3)
        for i in 0...2 { XCTAssertEqual(m.pixel(P(i, i)), .black) }
        XCTAssertTrue(m.pixel(P(1, 0)).isClear)
        m.undo()
        XCTAssertTrue(m.currentGrid.isBlank)
    }

    func testCleaningPutsBackWhatWasUnderneath() {
        let m = makeModel()
        m.pickColor(.white)
        tap(m, 1.5, 0.5)
        m.pickColor(.black)
        stroke(m, [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5)])
        XCTAssertEqual(m.pixel(P(1, 0)), .white, "the corner goes back to the white pixel, not to nothing")
    }

    func testOffKeepsEveryPixel() {
        let m = makeModel()
        m.pixelPerfect = false
        stroke(m, [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5)])
        XCTAssertEqual(opaqueCount(m.currentGrid), 3)
    }

    func testBigBrushesAreLeftAlone() {
        let m = makeModel()
        m.brushSize = 2
        XCTAssertFalse(m.pixelPerfectActive)
    }

    func testMirroredStrokeIsCleanedOnBothSides() {
        let m = makeModel()
        m.mirror = true
        stroke(m, [(2.5, 0.5), (3.5, 0.5), (3.5, 1.5)])
        XCTAssertEqual(opaqueCount(m.currentGrid), 4)
        XCTAssertTrue(m.pixel(P(3, 0)).isClear)
        XCTAssertTrue(m.pixel(P(3, 0).mirrored).isClear)
    }
}

final class ShadingTests: XCTestCase {
    func testDepthFollowsTheLight() {
        let r = PixelRect(x: 0, y: 0, width: 9, height: 9)
        XCTAssertEqual(Shading.depth(of: P(0, 0), in: r, light: .topLeft), 0, accuracy: 1e-9)
        XCTAssertEqual(Shading.depth(of: P(8, 8), in: r, light: .topLeft), 1, accuracy: 1e-9)
        XCTAssertEqual(Shading.depth(of: P(4, 4), in: r, light: .topLeft), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Shading.depth(of: P(8, 0), in: r, light: .left), 1, accuracy: 1e-9)
        XCTAssertEqual(Shading.depth(of: P(3, 0), in: r, light: .top), 0, accuracy: 1e-9)
    }

    func testShadeBrushDarkensTheFarSideOnly() {
        let m = makeModel()
        let purple = RGBA(hex: 0xC8B6FF)
        drawBlock(m, x: 0, y: 0, side: 9, color: purple)
        m.shadeMode = .shade
        m.lightDirection = .topLeft
        m.brushSize = 4
        // Scrub over the whole block.
        var path: [(Double, Double)] = []
        for y in stride(from: 0.5, through: 8.5, by: 1) { path += [(0.5, y), (8.5, y)] }
        stroke(m, path)
        let ramp = m.ramp(for: purple)
        XCTAssertEqual(m.pixel(P(0, 0)), purple, "the lit corner keeps the base colour")
        XCTAssertEqual(m.pixel(P(8, 8)), ramp[0], "the far corner takes the darkest step")
        XCTAssertLessThan(m.pixel(P(8, 8)).luminance, m.pixel(P(6, 6)).luminance + 1e-9)
        XCTAssertTrue(Set(m.currentGrid.pixels.filter { !$0.isClear }).isSubset(of: Set(ramp)))
        XCTAssertEqual(opaqueCount(m.currentGrid), 81, "shading never adds or removes pixels")
        // One undo step.
        m.undo()
        XCTAssertEqual(m.pixel(P(8, 8)), purple)
    }

    func testHighlightLightensTheNearSideAndKeepsShadows() {
        let m = makeModel()
        let green = RGBA(hex: 0x2E9E5B)
        drawBlock(m, x: 0, y: 0, side: 9, color: green)
        m.brushSize = 4
        var path: [(Double, Double)] = []
        for y in stride(from: 0.5, through: 8.5, by: 1) { path += [(0.5, y), (8.5, y)] }
        m.shadeMode = .shade
        stroke(m, path)
        let shadow = m.pixel(P(8, 8))
        m.pickColor(green)
        m.shadeMode = .highlight
        stroke(m, path)
        let ramp = m.ramp(for: green)
        XCTAssertEqual(m.pixel(P(0, 0)), ramp.last, "the lit corner takes the lightest step")
        XCTAssertEqual(m.pixel(P(8, 8)), shadow, "shadows are left alone")
    }

    func testShadingIgnoresOtherColoursAndEmptySpace() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 4, color: RGBA(hex: 0xFF5C8A))
        m.pickColor(.black)
        m.pixelPerfect = false
        tap(m, 1.5, 1.5)                                    // a black eye
        m.shadeMode = .shade
        let before = m.currentGrid
        tap(m, 20.5, 20.5)                                  // empty space: nothing happens
        XCTAssertEqual(m.currentGrid, before)
        XCTAssertFalse(m.canRedo)
        stroke(m, [(3.5, 3.5), (0.5, 0.5)])
        XCTAssertEqual(m.pixel(P(1, 1)), .black, "the eye isn't part of the ramp")
    }
}

final class SelectionToolTests: XCTestCase {
    func testLassoSelectsInsideThePath() {
        let mask = SelectionMask.lasso([P(0, 0), P(4, 0), P(4, 4), P(0, 4)])!
        XCTAssertEqual(mask.count, 25)
        let tri = SelectionMask.lasso([P(0, 0), P(6, 0), P(0, 6)])!
        XCTAssertTrue(tri.contains(P(1, 1)))
        XCTAssertFalse(tri.contains(P(5, 5)))
    }

    func testWandPicksTouchingPixelsOfOneColour() {
        var g = PixelGrid(width: 6, height: 4)
        for x in 0..<3 { g[x, 1] = .black }
        g[4, 1] = .black                                    // same colour, not touching
        g[1, 2] = .white
        let mask = SelectionMask.wand(in: g, at: P(0, 1), origin: P(10, 10))!
        XCTAssertEqual(mask.count, 3)
        XCTAssertEqual(mask.rect, PixelRect(x: 10, y: 11, width: 3, height: 1))
        XCTAssertNil(SelectionMask.wand(in: g, at: P(5, 3), origin: .zero))
    }

    func testOutlineOfASquareHasItsPerimeter() {
        XCTAssertEqual(SelectionMask(rect: PixelRect(x: 0, y: 0, width: 3, height: 2)).outline().count, 10)
    }

    func testLassoMovesOnlyTheCircledPixels() {
        let m = makeModel()
        m.pixelPerfect = false
        stroke(m, [(0.5, 0.5), (5.5, 0.5)])                 // a row of 6
        m.tool = .select
        m.selectionMode = .lasso
        stroke(m, [(-0.5, -0.5), (2.5, -0.5), (2.5, 1.5), (-0.5, 1.5)])   // around the first three
        XCTAssertNotNil(m.marqueeMask)
        stroke(m, [(1.5, 0.5), (1.5, 5.5)])                 // drag them down 5
        m.commitSelection()
        for x in 0...2 {
            XCTAssertTrue(m.pixel(P(x, 0)).isClear)
            XCTAssertEqual(m.pixel(P(x, 5)), .black)
        }
        for x in 3...5 { XCTAssertEqual(m.pixel(P(x, 0)), .black) }
    }

    func testWandThenDeleteRemovesOneColourRegion() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 3, color: .black)
        m.pickColor(.white)
        m.pixelPerfect = false
        tap(m, 1.5, 1.5)
        m.tool = .select
        m.selectionMode = .wand
        tap(m, 0.5, 0.5)
        XCTAssertEqual(m.marqueeMask?.count, 8)
        m.deleteSelection()
        XCTAssertEqual(opaqueCount(m.currentGrid), 1)
        XCTAssertEqual(m.pixel(P(1, 1)), .white)
    }

    func testQuarterTurnIsExact() {
        let patch = PixelPatch(width: 3, height: 1, pixels: [.black, .white, .clear])
        let turned = PatchTransform(angle: 90).apply(to: patch)
        XCTAssertEqual(turned.width, 1)
        XCTAssertEqual(turned.height, 3)
        XCTAssertEqual(turned.pixels, [.black, .white, .clear])
        let back = PatchTransform(angle: -90).apply(to: turned)
        XCTAssertEqual(back.pixels, patch.pixels)
        XCTAssertEqual(PatchTransform(flipH: true).apply(to: patch).pixels, [.clear, .white, .black])
        let doubled = PatchTransform(scale: 2).apply(to: patch)
        XCTAssertEqual(doubled.width, 6)
        XCTAssertEqual(doubled.height, 2)
        XCTAssertEqual(doubled.pixels.filter { $0 == .black }.count, 4)
    }

    func testRotatingASelectionKeepsItsCentreAndPixelCount() {
        let m = makeModel()
        m.pixelPerfect = false
        stroke(m, [(0.5, 2.5), (4.5, 2.5)])                 // 5 wide, centred on (2, 2)
        m.tool = .select
        stroke(m, [(0.5, 2.5), (4.5, 2.5)])
        XCTAssertTrue(m.rotateSelection(by: 90))
        m.commitSelection()
        XCTAssertEqual(opaqueCount(m.currentGrid), 5)
        for y in 0...4 { XCTAssertEqual(m.pixel(P(2, y)), .black) }
        m.undo()
        for x in 0...4 { XCTAssertEqual(m.pixel(P(x, 2)), .black) }
    }

    func testScalingASelectionGrowsTheArt() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 2, color: .black)
        m.selectAll()
        var t = m.selectionTransform
        t.scale = 2
        XCTAssertTrue(m.setSelectionTransform(t))
        t.scale = 3
        XCTAssertTrue(m.setSelectionTransform(t), "scaling again starts from the original pixels")
        m.commitSelection()
        XCTAssertEqual(opaqueCount(m.currentGrid), 36)
    }
}

final class ShapeThicknessTests: XCTestCase {
    func testThickRectangleGrowsInwards() {
        let thin = ShapeRaster.points(.rectangle, from: P(0, 0), to: P(9, 9), filled: false, thickness: 1)
        XCTAssertEqual(thin.count, 36)
        let thick = ShapeRaster.points(.rectangle, from: P(0, 0), to: P(9, 9), filled: false, thickness: 2)
        XCTAssertEqual(thick.count, 100 - 36)
        XCTAssertTrue(thick.allSatisfy { (0...9).contains($0.x) && (0...9).contains($0.y) })
        XCTAssertFalse(thick.contains(P(4, 4)))
    }

    func testThickLineAndEllipse() {
        XCTAssertEqual(ShapeRaster.points(.line, from: P(0, 0), to: P(4, 0), filled: false, thickness: 3).count, 7 * 3)
        let ring = Set(ShapeRaster.points(.ellipse, from: P(0, 0), to: P(15, 15), filled: false, thickness: 3))
        let solid = Set(ShapeRaster.points(.ellipse, from: P(0, 0), to: P(15, 15), filled: true))
        XCTAssertTrue(ring.isSubset(of: solid))
        XCTAssertFalse(ring.contains(P(8, 8)))
        XCTAssertTrue(ring.contains(P(8, 2)), "three pixels in from the top")
        XCTAssertFalse(ring.contains(P(8, 4)))
    }

    func testModelDrawsThickShapes() {
        let m = makeModel()
        m.tool = .shape
        m.shapeKind = .rectangle
        m.shapeThickness = 2
        stroke(m, [(0.5, 0.5), (9.5, 9.5)])
        XCTAssertEqual(opaqueCount(m.currentGrid), 64)
        m.shapeThickness = 99
        XCTAssertEqual(m.shapeThickness, 4)
    }
}

final class TimingTests: XCTestCase {
    private func threeFrames() -> EditorModel {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.addKeyframe()
        tap(m, 1.5, 0.5)
        m.addKeyframe()
        tap(m, 2.5, 0.5)
        return m
    }

    func testHoldsStretchAFrame() throws {
        let m = threeFrames()
        m.setHold(3, at: 1)
        XCTAssertEqual(m.frameDurations, [0.125, 0.375, 0.125])
        m.setHold(99, at: 0)
        XCTAssertEqual(m.project.frames[0].hold, Frame.maxHold)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.frames.map(\.hold), [Frame.maxHold, 3, 1])
    }

    func testPingPongPlaysThereAndBack() throws {
        let m = threeFrames()
        m.addKeyframe()
        XCTAssertEqual(m.playbackSequence.frames, [0, 1, 2, 3])
        m.setLoopMode(.pingPong)
        XCTAssertEqual(m.playbackSequence.frames, [0, 1, 2, 3, 2, 1])
        XCTAssertEqual(m.playbackSequence.durations.count, 6)
        XCTAssertTrue(m.playbackSequence.repeats)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.loopMode, .pingPong)
    }

    func testOnceStopsOnTheLastFrame() {
        let m = threeFrames()
        m.setLoopMode(.once)
        let seq = m.playbackSequence
        XCTAssertFalse(seq.repeats)
        XCTAssertEqual(seq.frame(at: 0.13), 1)
        XCTAssertEqual(seq.frame(at: 99), 2)
    }

    func testOnionSkinShowsSeveralFrames() {
        let m = threeFrames()
        m.addKeyframe()
        m.selectFrame(2)
        m.onionBefore = 2
        m.onionAfter = 1
        var st = m.canvasState()
        XCTAssertEqual(st.onionBefore.count, 2)
        XCTAssertEqual(st.onionAfter.count, 1)
        XCTAssertEqual(st.onion, m.project.frames[1].grid)
        XCTAssertEqual(st.onionBefore[1], m.project.frames[0].grid)
        let version = st.onionVersion
        m.selectFrame(0)
        st = m.canvasState()
        XCTAssertTrue(st.onionBefore.isEmpty)
        XCTAssertEqual(st.onionAfter.count, 1)
        XCTAssertNotEqual(st.onionVersion, version)
        m.onionBefore = 9
        XCTAssertEqual(m.onionBefore, EditorModel.maxOnionBefore)
        m.onionSkinEnabled = false
        XCTAssertNil(m.canvasState().onionVersion)
    }

    func testOnionCompositeFadesAndColours() {
        var a = PixelGrid(width: 3, height: 1), b = PixelGrid(width: 3, height: 1), c = PixelGrid(width: 3, height: 1)
        a[0, 0] = .white
        b[1, 0] = .white
        c[2, 0] = .white
        let out = OnionSkin.composite(before: [a, b], after: [c])!
        XCTAssertEqual(out[0, 0].a, 255, "the previous frame is solid")
        XCTAssertLessThan(out[1, 0].a, 255, "older frames fade")
        XCTAssertGreaterThan(out[0, 0].r, out[0, 0].b, "pink looks back")
        XCTAssertGreaterThan(out[2, 0].b, out[2, 0].r, "blue looks ahead")
        XCTAssertNil(OnionSkin.composite(before: [], after: []))
    }
}

final class AnimationPresetTests: XCTestCase {
    func testBounceDrawsFramesThatLeaveAndReturn() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 2, color: .black)
        XCTAssertTrue(m.applyPreset(.bounce, frames: 8, amount: 6))
        XCTAssertEqual(m.frameCount, 8)
        XCTAssertEqual(m.currentIndex, 0)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 0), .black, "the first frame is the art as it was")
        XCTAssertEqual(m.pixel(P(0, -6), frame: 4), .black, "the top of the bounce")
        XCTAssertTrue(m.pixel(P(0, 1), frame: 4).isClear)
        for i in 0..<8 { XCTAssertEqual(opaqueCount(m.project.frames[i].grid), 4) }
        m.undo()
        XCTAssertEqual(m.frameCount, 1)
    }

    func testProPresetsAskForPro() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 2, color: .black)
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        XCTAssertFalse(m.applyPreset(.squash, frames: 6, amount: 2))
        XCTAssertEqual(asked, .animationPresets)
        XCTAssertEqual(m.frameCount, 1)
        m.access = .pro
        XCTAssertTrue(m.applyPreset(.squash, frames: 6, amount: 2))
        XCTAssertEqual(m.frameCount, 6)
    }

    func testPresetOnASelectionLeavesTheRestAlone() {
        let m = makeModel(access: .pro)
        m.pixelPerfect = false
        tap(m, 0.5, 0.5)
        tap(m, 5.5, 0.5)
        m.tool = .select
        stroke(m, [(0.5, 0.5), (0.5, 0.5)])                 // select just the first pixel
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchCancelled()
        XCTAssertFalse(m.presetPreview(.shake, frames: 4, amount: 2).isEmpty)
        XCTAssertTrue(m.applyPreset(.shake, frames: 4, amount: 2))
        XCTAssertEqual(m.frameCount, 4)
        for i in 0..<4 { XCTAssertEqual(m.pixel(P(5, 0), frame: i), .black) }
        XCTAssertEqual(m.pixel(P(2, 0), frame: 1), .black)
        XCTAssertTrue(m.pixel(P(0, 0), frame: 1).isClear)
    }

    func testFreeFrameLimitStillApplies() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        XCTAssertFalse(m.applyPreset(.bounce, frames: 20, amount: 2))
        XCTAssertEqual(m.frameCount, 1)
    }

    func testColourCycleComesBackToTheStart() {
        var g = PixelGrid(width: 2, height: 1)
        g[0, 0] = RGBA(hex: 0xFF5C8A)
        let frames = AnimationPresets.frames(.colorCycle, subject: g, background: PixelGrid(width: 2, height: 1), count: 4, amount: 1)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[0], g)
        XCTAssertNotEqual(frames[2][0, 0], g[0, 0])
    }

    func testBlinkClosesTheEyes() {
        // A face: a 7 × 7 skin block with two 1 × 2 dark eyes.
        let skin = RGBA(hex: 0xE8B48A)
        var g = PixelGrid(width: 9, height: 9)
        for y in 1...7 { for x in 1...7 { g[x, y] = skin } }
        for y in 3...4 { g[3, y] = .black; g[5, y] = .black }
        let frames = AnimationPresets.frames(.blink, subject: g, background: PixelGrid(width: 9, height: 9), count: 8, amount: 1)
        XCTAssertEqual(frames[0], g)
        XCTAssertEqual(frames[7], g)
        XCTAssertEqual(frames[5][3, 3], skin, "the top of the eye is covered")
        XCTAssertEqual(frames[5][3, 4], .black, "a line is left for the closed eye")
        XCTAssertEqual(frames[5][5, 3], skin)
    }
}

final class AdjustColoursTests: XCTestCase {
    func testAdjustingASelectionChangesOnlyIt() {
        let m = makeModel()
        let pink = RGBA(hex: 0xFF5C8A)
        drawBlock(m, x: 0, y: 0, side: 4, color: pink)
        m.tool = .select
        stroke(m, [(0.5, 0.5), (1.5, 3.5)])                 // the left half
        m.beginAdjustment()
        XCTAssertEqual(m.adjustScopes.first, .selection)
        let adj = ColorAdjustment(hue: 120)
        XCTAssertEqual(m.previewAdjustment(adj, scope: .selection, snapToPalette: false), 1)
        XCTAssertNotEqual(m.pixel(P(0, 0)), pink, "the preview shows on the canvas")
        XCTAssertFalse(m.canRedo)
        m.cancelAdjustment()
        XCTAssertEqual(m.pixel(P(0, 0)), pink, "cancel puts it back")

        m.tool = .select
        stroke(m, [(0.5, 0.5), (1.5, 3.5)])
        m.beginAdjustment()
        m.previewAdjustment(adj, scope: .selection, snapToPalette: false)
        XCTAssertTrue(m.commitAdjustment(adj, scope: .selection, snapToPalette: false))
        let changed = m.pixel(P(0, 0))
        XCTAssertNotEqual(changed, pink)
        XCTAssertEqual(m.pixel(P(3, 3)), pink)
        XCTAssertEqual(m.project.extraColors, [changed], "the new colour joins the sprite's colours")
        m.undo()
        XCTAssertEqual(m.pixel(P(0, 0)), pink, "one undo step")
    }

    func testSnapToPaletteAddsNoColours() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 2, color: RGBA(hex: 0xFF5C8A))
        m.beginAdjustment()
        XCTAssertFalse(m.adjustScopes.contains(.selection))
        let adj = ColorAdjustment(hue: 100)
        XCTAssertEqual(m.previewAdjustment(adj, scope: .layer, snapToPalette: true), 0)
        m.commitAdjustment(adj, scope: .layer, snapToPalette: true)
        XCTAssertTrue(m.palette.contains(m.pixel(P(0, 0))))
        XCTAssertTrue(m.project.extraColors.isEmpty)
    }

    func testAllFramesNeedsPro() {
        let m = makeModel()
        let pink = RGBA(hex: 0xFF5C8A)
        drawBlock(m, x: 0, y: 0, side: 2, color: pink)
        m.duplicateFrame(at: 0)
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        m.beginAdjustment()
        XCTAssertFalse(m.commitAdjustment(ColorAdjustment(brightness: 40), scope: .allFrames, snapToPalette: false))
        XCTAssertEqual(asked, .adjustAllFrames)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 0), pink)
        m.access = .pro
        m.beginAdjustment()
        XCTAssertTrue(m.commitAdjustment(ColorAdjustment(brightness: 40), scope: .allFrames, snapToPalette: false))
        XCTAssertNotEqual(m.pixel(P(0, 0), frame: 0), pink)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 0), m.pixel(P(0, 0), frame: 1))
    }

    func testRampJoinsThePaletteOnce() throws {
        let m = makeModel()
        let blue = RGBA(hex: 0x3A86FF)
        XCTAssertEqual(m.addRampToPalette(from: blue), 4, "five steps, and the base is already a swatch")
        XCTAssertEqual(m.addRampToPalette(from: blue), 0)
        XCTAssertEqual(m.allColors.count, 14)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.extraColors, m.project.extraColors)
    }

    func testMergeSimilarColours() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 3, color: RGBA(hex: 0x3A86FF))
        m.pickColor(RGBA(hex: 0x3B87FE))
        m.pixelPerfect = false
        tap(m, 1.5, 1.5)
        XCTAssertEqual(m.colorHistogram.count, 2)
        XCTAssertEqual(m.mergeSimilarColors(), 1)
        XCTAssertEqual(m.colorHistogram, [RGBA(hex: 0x3A86FF): 9])
        m.undo()
        XCTAssertEqual(m.colorHistogram.count, 2)
    }
}

final class PhotoPixelizerTests: XCTestCase {
    /// A 64 × 64 "photo": left half red, right half blue, with one stray green pixel block.
    private func photo() -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: 64 * 64 * 4)
        for y in 0..<64 {
            for x in 0..<64 {
                let i = (y * 64 + x) * 4
                bytes[i] = x < 32 ? 220 : 20
                bytes[i + 1] = 30
                bytes[i + 2] = x < 32 ? 30 : 200
            }
        }
        return bytes
    }

    func testShrinksAndReducesColours() {
        var o = PhotoOptions()
        o.size = 32
        o.colorCount = 2
        let out = PhotoPixelizer.convert(rgba: photo(), width: 64, height: 64, options: o, palette: [])!
        XCTAssertEqual(out.grid.width, 32)
        XCTAssertEqual(out.grid.height, 32)
        XCTAssertEqual(out.colors.count, 2)
        XCTAssertEqual(Set(out.grid.pixels).count, 2)
        XCTAssertGreaterThan(out.grid[0, 0].r, out.grid[0, 0].b)
        XCTAssertGreaterThan(out.grid[31, 0].b, out.grid[31, 0].r)
    }

    func testKeepsTheShapeOfWidePhotos() {
        let bytes = [UInt8](repeating: 128, count: 100 * 50 * 4)
        var o = PhotoOptions()
        o.size = 48
        let out = PhotoPixelizer.convert(rgba: bytes, width: 100, height: 50, options: o, palette: [])!
        XCTAssertEqual(out.grid.width, 48)
        XCTAssertEqual(out.grid.height, 24)
    }

    func testUsesMyPaletteOrARetroMode() {
        var o = PhotoOptions()
        o.colors = .palette
        let mine = [RGBA.black, RGBA.white]
        let out = PhotoPixelizer.convert(rgba: photo(), width: 64, height: 64, options: o, palette: mine)!
        XCTAssertTrue(Set(out.grid.pixels).isSubset(of: Set(mine)))
        o.colors = .retro
        o.retro = .handheld
        o.dither = true
        let retro = PhotoPixelizer.convert(rgba: photo(), width: 64, height: 64, options: o, palette: mine)!
        XCTAssertTrue(Set(retro.grid.pixels).isSubset(of: Set(RetroMode.handheld.colors)))
    }

    func testCleanUpRemovesLonePixels() {
        var g = PixelGrid(width: 5, height: 5, fill: .white)
        g[2, 2] = .black
        XCTAssertEqual(PhotoPixelizer.cleanedUp(g)[2, 2], .white)
        g[2, 3] = .black
        XCTAssertEqual(PhotoPixelizer.cleanedUp(g)[2, 2], .black, "pairs are kept")
    }

    func testOutlineInksStrongEdges() {
        var g = PixelGrid(width: 4, height: 1, fill: .white)
        g[0, 0] = RGBA(hex: 0x333333)
        g[1, 0] = RGBA(hex: 0x333333)
        let out = PhotoPixelizer.outlined(g, ink: .black)
        XCTAssertEqual(out[1, 0], .black, "the dark side of the edge")
        XCTAssertEqual(out[0, 0], RGBA(hex: 0x333333))
        XCTAssertEqual(out[2, 0], .white)
    }

    func testMedianCutFindsTheMainColours() {
        let px = Array(repeating: RGBA(hex: 0xFF0000), count: 50) + Array(repeating: RGBA(hex: 0x0000FF), count: 50)
        XCTAssertEqual(Set(PhotoPixelizer.medianCut(px, count: 2)), [RGBA(hex: 0xFF0000), RGBA(hex: 0x0000FF)])
        XCTAssertEqual(PhotoPixelizer.medianCut(px, count: 8).count, 2, "never more colours than there are")
    }
}

// MARK: v2.1

final class RetroModeTests: XCTestCase {
    func testRetroCanvasLocksItsPalette() throws {
        let p = SpriteProject.retro(name: "R", mode: .handheld)
        XCTAssertEqual(p.palette, RetroMode.handheld.colors)
        XCTAssertFalse(p.isBlank, "a retro canvas isn't reused as a plain new canvas")
        let m = EditorModel(project: p)
        XCTAssertTrue(m.isPaletteLocked)
        m.setPaletteColor(.white, at: 0)
        XCTAssertEqual(m.palette, RetroMode.handheld.colors)
        m.applyPalette(SpriteProject.defaultPalette)
        XCTAssertEqual(m.palette, RetroMode.handheld.colors)
        // Dither is free here.
        m.dither = true
        XCTAssertTrue(m.dither)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.retroMode, .handheld)
        XCTAssertEqual(back.palette.count, 4)
    }

    func testOrdinaryCanvasesStillNeedProForDither() {
        let m = makeModel()
        m.dither = true
        XCTAssertFalse(m.dither)
    }
}

final class TileSceneTests: XCTestCase {
    func testStarterTilesAreSixteenPixelsSquare() {
        let tiles = StarterTiles.tiles
        XCTAssertEqual(tiles.count, 8)
        for t in tiles {
            XCTAssertEqual(t.grid.width, TileScene.tileSize)
            XCTAssertEqual(t.grid.height, TileScene.tileSize)
            XCTAssertFalse(t.grid.isBlank)
        }
        XCTAssertTrue(tiles.first { $0.name == "brick" }!.solid)
        XCTAssertTrue(tiles.first { $0.name == "water" }!.hazard)
        XCTAssertEqual(StarterTiles.tiles.map(\.id), tiles.map(\.id), "ids are stable")
    }

    func testPaintFillAndRender() {
        var s = TileScene(name: "S", columns: 6, rows: 4)
        s[0, 3] = 2
        XCTAssertEqual(s[0, 3], 2)
        XCTAssertEqual(s[99, 99], -1)
        s[1, 1] = 999
        XCTAssertEqual(s[1, 1], -1, "unknown tiles are empty")
        s.fill(1, at: PixelPoint(x: 3, y: 0))
        XCTAssertEqual(s[5, 0], 1)
        XCTAssertEqual(s[0, 3], 2, "the fill stops at other tiles")
        let picture = s.rendered()
        XCTAssertEqual(picture.width, 96)
        XCTAssertEqual(picture.height, 64)
        XCTAssertEqual(picture[0, 3 * 16], s.tiles[2].grid[0, 0])
    }

    func testResizeKeepsTheGround() {
        var s = TileScene.starter(name: "Night hills")
        let groundTile = s[0, s.rows - 1]
        XCTAssertNotEqual(groundTile, -1)
        XCTAssertFalse(s.needsPro)
        let coins = s.coins.count
        s.resize(columns: 40, rows: 16)
        XCTAssertEqual(s.columns, 40)
        XCTAssertEqual(s[0, 15], groundTile, "rows are added at the top")
        XCTAssertEqual(s.coins.count, coins)
        XCTAssertTrue(s.needsPro)
    }

    func testSceneStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scenes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SceneStore(directory: dir)
        var s = TileScene.starter(name: "Night hills")
        s.toggleCoin(at: PixelPoint(x: 0, y: 0))
        store.save(s)
        let again = SceneStore(directory: dir)
        XCTAssertEqual(again.scenes.count, 1)
        XCTAssertEqual(again.scenes[0].coins, s.coins)
        XCTAssertEqual(again.scenes[0].tiles, s.tiles)
        again.delete(id: s.id)
        XCTAssertTrue(SceneStore(directory: dir).scenes.isEmpty)
    }
}

final class PlaygroundTests: XCTestCase {
    /// A flat floor along the bottom row of a 12 × 6 scene, hero starting at column 1.
    private func flat() -> TileScene {
        var s = TileScene(name: "T", columns: 12, rows: 6)
        for x in 0..<12 { s[x, 5] = 1 }
        s.start = PixelPoint(x: 1, y: 4)
        return s
    }

    private func run(_ g: inout PlaygroundGame, seconds: Double, _ input: PlayInput) {
        for _ in 0..<Int(seconds * 60) { g.step(1.0 / 60, input: input) }
    }

    func testHeroStandsOnTheFloor() {
        var g = PlaygroundGame(scene: flat())
        run(&g, seconds: 0.5, PlayInput())
        XCTAssertTrue(g.onGround)
        XCTAssertEqual(g.y + g.heroHeight, 80, accuracy: 0.01)
    }

    func testRunningAndWalls() {
        var s = flat()
        s[6, 4] = 2                                         // a wall on the floor
        var g = PlaygroundGame(scene: s)
        run(&g, seconds: 3, PlayInput(right: true))
        XCTAssertEqual(g.x + g.heroWidth, 96, accuracy: 0.01, "stopped against the wall")
        run(&g, seconds: 3, PlayInput(left: true))
        XCTAssertEqual(g.x, 0, accuracy: 0.01, "the level's edge is a wall too")
        XCTAssertTrue(g.facingLeft)
    }

    func testJumpGoesUpAndComesDown() {
        var g = PlaygroundGame(scene: flat())
        run(&g, seconds: 0.3, PlayInput())
        let ground = g.y
        var top = ground
        var input = PlayInput(jump: true)
        for _ in 0..<90 {
            g.step(1.0 / 60, input: input)
            top = min(top, g.y)
            input.jump = true
        }
        XCTAssertLessThan(top, ground - 32, "clears two tiles")
        XCTAssertGreaterThan(top, ground - 56)
        XCTAssertEqual(g.y, ground, accuracy: 0.01, "holding jump doesn't bounce forever")
        XCTAssertEqual(g.events.filter { $0 == .jump }.count, 1)
    }

    func testCoinsAndWinning() {
        var s = flat()
        s.coins = [PixelPoint(x: 4, y: 4), PixelPoint(x: 7, y: 4)]
        var g = PlaygroundGame(scene: s)
        XCTAssertEqual(g.coinTotal, 2)
        run(&g, seconds: 1, PlayInput(right: true))
        XCTAssertEqual(g.coinsCollected, 1)
        XCTAssertEqual(g.status, .playing)
        run(&g, seconds: 2, PlayInput(right: true))
        XCTAssertEqual(g.status, .won)
        XCTAssertTrue(g.events.contains(.win))
        let t = g.elapsed
        run(&g, seconds: 1, PlayInput(right: true))
        XCTAssertEqual(g.elapsed, t, "the clock stops when you win")
    }

    func testGoalNeedsEveryCoinFirst() {
        var s = flat()
        s.coins = [PixelPoint(x: 9, y: 4)]
        s.goal = PixelPoint(x: 5, y: 4)
        var g = PlaygroundGame(scene: s)
        run(&g, seconds: 1.2, PlayInput(right: true))       // past the flag, no coin yet
        XCTAssertEqual(g.status, .playing)
        run(&g, seconds: 2, PlayInput(right: true))          // the coin
        XCTAssertEqual(g.coinsCollected, 1)
        XCTAssertEqual(g.status, .playing)
        run(&g, seconds: 2, PlayInput(left: true))           // back to the flag
        XCTAssertEqual(g.status, .won)
    }

    func testWaterAndFallingSendYouBack() {
        var s = flat()
        s[5, 5] = -1
        s[6, 5] = -1                                         // a gap
        var g = PlaygroundGame(scene: s)
        run(&g, seconds: 4, PlayInput(right: true))
        XCTAssertGreaterThanOrEqual(g.falls, 1)
        XCTAssertTrue(g.events.contains(.hurt))
        var w = flat()
        let water = w.tiles.firstIndex { $0.hazard }!
        w[4, 4] = water
        var g2 = PlaygroundGame(scene: w)
        run(&g2, seconds: 1.5, PlayInput(right: true))
        XCTAssertGreaterThanOrEqual(g2.falls, 1)
    }

    func testEnemiesPatrolAndHurt() {
        var s = flat()
        s.enemies = [PixelPoint(x: 8, y: 4)]
        var g = PlaygroundGame(scene: s)
        let startX = g.enemies[0].x
        run(&g, seconds: 1, PlayInput())
        XCTAssertNotEqual(g.enemies[0].x, startX)
        run(&g, seconds: 12, PlayInput())                    // it reaches the hero in the end
        XCTAssertGreaterThanOrEqual(g.falls, 1)
    }

    func testStarterLevelCanBeWalkedOnto() {
        var g = PlaygroundGame(scene: TileScene.starter(name: "Night hills"))
        run(&g, seconds: 1, PlayInput())
        XCTAssertTrue(g.onGround)
        XCTAssertEqual(g.falls, 0)
        XCTAssertEqual(g.coinTotal, 5)
    }
}

final class AcademyTests: XCTestCase {
    func testEveryLessonHasFramesThatFitTheFreeCanvas() {
        XCTAssertEqual(Academy.lessons.count, 6)
        XCTAssertEqual(Academy.lessons.filter(\.isFree).map(\.id), ["blink", "walk"])
        for lesson in Academy.lessons {
            XCTAssertGreaterThanOrEqual(lesson.frames.count, 4)
            XCTAssertLessThanOrEqual(lesson.frames.count, FeatureAccess.freeFrameLimit)
            for frame in lesson.frames {
                XCTAssertFalse(frame.isEmpty)
                XCTAssertEqual(Set(frame).count, frame.count, "no repeated squares in \(lesson.id)")
                XCTAssertTrue(frame.allSatisfy { abs($0.x) <= 16 && abs($0.y) <= 16 })
            }
        }
        XCTAssertEqual(Academy.lesson(id: "walk")?.frames.count, 8)
    }

    func testFollowingTheGuideFinishesEachStep() {
        let lesson = Academy.lesson(id: "blink")!
        let m = makeModel()
        m.pixelPerfect = false
        for step in 0..<lesson.frames.count {
            if step > 0 { m.addKeyframe() }
            XCTAssertFalse(Academy.isDone(lesson, step: step, model: m, playCountAtStart: 0))
            for p in Academy.guide(lesson, step: step)! { tap(m, Double(p.x) + 0.5, Double(p.y) + 0.5) }
            XCTAssertTrue(Academy.isDone(lesson, step: step, model: m, playCountAtStart: 0))
        }
        // The last step is pressing Play.
        XCTAssertNil(Academy.guide(lesson, step: lesson.frames.count))
        XCTAssertFalse(Academy.isDone(lesson, step: lesson.frames.count, model: m, playCountAtStart: m.playCount))
        m.isPlaying = true
        XCTAssertTrue(Academy.isDone(lesson, step: lesson.frames.count, model: m, playCountAtStart: m.playCount - 1))
    }

    func testIdeaOfTheDayChangesDailyAndWraps() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let a = DailyIdea.index(for: day, count: 30, calendar: cal)
        let b = DailyIdea.index(for: day.addingTimeInterval(86_400), count: 30, calendar: cal)
        XCTAssertEqual(b, (a + 1) % 30)
        XCTAssertEqual(DailyIdea.index(for: day.addingTimeInterval(3_600), count: 30, calendar: cal), a, "the same all day")
        XCTAssertEqual(DailyIdea.index(for: day, count: 0, calendar: cal), 0)
    }
}

// MARK: v2.2

final class StampTests: XCTestCase {
    func testStarterStamps() {
        let stamps = StarterStamps.stamps
        XCTAssertEqual(stamps.count, 8)
        XCTAssertTrue(stamps.allSatisfy { !$0.grid.isBlank && $0.grid.width <= Stamp.maxSide })
    }

    func testSaveASelectionAndStampItElsewhere() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stamps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = StampLibrary(url: dir.appendingPathComponent("stamps.json"))
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 3, color: .black)
        m.pixelPerfect = false
        tap(m, 10.5, 0.5)                                    // something else, not in the stamp
        m.tool = .select
        stroke(m, [(0.5, 0.5), (2.5, 2.5)])
        let source = try XCTUnwrap(m.stampSource())
        XCTAssertEqual(source.width, 3)
        XCTAssertEqual(opaqueCount(source), 9)
        let stamp = try XCTUnwrap(library.add(name: "  Block  ", grid: source))
        XCTAssertEqual(stamp.name, "Block")
        XCTAssertEqual(StampLibrary(url: library.url).stamps, [stamp], "saved to disk")

        let other = makeModel()
        XCTAssertTrue(other.placeStamp(stamp.grid, at: P(20, 20)))
        XCTAssertNotNil(other.floating, "it arrives as a selection you can move")
        other.commitSelection()
        XCTAssertEqual(opaqueCount(other.currentGrid), 9)
        XCTAssertEqual(other.pixel(P(20, 20)), .black)
        other.undo()
        XCTAssertTrue(other.currentGrid.isBlank)
    }

    func testStampTooBigForTheFreeCanvasIsRefused() {
        let m = makeModel()
        XCTAssertFalse(m.placeStamp(PixelGrid(width: 80, height: 80, fill: .black)))
        XCTAssertNil(m.floating)
    }
}

final class ZlibTests: XCTestCase {
    func testInflatesDynamicAndFixedBlocks() {
        let compressed: [UInt8] = [120, 218, 213, 146, 61, 118, 24, 49, 8, 132, 175, 194, 93, 28, 23, 126, 73, 225, 210, 45, 3, 20, 122, 80, 168, 228, 248, 249, 148, 91, 68, 197, 46, 172, 196, 104, 126, 214, 116, 67, 97, 110, 169, 113, 197, 57, 175, 59, 74, 234, 72, 101, 94, 73, 166, 60, 50, 207, 180, 14, 158, 225, 28, 55, 118, 203, 171, 237, 216, 230, 50, 29, 166, 200, 156, 162, 173, 240, 57, 244, 117, 212, 97, 105, 172, 170, 92, 0, 11, 4, 89, 70, 246, 166, 221, 54, 95, 11, 80, 228, 41, 221, 91, 17, 123, 129, 58, 204, 28, 107, 174, 142, 144, 90, 94, 76, 192, 232, 128, 147, 38, 155, 138, 214, 182, 93, 150, 87, 92, 121, 248, 194, 10, 28, 128, 32, 87, 124, 168, 11, 31, 43, 106, 175, 229, 250, 16, 26, 203, 98, 220, 7, 12, 243, 201, 128, 220, 88, 188, 142, 23, 114, 4, 20, 10, 64, 169, 4, 197, 22, 153, 114, 54, 204, 171, 224, 25, 22, 209, 126, 233, 2, 125, 113, 247, 70, 188, 3, 104, 19, 7, 250, 33, 193, 1, 249, 58, 14, 138, 231, 40, 159, 24, 60, 220, 206, 57, 131, 151, 51, 144, 229, 174, 55, 226, 76, 244, 140, 189, 226, 153, 224, 179, 230, 177, 86, 83, 3, 221, 101, 135, 145, 73, 140, 2, 241, 226, 86, 235, 132, 55, 102, 80, 146, 139, 86, 126, 159, 29, 132, 54, 215, 206, 11, 230, 165, 179, 224, 92, 140, 202, 9, 199, 158, 36, 31, 124, 109, 226, 4, 173, 254, 165, 103, 104, 72, 39, 148, 40, 54, 125, 153, 58, 89, 18, 238, 48, 32, 146, 142, 28, 135, 67, 227, 227, 227, 134, 111, 184, 163, 245, 142, 211, 101, 247, 209, 122, 110, 135, 238, 99, 15, 210, 251, 121, 250, 78, 3, 243, 253, 245, 243, 249, 231, 215, 231, 199, 239, 255, 168, 248, 11, 32, 121, 6, 185]
        let out = Zlib.inflate(compressed)
        XCTAssertEqual(out?.count, 780)
        XCTAssertEqual(Zlib.adler32(out ?? []), 544802489)
        let fixed: [UInt8] = [120, 1, 203, 72, 205, 201, 201, 87, 200, 64, 34, 11, 50, 43, 82, 115, 20, 82, 82, 147, 179, 1, 152, 153, 10, 118]
        XCTAssertEqual(Zlib.inflate(fixed).map { String(decoding: $0, as: UTF8.self) }, "hello hello hello pixel deck")
    }

    func testStoredStreamsRoundTrip() {
        let small: [UInt8] = [1, 2, 3, 250, 0]
        XCTAssertEqual(Zlib.inflate(Zlib.store(small)), small)
        XCTAssertEqual(Zlib.inflate(Zlib.store([])), [])
        let big = (0..<150_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        XCTAssertEqual(Zlib.inflate(Zlib.store(big)), big, "more than one stored block")
    }

    func testDamagedDataFailsInsteadOfCrashing() {
        XCTAssertNil(Zlib.inflate([]))
        XCTAssertNil(Zlib.inflate([0x78, 0x9C, 0xFF, 0xFF, 0xFF]))
        XCTAssertNil(Zlib.inflate([1, 2, 3, 4]))
        var cut = Zlib.store([1, 2, 3, 4, 5])
        cut.removeLast(6)
        XCTAssertNil(Zlib.inflate(cut))
    }
}

final class AsepriteTests: XCTestCase {
    private func sample() -> SpriteProject {
        let m = makeModel()
        m.pixelPerfect = false
        m.pickColor(RGBA(hex: 0xFF5C8A))
        tap(m, 0.5, 0.5)
        tap(m, 3.5, 2.5)
        m.addLayer(named: "Eyes")
        m.pickColor(.black)
        tap(m, 1.5, 1.5)
        m.addKeyframe()
        m.pickColor(RGBA(hex: 0x3A86FF))
        tap(m, 2.5, 0.5)
        m.setHold(2, at: 1)
        m.setFPS(10)
        return m.project
    }

    func testRoundTripKeepsLayersFramesAndTiming() throws {
        let project = sample()
        let file = try Aseprite.parse(Aseprite.encode(project))
        XCTAssertEqual(file.width, 4)
        XCTAssertEqual(file.height, 3)
        XCTAssertEqual(file.layerNames, ["Layer 1", "Eyes"])
        XCTAssertEqual(file.frames.count, 2)
        XCTAssertEqual(file.durations, [100, 200])
        let back = try XCTUnwrap(Aseprite.projects(from: file, name: "Back").first)
        XCTAssertEqual(back.layers.map(\.name), ["Layer 1", "Eyes"])
        XCTAssertEqual(back.fps, 10)
        XCTAssertEqual(back.frames.map(\.hold), [1, 2])
        let area = try XCTUnwrap(project.contentBounds)
        XCTAssertEqual(back.grids(croppedTo: back.bounds), project.grids(croppedTo: area), "every pixel survives")
        XCTAssertEqual(back.frames[0].layers[1].pixels.filter { !$0.isClear }, [.black])
    }

    func testTagsBecomeSeparateSprites() throws {
        var file = try Aseprite.parse(Aseprite.encode(sample()))
        file.tags = [AsepriteFile.Tag(name: "idle", from: 0, to: 0), AsepriteFile.Tag(name: "run", from: 0, to: 1)]
        let sprites = Aseprite.projects(from: file, name: "Knight")
        XCTAssertEqual(sprites.map(\.name), ["Knight idle", "Knight run"])
        XCTAssertEqual(sprites.map(\.frames.count), [1, 2])
        XCTAssertEqual(Aseprite.projects(from: file, name: "Knight", splitTags: false).count, 1)
        let flat = try XCTUnwrap(Aseprite.projects(from: file, name: "Knight", splitTags: false, keepLayers: false).first)
        XCTAssertEqual(flat.layers.count, 1)
        XCTAssertEqual(flat.frames[0].grid, sprites[1].frames[0].grid)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try Aseprite.parse(Data([1, 2, 3]))) { XCTAssertEqual($0 as? AsepriteError, .notAseprite) }
        XCTAssertThrowsError(try Aseprite.parse(Data(repeating: 0, count: 200))) { XCTAssertEqual($0 as? AsepriteError, .notAseprite) }
        var cut = [UInt8](Aseprite.encode(sample()))
        cut.removeLast(20)
        XCTAssertThrowsError(try Aseprite.parse(Data(cut)))
    }
}

final class CraftAndGuideTests: XCTestCase {
    func testBeadPatternCountsAndNames() throws {
        var g = PixelGrid(width: 6, height: 6)
        for x in 1...3 { g[x, 2] = RGBA(hex: 0x7BE07B) }
        g[1, 3] = .black
        let pattern = try XCTUnwrap(BeadPattern(g))
        XCTAssertEqual(pattern.grid.width, 3)
        XCTAssertEqual(pattern.grid.height, 2)
        XCTAssertEqual(pattern.total, 4)
        XCTAssertEqual(pattern.entries.map(\.count), [3, 1])
        XCTAssertEqual(pattern.entries.map(\.name), [.lightGreen, .black])
        XCTAssertEqual(pattern.entries.map(\.symbol), ["A", "B"])
        XCTAssertEqual(pattern.symbol(for: .black), "B")
        XCTAssertNil(BeadPattern(PixelGrid(width: 4, height: 4)))
    }

    func testEverydayColourNames() {
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0xFFFFFF)), .white)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0xFF0000)), .red)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0x3A86FF)), .blue)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0xFFD23F)), .yellow)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0x2E9E5B)), .green)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0x5E3B22)), .brown)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0xFF5C8A)), .pink)
        XCTAssertEqual(BeadName.name(for: RGBA(hex: 0x808080)), .grey)
    }

    func testMotionGuidesStandOnTheGroundAndFitTheirHeight() {
        for guide in MotionGuide.allCases {
            for height in MotionGuides.heights {
                var shapes = Set<[PixelPoint]>()
                for i in 0..<guide.poseCount {
                    let pts = MotionGuides.points(guide, index: i, height: height)
                    XCTAssertFalse(pts.isEmpty)
                    let ys = pts.map(\.y), xs = pts.map(\.x)
                    XCTAssertLessThanOrEqual(ys.max()!, height / 2, "\(guide) \(i): nothing below the ground")
                    XCTAssertGreaterThanOrEqual(ys.min()!, -height, "\(guide) \(i): not wildly tall")
                    XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, height + 4)
                    shapes.insert(pts.sorted { ($0.y, $0.x) < ($1.y, $1.x) })
                }
                XCTAssertGreaterThan(shapes.count, 1, "\(guide): the poses differ")
            }
        }
        XCTAssertEqual(MotionGuides.points(.walk, index: 8, height: 24), MotionGuides.points(.walk, index: 0, height: 24), "poses loop")
    }
}

final class AIToolTests: XCTestCase {
    func testDrawingToolsMakeUndoableSteps() throws {
        let m = makeModel()
        XCTAssertTrue(AITools.describe(m).contains("empty"))
        _ = try AITools.call("rect", ["x1": 0, "y1": 0, "x2": 3, "y2": 3, "color": "#FF5C8A", "filled": true], model: m)
        XCTAssertEqual(opaqueCount(m.currentGrid), 16)
        _ = try AITools.call("set_pixels", ["pixels": [[1, 1, "#000000"], [2, 1, "clear"]]], model: m)
        XCTAssertEqual(m.pixel(P(1, 1)), .black)
        XCTAssertTrue(m.pixel(P(2, 1)).isClear)
        _ = try AITools.call("set_pixels", ["x": 5, "y": 0, "rows": ["ab", ".a"], "legend": ["a": "#3A86FF", "b": "#FFFFFF"]], model: m)
        XCTAssertEqual(m.pixel(P(5, 0)), RGBA(hex: 0x3A86FF))
        XCTAssertEqual(m.pixel(P(6, 0)), .white)
        XCTAssertTrue(m.pixel(P(5, 1)).isClear)
        _ = try AITools.call("line", ["x1": 0, "y1": 6, "x2": 4, "y2": 6, "color": "#000000"], model: m)
        XCTAssertEqual(m.pixel(P(4, 6)), .black)
        let text = try AITools.call("read_canvas", [:], model: m)
        XCTAssertTrue(text.contains("#FF5C8A"))
        XCTAssertTrue(text.contains("x 0 to 6"))
        // Four drawing calls, four undo steps.
        for _ in 0..<4 { _ = try AITools.call("undo", [:], model: m) }
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertThrowsError(try AITools.call("undo", [:], model: m))
    }

    func testFramesLayersAndPalette() throws {
        let m = makeModel()
        _ = try AITools.call("add_layer", ["name": "Castle"], model: m)
        XCTAssertEqual(m.layers.map(\.name), ["Layer 1", "Castle"])
        _ = try AITools.call("rect", ["x1": 0, "y1": 0, "x2": 1, "y2": 0, "color": "#FFD23F"], model: m)
        _ = try AITools.call("add_frame", ["copy": true], model: m)
        XCTAssertEqual(m.frameCount, 2)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 1), RGBA(hex: 0xFFD23F))
        _ = try AITools.call("select_frame", ["frame": 1], model: m)
        XCTAssertEqual(m.currentIndex, 0)
        _ = try AITools.call("set_palette", ["colors": ["#111111", "#222222"]], model: m)
        XCTAssertEqual(m.palette[0], RGBA(hex: 0x111111))
        XCTAssertEqual(m.palette[2], SpriteProject.defaultPalette[2])
        _ = try AITools.call("fill", ["x": 0, "y": 0, "color": "#3A86FF"], model: m)
        XCTAssertEqual(m.pixel(P(1, 0)), RGBA(hex: 0x3A86FF))
        _ = try AITools.call("flip", ["direction": "horizontal"], model: m)
        _ = try AITools.call("set_speed", ["fps": 12], model: m)
        XCTAssertEqual(m.project.fps, 12)
    }

    func testMistakesAreExplainedNotDrawn() {
        let m = makeModel()
        XCTAssertThrowsError(try AITools.call("rect", ["x1": 0, "y1": 0, "x2": 200, "y2": 2, "color": "#000000"], model: m)) { e in
            XCTAssertTrue(((e as? AIToolError)?.message ?? "").contains("64"))
        }
        XCTAssertTrue(m.currentGrid.isBlank, "nothing is half drawn")
        XCTAssertFalse(m.canUndo)
        XCTAssertThrowsError(try AITools.call("line", ["x1": 0, "y1": 0, "x2": 1, "y2": 1, "color": "pinkish"], model: m))
        XCTAssertThrowsError(try AITools.call("select_frame", ["frame": 9], model: m))
        XCTAssertThrowsError(try AITools.call("teleport", [:], model: m))
        XCTAssertThrowsError(try AITools.call("set_pixels", ["rows": ["z"], "x": 0, "y": 0, "legend": [:] as [String: Any]], model: m))
    }

    func testEveryToolHasAValidSchema() throws {
        XCTAssertEqual(Set(AITools.all.map(\.name)).count, AITools.all.count)
        for tool in AITools.all {
            let schema = try JSONSerialization.jsonObject(with: Data(tool.schema.utf8)) as? [String: Any]
            XCTAssertEqual(schema?["type"] as? String, "object", tool.name)
        }
    }

    func testMotionGuideNeedsProAndIsNeverArt() {
        let m = makeModel()
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        m.motionGuide = .walk
        XCTAssertNil(m.motionGuide)
        XCTAssertEqual(asked, .motionGuides)
        m.access = .pro
        m.motionGuide = .walk
        let st = m.canvasState()
        XCTAssertEqual(st.guide, MotionGuides.points(.walk, index: 0, height: 24))
        XCTAssertFalse(st.guideGhost?.isEmpty ?? true)
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertNil(m.project.contentBounds)
    }
}

final class SharedLevelTests: XCTestCase {
    func testGoodLevelsPassAndDamagedOnesAreRefused() throws {
        let scene = TileScene.starter(name: "Night hills")
        XCTAssertTrue(scene.isValid)
        let data = try JSONEncoder().encode(scene)
        XCTAssertEqual(TileScene.decodeChecked(data)?.coins, scene.coins)

        // Someone else's file can say anything: wrong sizes must be refused, not drawn.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["columns"] = 90
        XCTAssertNil(TileScene.decodeChecked(try JSONSerialization.data(withJSONObject: object)), "cells no longer match the size")
        object["columns"] = scene.columns
        object["cells"] = [Int](repeating: 99, count: scene.columns * scene.rows)
        XCTAssertNil(TileScene.decodeChecked(try JSONSerialization.data(withJSONObject: object)), "tiles that don't exist")
        XCTAssertNil(TileScene.decodeChecked(Data("not a level".utf8)))
        XCTAssertNil(TileScene.decodeChecked(data, maxBytes: 10))
    }
}

final class V2ReviewFixTests: XCTestCase {
    func testRotationStaysWithinTheSlidersRange() {
        let m = makeModel()
        drawBlock(m, x: 0, y: 0, side: 3, color: .black)
        m.selectAll()
        for _ in 0..<7 {
            XCTAssertTrue(m.rotateSelection(by: 90))
            XCTAssertTrue((-180.0...180.0).contains(m.selectionTransform.angle))
        }
        m.commitSelection()
        XCTAssertEqual(opaqueCount(m.currentGrid), 9)
    }

    func testPlaybackClockStartsWhenPlayingStarts() {
        let m = makeModel()
        let before = Date()
        m.isPlaying = true
        XCTAssertGreaterThanOrEqual(m.playStartedAt, before)
        XCTAssertEqual(m.playCount, 1)
    }
}

final class SoundTests: XCTestCase {
    private func threeFrames() -> EditorModel {
        let m = makeModel()
        m.pixelPerfect = false
        tap(m, 0.5, 0.5)
        m.addKeyframe()
        tap(m, 1.5, 0.5)
        m.addKeyframe()
        tap(m, 2.5, 0.5)
        return m
    }

    private func clip(_ name: String = "Boing", seconds: Double = 0.5) -> SoundClip {
        SoundClip(name: name, frameID: UUID(), duration: seconds, fileExtension: "m4a")
    }

    func testSoundStaysWithItsFrame() throws {
        let m = threeFrames()
        XCTAssertTrue(m.addSound(clip("  Boing  "), toFrame: 1))
        XCTAssertEqual(m.sounds(onFrame: 1).map(\.name), ["Boing"])
        XCTAssertTrue(m.hasSound(onFrame: 1))
        XCTAssertFalse(m.hasSound(onFrame: 0))
        // Put a new frame in front: the sound moves along with its frame.
        m.selectFrame(0)
        m.addKeyframe()
        XCTAssertTrue(m.hasSound(onFrame: 2))
        XCTAssertFalse(m.hasSound(onFrame: 1))
        m.moveFrame(from: 2, by: 1)
        XCTAssertTrue(m.hasSound(onFrame: 3))
        // Saved and loaded with the sprite.
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.sounds, m.project.sounds)
        XCTAssertEqual(back.sounds(onFrame: 3).count, 1)
    }

    func testCuesFollowTimingHoldsAndPingPong() {
        let m = threeFrames()                               // 8 fps: 0.125 s a frame
        m.addSound(clip(), toFrame: 0)
        m.addSound(clip("Pop"), toFrame: 2)
        XCTAssertEqual(m.project.soundCues.map(\.time), [0, 0.25])
        m.setHold(3, at: 1)                                 // frame 2 is held for 3 beats
        XCTAssertEqual(m.project.soundCues.map(\.time), [0, 0.5])
        m.setHold(1, at: 1)
        m.setLoopMode(.pingPong)                            // 0 1 2 1
        XCTAssertEqual(m.project.soundCues.map(\.time), [0, 0.25])
        m.addSound(clip("Tick"), toFrame: 1)
        XCTAssertEqual(m.project.soundCues.filter { $0.time == 0.125 || $0.time == 0.375 }.count, 2, "it plays both times round")
        m.setSoundVolume(0, for: m.sounds(onFrame: 1)[0].id)
        XCTAssertEqual(m.project.soundCues.count, 2, "silent sounds make no cue")
    }

    func testDeletingAFrameKeepsItsSoundUntilTheSpriteCloses() {
        let m = threeFrames()
        m.addSound(clip(), toFrame: 2)
        let id = m.sounds(onFrame: 2)[0].id
        m.deleteFrame(at: 2)
        XCTAssertTrue(m.project.liveSounds.isEmpty)
        XCTAssertTrue(m.project.soundCues.isEmpty)
        m.undo()
        XCTAssertEqual(m.sounds(onFrame: 2).map(\.id), [id], "undo brings the frame back with its sound")
        m.deleteFrame(at: 2)
        XCTAssertEqual(m.pruneSounds().map(\.id), [id])
        XCTAssertTrue(m.project.sounds.isEmpty)
    }

    func testLimitsAndRemoving() {
        let m = threeFrames()
        for _ in 0..<SoundClip.maxPerFrame { XCTAssertTrue(m.addSound(clip(), toFrame: 0)) }
        XCTAssertFalse(m.addSound(clip(), toFrame: 0), "a frame holds four")
        XCTAssertFalse(m.addSound(clip(seconds: SoundClip.maxSeconds + 1), toFrame: 1))
        XCTAssertFalse(m.addSound(clip(), toFrame: 9))
        let first = m.sounds(onFrame: 0)[0].id
        m.moveSound(first, toFrame: 1)
        XCTAssertEqual(m.sounds(onFrame: 1).map(\.id), [first])
        m.removeSound(first)
        XCTAssertFalse(m.hasSound(onFrame: 1))
    }

    func testDuplicatedSpriteKeepsSoundsOnTheRightFrames() {
        let m = threeFrames()
        m.addSound(clip(), toFrame: 1)
        let copy = m.project.duplicated(name: "Copy")
        XCTAssertEqual(copy.sounds.count, 1)
        XCTAssertEqual(copy.sounds(onFrame: 1).count, 1)
        XCTAssertNotEqual(copy.sounds[0].frameID, m.project.sounds[0].frameID)
    }

    func testMixing() {
        var track = [Float](repeating: 0, count: 8)
        AudioMix.add([0.5, 0.5, 0.5], into: &track, at: 2, volume: 1)
        AudioMix.add([0.5, 0.5, 0.5, 0.5], into: &track, at: 6, volume: 0.5)   // runs off the end
        AudioMix.add([1], into: &track, at: 99, volume: 1)
        XCTAssertEqual(track, [0, 0, 0.5, 0.5, 0.5, 0, 0.25, 0.25])
        var loud: [Float] = [0.5, 1.6, -1.6]
        AudioMix.soften(&loud)
        XCTAssertEqual(loud[0], 0.5)
        XCTAssertLessThan(loud[1], 1)
        XCTAssertGreaterThan(loud[1], 0.8)
        XCTAssertEqual(loud[2], -loud[1])
        let id = UUID()
        let starts = AudioMix.starts(of: [SoundCue(clipID: id, time: 0.25, volume: 1)], loopSeconds: 1, loops: 3, total: 2.5)
        XCTAssertEqual(starts.map(\.time), [0.25, 1.25, 2.25])
    }
}
