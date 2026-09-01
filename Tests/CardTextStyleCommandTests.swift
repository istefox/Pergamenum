import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0027 §D4, §D7; plan `docs/superpowers/plans/2026-08-28-unificare-nota-e-testo-in-un-solo-strume.md`,
// Task 7 (R-06).
//
// `WorkspaceController.setTextColor(_:forNodeIDs:)` and `.setTextAlignment(_:forNodeIDs:)`
// are the write path the two new `CardCommand` cases (`.textColor`, `.textAlign`) call
// through - mirroring `setColor(_:forNodeIDs:)`'s own shape (`WorkspaceController.swift:536`):
// one `mutate` call writing at most one prefixed key, removing it rather than writing a
// default when the value is cleared.
//
// RED (Task 7): both methods are `fatalError` stubs until the coder fills them in, so every
// `@Test` below that calls either one is expected to crash the run, not merely fail an
// assertion, until that happens - the same contract `CardTextStyleTests.swift`'s own header
// documents for `CardTextStyle.read`/`.rgba`. Unlike that file, this one needs a real
// `WorkspaceController` + `CanvasStore` (the write path this task adds lives on the
// controller, not on the pure value type), so it follows `CanvasCropRoundTripTests`'s own
// shape (`Tests/CanvasCropTests.swift`) rather than `CardTextStyleTests.swift`'s.
@MainActor
@Suite struct CardTextStyleCommandTests {
    private struct TemporaryRoot: ~Copyable {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appending(path: "pergamenum-textstyle-cmd-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Setting colour writes exactly one key

    @Test func settingColorOnATextNodeWritesTheColorKeyAndNothingElseChanges() throws {
        let root = try TemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.addFreeText("ciao", at: .zero)
        let before = try #require(controller.document.node(id: id))

        controller.setTextColor(.preset(3), forNodeIDs: [id])

        let after = try #require(controller.document.node(id: id))
        #expect(after.unknown.count == 1)
        #expect(after.unknown[CardTextStyle.colorKey] == .string("3"))
        #expect(after.kind == before.kind)
        #expect(after.x == before.x)
        #expect(after.y == before.y)
        #expect(after.width == before.width)
        #expect(after.height == before.height)
        #expect(after.color == before.color)
        controller.detach()
    }

    // MARK: Setting then clearing alignment - no leftover key, no default written

    @Test func settingThenClearingAlignmentLeavesTheNodesUnknownExactlyAsItStarted() throws {
        let root = try TemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.addFreeText("ciao", at: .zero)
        let originalUnknown = try #require(controller.document.node(id: id)).unknown

        controller.setTextAlignment(.center, forNodeIDs: [id])
        controller.setTextAlignment(nil, forNodeIDs: [id])

        let node = try #require(controller.document.node(id: id))
        #expect(node.unknown == originalUnknown)
        #expect(node.unknown[CardTextStyle.alignKey] == nil)
        controller.detach()
    }

    // MARK: SPEC edge case - deleting all text leaves both properties in place

    @Test func deletingAllOfACardsTextLeavesColorAndAlignmentInPlace() throws {
        let root = try TemporaryRoot()
        let controller = try openedWorkspaceController(rootURL: root.url)
        let id = controller.addFreeText("ciao", at: .zero)
        controller.setTextColor(.preset(2), forNodeIDs: [id])
        controller.setTextAlignment(.right, forNodeIDs: [id])

        controller.setText("", forNodeID: id)

        let node = try #require(controller.document.node(id: id))
        #expect(node.kind == .text(""))
        let style = CardTextStyle.read(from: node)
        #expect(style.color == .preset(2))
        #expect(style.alignment == .right)
        controller.detach()
    }

    // MARK: A node that also carries a crop

    @Test func settingColorOrAlignmentLeavesAnExistingCropUntouched() throws {
        let canvas = """
        {"nodes":[{"id":"a","type":"text","x":0,"y":0,"width":220,"height":60,
                   "text":"ciao","pergamenum-crop":"0.1000 0.1000 0.5000 0.5000"}],"edges":[]}
        """
        let root = try TemporaryRoot()
        let store = CanvasStore(root: root.url)
        try store.save(
            try CanvasDocument(data: Data(canvas.utf8)), board: "\(root.url.lastPathComponent).canvas"
        )
        let controller = WorkspaceController()
        controller.attach(to: store)
        controller.open(board: "\(root.url.lastPathComponent).canvas")

        controller.setTextColor(.preset(5), forNodeIDs: ["a"])
        controller.setTextAlignment(.justify, forNodeIDs: ["a"])

        let node = try #require(controller.document.node(id: "a"))
        #expect(node.unknown[CanvasCrop.key] == .string("0.1000 0.1000 0.5000 0.5000"))
        #expect(node.unknown[CardTextStyle.colorKey] == .string("5"))
        #expect(node.unknown[CardTextStyle.alignKey] == .string("justify"))
        #expect(node.kind == .text("ciao"))
        controller.detach()
    }

    // MARK: R-06 - both survive a save/close/reopen of the board

    @Test func bothPropertiesSurviveASaveAndReopenOfTheBoard() throws {
        let root = try TemporaryRoot()
        let store = CanvasStore(root: root.url)
        let controller = WorkspaceController()
        controller.attach(to: store)
        // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
        // opened explicitly before there is anywhere for the controller to write to.
        let board = try store.createBoard(named: root.url.lastPathComponent, in: "")
        controller.open(board: board)
        let id = controller.addFreeText("ciao", at: CGPoint(x: 10, y: 20))

        controller.setTextColor(.hex("#A03060"), forNodeIDs: [id])
        controller.setTextAlignment(.left, forNodeIDs: [id])
        controller.flushPendingSave()
        controller.detach()

        let reloaded = try store.load(board: board)
        let node = try #require(reloaded.node(id: id))
        let style = CardTextStyle.read(from: node)
        #expect(style.color == .hex("#A03060"))
        #expect(style.alignment == .left)
        #expect(node.kind == .text("ciao"))
    }
}
