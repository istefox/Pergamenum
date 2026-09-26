import Foundation
import Testing
@testable import Pergamenum

// ADR-0054 §D4 (plan `docs/plans/pg-213-workspace-autosave-race.md`, Task 1): the pure
// three-way reconciliation `WorkspaceController.save()` asks when a guarded write refuses.
// No disk, no controller - `CanvasDocument.reconcile(mine:base:theirs:)` alone.

private func fileNode(
    id: String, path: String, subpath: String? = nil, x: CGFloat = 0, y: CGFloat = 0
) -> CanvasNode {
    CanvasNode(id: id, kind: .file(path: path, subpath: subpath), x: x, y: y, width: 260, height: 120)
}

private func textNode(id: String, text: String, x: CGFloat = 0, y: CGFloat = 0) -> CanvasNode {
    CanvasNode(id: id, kind: .text(text), x: x, y: y, width: 260, height: 120)
}

@Test func repointOfAFileNodeIsAdoptedAlongsideMinesUnrelatedAddition() {
    let base = CanvasDocument(nodes: [fileNode(id: "a", path: "old.md")])
    let theirs = CanvasDocument(nodes: [fileNode(id: "a", path: "new.md")])
    let mine = CanvasDocument(nodes: [
        fileNode(id: "a", path: "old.md"),
        textNode(id: "sticky", text: "appunto"),
    ])

    guard case .adopted(let merged) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirs) else {
        Issue.record("expected .adopted")
        return
    }
    guard case .file(let path, _) = merged.node(id: "a")?.kind else {
        Issue.record("expected node a to stay a .file node")
        return
    }
    #expect(path == "new.md")
    #expect(merged.node(id: "sticky") != nil, "mine's own unrelated addition must survive the merge")
}

@Test func repointOfANodeMineDeletedIsAdoptedWithoutResurrectingIt() {
    let base = CanvasDocument(nodes: [fileNode(id: "a", path: "old.md")])
    let theirs = CanvasDocument(nodes: [fileNode(id: "a", path: "new.md")])
    // mine deleted the node entirely.
    let mine = CanvasDocument(nodes: [])

    guard case .adopted(let merged) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirs) else {
        Issue.record("expected .adopted")
        return
    }
    #expect(merged.node(id: "a") == nil, "a deletion mine made must not be resurrected by a repoint")
}

@Test func theirsAddingANodeDiverges() {
    let base = CanvasDocument(nodes: [])
    let theirs = CanvasDocument(nodes: [fileNode(id: "new", path: "added.md")])
    let mine = CanvasDocument(nodes: [])

    guard case .diverged(let reasons) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirs) else {
        Issue.record("expected .diverged")
        return
    }
    #expect(reasons.contains("new"))
}

@Test func theirsRemovingANodeDiverges() {
    let base = CanvasDocument(nodes: [fileNode(id: "gone", path: "x.md")])
    let theirs = CanvasDocument(nodes: [])
    let mine = CanvasDocument(nodes: [fileNode(id: "gone", path: "x.md")])

    guard case .diverged(let reasons) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirs) else {
        Issue.record("expected .diverged")
        return
    }
    #expect(reasons.contains("gone"))
}

@Test func theirsChangingATextNodesTextOrGeometryDiverges() {
    let base = CanvasDocument(nodes: [textNode(id: "t", text: "prima")])
    let theirsText = CanvasDocument(nodes: [textNode(id: "t", text: "dopo")])
    let mine = CanvasDocument(nodes: [textNode(id: "t", text: "prima")])

    guard case .diverged(let reasons) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirsText) else {
        Issue.record("expected .diverged for a changed text body")
        return
    }
    #expect(reasons.contains("t"))

    let theirsGeometry = CanvasDocument(nodes: [textNode(id: "t", text: "prima", x: 500)])
    guard case .diverged(let geometryReasons) = CanvasDocument.reconcile(
        mine: mine, base: base, theirs: theirsGeometry
    ) else {
        Issue.record("expected .diverged for a changed geometry")
        return
    }
    #expect(geometryReasons.contains("t"))
}

