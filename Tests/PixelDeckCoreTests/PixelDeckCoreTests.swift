import XCTest
@testable import PixelDeckCore

final class PixelGridTests: XCTestCase {
    func testLineIsContinuousAndInclusive() {
        var g = PixelGrid(size: 8)
        g.drawLine(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 7, y: 3), color: .black)
        XCTAssertEqual(g[0, 0], .black)
        XCTAssertEqual(g[7, 3], .black)
        XCTAssertEqual(g.pixels.filter { !$0.isClear }.count, 8)
    }

    func testFloodFillStopsAtBorders() {
        var g = PixelGrid(size: 8)
        for i in 0..<8 { g[3, i] = .black }
        g.floodFill(from: PixelPoint(x: 0, y: 0), with: .white)
        XCTAssertEqual(g[2, 7], .white)
        XCTAssertEqual(g[3, 4], .black)
        XCTAssertEqual(g[4, 0], .clear)
    }

    func testCodableRoundTrip() throws {
        var g = PixelGrid(size: 16)
        g[5, 9] = RGBA(hex: 0x12AB34)
        let p = SpriteProject(name: "A", size: 16)
        var q = p
        q.frames[0].grid = g
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(SpriteProject.self, from: data)
        XCTAssertEqual(back.frames[0].grid, g)
        XCTAssertEqual(back.name, "A")
    }

    func testScaledBytes() {
        var g = PixelGrid(size: 2)
        g[1, 0] = .black
        let b = g.rgbaBytes(scale: 2)
        XCTAssertEqual(b.count, 4 * 4 * 4)
        // Row 0, x = 2 and 3 are black.
        XCTAssertEqual(b[2 * 4 + 3], 255)
        XCTAssertEqual(b[3 * 4 + 3], 255)
        XCTAssertEqual(b[1 * 4 + 3], 0)
    }
}

final class MotionPathTests: XCTestCase {
    func testRefinedKeepsEndpointsAndRemovesJitter() {
        var path = MotionPath()
        for i in 1...40 {
            path.append(Vec2(x: Double(i) * 0.25, y: (i % 2 == 0 ? 0.2 : -0.2)))
        }
        let r = path.refined()
        XCTAssertEqual(r.points.first, .zero)
        XCTAssertEqual(r.points.last, path.end)
        XCTAssertLessThan(r.length, path.length)
    }

    func testPointAtFractionIsByDistance() {
        let p = MotionPath(points: [.zero, Vec2(x: 10, y: 0), Vec2(x: 10, y: 10)])
        XCTAssertEqual(p.point(atFraction: 0.5), Vec2(x: 10, y: 0))
        XCTAssertEqual(p.point(atFraction: 0.75), Vec2(x: 10, y: 5))
        XCTAssertEqual(p.point(atFraction: 1), Vec2(x: 10, y: 10))
    }

    func testOffsetsEndExactlyAtDestination() {
        let plan = TweenPlan(sourceRect: PixelRect(x: 0, y: 0, width: 1, height: 1),
                             patch: PixelPatch(width: 1, height: 1, pixels: [.black]),
                             path: .straight(to: Vec2(x: 6.4, y: 0)), easing: .easeInOut)
        let o = plan.offsets(count: 4)
        XCTAssertEqual(o.count, 4)
        XCTAssertEqual(o.last, PixelPoint(x: 6, y: 0))
        XCTAssertEqual(o.map(\.x), o.map(\.x).sorted())
    }
}

