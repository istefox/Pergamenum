import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D7, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-17.
//
// PG-054's disk check stays: a folder card is recognised from the disk every time it is asked,
// so a folder created after the board was loaded, with no reload in between, is a folder card on
// the next render. Task 6 checks folder-ness once per node per render, never once per load.

@MainActor
@Test func aFolderCreatedAfterTheBoardLoadedIsStillAFolderCard() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    let board = try store.createBoard(named: "Lavagna", in: "")
    let sibling = CanvasNode(
        id: "aaaa000000000001", kind: .file(path: "Nuova cartella", subpath: nil),
        x: 0, y: 0, width: 260, height: 180
    )
    let nested = CanvasNode(
        id: "aaaa000000000002", kind: .file(path: "Nord/Sud", subpath: nil),
        x: 300, y: 0, width: 260, height: 180
    )
    let file = CanvasNode(
        id: "aaaa000000000003", kind: .file(path: "Nota.md", subpath: nil),
        x: 600, y: 0, width: 260, height: 180
    )
    try CanvasDocument(nodes: [sibling, nested, file]).encoded()
        .write(to: root.url.appending(path: board, directoryHint: .notDirectory))

    let workspace = WorkspaceController()
    workspace.attach(to: store)
    workspace.open(board: board)
    let loadedSibling = try #require(workspace.document.node(id: sibling.id))
    let loadedNested = try #require(workspace.document.node(id: nested.id))
    let loadedFile = try #require(workspace.document.node(id: file.id))

    #expect(workspace.subfolder(for: loadedSibling) == nil)
    #expect(workspace.subfolder(for: loadedNested) == nil)

    // Created on disk with no reload in between.
    try root.makeDirectory("Nuova cartella")
    try root.makeDirectory("Nord/Sud")
    try root.makeFile("Nota.md", "# Nota\n")

    #expect(workspace.subfolder(for: loadedSibling) == "Nuova cartella")
    #expect(workspace.subfolder(for: loadedNested) == "Nord/Sud")
    #expect(workspace.subfolder(for: loadedFile) == nil)
    workspace.detach()
}
