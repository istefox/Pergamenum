import Foundation
import Testing
@testable import Pergamenum

// ADR-0021 ("A task carries its Workspace and its place in a project as caret markers in
// its own line, and nothing new is stored anywhere else"), §D7 and §D8. Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 7: the
// board dashboard's "Note referenziate" section (R-06), pure - no index, no vault, no
// SwiftUI, tested against a `CanvasDocument` built in memory.
//
// `Sources/Core/Canvas/WorkspaceReferences.swift`'s `notes(in:)` is a signature-only stub
// as of this commit, returning `[]` unconditionally: every test below is expected to fail
// red on its assertions, not to fail to compile - the coder's Task 7 work fills in the
// `.file`/`.text` node walk this file already encodes as assertions.
//
// The task half of the dashboard, "Task assegnati", is `IndexSnapshot.tasks(assignedToWorkspace:)`,
// already implemented and covered by `Tests/TaskMarkerTests.swift` (Task 2); this file does
// not duplicate that coverage.

/// A minimal node of the given kind, geometry irrelevant to this pure function.
private func node(_ id: String, _ kind: CanvasNode.Kind) -> CanvasNode {
    CanvasNode(id: id, kind: kind, x: 0, y: 0, width: 100, height: 100)
}

// MARK: - `.file` nodes whose path ends `.md` (ADR-0021 D8)

@Test func pathsOfMarkdownFileNodesAreIncluded() {
    let document = CanvasDocument(nodes: [
        node("a", .file(path: "01 Progetti/Cliente.md", subpath: nil)),
        node("b", .file(path: "03 Risorse/Fattura.md", subpath: "#Sezione")),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(Set(notes) == ["01 Progetti/Cliente.md", "03 Risorse/Fattura.md"])
}

@Test func fileNodesNotEndingInMdAreIgnored() {
    let document = CanvasDocument(nodes: [
        node("a", .file(path: "01 Progetti/Cliente.md", subpath: nil)),
        node("b", .file(path: "03 Risorse/doc.pdf", subpath: nil)),
        node("c", .file(path: "assets/foto.png", subpath: nil)),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(notes == ["01 Progetti/Cliente.md"])
}

// MARK: - Wikilinks inside `.text` nodes (ADR-0021 D8)

@Test func wikilinksInsideTextNodesAreIncluded() {
    let document = CanvasDocument(nodes: [
        node("a", .text("Vedi anche [[Nota A]] e [[Nota B]] per il contesto.")),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(Set(notes) == ["Nota A", "Nota B"])
}

@Test func textNodeWithNoWikilinkContributesNothing() {
    let document = CanvasDocument(nodes: [
        node("a", .text("Un promemoria sciolto, senza alcun link.")),
    ])

    #expect(WorkspaceReferences.notes(in: document) == [])
}

// MARK: - `.link` and `.group` nodes are ignored (ADR-0021 D8)

@Test func linkAndGroupNodesAreIgnored() {
    let document = CanvasDocument(nodes: [
        node("a", .file(path: "Nota.md", subpath: nil)),
        node("b", .link(url: "https://jsoncanvas.org")),
        node("c", .group(label: "Zona")),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(notes == ["Nota.md"])
}

// MARK: - De-duplication (ADR-0021 D8)

@Test func aWikilinkRepeatedAcrossTextNodesAppearsOnce() {
    let document = CanvasDocument(nodes: [
        node("a", .text("Prima citazione: [[Nota A]].")),
        node("b", .text("Seconda citazione, stessa nota: [[Nota A]].")),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(notes.filter { $0 == "Nota A" }.count == 1)
}

@Test func aFileNodeRepeatedTwiceContributesOnePath() {
    // Two cards pinned to the same note - the same path placed twice on the board.
    let document = CanvasDocument(nodes: [
        node("a", .file(path: "Nota.md", subpath: nil)),
        node("b", .file(path: "Nota.md", subpath: nil)),
    ])

    let notes = WorkspaceReferences.notes(in: document)

    #expect(notes == ["Nota.md"])
}

// MARK: - Stable order (ADR-0021 D8)

@Test func repeatedCallsOnTheSameDocumentReturnIdenticalOrder() {
    let document = CanvasDocument(nodes: [
        node("a", .file(path: "01 Progetti/Cliente.md", subpath: nil)),
        node("b", .text("Vedi [[Nota A]] e [[Nota B]].")),
        node("c", .file(path: "03 Risorse/Fattura.md", subpath: nil)),
    ])

    let first = WorkspaceReferences.notes(in: document)
    let second = WorkspaceReferences.notes(in: document)

    #expect(first == second)
    #expect(Set(first) == ["01 Progetti/Cliente.md", "Nota A", "Nota B", "03 Risorse/Fattura.md"])
}

// MARK: - A board with no notes returns `[]`

@Test func aBoardWithNoNotesReturnsAnEmptyArray() {
    let document = CanvasDocument(nodes: [
        node("a", .link(url: "https://jsoncanvas.org")),
        node("b", .group(label: "Zona")),
        node("c", .text("Nessun link qui dentro.")),
        node("d", .file(path: "immagine.png", subpath: nil)),
    ])

    #expect(WorkspaceReferences.notes(in: document) == [])
}

@Test func anEmptyCanvasReturnsAnEmptyArray() {
    #expect(WorkspaceReferences.notes(in: .empty) == [])
}