final class EditorModelTests: XCTestCase {
    func testPencilStrokeAndUndo() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 8))
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5))
        m.touchMoved(to: Vec2(x: 4.5, y: 0.5))
        m.touchEnded()
        XCTAssertEqual(m.currentGrid[4, 0], .black)
        XCTAssertTrue(m.canUndo)
        m.undo()
        XCTAssertTrue(m.currentGrid.isBlank)
        m.redo()
        XCTAssertEqual(m.currentGrid[2, 0], .black)
    }

    func testCancelledStrokeLeavesNoTrace() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 8))
        m.touchBegan(at: Vec2(x: 1.5, y: 1.5))
        m.touchCancelled()
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertFalse(m.canUndo)
    }

    func testAddKeyframeShowsOnionSkin() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 8))
        m.touchBegan(at: Vec2(x: 1.5, y: 1.5)); m.touchEnded()
        m.addKeyframe()
        XCTAssertEqual(m.frameCount, 2)
        XCTAssertEqual(m.currentIndex, 1)
        XCTAssertTrue(m.currentGrid.isBlank)
        XCTAssertEqual(m.onionGrid?[1, 1], .black)
    }

    /// Select a 2×2 block, drag it 6 px right along a wobbly path, then tween.
    private func movedBlockModel() -> EditorModel {
        let m = EditorModel(project: SpriteProject(name: "T", size: 16))
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchMoved(to: Vec2(x: 1.5, y: 0.5)); m.touchEnded()
        m.touchBegan(at: Vec2(x: 0.5, y: 1.5)); m.touchMoved(to: Vec2(x: 1.5, y: 1.5)); m.touchEnded()
        m.tool = .select
        m.touchBegan(at: Vec2(x: 0.2, y: 0.2)); m.touchMoved(to: Vec2(x: 1.8, y: 1.8)); m.touchEnded()
        XCTAssertEqual(m.marquee, PixelRect(x: 0, y: 0, width: 2, height: 2))
        m.touchBegan(at: Vec2(x: 1, y: 1))
        for i in 1...24 { m.touchMoved(to: Vec2(x: 1 + Double(i) * 0.25, y: 1 + (i % 3 == 0 ? 0.3 : 0))) }
        m.touchEnded()
        return m
    }

    func testMoveSelection() {
        let m = movedBlockModel()
        XCTAssertEqual(m.selectionRect?.origin, PixelPoint(x: 6, y: 0))
        XCTAssertEqual(m.currentGrid[6, 0], .black)
        XCTAssertEqual(m.currentGrid[0, 0], .clear)
        XCTAssertTrue(m.canTween)
    }

    func testTweenInsertsFramesAlongPath() {
        let m = movedBlockModel()
        m.generateTween(frameCount: 6, easing: .linear, style: .traced, mode: .insertFrames)
        XCTAssertEqual(m.frameCount, 7)
        XCTAssertEqual(m.project.frames[0].grid[0, 0], .black, "first frame back at the start")
        XCTAssertEqual(m.project.frames[6].grid[6, 0], .black, "last frame at the destination")
        XCTAssertEqual(m.project.frames[6].grid[0, 0], .clear)
        // Every frame holds exactly the 4 block pixels, moving monotonically right.
        var lastX = -1
        for f in m.project.frames {
            XCTAssertEqual(f.grid.pixels.filter { !$0.isClear }.count, 4)
            let x = (0..<16).first { f.grid[$0, 0] == .black }!
            XCTAssertGreaterThanOrEqual(x, lastX)
            lastX = x
        }
        XCTAssertEqual(m.currentIndex, 6)
        m.undo()
        XCTAssertEqual(m.frameCount, 1)
    }

    func testTweenAcrossExistingFramesKeepsTheirOtherPixels() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 16))
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchEnded()
        m.addKeyframe(); m.addKeyframe()
        m.touchBegan(at: Vec2(x: 10.5, y: 10.5)); m.touchEnded() // background detail in frame 3
        m.selectFrame(0)
        m.tool = .select
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchEnded() // 1×1 marquee
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchMoved(to: Vec2(x: 4.5, y: 0.5)); m.touchEnded()
        m.generateTween(frameCount: 0, easing: .linear, style: .straight, mode: .spreadAcrossFollowing)
        XCTAssertEqual(m.frameCount, 3)
        XCTAssertEqual(m.project.frames[0].grid[0, 0], .black)
        XCTAssertEqual(m.project.frames[1].grid[2, 0], .black)
        XCTAssertEqual(m.project.frames[2].grid[4, 0], .black)
        XCTAssertEqual(m.project.frames[2].grid[10, 10], .black)
    }

    func testStorePersists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        let p = store.create(size: 32)
        store.flush()
        let reloaded = ProjectStore(directory: dir)
        XCTAssertEqual(reloaded.projects.map(\.id), [p.id])
        XCTAssertEqual(reloaded.projects[0].size, 32)
        try? FileManager.default.removeItem(at: dir)
    }

    func testSpriteSheetGrid() {
        var a = PixelGrid(size: 2); a[0, 0] = .black
        var b = PixelGrid(size: 2); b[1, 1] = .white
        let sheet = SpriteSheet(grids: [a, b, a], scale: 1, layout: .grid)
        XCTAssertEqual(sheet.columns, 2)
        XCTAssertEqual(sheet.rows, 2)
        XCTAssertEqual(sheet.width, 4)
        // Frame 1 (b) is at x 2…3, y 0…1; its pixel (1,1) → sheet (3,1).
        XCTAssertEqual(sheet.bytes[(1 * 4 + 3) * 4], 255)
        let meta = sheet.metadata(fps: 10, imageName: "s.png")
        XCTAssertEqual(meta.frames[2].y, 2)
    }
}

