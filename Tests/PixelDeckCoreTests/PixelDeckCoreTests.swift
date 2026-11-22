import XCTest
@testable import PixelDeckCore

/// A model drawing in black, so assertions are easy to read.
private func makeModel(_ name: String = "T", access: FeatureAccess = .free) -> EditorModel {
    let m = EditorModel(project: SpriteProject(name: name))
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

final class PixelGridTests: XCTestCase {
    func testLineIsContinuousAndInclusive() {
        var g = PixelGrid(size: 8)
        g.drawLine(from: P(0, 0), to: P(7, 3), color: .black)
        XCTAssertEqual(g[0, 0], .black)
        XCTAssertEqual(g[7, 3], .black)
        XCTAssertEqual(g.pixels.filter { !$0.isClear }.count, 8)
    }

    func testFloodFillStopsAtBordersAndLimit() {
        var g = PixelGrid(width: 10, height: 8)
        for i in 0..<8 { g[3, i] = .black }
        g.floodFill(from: P(0, 0), with: .white)
        XCTAssertEqual(g[2, 7], .white)
        XCTAssertEqual(g[3, 4], .black)
        XCTAssertEqual(g[4, 0], .clear)

        var h = PixelGrid(width: 10, height: 10)
        h.floodFill(from: P(5, 5), with: .white, within: PixelRect(x: 4, y: 4, width: 3, height: 3))
        XCTAssertEqual(h.pixels.filter { !$0.isClear }.count, 9)
    }

    func testReframeKeepsWorldPositions() {
        var g = PixelGrid(width: 4, height: 4)
        g[1, 2] = .black                                      // world (11, 22) for a grid at (10, 20)
        let r = g.reframed(from: PixelRect(x: 10, y: 20, width: 4, height: 4),
                           to: PixelRect(x: 5, y: 18, width: 12, height: 9))
        XCTAssertEqual(r.width, 12)
        XCTAssertEqual(r[11 - 5, 22 - 18], .black)
        XCTAssertEqual(r.pixels.filter { !$0.isClear }.count, 1)
        XCTAssertEqual(g.opaqueBounds, PixelRect(x: 1, y: 2, width: 1, height: 1))
    }

    func testScaledBytesRectangular() {
        var g = PixelGrid(width: 3, height: 2)
        g[2, 1] = .black
        let b = g.rgbaBytes(scale: 2)
        XCTAssertEqual(b.count, 6 * 4 * 4)
        // Row 3 (second pixel row, second copy), x = 4 and 5 are black.
        XCTAssertEqual(b[(3 * 6 + 4) * 4 + 3], 255)
        XCTAssertEqual(b[(3 * 6 + 3) * 4 + 3], 0)
    }

    func testRunLengthEncodingRoundTripAndIsSmall() throws {
        var g = PixelGrid(width: 256, height: 200)
        g.drawLine(from: P(0, 0), to: P(199, 199), color: .black)
        g[3, 150] = RGBA(hex: 0xABCDEF)
        XCTAssertLessThan(g.runLengthEncoded().count, 4000)
        XCTAssertEqual(try JSONDecoder().decode(PixelGrid.self, from: JSONEncoder().encode(g)), g)
    }

    func testCorruptRunLengthDataFailsInsteadOfCrashing() {
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([1, 0, 0, 0, 0])))
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([0xFF, 0xFF, 0, 0, 0, 0])))
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([0, 0, 0, 0, 0, 0])))
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data()))
    }
}

final class MotionPathTests: XCTestCase {
    func testRefinedKeepsEndpointsAndRemovesJitter() {
        var path = MotionPath()
        for i in 1...40 { path.append(Vec2(x: Double(i) * 0.25, y: (i % 2 == 0 ? 0.2 : -0.2))) }
        let r = path.refined()
        XCTAssertEqual(r.points.first, .zero)
        XCTAssertEqual(r.points.last, path.end)
        XCTAssertLessThan(r.length, path.length)
    }

    func testPointAtFractionIsByDistance() {
        let p = MotionPath(points: [.zero, Vec2(x: 10, y: 0), Vec2(x: 10, y: 10)])
        XCTAssertEqual(p.point(atFraction: 0.5), Vec2(x: 10, y: 0))
        XCTAssertEqual(p.point(atFraction: 0.75), Vec2(x: 10, y: 5))
    }

    func testOffsetsEndExactlyAtDestination() {
        let plan = TweenPlan(sourceRect: PixelRect(x: 0, y: 0, width: 1, height: 1),
                             patch: PixelPatch(width: 1, height: 1, pixels: [.black]),
                             path: .straight(to: Vec2(x: 6.4, y: 0)), easing: .easeInOut)
        let o = plan.offsets(count: 4)
        XCTAssertEqual(o.last, P(6, 0))
        XCTAssertEqual(o.map(\.x), o.map(\.x).sorted())
    }
}

final class InfiniteCanvasTests: XCTestCase {
    func testDrawingFarAwayGrowsTheCanvasThenTrims() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        tap(m, 40.5, -30.5)                                    // well outside the starting 16×16
        XCTAssertEqual(m.pixel(P(0, 0)), .black)
        XCTAssertEqual(m.pixel(P(40, -31)), .black)
        // Trimmed to the art plus a 2-pixel margin.
        XCTAssertEqual(m.contentBounds, PixelRect(x: 0, y: -31, width: 41, height: 32))
        XCTAssertEqual(m.bounds, PixelRect(x: -2, y: -33, width: 45, height: 36))
    }

    func testFreeArtIsCappedAndOffersPro() {
        let m = makeModel()
        var asked: [ProFeature] = []
        m.onProRequired = { asked.append($0) }
        tap(m, 0.5, 0.5)
        stroke(m, [(63.5, 0.5), (70.5, 0.5), (80.5, 0.5)])     // one gesture past the 64-px cap
        XCTAssertEqual(m.pixel(P(63, 0)), .black, "x 0…63 is 64 px: allowed")
        XCTAssertEqual(m.pixel(P(70, 0)), .clear)
        XCTAssertEqual(asked, [.largeCanvas], "offered once per gesture")

        m.access = .pro
        tap(m, 300.5, 0.5)
        XCTAssertEqual(m.pixel(P(300, 0)), .black)
        tap(m, 600.5, 0.5)
        XCTAssertEqual(m.pixel(P(600, 0)), .clear, "Pro cap is 512")
    }

    func testMirrorPaintsBothSides() {
        let m = makeModel()
        m.mirror = true
        stroke(m, [(2.5, 3.5), (5.5, 3.5)])
        XCTAssertEqual(m.pixel(P(2, 3)), .black)
        XCTAssertEqual(m.pixel(P(-3, 3)), .black)
        XCTAssertEqual(m.pixel(P(-6, 3)), .black)
    }

    func testFillOfOpenSpaceStaysInsideTheArt() {
        let m = makeModel()
        // A 5×5 square outline from (0,0) to (4,4).
        stroke(m, [(0.5, 0.5), (4.5, 0.5), (4.5, 4.5), (0.5, 4.5), (0.5, 0.5)])
        m.tool = .fill
        m.pickColor(.white)
        m.tool = .fill
        tap(m, 2.5, 2.5)                                       // inside the shape
        XCTAssertEqual(m.pixel(P(2, 2)), .white)
        XCTAssertEqual(m.pixel(P(5, 5)), .clear)
        tap(m, 20.5, 20.5)                                     // empty space far away: nothing happens
        XCTAssertEqual(m.pixel(P(20, 20)), .clear)
        XCTAssertEqual(m.contentBounds, PixelRect(x: 0, y: 0, width: 5, height: 5))
    }

    func testCancelledStrokeRestoresBounds() {
        let m = makeModel()
        let before = m.bounds
        m.touchBegan(at: Vec2(x: 30.5, y: 30.5))
        m.touchCancelled()
        XCTAssertEqual(m.bounds, before)
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertFalse(m.canUndo)
    }

    func testUndoRestoresBoundsToo() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        let small = m.bounds
        tap(m, 30.5, 30.5)
        XCTAssertNotEqual(m.bounds, small)
        m.undo()
        XCTAssertEqual(m.bounds, small)
        XCTAssertEqual(m.pixel(P(0, 0)), .black)
        XCTAssertEqual(m.pixel(P(30, 30)), .clear)
    }

    func testPaletteEditIsStoredAndSelected() {
        let m = makeModel()
        m.setPaletteColor(RGBA(hex: 0x123456), at: 3)
        XCTAssertEqual(m.palette[3], RGBA(hex: 0x123456))
        tap(m, 0.5, 0.5)
        XCTAssertEqual(m.pixel(P(0, 0)), RGBA(hex: 0x123456))
    }
}

