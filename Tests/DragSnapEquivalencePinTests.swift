import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D10, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-18.
//
// A drag's snapping, pinned to today's per-tick formula before Task 6 captures the candidates once
// at the start of the drag: for every translation in a sequence, `dragTranslation` and
// `activeGuides` equal `BoardGeometry.snapped` over `document.nodes` recomputed in the test, and
// the committed move after `endDrag` is the last translation. Grid on and off, zoom 0.5, 1 and 2,
// an explicit anchor, a defaulted anchor, an anchor absent from the document, and a group.

struct DragPinCase: Sendable, CustomStringConvertible {
    let nodeIDs: Set<String>
    let anchor: String?
    let grid: Bool
    let zoom: CGFloat
    var description: String { "\(nodeIDs.sorted()) anchor \(anchor ?? "default") grid \(grid) zoom \(zoom)" }
}

enum DragPinTable {
    static let one = "aaaa000000000001"
    static let two = "aaaa000000000002"
    static let three = "aaaa000000000003"
    static let group = "aaaa00000000000a"
    static let inner = "aaaa00000000000b"
    static let innerSecond = "aaaa00000000000c"
    static let far = "aaaa000000000009"

    static let nodes: [CanvasNode] = [
        CanvasNode(id: one, kind: .text("uno"), x: 0, y: 0, width: 200, height: 100),
        CanvasNode(id: two, kind: .text("due"), x: 300, y: 0, width: 200, height: 100),
        CanvasNode(id: three, kind: .text("tre"), x: 0, y: 300, width: 100, height: 100),
        CanvasNode(id: group, kind: .group(label: "Gruppo"), x: 600, y: 0, width: 400, height: 400),
        CanvasNode(id: inner, kind: .text("dentro"), x: 650, y: 50, width: 100, height: 100),
        CanvasNode(id: innerSecond, kind: .text("dentro due"), x: 700, y: 200, width: 100, height: 100),
        CanvasNode(id: far, kind: .text("lontano"), x: 1200, y: 1200, width: 150, height: 90),
    ]

    static let drags: [(nodeIDs: Set<String>, anchor: String?)] = [
        ([one], one),
        ([group], group),
        ([one, three], nil),
        ([two], "ffff000000000000"),
    ]

    static let cases: [DragPinCase] = drags.flatMap { drag in
        [false, true].flatMap { grid in
            ([0.5, 1, 2] as [CGFloat]).map { zoom in
                DragPinCase(nodeIDs: drag.nodeIDs, anchor: drag.anchor, grid: grid, zoom: zoom)
            }
        }
    }

    /// Cumulative reports of one gesture: near an edge, on a centre, past a card, back again.
    static let translations: [CGSize] = [
        CGSize(width: 3, height: 2),
        CGSize(width: 95, height: -1),
        CGSize(width: 298, height: 4),
        CGSize(width: 301.5, height: 99),
        CGSize(width: -7, height: 305),
        CGSize(width: 0, height: 0),
        CGSize(width: 410, height: 197),
        CGSize(width: 55.25, height: 12.75),
    ]
}

/// Today's formula (`WorkspaceController+Gestures.swift`, `updateDrag`), recomputed per tick.
@MainActor
private func reference(
    _ controller: WorkspaceController, anchorID: String?, translation: CGSize
) -> (translation: CGSize, guides: [BoardGeometry.Guide])? {
    guard let anchorID, let anchor = controller.document.node(id: anchorID) else { return nil }
    let proposed = anchor.frame.offsetBy(dx: translation.width, dy: translation.height)
    let others = controller.document.nodes.filter { !controller.draggingIDs.contains($0.id) }.map(\.frame)
    let (snapped, guides) = BoardGeometry.snapped(
        proposed, to: others,
        threshold: 6 / max(controller.zoom, 0.01),
        gridStep: controller.snapsToGrid ? WorkspaceController.gridStep : nil
    )
    return (CGSize(width: snapped.minX - anchor.x, height: snapped.minY - anchor.y), guides)
}

@MainActor
@Test(arguments: DragPinTable.cases)
func aDragSnapsExactlyAsTheBaselineFormula(_ pinCase: DragPinCase) throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    for node in DragPinTable.nodes { controller.addNode(node) }
    controller.snapsToGrid = pinCase.grid
    controller.zoom = pinCase.zoom
    let before = controller.document.nodes

    controller.beginDrag(nodeIDs: pinCase.nodeIDs, anchor: pinCase.anchor)
    let anchorID = pinCase.anchor ?? pinCase.nodeIDs.first
    let dragging = controller.draggingIDs
    #expect(dragging == BoardGeometry.expandingGroups(pinCase.nodeIDs, among: before))

    for translation in DragPinTable.translations {
        controller.updateDrag(translation: translation)
        if let expected = reference(controller, anchorID: anchorID, translation: translation) {
            #expect(controller.dragTranslation == expected.translation, "\(translation)")
            #expect(controller.activeGuides == expected.guides, "\(translation)")
        } else {
            #expect(controller.dragTranslation == translation, "\(translation)")
            #expect(controller.activeGuides.isEmpty, "\(translation)")
        }
    }

    let committed = controller.dragTranslation
    controller.endDrag()
    #expect(controller.draggingIDs.isEmpty)
    #expect(controller.dragTranslation == .zero)
    #expect(controller.activeGuides.isEmpty)
    for node in before {
        let after = try #require(controller.document.node(id: node.id))
        let delta = dragging.contains(node.id) ? committed : .zero
        #expect(after.x == node.x + delta.width, "\(node.id)")
        #expect(after.y == node.y + delta.height, "\(node.id)")
    }
    controller.detach()
}