final class FeatureAccessTests: XCTestCase {
    func testFreeFrameLimitAsksForPro() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 8))
        var asked: ProFeature?
        m.onProRequired = { asked = $0 }
        for _ in 1..<FeatureAccess.freeFrameLimit { XCTAssertTrue(m.addKeyframe()) }
        XCTAssertEqual(m.frameCount, FeatureAccess.freeFrameLimit)
        XCTAssertNil(asked)
        XCTAssertFalse(m.addKeyframe())
        XCTAssertEqual(asked, .unlimitedFrames)
        XCTAssertEqual(m.frameCount, FeatureAccess.freeFrameLimit)

        m.access = .pro
        XCTAssertTrue(m.addKeyframe())
    }

    func testTweenInsertRespectsLimit() {
        let m = EditorModel(project: SpriteProject(name: "T", size: 16))
        var asked = false
        m.onProRequired = { _ in asked = true }
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchEnded()
        m.tool = .select
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchEnded()
        m.touchBegan(at: Vec2(x: 0.5, y: 0.5)); m.touchMoved(to: Vec2(x: 8.5, y: 0.5)); m.touchEnded()
        m.generateTween(frameCount: 40, easing: .linear, style: .straight, mode: .insertFrames)
        XCTAssertTrue(asked)
        XCTAssertEqual(m.frameCount, 1)
        XCTAssertNotNil(m.floating, "selection is kept so the user can try fewer frames")
        m.generateTween(frameCount: m.remainingFrameAllowance, easing: .linear, style: .straight, mode: .insertFrames)
        XCTAssertEqual(m.frameCount, FeatureAccess.freeFrameLimit)
    }

    func testCanvasSizes() {
        XCTAssertTrue(FeatureAccess.free.allowsCanvas(size: 32))
        XCTAssertFalse(FeatureAccess.free.allowsCanvas(size: 64))
        XCTAssertTrue(FeatureAccess.pro.allowsCanvas(size: 256))
        XCTAssertFalse(FeatureAccess.free.allowsGIF)
    }

    func testStoreCoalescesWritesAndFlushes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        var p = store.create(size: 8)
        for i in 0..<20 {
            p.name = "Name \(i)"
            store.save(p)
        }
        store.flush()
        XCTAssertEqual(ProjectStore(directory: dir).projects.first?.name, "Name 19")
        store.delete(id: p.id)
        store.flush()
        XCTAssertTrue(ProjectStore(directory: dir).projects.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }
}

