import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0023 §D11: Duplica - a new node, a new id, a grid-step offset, and not one byte
// written outside the `.canvas`.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 2.
//
// RED (Task 2): `CanvasID.generate(avoiding:using:)` is a placeholder that calls `make()`
// once and never retries, so its collision-avoidance assertions fail on their assertions.
// `WorkspaceController.duplicate(nodeIDs:)` is a placeholder that returns `[]` and mutates
// nothing, so every assertion below that reads `document.nodes`, `document.edges`,
// `selection` or the id it returns fails on its assertion, not on a build error. Neither
// throws, neither force-unwraps.

// MARK: - `CanvasID.generate(avoiding:using:)` (ADR-0023 §D11)

@Test func generateAvoidingReturnsTheStubsValueWhenItIsFree() {
    let id = CanvasID.generate(avoiding: ["existing-a", "existing-b"], using: { "fresh-id" })
    #expect(id == "fresh-id")
}

@Test func generateAvoidingRetriesPastTwoCollisionsAndReturnsTheThirdValue() {
    var attempts = ["taken-1", "taken-2", "fresh-id"]
    let id = CanvasID.generate(avoiding: ["taken-1", "taken-2"], using: {
        attempts.removeFirst()
    })
    #expect(id == "fresh-id")
}

// The deterministic escape ADR-0023 §D11 describes: a generator that can never produce a
// free value on its own must still terminate with an id `taken` does not hold, not loop
// forever and not return the collision.
@Test func generateAvoidingTerminatesAndEscapesEvenWhenTheStubAlwaysCollides() {
    let taken: Set<String> = ["stuck"]
    let id = CanvasID.generate(avoiding: taken, using: { "stuck" })
    #expect(!taken.contains(id))
}

// `generate()` with no arguments must stay exactly what it was - `Tests/CanvasTests.swift`
// already pins its shape; this is a coverage note, not a duplicate assertion.

// MARK: - `WorkspaceController.duplicate(nodeIDs:)` fixtures

@MainActor
@Suite struct CanvasDuplicateWorkspaceControllerTests {
    // MARK: - New node's own fields (R-10)

    @Test func duplicatingOneFileNodeAppendsACopyWithANewIdAndAGridStepOffset() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.placeFile("foto.png", at: CGPoint(x: 100, y: 200))
        controller.setColor(.preset(3), forNodeIDs: [id])
        let original = try #require(controller.document.node(id: id))

        let newIDs = controller.duplicate(nodeIDs: [id])