final class EditorModelTests: XCTestCase {
    func testPencilStrokeAndUndo() {
        let m = makeModel()
        stroke(m, [(0.5, 0.5), (4.5, 0.5)])
        XCTAssertEqual(m.pixel(P(4, 0)), .black)
        m.undo()
        XCTAssertTrue(m.currentGrid.isBlank)
        m.redo()
        XCTAssertEqual(m.pixel(P(2, 0)), .black)
    }

    func testAddKeyframeShowsOnionSkin() {
        let m = makeModel()
        tap(m, 1.5, 1.5)
        m.addKeyframe()
        XCTAssertEqual(m.currentIndex, 1)
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertEqual(m.onionGrid?[P(1, 1) - m.bounds.origin], .black)
    }

    func testPlayingFrameStateHasNoOverlays() {
        let m = makeModel()
        tap(m, 1.5, 1.5)
        m.tool = .select
        tap(m, 1.5, 1.5)
        XCTAssertNotNil(m.canvasState().selection)
        XCTAssertNil(m.canvasState(playingFrame: 0).selection)
    }

    /// Select a 2×2 block, drag it 6 px right along a wobbly path.
    private func movedBlockModel() -> EditorModel {
        let m = makeModel()
        stroke(m, [(0.5, 0.5), (1.5, 0.5)])
        stroke(m, [(0.5, 1.5), (1.5, 1.5)])
        m.tool = .select
        stroke(m, [(0.2, 0.2), (1.8, 1.8)])
        XCTAssertEqual(m.marquee, PixelRect(x: 0, y: 0, width: 2, height: 2))
        m.touchBegan(at: Vec2(x: 1, y: 1))
        for i in 1...24 { m.touchMoved(to: Vec2(x: 1 + Double(i) * 0.25, y: 1 + (i % 3 == 0 ? 0.3 : 0))) }
        m.touchEnded()
        return m
    }

    func testMoveSelection() {
        let m = movedBlockModel()
        XCTAssertEqual(m.selectionRect?.origin, P(6, 0))
        XCTAssertEqual(m.pixel(P(6, 0)), .black)
        XCTAssertEqual(m.pixel(P(0, 0)), .clear)
        XCTAssertTrue(m.canTween)
    }

    func testMovingSelectionOffTheCanvasGrowsIt() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.tool = .select
        tap(m, 0.5, 0.5)
        stroke(m, [(0.5, 0.5), (30.5, 0.5)])
        m.commitSelection()
        XCTAssertEqual(m.pixel(P(30, 0)), .black)
        XCTAssertEqual(m.pixel(P(0, 0)), .clear)
    }

    func testTweenInsertsFramesAlongPath() {
        let m = movedBlockModel()
        m.generateTween(frameCount: 6, easing: .linear, style: .traced, mode: .insertFrames)
        XCTAssertEqual(m.frameCount, 7)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 0), .black, "first frame back at the start")
        XCTAssertEqual(m.pixel(P(6, 0), frame: 6), .black, "last frame at the destination")
        XCTAssertEqual(m.pixel(P(0, 0), frame: 6), .clear)
        var lastX = Int.min
        for i in 0..<m.frameCount {
            XCTAssertEqual(m.project.frames[i].grid.pixels.filter { !$0.isClear }.count, 4)
            let x = (-2..<12).first { m.pixel(P($0, 0), frame: i) == .black }!
            XCTAssertGreaterThanOrEqual(x, lastX)
            lastX = x
        }
        m.undo()
        XCTAssertEqual(m.frameCount, 1)
    }

    func testTweenAcrossExistingFramesKeepsTheirOtherPixels() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.addKeyframe(); m.addKeyframe()
        tap(m, 10.5, 10.5)                                     // background detail in frame 3
        m.selectFrame(0)
        m.tool = .select
        tap(m, 0.5, 0.5)
        stroke(m, [(0.5, 0.5), (4.5, 0.5)])
        m.generateTween(frameCount: 0, easing: .linear, style: .straight, mode: .spreadAcrossFollowing)
        XCTAssertEqual(m.frameCount, 3)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 0), .black)
        XCTAssertEqual(m.pixel(P(2, 0), frame: 1), .black)
        XCTAssertEqual(m.pixel(P(4, 0), frame: 2), .black)
        XCTAssertEqual(m.pixel(P(10, 10), frame: 2), .black)
    }
}

final class FeatureAccessTests: XCTestCase {
    func testFreeFrameLimitAsksForPro() {
        let m = makeModel()
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        for _ in 1..<FeatureAccess.freeFrameLimit { XCTAssertTrue(m.addKeyframe()) }
        XCTAssertNil(asked)
        XCTAssertFalse(m.addKeyframe())
        XCTAssertEqual(asked, .unlimitedFrames)
        m.access = .pro
        XCTAssertTrue(m.addKeyframe())
    }

    func testMemoryBudget() {
        XCTAssertEqual(FeatureAccess.pro.frameLimit(forArea: 256 * 256), 256)
        XCTAssertEqual(FeatureAccess.pro.frameLimit(forArea: 128 * 128), 999)
        XCTAssertEqual(FeatureAccess.free.frameLimit(forArea: 32 * 32), FeatureAccess.freeFrameLimit)
        XCTAssertTrue(FeatureAccess.free.allowsArt(PixelRect(x: -40, y: 0, width: 64, height: 64)))
        XCTAssertFalse(FeatureAccess.free.allowsArt(PixelRect(x: 0, y: 0, width: 65, height: 1)))
    }
}

final class PersistenceTests: XCTestCase {
    func testProjectRoundTrip() throws {
        let m = makeModel("A")
        tap(m, -5.5, 7.5)
        m.setPaletteColor(.white, at: 0)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.bounds, m.bounds)
        XCTAssertEqual(back.frames[0].grid, m.currentGrid)
        XCTAssertEqual(back.palette[0], .white)
    }

    func testOldSquareFilesStillLoad() throws {
        var g = PixelGrid(size: 8)
        g[1, 1] = .black
        let legacyGrid = #"{"size":8,"rgba":"\#(Data(g.rgbaBytes()).base64EncodedString())"}"#
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old","size":8,"fps":12,"frames":[{"id":"\#(UUID().uuidString)","grid":\#(legacyGrid)}]}"#
        let p = try JSONDecoder().decode(SpriteProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.bounds, PixelRect(x: -4, y: -4, width: 8, height: 8))
        XCTAssertEqual(p.frames[0].grid[1, 1], .black)
        XCTAssertEqual(p.palette, SpriteProject.defaultPalette)
        XCTAssertEqual(p.fps, 12)
    }

    func testDamagedProjectLoadsAsEditable() throws {
        let good = try JSONEncoder().encode(PixelGrid(size: 8))
        let goodFrame = #"{"id":"\#(UUID().uuidString)","grid":\#(String(decoding: good, as: UTF8.self))}"#
        let json = """
        {"id":"\(UUID().uuidString)","name":"  ","size":8,"fps":500,
         "frames":[{"id":"\(UUID().uuidString)","grid":{"size":16,"rle":""}}, {"garbage":true}, \(goodFrame)]}
        """
        let p = try JSONDecoder().decode(SpriteProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.frames.count, 1)
        XCTAssertEqual(p.fps, SpriteProject.maxFPS)
        XCTAssertEqual(p.name, "Sprite")
        let huge = #"{"id":"\#(UUID().uuidString)","name":"H","size":100000,"frames":[]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SpriteProject.self, from: Data(huge.utf8)))
    }

    func testStoreSavesCoalescesAndDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        var p = store.create(baseName: "Lutin")
        XCTAssertEqual(p.name, "Lutin 1")
        for i in 0..<20 { p.name = "Name \(i)"; store.save(p) }
        store.duplicate(id: p.id) { "Copie de \($0)" }
        store.flush()
        let reloaded = ProjectStore(directory: dir)
        XCTAssertTrue(reloaded.projects.contains { $0.name == "Name 19" })
        XCTAssertTrue(reloaded.projects.contains { $0.name == "Copie de Name 19" })
        store.delete(id: p.id)
        store.flush()
        XCTAssertEqual(ProjectStore(directory: dir).projects.count, 1)
        try? FileManager.default.removeItem(at: dir)
    }
}