final class LocalisableNamesTests: XCTestCase {
    func testStoreUsesCallerProvidedNames() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(directory: dir)
        let a = store.create(size: 8, baseName: "Lutin")
        XCTAssertEqual(a.name, "Lutin 1")
        XCTAssertEqual(store.create(size: 8, baseName: "Lutin").name, "Lutin 2")
        store.duplicate(id: a.id) { "Copie de \($0)" }
        XCTAssertTrue(store.projects.contains { $0.name == "Copie de Lutin 1" })
        try? FileManager.default.removeItem(at: dir)
    }
}

final class RobustnessTests: XCTestCase {
    func testRunLengthEncodingRoundTripAndIsSmall() throws {
        var g = PixelGrid(size: 256)
        g.drawLine(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 255, y: 255), color: .black)
        g[3, 200] = RGBA(hex: 0xABCDEF)
        let rle = g.runLengthEncoded()
        // A diagonal breaks every row into runs (~513 runs × 6 bytes) — still ~1% of the 262 144 raw bytes.
        XCTAssertLessThan(rle.count, 4000)
        XCTAssertEqual(PixelGrid(size: 256, runLengthEncoded: rle), g)
        let json = try JSONEncoder().encode(g)
        XCTAssertEqual(try JSONDecoder().decode(PixelGrid.self, from: json), g)
    }

    func testCorruptRunLengthDataFailsInsteadOfCrashing() {
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([1, 0, 0, 0, 0])))      // truncated
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([0xFF, 0xFF, 0, 0, 0, 0]))) // too many pixels
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data([0, 0, 0, 0, 0, 0])))     // zero-length run
        XCTAssertNil(PixelGrid(size: 8, runLengthEncoded: Data()))                        // too few pixels
    }

    func testLegacyRawFormatStillLoads() throws {
        var g = PixelGrid(size: 2); g[1, 1] = .black
        let legacy = #"{"size":2,"rgba":"\#(Data(g.rgbaBytes()).base64EncodedString())"}"#
        XCTAssertEqual(try JSONDecoder().decode(PixelGrid.self, from: Data(legacy.utf8)), g)
    }

    func testDamagedProjectLoadsAsEditable() throws {
        let good = try JSONEncoder().encode(PixelGrid(size: 8))
        let goodFrame = #"{"id":"\#(UUID().uuidString)","grid":\#(String(decoding: good, as: UTF8.self))}"#
        let json = """
        {"id":"\(UUID().uuidString)","name":"  ","size":8,"fps":500,
         "frames":[{"id":"\(UUID().uuidString)","grid":{"size":16,"rle":""}}, {"garbage":true}, \(goodFrame)]}
        """
        let p = try JSONDecoder().decode(SpriteProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.frames.count, 1, "the bad and wrong-size frames are dropped, the good one kept")
        XCTAssertEqual(p.fps, 30)
        XCTAssertEqual(p.name, "Sprite")

        let empty = #"{"id":"\#(UUID().uuidString)","name":"E","size":8,"frames":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(SpriteProject.self, from: Data(empty.utf8)).frames.count, 1)

        let huge = #"{"id":"\#(UUID().uuidString)","name":"H","size":100000,"frames":[]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SpriteProject.self, from: Data(huge.utf8)))
    }

    func testMemoryBudgetLimitsBigCanvases() {
        XCTAssertEqual(FeatureAccess.pro.frameLimit(forCanvas: 256), 256)
        XCTAssertEqual(FeatureAccess.pro.frameLimit(forCanvas: 128), 999)
        XCTAssertEqual(FeatureAccess.free.frameLimit(forCanvas: 32), FeatureAccess.freeFrameLimit)

        let m = EditorModel(project: SpriteProject(name: "Big", size: 256))
        m.access = .pro
        var asked = false
        m.onProRequired = { _ in asked = true }
        while m.addKeyframe() {}
        XCTAssertEqual(m.frameCount, 256)
        XCTAssertFalse(asked, "Pro users aren't offered Pro when the memory budget is the limit")
    }
}
