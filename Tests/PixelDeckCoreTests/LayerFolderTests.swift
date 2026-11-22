import XCTest
@testable import PixelDeckCore

final class LayerFolderTests: XCTestCase {
    private func P(_ x: Int, _ y: Int) -> PixelPoint { PixelPoint(x: x, y: y) }

    private func tap(_ m: EditorModel, _ x: Double, _ y: Double) {
        m.touchBegan(at: Vec2(x: x, y: y))
        m.touchEnded()
    }

    /// Five layers, bottom to top: A B C D E, each with one pixel at (its number, 0).
    private func fiveLayers() -> EditorModel {
        let m = EditorModel(project: SpriteProject(name: "T"))
        m.access = .pro
        m.renameLayer(0, to: "A")
        tap(m, 0.5, 0.5)
        for (n, name) in ["B", "C", "D", "E"].enumerated() {
            m.addLayer(named: name)
            tap(m, Double(n + 1) + 0.5, 0.5)
        }
        return m
    }

    private func names(_ m: EditorModel) -> String { m.layers.map(\.name).joined() }

    /// The outline as text, top first: loose layers as letters, folders in brackets.
    private func outline(_ m: EditorModel) -> String {
        m.project.layerOutline.map { entry in
            switch entry {
            case .layer(_, let index): m.layers[index].name
            case .folder(let f, let indices): "[\(f.name):" + indices.map { m.layers[$0].name }.joined() + "]"
            }
        }.joined(separator: " ")
    }

    /// Each layer still holds its own pixel, wherever it has moved to.
    private func assertPixelsFollowedTheirLayers(_ m: EditorModel, file: StaticString = #filePath, line: UInt = #line) {
        let frame = m.project.frames[0]
        for (i, layer) in m.layers.enumerated() {
            let x = Int(layer.name.unicodeScalars.first!.value) - 65       // A is 0, B is 1...
            let local = P(x, 0) - m.project.bounds.origin
            XCTAssertFalse(frame.layers[i][local].isClear, "\(layer.name)'s pixel moved with it", file: file, line: line)
        }
    }

    func testGroupingAndTheOutline() {
        let m = fiveLayers()
        XCTAssertEqual(outline(m), "E D C B A")
        let f = m.newFolder(containing: 1, named: "Body")!          // B
        XCTAssertEqual(outline(m), "E D C [Body:B] A")
        // C joins: it goes on top of the folder's layers, which is where it already is.
        m.moveLayer(2, toFolder: f)
        XCTAssertEqual(outline(m), "E D [Body:CB] A")
        // E joins from the top of the stack: it moves down next to the others.
        m.moveLayer(4, toFolder: f)
        XCTAssertEqual(outline(m), "D [Body:ECB] A")
        XCTAssertEqual(names(m), "ABCED")
        assertPixelsFollowedTheirLayers(m)
        // C leaves: it comes out just above the folder.
        m.moveLayer(m.layers.firstIndex { $0.name == "C" }!, toFolder: nil)
        XCTAssertEqual(outline(m), "D C [Body:EB] A")
        assertPixelsFollowedTheirLayers(m)
    }

    func testMovingLayersAndFolders() {
        let m = fiveLayers()
        let f = m.newFolder(containing: 1, named: "F")!             // B
        m.moveLayer(2, toFolder: f)                                 // C
        XCTAssertEqual(outline(m), "E D [F:CB] A")
        // Inside a folder a layer moves among its folder's layers only.
        XCTAssertNil(m.layerMoveTarget(2, by: 1))                   // C is the folder's top
        m.moveLayer(1, by: 1)                                       // B over C
        XCTAssertEqual(outline(m), "E D [F:BC] A")
        // A loose layer steps over the whole folder.
        m.moveLayer(0, by: 1)                                       // A
        XCTAssertEqual(outline(m), "E D A [F:BC]")
        m.moveLayer(m.layers.firstIndex { $0.name == "A" }!, by: -1)
        XCTAssertEqual(outline(m), "E D [F:BC] A")
        // The folder moves as one.
        XCTAssertTrue(m.canMoveFolder(f, by: 1))
        m.moveFolder(f, by: 1)
        XCTAssertEqual(outline(m), "E [F:BC] D A")
        m.moveFolder(f, by: 1)
        XCTAssertEqual(outline(m), "[F:BC] E D A")
        XCTAssertFalse(m.canMoveFolder(f, by: 1))
        // Over another folder, both stay whole.
        let g = m.newFolder(containing: m.layers.firstIndex { $0.name == "D" }!, named: "G")!
        m.moveLayer(m.layers.firstIndex { $0.name == "A" }!, toFolder: g)
        XCTAssertEqual(outline(m), "[F:BC] E [G:AD]")
        m.moveFolder(g, by: 1)
        m.moveFolder(g, by: 1)
        XCTAssertEqual(outline(m), "[G:AD] [F:BC] E")
        assertPixelsFollowedTheirLayers(m)
        // The layer being drawn on is still the same layer.
        let active = m.layers[m.activeLayer].name
        m.moveFolder(g, by: -1)
        XCTAssertEqual(m.layers[m.activeLayer].name, active)
    }