final class StarterAndExportTests: XCTestCase {
    func testCharacterSpritesParse() throws {
        let json = """
        {"pal": {"k": "#1B1530", "g": "#7BE07B"},
         "blob": {"w": 3, "h": 2, "fps": 4, "frames": [["kgk", ".g."], ["...", "kkk"]]},
         "broken": {"w": 3, "h": 2, "frames": [["too", "many", "rows"]]}}
        """
        let lib = CharacterSpriteLibrary.parse(Data(json.utf8))
        XCTAssertNil(lib["broken"])
        let blob = try XCTUnwrap(lib["blob"])
        XCTAssertEqual(blob.frames.count, 2)
        XCTAssertEqual(blob.frames[0][1, 0], RGBA(hex: 0x7BE07B))
        XCTAssertEqual(blob.frames[0][0, 1], .clear)
        XCTAssertEqual(blob.frame(at: 0.3).pixels, blob.frames[1].pixels, "0.3 s × 4 fps → frame 1")
        let project = blob.makeProject(name: "Blob")
        XCTAssertEqual(project.bounds, PixelRect(x: -1, y: -1, width: 3, height: 2))
        XCTAssertEqual(project.fps, 4)
        XCTAssertEqual(project.contentBounds, PixelRect(x: -1, y: -1, width: 3, height: 2))
    }

    func testRectangularSpriteSheet() {
        var a = PixelGrid(width: 3, height: 2); a[0, 0] = .black
        var b = PixelGrid(width: 3, height: 2); b[2, 1] = .white
        let sheet = SpriteSheet(grids: [a, b, a], scale: 1, layout: .grid)
        XCTAssertEqual(sheet.columns, 2)
        XCTAssertEqual(sheet.width, 6)
        XCTAssertEqual(sheet.height, 4)
        XCTAssertEqual(sheet.bytes[(1 * 6 + 5) * 4], 255)      // frame 1's (2,1) → sheet (5,1)
        XCTAssertEqual(sheet.metadata(fps: 10, imageName: "s.png").frames[2].y, 2)
    }

    func testCroppedExportGrids() {
        let m = makeModel()
        tap(m, 3.5, -2.5)
        tap(m, 5.5, 1.5)
        let content = m.contentBounds!
        XCTAssertEqual(content, PixelRect(x: 3, y: -3, width: 3, height: 5))
        let grids = m.project.grids(croppedTo: content)
        XCTAssertEqual(grids[0].width, 3)
        XCTAssertEqual(grids[0][0, 0], .black)
        XCTAssertEqual(grids[0][2, 4], .black)
    }
}

final class ReviewFixTests: XCTestCase {
    func testFillThatBecomesAPinchChangesNothing() {
        let m = makeModel()
        stroke(m, [(0.5, 0.5), (4.5, 0.5), (4.5, 4.5), (0.5, 4.5), (0.5, 0.5)])
        m.pickColor(.white)
        m.tool = .fill
        m.touchBegan(at: Vec2(x: 2.5, y: 2.5))
        m.touchCancelled()
        XCTAssertEqual(m.pixel(P(2, 2)), .clear)
        tap(m, 2.5, 2.5)
        XCTAssertEqual(m.pixel(P(2, 2)), .white)
    }

    func testEyedropperPicksOnLiftOnly() {
        let m = makeModel()
        tap(m, 1.5, 1.5)
        m.pickColor(.white)
        m.tool = .eyedropper
        m.touchBegan(at: Vec2(x: 1.5, y: 1.5))
        m.touchCancelled()
        XCTAssertEqual(m.tool, .eyedropper)
        tap(m, 1.5, 1.5)
        XCTAssertEqual(m.color, .black)
        XCTAssertEqual(m.tool, .pencil)
    }

    func testUndoHistoryIsCappedByMemory() {
        let m = makeModel(access: .pro)
        // ~500×500 art: each snapshot is up to ~1 MB per frame; 50 steps would be far less than
        // the budget, so add frames to make each snapshot big.
        tap(m, -240.5, -240.5)
        tap(m, 250.5, 250.5)
        for _ in 0..<40 { m.addKeyframe() }
        var steps = 0
        while m.canUndo { m.undo(); steps += 1 }
        XCTAssertLessThan(steps, 50, "large sprites keep fewer undo steps")
        XCTAssertGreaterThan(steps, 0)
    }
}

final class ShapeTests: XCTestCase {
    func testRectangleOutlineAndFill() {
        let outline = ShapeRaster.points(.rectangle, from: P(0, 0), to: P(4, 3), filled: false)
        XCTAssertEqual(Set(outline).count, 5 * 4 - 3 * 2)
        let filled = ShapeRaster.points(.rectangle, from: P(4, 3), to: P(0, 0), filled: true)
        XCTAssertEqual(Set(filled).count, 20)
    }

    func testEllipseIsSymmetricAndInsideItsBox() {
        for (w, h) in [(5, 5), (8, 6), (2, 7), (11, 4)] {
            let r = PixelRect(x: 0, y: 0, width: w, height: h)
            let pts = Set(ShapeRaster.ellipse(r))
            XCTAssertTrue(pts.allSatisfy { r.contains($0) }, "\(w)×\(h) stays in its box")
            for p in pts {
                XCTAssertTrue(pts.contains(P(w - 1 - p.x, p.y)), "\(w)×\(h) mirrors left-right")
                XCTAssertTrue(pts.contains(P(p.x, h - 1 - p.y)), "\(w)×\(h) mirrors top-bottom")
            }
            // Touches all four sides.
            XCTAssertTrue(pts.contains { $0.x == 0 } && pts.contains { $0.x == w - 1 })
            XCTAssertTrue(pts.contains { $0.y == 0 } && pts.contains { $0.y == h - 1 })
        }
    }

    func testFilledCircleHasNoHoles() {
        let pts = Set(ShapeRaster.points(.ellipse, from: P(0, 0), to: P(9, 9), filled: true))
        for y in 0..<10 {
            let row = pts.filter { $0.y == y }.map(\.x)
            XCTAssertEqual(row.count, (row.max()! - row.min()!) + 1)
        }
    }

    func testTriangleIsSymmetricWithApexOnDragSide() {
        let down = Set(ShapeRaster.points(.triangle, from: P(0, 0), to: P(7, 5), filled: false))
        for p in down { XCTAssertTrue(down.contains(P(7 - p.x, p.y))) }
        XCTAssertTrue(down.contains(P(3, 0)) && down.contains(P(4, 0)), "even width: 2-pixel apex at the top")
        XCTAssertEqual(down.filter { $0.y == 5 }.count, 8, "full base at the bottom")
        let up = Set(ShapeRaster.points(.triangle, from: P(0, 5), to: P(6, 0), filled: false))
        XCTAssertTrue(up.contains(P(3, 5)), "dragging up puts the apex at the bottom")
    }

    func testLockedProportions() {
        XCTAssertEqual(ShapeRaster.constrained(.line, from: P(0, 0), to: P(10, 2)), P(10, 0))
        XCTAssertEqual(ShapeRaster.constrained(.line, from: P(0, 0), to: P(7, -6)), P(7, -7))
        XCTAssertEqual(ShapeRaster.constrained(.rectangle, from: P(0, 0), to: P(-3, 8)), P(-8, 8))
    }
}

final class LayerTests: XCTestCase {
    func testFirstShapeGoesOnItsOwnLayerAboveTheArt() {
        let m = makeModel()
        stroke(m, [(0.5, 0.5), (5.5, 0.5)])                     // art on layer 1
        m.tool = .shape
        m.shapeKind = .rectangle
        m.pickColor(.white)
        stroke(m, [(0.5, 0.5), (3.5, 3.5)])
        XCTAssertEqual(m.layers.count, 2)
        XCTAssertEqual(m.layers[1].name, "Shapes")
        XCTAssertEqual(m.activeLayer, 1)
        XCTAssertEqual(m.pixel(P(0, 0)), .white, "shape layer is on top")
        XCTAssertEqual(m.pixel(P(5, 0)), .black, "art underneath untouched")
        XCTAssertEqual(m.project.frames[0].layers[0][P(0, 0) - m.bounds.origin], .black)

        m.setLayerVisible(1, false)
        XCTAssertEqual(m.pixel(P(0, 0)), .black, "hiding the shapes layer shows the art")
    }