        #expect(controller.document.nodes.count == 2)
        #expect(newIDs.count == 1)
        let newID = try #require(newIDs.first)
        #expect(newID != id)
        let copy = try #require(controller.document.node(id: newID))
        #expect(copy.kind == original.kind)
        #expect(copy.width == original.width)
        #expect(copy.height == original.height)
        #expect(copy.color == original.color)
        #expect(copy.unknown == original.unknown)
        #expect(copy.x == original.x + WorkspaceController.gridStep)
        #expect(copy.y == original.y + WorkspaceController.gridStep)
        controller.detach()
    }

    // MARK: - Id collision, nodes AND edges (§D11)

    @Test func theCopysIdDiffersFromEveryIdAlreadyInTheDocumentAcrossNodesAndEdges() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let a = controller.placeFile("a.png", at: .zero)
        let b = controller.placeFile("b.png", at: CGPoint(x: 300, y: 0))
        let edgeID = try #require(controller.connect(from: a, to: b))

        let newIDs = controller.duplicate(nodeIDs: [a])
        let newID = try #require(newIDs.first)

        let otherNodeIDs = Set(controller.document.nodes.map(\.id)).subtracting([newID])
        let edgeIDs = Set(controller.document.edges.map(\.id))
        #expect(!otherNodeIDs.contains(newID))
        #expect(!edgeIDs.contains(newID))
        // Sanity: the pre-existing edge itself must still be there, untouched.
        #expect(edgeIDs.contains(edgeID))
        controller.detach()
    }

    // MARK: - Edges untouched (§D11: "edges are not duplicated")

    @Test func edgesAreUnchangedWhenDuplicatingANodeThatHasOneOnIt() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let a = controller.placeFile("a.png", at: .zero)
        let b = controller.placeFile("b.png", at: CGPoint(x: 300, y: 0))
        _ = controller.connect(from: a, to: b)
        let edgesBefore = controller.document.edges

        controller.duplicate(nodeIDs: [a])

        #expect(controller.document.edges == edgesBefore)
        controller.detach()
    }

    // MARK: - Crop key survives (R-11's rendering premise)

    @Test func aNodeCarryingACropDuplicatesWithTheCropKeyIntact() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.placeFile("foto.png", at: .zero)
        controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
        controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
        controller.endCrop(confirm: true)
        let cropValue = try #require(controller.document.node(id: id)?.unknown[CanvasCrop.key])

        let newIDs = controller.duplicate(nodeIDs: [id])
        let newID = try #require(newIDs.first)
        let copy = try #require(controller.document.node(id: newID))

        #expect(copy.unknown[CanvasCrop.key] == cropValue)
        controller.detach()
    }

    // MARK: - R-10's real content: only the `.canvas` file's bytes change

    @Test func duplicatingChangesOnlyTheCanvasFilesBytesNotTheFolderListing() throws {
        let root = try CanvasTemporaryRoot()
        try root.makeFile("foto.png", "not a real png, only presence matters here")
        let store = CanvasStore(root: root.url)
        let controller = WorkspaceController()
        controller.attach(to: store)
        // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
        // opened explicitly before the controller has anywhere to write to.
        let board = try store.createBoard(named: root.url.lastPathComponent, in: "")
        controller.open(board: board)
        let id = controller.placeFile("foto.png", at: .zero)
        controller.flushPendingSave()

        // Addressed by its own path (ADR-0025 §D1): the root board is the `.canvas`
        // named after the vault, which is the path the controller opened.
        let canvasURL = try store.url(forBoard: "\(root.url.lastPathComponent).canvas")
        let namesBefore = try FileManager.default
            .contentsOfDirectory(atPath: root.url.path(percentEncoded: false)).sorted()
        let bytesBefore = try Data(contentsOf: canvasURL)

        controller.duplicate(nodeIDs: [id])
        controller.flushPendingSave()

        let namesAfter = try FileManager.default
            .contentsOfDirectory(atPath: root.url.path(percentEncoded: false)).sorted()
        let bytesAfter = try Data(contentsOf: canvasURL)

        #expect(namesBefore == namesAfter)
        #expect(bytesAfter != bytesBefore)
        controller.detach()
    }

    // MARK: - R-11: missing referenced file

    @Test func duplicatingANodeWhoseFileNoLongerExistsStillCreatesTheCopy() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        // No file written for "sparita.png" - the node is a pointer to nothing, the same
        // way a card whose source vanished from the Finder already renders (broken-file
        // placeholder), and duplicating it must not special-case that.
        let id = controller.addNode(CanvasNode(
            id: CanvasID.generate(), kind: .file(path: "sparita.png", subpath: nil),
            x: 0, y: 0, width: 260, height: 180
        ))

        let newIDs = controller.duplicate(nodeIDs: [id])

        #expect(controller.document.nodes.count == 2)
        let newID = try #require(newIDs.first)
        let copy = try #require(controller.document.node(id: newID))
        #expect(copy.kind == .file(path: "sparita.png", subpath: nil))
        #expect(!FileManager.default.fileExists(
            atPath: root.url.appending(path: "sparita.png", directoryHint: .notDirectory).path(percentEncoded: false)
        ))
        controller.detach()
    }

    // MARK: - Round-trip (R-10)

    @Test func aDuplicateSurvivesSaveAndLoadAsTwoNodesWithDistinctIdsAndTheSameFile() throws {
        let root = try CanvasTemporaryRoot()
        let store = CanvasStore(root: root.url)
        let controller = WorkspaceController()
        controller.attach(to: store)
        // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
        // opened explicitly before the controller has anywhere to write to.
        let board = try store.createBoard(named: root.url.lastPathComponent, in: "")
        controller.open(board: board)
        let id = controller.placeFile("foto.png", at: .zero)

        controller.duplicate(nodeIDs: [id])
        controller.flushPendingSave()
        controller.detach()

        let reloaded = try store.load(board: "\(root.url.lastPathComponent).canvas")
        #expect(reloaded.nodes.count == 2)
        #expect(Set(reloaded.nodes.map(\.id)).count == 2)
        let paths = reloaded.nodes.compactMap { node -> String? in
            if case .file(let path, _) = node.kind { return path }
            return nil
        }
        #expect(paths.sorted() == ["foto.png", "foto.png"])
    }

    // MARK: - Selection cascades (§D8)

    @Test func selectionAfterDuplicateIsExactlyTheNewIdsSoASecondDuplicaCascades() throws {
        let root = try CanvasTemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.placeFile("foto.png", at: .zero)
        controller.select(nodeID: id, adding: false)

        let firstIDs = controller.duplicate(nodeIDs: [id])
        #expect(controller.selection == Set(firstIDs))

        let secondIDs = controller.duplicate(nodeIDs: controller.selection)
        #expect(controller.selection == Set(secondIDs))
        // A second Duplica must cascade from the fresh selection, not re-duplicate the
        // original card.
        #expect(Set(secondIDs).isDisjoint(with: Set(firstIDs)))
        controller.detach()
    }
}