    func testHidingAFolderHidesItsLayers() {
        let m = fiveLayers()
        let f = m.newFolder(containing: 1, named: "F")!             // B at (1, 0)
        m.moveLayer(2, toFolder: f)                                 // C at (2, 0)
        XCTAssertFalse(m.pixel(P(1, 0)).isClear)
        m.setFolderVisible(f, false)
        XCTAssertTrue(m.pixel(P(1, 0)).isClear)
        XCTAssertTrue(m.pixel(P(2, 0)).isClear)
        XCTAssertFalse(m.pixel(P(0, 0)).isClear, "layers outside the folder still show")
        XCTAssertTrue(m.layers[1].isVisible, "each layer keeps its own setting")
        m.undo()
        XCTAssertFalse(m.pixel(P(1, 0)).isClear)
        m.setFolderVisible(f, false)
        m.ungroupFolder(f)
        XCTAssertFalse(m.pixel(P(1, 0)).isClear, "out of a hidden folder, the layers show again")
        XCTAssertTrue(m.folders.isEmpty)
    }

    func testNewLayersJoinTheFolderTheyAreAddedIn() {
        let m = fiveLayers()
        let f = m.newFolder(containing: 2, named: "F")!             // C
        m.selectLayer(2)
        m.addLayer(named: "X")
        XCTAssertEqual(m.layers[3].folderID, f)
        XCTAssertEqual(outline(m), "E D [F:XC] B A")
    }

    func testDeletingAndEmptyingFolders() {
        let m = fiveLayers()
        let f = m.newFolder(containing: 1, named: "F")!
        m.moveLayer(2, toFolder: f)
        XCTAssertTrue(m.canDeleteFolder(f))
        m.selectLayer(2)
        m.deleteFolder(f)
        XCTAssertEqual(outline(m), "E D A")
        XCTAssertTrue(m.folders.isEmpty)
        XCTAssertEqual(m.layers[m.activeLayer].name, "A")
        assertPixelsFollowedTheirLayers(m)
        m.undo()
        XCTAssertEqual(outline(m), "E D [F:CB] A")
        // Deleting the last layer in a folder removes the folder.
        let g = m.newFolder(containing: 0, named: "G")!
        XCTAssertNotNil(m.project.folder(id: g))
        m.deleteLayer(0)
        XCTAssertNil(m.project.folder(id: g))
        // A folder holding every layer can't be deleted with them.
        let solo = EditorModel(project: SpriteProject(name: "S"))
        let all = solo.newFolder(containing: 0)!
        XCTAssertFalse(solo.canDeleteFolder(all))
        solo.deleteFolder(all)
        XCTAssertEqual(solo.layers.count, 1)
    }

    func testFoldersAreSavedAndTidiedOnOpening() throws {
        let m = fiveLayers()
        let f = m.newFolder(containing: 1, named: "Body")!
        m.moveLayer(2, toFolder: f)
        m.setFolderCollapsed(f, true)
        m.setFolderVisible(f, false)
        let back = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(m.project))
        XCTAssertEqual(back.folders.map(\.name), ["Body"])
        XCTAssertEqual(back.folders[0].isCollapsed, true)
        XCTAssertEqual(back.layers.map { $0.folderID == f }, [false, true, true, false, false])
        XCTAssertEqual(back.layerVisibility, [true, false, false, true, true])
        let local = P(1, 0) - back.bounds.origin
        XCTAssertTrue(back.frames[0].grid[local].isClear, "a hidden folder's layers stay hidden when the sprite is opened")

        // A file whose folders have come apart is put right: stray layers are loose again.
        var layers = [LayerInfo(name: "A"), LayerInfo(name: "B"), LayerInfo(name: "C"), LayerInfo(name: "D")]
        var folders = [LayerFolder(name: "F"), LayerFolder(name: "Empty")]
        let unknown = UUID()
        layers[0].folderID = folders[0].id          // apart from the group at the top
        layers[1].folderID = unknown
        layers[3].folderID = folders[0].id
        SpriteProject.tidyFolders(layers: &layers, folders: &folders)
        XCTAssertEqual(layers.map { $0.folderID != nil }, [false, false, false, true])
        XCTAssertEqual(folders.map(\.name), ["F"])
        // A sprite saved before folders existed opens with none.
        let plain = try JSONDecoder().decode(SpriteProject.self, from: JSONEncoder().encode(SpriteProject(name: "Old")))
        XCTAssertTrue(plain.folders.isEmpty)
    }
}