    func testShapePreviewFollowsTheDragAndCancelLeavesNothing() {
        let m = makeModel()
        m.tool = .shape
        m.shapeKind = .line
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5))
        m.touchMoved(to: Vec2(x: 9.5, y: 0.5))
        m.touchMoved(to: Vec2(x: 0.5, y: 9.5))                // the previous preview is replaced
        XCTAssertEqual(m.pixel(P(0, 9)), .black)
        XCTAssertEqual(m.pixel(P(9, 0)), .clear)
        m.touchCancelled()
        XCTAssertTrue(m.currentGrid.isBlank)
    }

    func testShapesGrowTheCanvasAndMirror() {
        let m = makeModel()
        m.tool = .shape
        m.shapeKind = .ellipse
        m.shapeFilled = true
        m.mirror = true
        stroke(m, [(20.5, 20.5), (30.5, 30.5)])
        XCTAssertEqual(m.pixel(P(25, 25)), .black)
        XCTAssertEqual(m.pixel(P(-26, 25)), .black, "mirrored across x = 0")
    }

    func testLayerOpsAreUndoableAndAffectEveryFrame() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.addKeyframe()
        m.addLayer()
        XCTAssertEqual(m.layers.count, 2)
        XCTAssertTrue(m.project.frames.allSatisfy { $0.layers.count == 2 })
        tap(m, 1.5, 1.5)                                        // on the new layer, frame 2
        m.moveLayer(1, by: -1)
        XCTAssertEqual(m.activeLayer, 0)
        m.selectLayer(1)
        m.mergeLayerDown()
        XCTAssertEqual(m.layers.count, 1)
        XCTAssertEqual(m.pixel(P(1, 1)), .black)
        m.undo()                                                // un-merge
        XCTAssertEqual(m.layers.count, 2)
        m.deleteLayer(0)
        XCTAssertEqual(m.layers.count, 1)
        m.deleteLayer(0)
        XCTAssertEqual(m.layers.count, 1, "the last layer stays")
    }

    func testTweenKeepsOtherLayersInNewFrames() {
        let m = makeModel()
        tap(m, 10.5, 10.5)                                      // background detail, layer 1
        m.addLayer()
        tap(m, 0.5, 0.5)                                        // the mover, layer 2
        m.tool = .select
        tap(m, 0.5, 0.5)
        stroke(m, [(0.5, 0.5), (6.5, 0.5)])
        m.generateTween(frameCount: 3, easing: .linear, style: .straight, mode: .insertFrames)
        XCTAssertEqual(m.frameCount, 4)
        for i in 0..<4 { XCTAssertEqual(m.pixel(P(10, 10), frame: i), .black, "background in frame \(i)") }
        XCTAssertEqual(m.pixel(P(6, 0), frame: 3), .black)
        XCTAssertEqual(m.pixel(P(0, 0), frame: 3), .clear)
    }

    func testLayersPersistAndOldFilesLoadAsOneLayer() throws {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.addLayer(named: "Top")
        tap(m, 2.5, 2.5)
        m.setLayerVisible(0, false)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.layers.map(\.name), ["Layer 1", "Top"])
        XCTAssertEqual(back.layers.map(\.isVisible), [false, true])
        XCTAssertEqual(back.frames[0].grid, m.currentGrid, "flattened image rebuilt on load")
        XCTAssertEqual(back.frames[0].layers.count, 2)

        let old = try JSONEncoder().encode(PixelGrid(size: 8))
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old","size":8,"frames":[{"id":"\#(UUID().uuidString)","grid":\#(String(decoding: old, as: UTF8.self))}]}"#
        let p = try JSONDecoder().decode(SpriteProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.layers.count, 1)
        XCTAssertEqual(p.frames[0].layers.count, 1)
    }
}

final class ToolSwitchTests: XCTestCase {
    func testEraserToggleAndPreviousTool() {
        let m = makeModel()
        m.tool = .fill
        m.toggleEraser()
        XCTAssertEqual(m.tool, .eraser)
        m.toggleEraser()
        XCTAssertEqual(m.tool, .fill, "back to the tool before the eraser")
        m.tool = .shape
        m.switchToPreviousTool()
        XCTAssertEqual(m.tool, .fill)
        m.switchToPreviousTool()
        XCTAssertEqual(m.tool, .shape)
    }

    func testStepFrameWraps() {
        let m = makeModel()
        m.addKeyframe(); m.addKeyframe()
        XCTAssertEqual(m.currentIndex, 2)
        m.stepFrame(1)
        XCTAssertEqual(m.currentIndex, 0)
        m.stepFrame(-1)
        XCTAssertEqual(m.currentIndex, 2)
    }

    func testCoalescedSamplesDrawAContinuousLine() {
        // The canvas feeds every Pencil sample; sub-pixel steps must still join up.
        let m = makeModel()
        m.touchBegan(at: Vec2(x: 0.2, y: 0.5))
        var x = 0.2
        while x < 10 { x += 0.37; m.touchMoved(to: Vec2(x: x, y: 0.5 + x * 0.3)) }
        m.touchEnded()
        // No gaps: every column from start to end has a painted pixel.
        for x in 0..<10 {
            XCTAssertTrue((-2..<8).contains { m.pixel(P(x, $0)) == .black }, "column \(x) painted")
        }
    }
}

final class PlaybackTimingTests: XCTestCase {
    func testLinearIsEvenAndEasingKeepsTheLoopLength() {
        XCTAssertEqual(PlaybackTiming.durations(count: 4, fps: 8, easing: .linear), [0.125, 0.125, 0.125, 0.125])
        for e in Easing.allCases {
            let d = PlaybackTiming.durations(count: 10, fps: 10, easing: e)
            XCTAssertEqual(d.reduce(0, +), 1.0, accuracy: 0.001, "\(e) keeps a 1 s loop")
            XCTAssertTrue(d.allSatisfy { $0 >= PlaybackTiming.minimumDuration })
        }
    }

    func testEasingShapesTheTiming() {
        let easeIn = PlaybackTiming.durations(count: 8, fps: 8, easing: .easeIn)
        XCTAssertGreaterThan(easeIn.first!, easeIn.last!, "ease in: slow start, so early frames last longer")
        let easeOut = PlaybackTiming.durations(count: 8, fps: 8, easing: .easeOut)
        XCTAssertLessThan(easeOut.first!, easeOut.last!)
        let inOut = PlaybackTiming.durations(count: 8, fps: 8, easing: .easeInOut)
        XCTAssertGreaterThan(inOut.first!, inOut[3])
        XCTAssertGreaterThan(inOut.last!, inOut[4])
        XCTAssertEqual(inOut.first!, inOut.last!, accuracy: 0.0001, "symmetric")
    }

    func testFrameIndexFollowsDurations() {
        let d = [0.5, 0.1, 0.4]
        XCTAssertEqual(PlaybackTiming.frameIndex(at: 0.2, durations: d), 0)
        XCTAssertEqual(PlaybackTiming.frameIndex(at: 0.55, durations: d), 1)
        XCTAssertEqual(PlaybackTiming.frameIndex(at: 0.7, durations: d), 2)
        XCTAssertEqual(PlaybackTiming.frameIndex(at: 1.2, durations: d), 0, "loops")
    }

    func testEasedPlaybackIsProAndPersists() throws {
        let m = makeModel()
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        m.setPlaybackEasing(.easeInOut)
        XCTAssertEqual(asked, .timing)
        XCTAssertEqual(m.project.playbackEasing, .linear)
        m.access = .pro
        m.setPlaybackEasing(.easeInOut)
        XCTAssertEqual(m.project.playbackEasing, .easeInOut)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.playbackEasing, .easeInOut)
    }

    func testSheetMetadataCarriesPerFrameDurations() {
        let sheet = SpriteSheet(grids: [PixelGrid(size: 2), PixelGrid(size: 2)], scale: 1, layout: .strip)
        let meta = sheet.metadata(fps: 10, imageName: "s.png", durations: [0.15, 0.05])
        XCTAssertEqual(meta.frames.map(\.durationMs), [150, 50])
        XCTAssertEqual(sheet.metadata(fps: 10, imageName: "s.png").frames.map(\.durationMs), [100, 100])
    }
}

final class MoreShapeTests: XCTestCase {
    func testPolygonsStayInTheirBoxAndTouchItsSides() {
        for kind in [ShapeKind.diamond, .pentagon, .hexagon, .octagon, .parallelogram, .star] {
            for filled in [false, true] {
                let pts = Set(ShapeRaster.points(kind, from: P(0, 0), to: P(20, 16), filled: filled))
                let box = PixelRect(x: 0, y: 0, width: 21, height: 17)
                XCTAssertTrue(pts.allSatisfy { box.contains($0) }, "\(kind) stays in its box")
                XCTAssertTrue(pts.contains { $0.x == 0 } && pts.contains { $0.x == 20 }, "\(kind) spans the width")
                XCTAssertTrue(pts.contains { $0.y == 0 } && pts.contains { $0.y == 16 }, "\(kind) spans the height")
            }
        }
    }

    func testSymmetricShapesAreSymmetric() {
        for kind in [ShapeKind.diamond, .hexagon, .octagon] {
            for w in [9, 10, 15] {
                let pts = Set(ShapeRaster.points(kind, from: P(0, 0), to: P(w - 1, w - 1), filled: false))
                for p in pts {
                    XCTAssertTrue(pts.contains(P(w - 1 - p.x, p.y)), "\(kind) \(w) mirrors left-right")
                }
            }
        }
    }

