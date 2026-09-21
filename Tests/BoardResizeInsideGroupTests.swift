import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// Plan `docs/plans/ui-suite-replacement.md` Task 5, PR 1, ADR-0053 §D2: no seam, no production
// change. Converts `UITests/WorkspaceBoardUITests.swift:161`, `testACardInsideAGroupCanBeSelected`,
// through the resize entry points the board's own grips call - `select(nodeID:adding:)`, then
// `beginResize`/`updateResize`/`endResize` - followed by `flushPendingSave()` and a reload from
// disk, which is the file-as-record the GUI test read back.
//
// Unlike the GUI test, which "never observes the selection, only that the card widened" (census,
// WorkspaceBoardUITests), this one asserts the selection too, and that neither the group that holds
// the card nor any other card moved.
//
// What stays out of reach in-process (R-08, census "wiring lost"): that a real click reaches a card
// through the group's hollow middle, and that the corner grip half outside the card can be hit -
// pointer hit-testing on a hosted view. `testACornerGripResizesTheCard` (Board :64) is the GUI test
// that keeps the grip chain, and the group frame's real hit-testing has no in-process cover.
//
// This is a characterisation test: it passes on the code as it stands, so it has no red of its own.
// It asserts the fixture's own numbers before the resize as well as after, so a resize that quietly
// did nothing fails it.

/// `WorkspaceBoardUITests.fixture`, verbatim: two cards, a group, and a card inside the group.
private let fixture = """
{
  "nodes": [
    { "id": "aaaa000000000001", "type": "text", "text": "CARD A",
      "x": 0, "y": 0, "width": 240, "height": 140, "color": "3" },
    { "id": "bbbb000000000002", "type": "text", "text": "CARD B",
      "x": 700, "y": 0, "width": 240, "height": 140, "color": "5" },
    { "id": "gggg000000000003", "type": "group", "label": "GRUPPO",
      "x": 0, "y": 320, "width": 900, "height": 460 },
    { "id": "cccc000000000004", "type": "text", "text": "CARD C dentro il gruppo",
      "x": 320, "y": 470, "width": 260, "height": 150, "color": "4" }
  ],
  "edges": []
}
"""

private let insideID = "cccc000000000004"
private let groupID = "gggg000000000003"

private func frame(of id: String, in document: CanvasDocument) throws -> CGRect {
    try #require(document.node(id: id)).frame
}

@MainActor
@Test func aCardInsideAGroupIsSelectedAndThenGrowsFromItsCornerGripAndTheFileKeepsIt() throws {
    let root = try CanvasTemporaryRoot()
    let board = "\(root.url.lastPathComponent).canvas"
    try fixture.write(
        to: root.url.appending(path: board, directoryHint: .notDirectory), atomically: true, encoding: .utf8
    )
    let store = CanvasStore(root: root.url)
    let workspace = WorkspaceController()
    workspace.attach(to: store)
    workspace.open(board: board)
    let before = try frame(of: insideID, in: workspace.document)
    #expect(before == CGRect(x: 320, y: 470, width: 260, height: 150))

    // A click on the card selects it, whatever holds it: the group is hollow (SPEC §6.5).
    workspace.select(nodeID: insideID, adding: false)
    #expect(workspace.selection == [insideID])

    // The grip is a `DragGesture` on the bottom-right corner; the GUI test dragged it by
    // (120, 70) at zoom 1, which is 120 by 70 board units.
    workspace.beginResize(nodeID: insideID, handle: .bottomRight)
    #expect(workspace.resizingNodeID == insideID)
    workspace.updateResize(translation: CGSize(width: 120, height: 70), lockAspect: false)
    // While the drag is in flight the card is drawn at the new size and nothing is written yet.
    let inFlight = try #require(workspace.document.node(id: insideID))
    #expect(workspace.displayFrame(for: inFlight) == CGRect(x: 320, y: 470, width: 380, height: 220))
    #expect(inFlight.frame == before)
    workspace.endResize()
    #expect(workspace.resizingNodeID == nil)
    #expect(workspace.selection == [insideID])

    workspace.flushPendingSave()
    workspace.detach()

    // Read back off the file, which is the app's own record of the change: the far edges moved, the
    // origin did not, and the group and the two other cards are where they were.
    let reloaded = try store.load(board: board)
    #expect(try frame(of: insideID, in: reloaded) == CGRect(x: 320, y: 470, width: 380, height: 220))
    #expect(try frame(of: groupID, in: reloaded) == CGRect(x: 0, y: 320, width: 900, height: 460))
    #expect(try frame(of: "aaaa000000000001", in: reloaded) == CGRect(x: 0, y: 0, width: 240, height: 140))
    #expect(try frame(of: "bbbb000000000002", in: reloaded) == CGRect(x: 700, y: 0, width: 240, height: 140))
}