@Test func theirsChangingAnEdgeOrATopLevelUnknownKeyDivergesNamingIt() {
    let edge = CanvasEdge(id: "e1", fromNode: "a", toNode: "b")
    let base = CanvasDocument(
        nodes: [fileNode(id: "a", path: "a.md"), fileNode(id: "b", path: "b.md")],
        edges: [edge]
    )
    var changedEdge = edge
    changedEdge.label = "nuovo"
    let theirsEdge = CanvasDocument(
        nodes: base.nodes, edges: [changedEdge]
    )
    guard case .diverged(let reasons) = CanvasDocument.reconcile(mine: base, base: base, theirs: theirsEdge) else {
        Issue.record("expected .diverged for a changed edge")
        return
    }
    #expect(reasons.contains("e1"))

    let baseWithKey = CanvasDocument(nodes: base.nodes, edges: [edge], unknown: ["pergamenum-color": .string("blu")])
    let theirsKey = CanvasDocument(
        nodes: base.nodes, edges: [edge], unknown: ["pergamenum-color": .string("rosso")]
    )
    guard case .diverged(let keyReasons) = CanvasDocument.reconcile(
        mine: baseWithKey, base: baseWithKey, theirs: theirsKey
    ) else {
        Issue.record("expected .diverged for a changed top-level unknown key")
        return
    }
    #expect(keyReasons.contains("pergamenum-color"))
}

@Test func identicalBaseAndTheirsAdoptsMineUnchanged() {
    let base = CanvasDocument(nodes: [fileNode(id: "a", path: "x.md")])
    let mine = CanvasDocument(nodes: [
        fileNode(id: "a", path: "x.md"),
        textNode(id: "sticky", text: "appunto"),
    ])

    guard case .adopted(let merged) = CanvasDocument.reconcile(mine: mine, base: base, theirs: base) else {
        Issue.record("expected .adopted(mine) when base == theirs")
        return
    }
    #expect(merged == mine)
}

@Test func mineUnchangedFromBaseAdoptsTheirsRepoint() {
    let base = CanvasDocument(nodes: [fileNode(id: "a", path: "old.md")])
    let theirs = CanvasDocument(nodes: [fileNode(id: "a", path: "new.md")])

    guard case .adopted(let merged) = CanvasDocument.reconcile(mine: base, base: base, theirs: theirs) else {
        Issue.record("expected .adopted")
        return
    }
    #expect(merged == theirs)
}

// MARK: - Duplicate ids diverge instead of trapping (ADR-0064 §D6.1, R-09)
//
// Written in the same change as the fix (plan Rule 1): before it, each of these reached
// `Dictionary(uniqueKeysWithValues:)` with a repeated key and killed the test host.

@Test func reconcilingDuplicateNodeIdsDiverges() {
    let base = CanvasDocument(nodes: [textNode(id: "a", text: "uno"), textNode(id: "a", text: "due")])
    let theirs = CanvasDocument(nodes: [textNode(id: "a", text: "uno"), textNode(id: "a", text: "tre")])

    #expect(CanvasDocument.reconcile(mine: base, base: base, theirs: theirs) == .diverged(["a"]))
}

@Test func reconcilingDuplicateEdgeIdsDiverges() {
    let nodes = [textNode(id: "a", text: "uno"), textNode(id: "b", text: "due")]
    let edge = CanvasEdge(id: "e", fromNode: "a", toNode: "b")
    let base = CanvasDocument(nodes: nodes, edges: [edge, edge])
    let theirs = CanvasDocument(nodes: nodes, edges: [edge, CanvasEdge(id: "e", fromNode: "b", toNode: "a")])

    #expect(CanvasDocument.reconcile(mine: base, base: base, theirs: theirs) == .diverged(["e"]))
}

@Test func aDuplicateIdInTheirsAloneDiverges() {
    let base = CanvasDocument(nodes: [textNode(id: "a", text: "uno")])
    let theirs = CanvasDocument(nodes: [textNode(id: "a", text: "uno"), textNode(id: "a", text: "due")])

    #expect(CanvasDocument.reconcile(mine: base, base: base, theirs: theirs) == .diverged(["a"]))
}