    func testFilledShapesHaveNoHoles() {
        // Every row of a filled convex shape is one solid run.
        for kind in [ShapeKind.diamond, .pentagon, .hexagon, .octagon, .parallelogram] {
            let pts = Set(ShapeRaster.points(kind, from: P(0, 0), to: P(17, 13), filled: true))
            for y in 0...13 {
                let row = pts.filter { $0.y == y }.map(\.x)
                guard let lo = row.min(), let hi = row.max() else { continue }
                XCTAssertEqual(row.count, hi - lo + 1, "\(kind) row \(y) is solid")
            }
        }
        // The star's centre is filled, and the gap between two points at the top stays empty.
        let star = Set(ShapeRaster.points(.star, from: P(0, 0), to: P(30, 30), filled: true))
        XCTAssertTrue(star.contains(P(15, 16)))
        XCTAssertFalse(star.contains(P(4, 3)))
    }

    func testNewShapesDrawThroughTheModel() {
        let m = makeModel()
        m.tool = .shape
        m.shapeKind = .hexagon
        m.shapeFilled = true
        stroke(m, [(0.5, 0.5), (12.5, 10.5)])
        XCTAssertEqual(m.pixel(P(6, 5)), .black, "centre filled")
        XCTAssertEqual(m.pixel(P(0, 0)), .clear, "hexagon corners are cut")
    }
}

final class FrameClipboardTests: XCTestCase {
    func testPasteReplacesCurrentFrameInPlace() {
        let m = makeModel()
        tap(m, 2.5, 3.5)
        let clip = try! XCTUnwrap(m.copyFrame(at: 0))
        m.addKeyframe()
        tap(m, 9.5, 9.5)
        XCTAssertTrue(m.pasteFrame(clip, asNewFrame: false))
        XCTAssertEqual(m.frameCount, 2)
        XCTAssertEqual(m.currentIndex, 1)
        XCTAssertEqual(m.pixel(P(2, 3)), .black, "pasted where it was copied from")
        XCTAssertEqual(m.pixel(P(9, 9)), .clear, "paste replaces the frame")
        m.undo()
        XCTAssertEqual(m.pixel(P(9, 9)), .black, "undo brings the old frame back")
        XCTAssertEqual(m.pixel(P(2, 3)), .clear)
    }

    func testPasteAsNewFrameInsertsAfterCurrent() {
        let m = makeModel()
        tap(m, 1.5, 1.5)
        let clip = try! XCTUnwrap(m.copyFrame(at: 0))
        tap(m, 5.5, 5.5)                                 // the copy doesn't change later
        XCTAssertTrue(m.pasteFrame(clip, asNewFrame: true))
        XCTAssertEqual(m.frameCount, 2)
        XCTAssertEqual(m.currentIndex, 1)
        XCTAssertEqual(m.pixel(P(1, 1)), .black)
        XCTAssertEqual(m.pixel(P(5, 5)), .clear)
        XCTAssertEqual(m.pixel(P(5, 5), frame: 0), .black)
    }

    func testPasteKeepsLayersAndWorksAcrossSprites() {
        let a = makeModel("A")
        tap(a, 0.5, 0.5)                                 // layer 1
        a.addLayer()
        a.pickColor(.white)
        tap(a, 1.5, 0.5)                                 // layer 2
        let clip = try! XCTUnwrap(a.copyFrame(at: 0))

        // Same layer count: each layer goes back to its own layer.
        let b = makeModel("B")
        b.addLayer()
        XCTAssertTrue(b.pasteFrame(clip, asNewFrame: false))
        XCTAssertEqual(b.pixel(P(0, 0)), .black)
        XCTAssertEqual(b.pixel(P(1, 0)), .white)
        let o = b.bounds.origin
        XCTAssertEqual(b.project.frames[0].layers[0][1 - o.x, 0 - o.y], .clear, "white stays on the top layer")

        // Different layer count: the art lands flattened on the active layer.
        let c = makeModel("C")
        XCTAssertTrue(c.pasteFrame(clip, asNewFrame: false))
        XCTAssertEqual(c.pixel(P(0, 0)), .black)
        XCTAssertEqual(c.pixel(P(1, 0)), .white)
        XCTAssertEqual(c.layers.count, 1)
    }

    func testPastingABlankFrameClearsIt() {
        let m = makeModel()
        let clip = try! XCTUnwrap(m.copyFrame(at: 0))
        XCTAssertTrue(clip.isBlank)
        tap(m, 3.5, 3.5)
        m.pasteFrame(clip, asNewFrame: false)
        XCTAssertEqual(m.pixel(P(3, 3)), .clear)
    }

    func testPasteRespectsTheFrameLimit() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        let clip = try! XCTUnwrap(m.copyFrame(at: 0))
        while m.frameCount < m.frameLimit { m.addKeyframe() }
        XCTAssertFalse(m.pasteFrame(clip, asNewFrame: true))
        XCTAssertEqual(m.frameCount, m.frameLimit)
        XCTAssertTrue(m.pasteFrame(clip, asNewFrame: false), "replacing still works at the limit")
    }
}

final class TraceImageTests: XCTestCase {
    func testNewPictureCoversTheArt() {
        let art = PixelRect(x: -4, y: -2, width: 20, height: 10)
        let wide = TraceSettings.placed(aspect: 0.25, over: art)          // wider than the art
        XCTAssertEqual(wide.height, 10, accuracy: 1e-9)
        XCTAssertEqual(wide.centerX, 6); XCTAssertEqual(wide.centerY, 3)
        let tall = TraceSettings.placed(aspect: 2, over: art)
        XCTAssertEqual(tall.width, 20, accuracy: 1e-9)
        let blank = TraceSettings.placed(aspect: 1, over: nil)
        XCTAssertEqual(blank.width, 32); XCTAssertEqual(blank.centerX, 0)
    }

    func testSettingsAreClamped() {
        var t = TraceSettings()
        t.opacity = 7; t.width = .nan; t.aspect = -1
        let s = t.sanitized
        XCTAssertEqual(s.opacity, 1); XCTAssertEqual(s.width, 32); XCTAssertEqual(s.aspect, 0.05)
    }

    func testTraceIsSavedAndOldFilesLoad() throws {
        var p = SpriteProject(name: "T")
        var t = TraceSettings(); t.opacity = 0.3; t.width = 48; t.isVisible = false
        p.trace = t
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(SpriteProject.self, from: data).trace, t)
        p.trace = nil
        XCTAssertNil(try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(p)).trace)
    }

    func testCanvasShowsTraceUnderTheArtButNotInFramesOrPlayback() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.setTrace(TraceSettings())
        XCTAssertNotNil(m.canvasState().trace)
        XCTAssertNil(m.canvasState(playingFrame: 0).trace, "playback shows the result only")
        var hidden = TraceSettings(); hidden.isVisible = false
        m.setTrace(hidden)
        let before = m.canvasState()
        XCTAssertNil(before.trace)
        m.setTrace(TraceSettings())
        XCTAssertNotEqual(before, m.canvasState(), "the canvas redraws when the picture changes")
        XCTAssertTrue(m.canUndo, "drawing is still undoable")
        m.undo()
        XCTAssertNotNil(m.trace, "undo doesn't remove the tracing picture")
    }
}

final class PalettePresetTests: XCTestCase {
    func testPresetsHaveTenDistinctOpaqueColours() {
        for p in PalettePreset.allCases {
            XCTAssertEqual(p.colors.count, 10, p.rawValue)
            XCTAssertEqual(Set(p.colors).count, 10, "\(p.rawValue) has no repeats")
            XCTAssertTrue(p.colors.allSatisfy { $0.a == 255 })
        }
        XCTAssertEqual(PalettePreset.pixelDeck.colors, SpriteProject.defaultPalette)
    }

    func testApplyingAPaletteKeepsTheSelectedSlotAndTheArt() {
        let m = makeModel()
        m.pickColor(m.palette[3])
        tap(m, 0.5, 0.5)
        let drawn = m.pixel(P(0, 0))
        m.applyPalette(PalettePreset.ocean.colors)
        XCTAssertEqual(m.palette, PalettePreset.ocean.colors)
        XCTAssertEqual(m.color, PalettePreset.ocean.colors[3])
        XCTAssertEqual(m.pixel(P(0, 0)), drawn, "the art keeps its colours")
        m.applyPalette([.black])                       // wrong size: ignored
        XCTAssertEqual(m.palette, PalettePreset.ocean.colors)
    }
}

