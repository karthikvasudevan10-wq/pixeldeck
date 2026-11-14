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
        XCTAssertEqual(p.fps, 30)
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
