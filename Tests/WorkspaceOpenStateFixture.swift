import Foundation
@testable import Pergamenum

/// The vault `UITests/WorkspaceOpenStateUITests.swift` builds in `makeFixtureBoards()`, with the
/// same names and the same card ids, written to a throwaway directory so the tests converted from
/// that file (plan `docs/plans/ui-suite-replacement.md`, Task 5, PR 1) run against the shape the
/// GUI tests ran against.
///
/// Shared by `WorkspaceEnterFolderTests` and `WorkspaceRowLabelTests`, which both end by asking
/// which rows of the tree read as selected.
enum OpenStateFixture {
    /// A folder holding two boards directly and a third one a level down: entering it is
    /// `.ambiguous`, and it counts three boards.
    static let boardFolder = "Vibrofer"
    static let boardFile = "Vibrofer/Vibrofer.canvas"
    static let siblingBoardFile = "Vibrofer/Altro.canvas"
    static let nestedBoardFile = "Vibrofer/Dettaglio/Dettaglio.canvas"
    /// A folder holding nothing at all: entering it is `.notFound`.
    static let emptyFolder = "Vuota"
    /// A board-less grouping folder whose only content is a subfolder that owns a board:
    /// entering it is `.notFound` as well, and it counts one board.
    static let groupingFolder = "Progetti"
    static let groupingChildBoardFile = "Progetti/Cliente/Cliente.canvas"
    /// The two folder cards the root board carries: one at `boardFolder`, one at `emptyFolder`.
    static let ambiguousFolderCardID = "folder-card-ambiguous"
    static let notFoundFolderCardID = "folder-card-notfound"

    private static let emptyCanvas = #"{ "nodes": [], "edges": [] }"#

    private static var rootCanvas: String {
        """
        {
          "nodes": [
            { "id": "\(ambiguousFolderCardID)", "type": "file", "file": "\(boardFolder)",
              "x": 0, "y": 0, "width": 200, "height": 120 },
            { "id": "\(notFoundFolderCardID)", "type": "file", "file": "\(emptyFolder)",
              "x": 300, "y": 0, "width": 200, "height": 120 }
          ],
          "edges": []
        }
        """
    }

    /// The root board's own path: named after the vault only because the fixture writes it that
    /// way, as the GUI file's `rootBoardRow` says (no rule derives a board from a folder's name).
    static func rootBoardFile(in root: URL) -> String { "\(root.lastPathComponent).canvas" }

    /// Writes the vault and returns the root board's path. The root board alone carries the two
    /// folder cards; every other board is the plain empty canvas.
    @discardableResult
    static func write(in root: URL) throws -> String {
        let rootBoard = rootBoardFile(in: root)
        try write(rootCanvas, at: rootBoard, in: root)
        for board in [boardFile, siblingBoardFile, nestedBoardFile, groupingChildBoardFile] {
            try write(emptyCanvas, at: board, in: root)
        }
        try FileManager.default.createDirectory(
            at: root.appending(path: emptyFolder, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return rootBoard
    }

    static func write(_ contents: String, at path: String, in root: URL) throws {
        let url = root.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A controller attached to `root` with nothing open, which is what `attach` leaves
    /// (ADR-0025 §D4).
    @MainActor
    static func attachedWorkspace(in root: URL, vault: VaultController? = nil) -> WorkspaceController {
        let workspace = WorkspaceController()
        workspace.attach(to: CanvasStore(root: root), vault: vault)
        return workspace
    }

    /// The tree as the sidebar builds it from a scan of `root`.
    static func tree(in root: URL) -> [WorkspaceTree.Node] {
        let store = CanvasStore(root: root)
        return WorkspaceTree.build(folders: store.allFolders(), boards: store.allBoards())
    }

    /// The labels of the rows that read as selected when the controller holds `selection`: the
    /// derivation `WorkspaceRow.isSelected` makes (`selection?.path == node.id`), then the label
    /// the row would carry, then the same ", aperta" / ", selezionata" filter the GUI test's
    /// `selectedRowsInTree` applied. Every row of the tree, expanded or not.
    ///
    /// The one line of the view this repeats is that `isSelected` derivation: it is private to
    /// `WorkspaceRow`, and the label seam takes the boolean rather than the selection.
    static func litLabels(in tree: [WorkspaceTree.Node], selection: WorkspaceSelection?) -> [String] {
        WorkspaceTree.flattened(tree)
            .map { row in
                WorkspaceRow.accessibilityLabel(
                    kind: row.node.kind, name: row.node.name, boardCount: row.node.boardCount,
                    isSelected: selection?.path == row.node.id
                )
            }
            .filter { $0.hasSuffix(", aperta") || $0.hasSuffix(", selezionata") }
    }
}