final class ShowcaseSpriteTests: XCTestCase {
    private func load(_ name: String) throws -> [String: CharacterSprite] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PixelDeck/Resources/Starter/\(name).json")
        return CharacterSpriteLibrary.parse(try Data(contentsOf: url))
    }

    func testShowcaseScenesParseAndNeedPro() throws {
        let lib = try load("showcase")
        for key in CharacterSpriteLibrary.showcaseOrder {
            let s = try XCTUnwrap(lib[key], key)
            XCTAssertEqual(s.frames.count, 16)
            XCTAssertGreaterThan(max(s.width, s.height), FeatureAccess.freeMaxArtSide, "\(key) is a Pro-size sprite")
            XCTAssertLessThanOrEqual(max(s.width, s.height), FeatureAccess.proMaxArtSide)
            XCTAssertTrue(s.frames.allSatisfy { $0.width == s.width && $0.height == s.height })
            XCTAssertNotEqual(s.frames[0], s.frames[1], "\(key) is animated")
            // Fully painted scenes: no transparent pixels.
            XCTAssertNil(s.frames[0].pixels.first { $0.a == 0 })
            let p = s.makeProject(name: key)
            XCTAssertFalse(FeatureAccess.free.allowsArt(p.visibleContentBounds!))
            XCTAssertTrue(FeatureAccess.pro.allowsArt(p.visibleContentBounds!))
        }
    }

    func testSpritePaletteAddsToTheSharedOne() {
        let json = ##"{"pal":{"a":"#000000"},"s":{"w":2,"h":1,"pal":{"b":"#FFFFFF"},"frames":[["ab"]]}}"##
        let s = CharacterSpriteLibrary.parse(Data(json.utf8))["s"]!
        XCTAssertEqual(s.frames[0][0, 0], RGBA(hex: 0x000000))
        XCTAssertEqual(s.frames[0][1, 0], RGBA(hex: 0xFFFFFF))
    }

    func testStartersStillLoad() throws {
        let lib = try load("sprites")
        for key in CharacterSpriteLibrary.order { XCTAssertNotNil(lib[key], key) }
    }
}

final class SyncStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testRelocateMergesKeepingTheNewerVersion() {
        let local = ProjectStore(directory: tempDir())
        var shared = SpriteProject(name: "Local edit")
        shared.modifiedAt = Date(timeIntervalSince1970: 2_000)
        local.save(shared)
        local.save(SpriteProject(name: "Only local"))
        local.flush()

        let cloudDir = tempDir()
        let cloud = ProjectStore(directory: cloudDir)
        var older = shared; older.name = "Cloud (older)"; older.modifiedAt = Date(timeIntervalSince1970: 1_000)
        cloud.save(older)
        cloud.save(SpriteProject(name: "Only cloud"))
        cloud.flush()

        let oldDir = local.directory
        local.relocate(to: cloudDir, removingOld: true)
        XCTAssertEqual(Set(local.projects.map(\.name)), ["Local edit", "Only local", "Only cloud"])
        XCTAssertEqual(Set(ProjectStore(directory: cloudDir).projects.map(\.name)), ["Local edit", "Only local", "Only cloud"])
        XCTAssertTrue(ProjectStore(directory: oldDir).projects.isEmpty, "local copies removed once in iCloud")
    }

    func testMergeFromDiskPicksUpOtherDevices() {
        let dir = tempDir()
        let here = ProjectStore(directory: dir)
        // Saved directly: "New canvas" (create) would reuse one empty sprite for all three.
        let kept = SpriteProject(name: "Kept 1"); here.save(kept)
        let doomed = SpriteProject(name: "Doomed 1"); here.save(doomed)
        var changed = SpriteProject(name: "Changed 1"); here.save(changed)
        here.flush()

        // Another device: edits one, deletes one, adds one (through the shared folder).
        let there = ProjectStore(directory: dir)
        changed.name = "Changed elsewhere"; changed.modifiedAt = Date().addingTimeInterval(60)
        there.save(changed)
        there.delete(id: doomed.id)
        there.save(SpriteProject(name: "New elsewhere"))
        there.flush()

        // And an unsaved edit here must survive.
        let fresh = SpriteProject(name: "Fresh 1"); here.save(fresh)
        here.mergeFromDisk()
        let names = Set(here.projects.map(\.name))
        XCTAssertTrue(names.contains("Changed elsewhere"))
        XCTAssertTrue(names.contains("New elsewhere"))
        XCTAssertTrue(names.contains(kept.name))
        XCTAssertTrue(names.contains(fresh.name), "not-yet-written work is kept")
        XCTAssertFalse(names.contains(doomed.name), "deleted on the other device")
    }

    func testStartersHaveTheSameIdOnEveryDevice() {
        XCTAssertEqual(UUID(stableName: "pixeldeck.starter.slime"), UUID(stableName: "pixeldeck.starter.slime"))
        XCTAssertNotEqual(UUID(stableName: "pixeldeck.starter.slime"), UUID(stableName: "pixeldeck.starter.coin"))
        let s = CharacterSprite(key: "slime", width: 2, height: 2, fps: 8, frames: [PixelGrid(width: 2, height: 2)])
        XCTAssertEqual(s.makeProject(name: "A").id, s.makeProject(name: "B").id)
    }

    func testFixedDatesLetStartersMergeAndEditsWin() {
        let dir = tempDir()
        let a = ProjectStore(directory: dir)
        let s = CharacterSprite(key: "coin", width: 2, height: 2, fps: 8, frames: [PixelGrid(width: 2, height: 2)])
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        a.add([s.makeProject(name: "Coin")], before: date)
        var edited = a.projects[0]; edited.name = "My coin"; edited.modifiedAt = Date()
        a.save(edited); a.flush()
        // A second device seeds the same starter, then merges.
        let b = ProjectStore(directory: tempDir())
        b.add([s.makeProject(name: "Coin")], before: date)
        b.relocate(to: dir, removingOld: true)
        XCTAssertEqual(b.projects.count, 1)
        XCTAssertEqual(b.projects[0].name, "My coin")
    }
}

final class StaleSaveTests: XCTestCase {
    func testAnOlderCopyNeverOverwritesANewerOne() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        var p = store.create()
        let stale = p
        p.name = "Newer"; p.modifiedAt = Date().addingTimeInterval(10)
        store.save(p)
        store.save(stale)                       // e.g. an editor closing with the old version
        XCTAssertEqual(store.project(id: p.id)?.name, "Newer")
    }
}

final class CloudPlaceholderTests: XCTestCase {
    func testEvictedFilesAreNotTreatedAsDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        let p = store.create()
        store.flush()
        // iCloud evicts the file, leaving a placeholder.
        let file = dir.appendingPathComponent("\(p.id.uuidString).json")
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent(".\(p.id.uuidString).json.icloud"))
        store.mergeFromDisk()
        XCTAssertNotNil(store.project(id: p.id))
    }

    func testOwnWritesAreNotReadBack() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        var p = store.create()
        p.name = "Edited"; p.modifiedAt = Date().addingTimeInterval(5)
        store.save(p)
        store.flush()
        store.mergeFromDisk()
        XCTAssertEqual(store.project(id: p.id)?.name, "Edited")
        XCTAssertEqual(store.projects.count, 1)
    }
}

final class CommunityTests: XCTestCase {
    func testPostArtRoundTripsTrimmedAndFlattened() throws {
        let m = makeModel()
        tap(m, 3.5, 4.5)
        m.addLayer(); m.pickColor(.white); tap(m, 5.5, 4.5)
        m.addKeyframe(); tap(m, 4.5, 6.5)
        m.setPlaybackEasing(.easeIn)                    // ignored on free; fine either way
        let art = try XCTUnwrap(PostArt(project: m.project))
        XCTAssertEqual(art.width, 3); XCTAssertEqual(art.height, 3)
        XCTAssertEqual(art.frames.count, 2)
        XCTAssertEqual(art.frames[0][0, 0], .black); XCTAssertEqual(art.frames[0][2, 0], .white)
        let back = try XCTUnwrap(PostArt.decode(art.encoded()))
        XCTAssertEqual(back, art)
        let remix = back.makeProject(name: "Remix")
        XCTAssertEqual(remix.frames.count, 2)
        XCTAssertEqual(remix.visibleContentBounds?.width, 3)
    }

    func testBlankSpritesCantBePostedAndBadPostsAreRejected() throws {
        XCTAssertNil(PostArt(project: SpriteProject(name: "Blank")))
        var art = try XCTUnwrap(PostArt(project: StarterArtFixture.project()))
        art.width = 9999
        XCTAssertNil(PostArt.decode(try art.encoded()), "out-of-range sizes are refused")
        XCTAssertNil(PostArt.decode(Data("not json".utf8)))
    }

