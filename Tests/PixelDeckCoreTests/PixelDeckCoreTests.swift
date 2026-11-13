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
