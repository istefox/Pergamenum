import Foundation
import Testing
@testable import Pergamenum

// ADR-0053 §D2 #2, plan `docs/plans/ui-suite-replacement.md` Task 5, PR 1: the words a Workspace
// tree row carries for VoiceOver (`WorkspaceRow.swift`'s `private var accessibilityLabel`) become a
// pure `WorkspaceRow.accessibilityLabel(kind:name:boardCount:isSelected:)`.
//
// Converts `UITests/WorkspaceOpenStateUITests.swift:216`,
// `testClickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow_R04`: an open board is
// closed by selecting a board-less folder's row, and that row alone reads as selected. What stays
// out of reach in-process is the label *as read from the accessibility tree* (R-08: the tree is
// one childless group) - these tests read the string, and `.accessibilityLabel(...)` attaching it
// to the row is not tested by anything but the GUI tests that stay.

@Test func aBoardRowReadsItsNameAndSaysOpenOnlyWhenItIsTheOpenOne() {
    let kind = WorkspaceTree.Node.Kind.board(path: "A/x.canvas")

    let closed = WorkspaceRow.accessibilityLabel(kind: kind, name: "x", boardCount: 1, isSelected: false)
    let open = WorkspaceRow.accessibilityLabel(kind: kind, name: "x", boardCount: 1, isSelected: true)

    #expect(closed == "Workspace x")
    #expect(open == "Workspace x, aperta")
}

@Test func aFolderRowReadsItsNameAndItsBoardCountAndSaysSelectedOnlyWhenItIsTheSelectedOne() {
    #expect(
        WorkspaceRow.accessibilityLabel(kind: .folder, name: "Progetti", boardCount: 1, isSelected: false)
            == "Cartella Progetti, 1 Workspace"
    )
    #expect(
        WorkspaceRow.accessibilityLabel(kind: .folder, name: "Progetti", boardCount: 1, isSelected: true)
            == "Cartella Progetti, 1 Workspace, selezionata"
    )
}

@Test func aFolderWithNoBoardStillSaysHowManyItHolds() {
    #expect(
        WorkspaceRow.accessibilityLabel(kind: .folder, name: "Vuota", boardCount: 0, isSelected: false)
            == "Cartella Vuota, 0 Workspace"
    )
}

/// The two suffixes the GUI tests told the rows apart by (`selectedRowsInTree`): a board says
/// ", aperta" and a folder ", selezionata", so a lit row never reads as the other kind.
@Test func onlyABoardSaysOpenAndOnlyAFolderSaysSelected() {
    let board = WorkspaceRow.accessibilityLabel(
        kind: .board(path: "x.canvas"), name: "x", boardCount: 1, isSelected: true
    )
    let folder = WorkspaceRow.accessibilityLabel(kind: .folder, name: "x", boardCount: 1, isSelected: true)

    #expect(board.hasSuffix(", aperta") && !board.hasSuffix(", selezionata"))
    #expect(folder.hasSuffix(", selezionata") && !folder.hasSuffix(", aperta"))
}

// MARK: - OpenState :216

@MainActor
@Test func clickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow() throws {
    let root = try CanvasTemporaryRoot()
    let rootBoard = try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    let tree = OpenStateFixture.tree(in: root.url)

    // The root board opens first, as the GUI test clicks its row, and is the only lit row.
    let rootRow = try #require(WorkspaceTree.node(withID: rootBoard, in: tree))
    workspace.select(WorkspaceBrowser.selection(for: rootRow))
    #expect(workspace.isShowingBoard)
    let openName = (rootBoard as NSString).deletingPathExtension
    #expect(OpenStateFixture.litLabels(in: tree, selection: workspace.current) == ["Workspace \(openName), aperta"])

    // Then a click on the board-less grouping folder's row, which asks the same function the
    // `List`'s binding asks what selecting it means.
    let grouping = try #require(WorkspaceTree.node(withID: OpenStateFixture.groupingFolder, in: tree))
    #expect(grouping.kind == .folder)
    workspace.select(WorkspaceBrowser.selection(for: grouping))

    // "Nessuna board aperta": the open board is closed, nothing is drawn, and the one row that
    // reads as selected is the folder's own.
    #expect(!workspace.isShowingBoard)
    #expect(workspace.current == .folder("Progetti"))
    #expect(
        OpenStateFixture.litLabels(in: tree, selection: workspace.current)
            == ["Cartella Progetti, 1 Workspace, selezionata"]
    )
    workspace.detach()
}