    func testFilterBlocksProfanityLinksAndContactsButNotInnocentWords() {
        for bad in ["fuck", "F*U*C*K this", "fuuuuck", "sh1t", "f u c k", "visit www.example.com", "mysite.com",
                    "mail me a@b.co", "call 5551234567", "http://x", "kys"] {
            XCTAssertFalse(ContentFilter.isAcceptable(bad), bad)
        }
        for ok in ["Classic slime", "Scunthorpe sunset", "Grass bass", "Moon & stars", "Peaceful valley 2", "Dickens' cat", "Cocktail hour"] {
            XCTAssertTrue(ContentFilter.isAcceptable(ok), ok)
        }
    }

    func testTidy() {
        XCTAssertEqual(ContentFilter.tidy("  Hello \n\t world  ", maxLength: 40), "Hello world")
        XCTAssertEqual(ContentFilter.tidy(String(repeating: "a", count: 99), maxLength: 40).count, 40)
    }

    func testModerationRules() {
        func visible(_ reporters: Set<String> = [], blocked: Set<String> = [], mine: Set<String> = [], title: String = "Hi") -> Bool {
            CommunityModeration.isVisible(postID: "p", authorID: "u", title: title, author: "Nick",
                                          reporters: reporters, blockedAuthors: blocked, reportedByMe: mine)
        }
        XCTAssertTrue(visible())
        XCTAssertTrue(visible(["a", "b"]))
        XCTAssertFalse(visible(["a", "b", "c"]), "hidden after three reports")
        XCTAssertFalse(visible(blocked: ["u"]))
        XCTAssertFalse(visible(mine: ["p"]))
        XCTAssertFalse(visible(title: "shit"))
    }
}

enum StarterArtFixture {
    static func project() -> SpriteProject {
        var g = PixelGrid(width: 4, height: 4)
        g[1, 1] = .black
        return SpriteProject(name: "F", bounds: PixelRect(x: 0, y: 0, width: 4, height: 4), frames: [g], fps: 8)
    }
}

final class StillSpriteTests: XCTestCase {
    func testStillsParseAreSingleFrameAndFree() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PixelDeck/Resources/Starter/stills.json")
        let lib = CharacterSpriteLibrary.parse(try Data(contentsOf: url))
        XCTAssertEqual(CharacterSpriteLibrary.stillsOrder.count, 8)
        for key in CharacterSpriteLibrary.stillsOrder {
            let s = try XCTUnwrap(lib[key], key)
            XCTAssertEqual(s.frames.count, 1, "\(key) is a still")
            XCTAssertTrue(FeatureAccess.free.allowsArt(PixelRect(x: 0, y: 0, width: s.width, height: s.height)), "\(key) is editable for free")
            XCTAssertNotNil(s.frames[0].opaqueBounds, "\(key) isn't blank")
        }
    }
}

final class BlankCanvasTests: XCTestCase {
    private func store() -> ProjectStore {
        ProjectStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testNewCanvasReusesAnEmptySprite() {
        let s = store()
        let a = s.create()
        let b = s.create()
        XCTAssertEqual(a.id, b.id, "an empty sprite is reused")
        XCTAssertEqual(s.projects.count, 1)
    }

    func testDrawnSpritesAreNotReused() {
        let s = store()
        let m = EditorModel(project: s.create())
        m.onChange = { s.save($0) }
        m.pickColor(.black)
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchEnded()
        XCTAssertFalse(s.projects[0].isBlank)
        let next = s.create()
        XCTAssertNotEqual(next.id, m.project.id)
        XCTAssertEqual(s.projects.count, 2)
    }

    func testMoreFramesOrATracingPictureCountAsWork() {
        var p = SpriteProject(name: "x")
        XCTAssertTrue(p.isBlank)
        p.trace = TraceSettings()
        XCTAssertFalse(p.isBlank)
        let m = EditorModel(project: SpriteProject(name: "y"))
        m.addKeyframe()
        XCTAssertFalse(m.project.isBlank)
    }

    func testExtraBlanksAreCleanedUp() {
        let s = store()
        for i in 0..<4 {
            var p = SpriteProject(name: "Blank \(i)")
            p.modifiedAt = Date(timeIntervalSince1970: Double(1000 + i))
            s.save(p)
        }
        XCTAssertEqual(s.removeExtraBlanks().count, 3)
        XCTAssertEqual(s.projects.map(\.name), ["Blank 3"], "the newest blank is kept")
    }
}

final class CustomPaletteTests: XCTestCase {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("palettes.json")
    }

    func testSaveRenameUpdateDeleteAndReload() throws {
        let u = url()
        let lib = PaletteLibrary(url: u)
        let a = try XCTUnwrap(lib.add(name: "  Dusk  ", colors: PalettePreset.sunset.colors))
        let b = try XCTUnwrap(lib.add(name: "", colors: PalettePreset.ocean.colors))
        XCTAssertEqual(a.name, "Dusk")
        XCTAssertEqual(b.name, "My palette 2", "blank names get a default")
        XCTAssertEqual(lib.palettes.first?.id, b.id, "newest first")
        lib.rename(a.id, to: "Evening")
        lib.update(a.id, colors: PalettePreset.forest.colors)
        let reloaded = PaletteLibrary(url: u)
        XCTAssertEqual(reloaded.palettes.count, 2)
        XCTAssertEqual(reloaded.palettes.last?.name, "Evening")
        XCTAssertEqual(reloaded.palettes.last?.colors, PalettePreset.forest.colors)
        reloaded.delete(b.id)
        XCTAssertEqual(PaletteLibrary(url: u).palettes.map(\.name), ["Evening"])
    }

    func testOnlyFullPalettesAreSavedAndDamagedFilesLoadEmpty() throws {
        let u = url()
        let lib = PaletteLibrary(url: u)
        XCTAssertNil(lib.add(name: "Short", colors: [.black]))
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: u)
        XCTAssertTrue(PaletteLibrary(url: u).palettes.isEmpty)
    }

    func testApplyingASavedPaletteUsesItsColours() throws {
        let lib = PaletteLibrary(url: url())
        let saved = try XCTUnwrap(lib.add(name: "Mine", colors: PalettePreset.neon.colors))
        let m = EditorModel(project: SpriteProject(name: "x"))
        m.applyPalette(saved.colors)
        XCTAssertEqual(m.palette, PalettePreset.neon.colors)
    }
}

final class OnionSkinTests: XCTestCase {
    func testInnerFeaturesStayVisible() {
        // A green face with dark eyes and a red mouth.
        var g = PixelGrid(width: 7, height: 7, fill: RGBA(hex: 0x7BE07B))
        g[2, 2] = RGBA(hex: 0x1B1530); g[4, 2] = RGBA(hex: 0x1B1530)
        g[3, 4] = RGBA(hex: 0xE63946)
        let o = OnionSkin.tint(g)
        let face = o[5, 5]                               // plain face, no different neighbours
        XCTAssertNotEqual(o[2, 2], face, "eyes differ from the face")
        XCTAssertNotEqual(o[3, 4], face, "the mouth differs from the face")
        XCTAssertNotEqual(o[2, 3], face, "pixels next to a feature are edged")
        XCTAssertEqual(face.a, 255)
    }

    func testClearStaysClearAndColoursArePink() {
        var g = PixelGrid(width: 3, height: 1)
        g[1, 0] = RGBA(hex: 0x3A86FF)
        let o = OnionSkin.tint(g)
        XCTAssertTrue(o[0, 0].isClear); XCTAssertTrue(o[2, 0].isClear)
        XCTAssertGreaterThan(o[1, 0].r, o[1, 0].g, "tinted pink")
    }
}

final class GuidedTourTests: XCTestCase {
    /// Plays the whole tour the way a user would, checking each step finishes only when done.
    func testTheWholeTour() {
        let project = SpriteProject(name: "My first animation")
        let m = EditorModel(project: project)
        var step = TourStep.pickColor
        var base = TourBaseline(m)
        func done() -> Bool { GuidedTour.isDone(step, model: m, baseline: base, tourProjectID: project.id) }
        func advance() { step = step.next!; base = TourBaseline(m) }
        func paint(_ pts: [PixelPoint]) { for p in pts { m.touchBegan(at: Vec2(x: Double(p.x) + 0.5, y: Double(p.y) + 0.5)); m.touchEnded() } }

        XCTAssertFalse(done())
        m.pickColor(GuidedTour.pink); XCTAssertTrue(done()); advance()

        paint(Array(GuidedTour.heart.prefix(10))); XCTAssertFalse(done(), "half a heart isn't enough")
        paint(GuidedTour.heart); XCTAssertTrue(done()); advance()

        m.undo(); XCTAssertFalse(done(), "undo alone")
        m.redo(); XCTAssertTrue(done()); advance()

        XCTAssertTrue(step.hasNextButton); advance()     // zoom

        XCTAssertFalse(done())
        m.addKeyframe(); XCTAssertTrue(done()); advance()

        paint(GuidedTour.raisedHeart); XCTAssertTrue(done()); advance()

        XCTAssertFalse(done())
        m.onionOpacity = 0.6; XCTAssertTrue(done()); advance()

        m.duplicateFrame(at: 0); XCTAssertTrue(done()); advance()

        XCTAssertFalse(done(), "low, low, high isn't a bounce yet")
        m.moveFrame(from: 1, by: 1); XCTAssertTrue(done(), "low, high, low"); advance()

        m.isPlaying = true; XCTAssertTrue(done()); m.isPlaying = false; advance()

        XCTAssertTrue(step.hasNextButton); advance()     // more tools

        XCTAssertEqual(step, .newCanvas)
        XCTAssertFalse(done())
        m.load(SpriteProject(name: "Mine")); XCTAssertTrue(done())
        XCTAssertNil(step.next, "swiping right is the last step")
    }

    func testGuidesFitTheStartingCanvas() {
        let start = SpriteProject.initialBounds
        for p in GuidedTour.heart + GuidedTour.raisedHeart { XCTAssertTrue(start.contains(p), "\(p)") }
        XCTAssertEqual(GuidedTour.heart.count, 27)
    }
}

final class BrushAndTransformTests: XCTestCase {
    private func painted(_ m: EditorModel) -> Set<PixelPoint> {
        var out = Set<PixelPoint>()
        let b = m.bounds
        for y in b.y..<b.maxY { for x in b.x..<b.maxX where !m.pixel(PixelPoint(x: x, y: y)).isClear { out.insert(PixelPoint(x: x, y: y)) } }
        return out
    }

    func testBrushSizesAndRoundTips() {
        let m = makeModel()
        m.brushSize = 3
        tap(m, 5.5, 5.5)
        XCTAssertEqual(painted(m).count, 9)
        let r = makeModel()
        r.brushSize = 3; r.brushRound = true
        tap(r, 5.5, 5.5)
        XCTAssertEqual(painted(r).count, 5, "round 3 is a plus")
        m.brushSize = 9
        XCTAssertEqual(m.brushSize, EditorModel.maxBrushSize)
    }

    func testDitherAndFourWaySymmetryArePro() {
        var asked: [ProFeature] = []
        let free = makeModel()
        free.onProRequired = { asked.append($0) }
        free.dither = true; free.mirrorVertical = true
        XCTAssertFalse(free.dither); XCTAssertFalse(free.mirrorVertical)
        XCTAssertEqual(asked, [.artistBrushes, .artistBrushes])

        let pro = makeModel(access: .pro)
        pro.dither = true; pro.brushSize = 4
        tap(pro, 0.5, 0.5)
        let pts = painted(pro)
        XCTAssertEqual(pts.count, 8, "half of a 4x4 square")
        XCTAssertTrue(pts.allSatisfy { ($0.x + $0.y) & 1 == 0 }, "a fixed checkerboard")

        let quad = makeModel(access: .pro)
        quad.mirror = true; quad.mirrorVertical = true
        tap(quad, 2.5, 3.5)
        XCTAssertEqual(painted(quad), [P(2, 3), P(-3, 3), P(2, -4), P(-3, -4)])
    }

    func testFlipAndRotate() {
        let m = makeModel()
        // An L: (0,0) (0,1) (0,2) (1,2)
        for (x, y) in [(0, 0), (0, 1), (0, 2), (1, 2)] { tap(m, Double(x) + 0.5, Double(y) + 0.5) }
        let original = painted(m)
        XCTAssertTrue(m.transform(.flipHorizontal, allFrames: false))
        XCTAssertEqual(painted(m), [P(1, 0), P(1, 1), P(1, 2), P(0, 2)])
        m.transform(.flipHorizontal, allFrames: false)
        XCTAssertEqual(painted(m), original, "two flips undo each other")
        for _ in 0..<4 { m.transform(.rotateClockwise, allFrames: false) }
        XCTAssertEqual(painted(m), original, "four quarter turns")
        m.transform(.rotateClockwise, allFrames: false)
        XCTAssertEqual(painted(m).count, 4)
        m.transform(.rotateCounterClockwise, allFrames: false)
        XCTAssertEqual(painted(m), original)
        m.undo()
        XCTAssertNotEqual(painted(m), original, "undo steps back one transform")
    }

    func testAllFramesTurnAroundTheSameCentre() {
        let m = makeModel()
        tap(m, 0.5, 0.5)
        m.addKeyframe()
        tap(m, 3.5, 0.5)
        m.transform(.flipHorizontal, allFrames: true)
        XCTAssertEqual(m.pixel(P(3, 0), frame: 0), .black, "frame 1's pixel moved across the shared art")
        XCTAssertEqual(m.pixel(P(0, 0), frame: 1), .black)
        XCTAssertFalse(makeModel().transform(.rotateClockwise, allFrames: true), "nothing to turn")
    }
}

final class PaletteImportTests: XCTestCase {
    func testHexGimpAndPaintNet() throws {
        let hex = try XCTUnwrap(PaletteImport.parse(Data("ff0000\n#00FF00\n\n0000ff\nff0000\nnot a colour".utf8), fileName: "Primary.hex"))
        XCTAssertEqual(hex.name, "Primary")
        XCTAssertEqual(hex.colors, [RGBA(hex: 0xFF0000), RGBA(hex: 0x00FF00), RGBA(hex: 0x0000FF)], "duplicates and junk dropped")

        let gpl = try XCTUnwrap(PaletteImport.parse(Data("GIMP Palette\nName: Sunset\nColumns: 4\n#\n255 128   0\tOrange\n 10 20 30 Night\n".utf8), fileName: "x.gpl"))
        XCTAssertEqual(gpl.name, "Sunset")
        XCTAssertEqual(gpl.colors, [RGBA(r: 255, g: 128, b: 0), RGBA(r: 10, g: 20, b: 30)])

        let pdn = try XCTUnwrap(PaletteImport.parse(Data("; paint.net palette\nFF112233\nFFAABBCC\n".utf8), fileName: "p.txt"))
        XCTAssertEqual(pdn.colors, [RGBA(hex: 0x112233), RGBA(hex: 0xAABBCC)])

        XCTAssertNil(PaletteImport.parse(Data("hello".utf8), fileName: "nothing.txt"))
    }

    func testBigPalettesSplitIntoTens() {
        let colors = (0..<23).map { RGBA(r: UInt8($0 * 10), g: 0, b: 0) }
        let sets = PaletteImport.sets(name: "Big", colors: colors)
        XCTAssertEqual(sets.map(\.name), ["Big 1/3", "Big 2/3", "Big 3/3"])
        XCTAssertTrue(sets.allSatisfy { $0.colors.count == 10 })
        XCTAssertEqual(Array(sets[2].colors.prefix(3)), Array(colors.suffix(3)), "the last set starts with the leftovers")
        XCTAssertEqual(PaletteImport.sets(name: "Few", colors: [.black]).first?.colors.count, 10)
    }
}

final class TimelapseTests: XCTestCase {
    func testRecordsChangesOnlyAndPlaysOnOneCanvas() {
        let m = makeModel()
        var t = Timelapse()
        t.record(m.currentGrid, bounds: m.bounds)
        XCTAssertTrue(t.isEmpty, "blank frames aren't recorded")
        tap(m, 0.5, 0.5)
        t.record(m.currentGrid, bounds: m.bounds)
        t.record(m.currentGrid, bounds: m.bounds)
        XCTAssertEqual(t.shots.count, 1, "no duplicates")
        tap(m, 20.5, 5.5)                                  // the art grows
        t.record(m.currentGrid, bounds: m.bounds)
        let frames = t.playbackFrames()
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].width, frames[1].width, "one canvas for all shots")
        XCTAssertEqual(frames[0].width, 21)
    }

    func testThinsWhenFullButKeepsTheEnd() {
        var t = Timelapse()
        var g = PixelGrid(width: 1, height: 1)
        for i in 0..<(Timelapse.maxShots + 1) {
            g[0, 0] = RGBA(r: UInt8(i % 256), g: UInt8(i / 256), b: 1)
            t.record(g, bounds: PixelRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertLessThanOrEqual(t.shots.count, Timelapse.maxShots)
        XCTAssertEqual(t.shots.last?.grid[0, 0], g[0, 0], "the finished art is kept")
    }
}
