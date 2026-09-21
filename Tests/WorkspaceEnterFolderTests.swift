import Foundation
import Testing
@testable import Pergamenum

// ADR-0053 §D2 #1, plan `docs/plans/ui-suite-replacement.md` Task 5, PR 1: the three copies of
// "resolve the board; if `.unique` select it, else select the folder" (`BoardChrome`'s breadcrumb,
// `BoardCardMenu`'s folder card, `WorkspaceView.placePendingNote`) become one
// `WorkspaceController.enter(folder:)`, and the sentence `placePendingNote` records becomes
// `WorkspaceBoardResolver.placementProblem`.
//
// Converts, from `UITests/WorkspaceOpenStateUITests.swift`, `:370` and `:383` (a folder card's
// double click) and `:405` and `:425` (a breadcrumb ancestor), and from
// `UITests/WorkspaceIntegrationUITests.swift` `:166` (a note sent from a folder with no boards).
// The GUI tests stay until `--affected` has proved the collapse (SPEC R-10).
//
// RED: `enter(folder:)` resolves and returns but selects nothing, and `placementProblem` answers
// nil, so the assertions below that read the selection or the sentence fail on their `#expect`.
// The ones that read only the returned resolution already pass.

// MARK: - The three resolutions (ADR-0025 §D5)

@MainActor
@Test func enteringAFolderThatHoldsOneBoardOpensThatBoard() throws {
    let root = try CanvasTemporaryRoot()
    try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)

    let resolution = workspace.enter(folder: "Vibrofer/Dettaglio")

    #expect(resolution == .unique(BoardPath(value: OpenStateFixture.nestedBoardFile)))
    #expect(workspace.current == .board(path: OpenStateFixture.nestedBoardFile))
    #expect(workspace.isShowingBoard)
    workspace.detach()
}

// MARK: - A folder card's double click (OpenState :370, :383)

@MainActor
@Test func doubleClickingAnAmbiguousFolderCardClosesTheBoardAndSelectsTheFolder() throws {
    let root = try CanvasTemporaryRoot()
    let rootBoard = try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    workspace.open(board: rootBoard)
    #expect(workspace.isShowingBoard)

    // What `BoardCardActions.open(_:)` asks of the card before it enters anything.
    let card = try #require(workspace.document.node(id: OpenStateFixture.ambiguousFolderCardID))
    let folder = try #require(workspace.subfolder(for: card))
    let resolution = workspace.enter(folder: folder)

    #expect(folder == OpenStateFixture.boardFolder)
    #expect(resolution == .ambiguous)
    #expect(workspace.current == .folder("Vibrofer"))
    // "Nessuna board aperta" is what the pane draws when no board is showing.
    #expect(!workspace.isShowingBoard)
    let lit = OpenStateFixture.litLabels(in: OpenStateFixture.tree(in: root.url), selection: workspace.current)
    #expect(lit == ["Cartella Vibrofer, 3 Workspace, selezionata"])
    workspace.detach()
}

@MainActor
@Test func doubleClickingAFolderCardWithNoBoardsClosesTheBoardAndSelectsTheFolder() throws {
    let root = try CanvasTemporaryRoot()
    let rootBoard = try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    workspace.open(board: rootBoard)
    #expect(workspace.isShowingBoard)

    let card = try #require(workspace.document.node(id: OpenStateFixture.notFoundFolderCardID))
    let folder = try #require(workspace.subfolder(for: card))
    let resolution = workspace.enter(folder: folder)

    #expect(folder == OpenStateFixture.emptyFolder)
    #expect(resolution == .notFound)
    #expect(workspace.current == .folder("Vuota"))
    #expect(!workspace.isShowingBoard)
    let lit = OpenStateFixture.litLabels(in: OpenStateFixture.tree(in: root.url), selection: workspace.current)
    #expect(lit == ["Cartella Vuota, 0 Workspace, selezionata"])
    workspace.detach()
}

// MARK: - A breadcrumb ancestor (OpenState :405, :425)

@MainActor
@Test func clickingAnAmbiguousBreadcrumbAncestorSelectsTheFolderInsteadOfABoard() throws {
    let root = try CanvasTemporaryRoot()
    try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    workspace.open(board: OpenStateFixture.nestedBoardFile)
    let tree = OpenStateFixture.tree(in: root.url)
    #expect(OpenStateFixture.litLabels(in: tree, selection: workspace.current) == ["Workspace Dettaglio, aperta"])

    // The trail is ["Workspace", "Vibrofer", "Dettaglio", "Dettaglio"]: `breadcrumb-crumb-1`, the
    // segment the GUI test clicked, is the first ancestor after the root, and what a click on a
    // segment hands `BoardTopBar.open(ancestor:)` is that segment's `folder`.
    let crumb = workspace.breadcrumb[1]
    #expect(crumb == BreadcrumbSegment(title: "Vibrofer", folder: "Vibrofer"))
    let resolution = workspace.enter(folder: crumb.folder)

    #expect(resolution == .ambiguous)
    #expect(workspace.current == .folder("Vibrofer"))
    #expect(!workspace.isShowingBoard)
    #expect(
        OpenStateFixture.litLabels(in: tree, selection: workspace.current)
            == ["Cartella Vibrofer, 3 Workspace, selezionata"]
    )
    workspace.detach()
}

@MainActor
@Test func clickingANotFoundBreadcrumbAncestorSelectsTheFolderInsteadOfABoard() throws {
    let root = try CanvasTemporaryRoot()
    try OpenStateFixture.write(in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    workspace.open(board: OpenStateFixture.groupingChildBoardFile)
    let tree = OpenStateFixture.tree(in: root.url)
    #expect(OpenStateFixture.litLabels(in: tree, selection: workspace.current) == ["Workspace Cliente, aperta"])

    // "Progetti" holds no board directly, only `Cliente/Cliente.canvas` one level down.
    let crumb = workspace.breadcrumb[1]
    #expect(crumb == BreadcrumbSegment(title: "Progetti", folder: "Progetti"))
    let resolution = workspace.enter(folder: crumb.folder)

    #expect(resolution == .notFound)
    #expect(workspace.current == .folder("Progetti"))
    #expect(!workspace.isShowingBoard)
    #expect(
        OpenStateFixture.litLabels(in: tree, selection: workspace.current)
            == ["Cartella Progetti, 1 Workspace, selezionata"]
    )
    workspace.detach()
}

// MARK: - The one input on which the old copies differ (ADR-0053 §D3)

/// `BoardTopBar.open(ancestor:)` guarded `folder.isEmpty` before it asked the resolver and kept
/// that guard at its call site. The folder card's copy had none, and on `""` selected
/// `.folder("")` when the resolver said `.ambiguous` or `.notFound`, a spelling ADR-0025 §D3 says
/// the app never produces. `enter(folder:)` selects `nil` there.
@MainActor
@Test func enteringTheEmptyPathNeverSelectsTheFolderNamedEmpty() throws {
    let ambiguous = try CanvasTemporaryRoot()
    try OpenStateFixture.write(#"{ "nodes": [], "edges": [] }"#, at: "Uno.canvas", in: ambiguous.url)
    try OpenStateFixture.write(#"{ "nodes": [], "edges": [] }"#, at: "Due.canvas", in: ambiguous.url)
    let crowded = OpenStateFixture.attachedWorkspace(in: ambiguous.url)
    crowded.open(board: "Uno.canvas")
    #expect(crowded.isShowingBoard)

    #expect(crowded.enter(folder: "") == .ambiguous)
    #expect(crowded.current == nil)
    #expect(!crowded.isShowingBoard)
    crowded.detach()

    let empty = try CanvasTemporaryRoot()
    let bare = OpenStateFixture.attachedWorkspace(in: empty.url)

    #expect(bare.enter(folder: "") == .notFound)
    #expect(bare.current == nil)
    bare.detach()
}

/// Why the breadcrumb's guard has to stay where it is: a root with exactly one board is `.unique`
/// for `""`, so the resolver alone would open it for a click that means "nothing selected".
@MainActor
@Test func enteringTheEmptyPathOpensTheRootBoardWhenThereIsExactlyOne() throws {
    let root = try CanvasTemporaryRoot()
    try OpenStateFixture.write(#"{ "nodes": [], "edges": [] }"#, at: "Sola.canvas", in: root.url)
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)

    #expect(workspace.enter(folder: "") == .unique(BoardPath(value: "Sola.canvas")))
    #expect(workspace.current == .board(path: "Sola.canvas"))
    workspace.detach()
}

/// The reachability question ADR-0053 §D3 left open: can a folder card carry the empty path? A
/// hand-written `.canvas` can, and `subfolder(for:)` reads it as the vault root, so the card's
/// double click reaches `enter(folder: "")`.
@MainActor
@Test func aFileCardWithAnEmptyPathIsAFolderCardForTheVaultRoot() throws {
    let root = try CanvasTemporaryRoot()
    try OpenStateFixture.write(
        """
        { "nodes": [ { "id": "vuota", "type": "file", "file": "", "x": 0, "y": 0, "width": 200, "height": 120 } ],
          "edges": [] }
        """,
        at: "Radice.canvas", in: root.url
    )
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    workspace.open(board: "Radice.canvas")

    let card = try #require(workspace.document.node(id: "vuota"))

    #expect(workspace.subfolder(for: card) == "")
    workspace.detach()
}

// MARK: - A note sent from a folder with no board (Integration :166)

/// `WorkspaceView.placePendingNote` selects the folder, writes nothing and records a problem
/// naming the note; the sentence is `placementProblem`'s. The GUI test read it back through
/// Impostazioni; here it is read off the vault's own problem list.
@MainActor
@Test func sendingANoteFromAFolderWithNoBoardsSelectsTheFolderAndRecordsAProblem() async throws {
    let vault = try TemporaryVault()
    try vault.write("# Nota orfana\n", to: "SenzaBoard/NotaOrfana.md")
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    let workspace = WorkspaceController()
    workspace.attach(to: CanvasStore(root: vault.root), vault: vaultController)

    let pending = "SenzaBoard/NotaOrfana.md"
    let folder = (pending as NSString).deletingLastPathComponent
    let resolution = workspace.enter(folder: folder)
    let sentence = try #require(
        WorkspaceBoardResolver.placementProblem(for: pending, inFolder: folder, resolution: resolution)
    )
    workspace.recordProblem(sentence)

    #expect(resolution == .notFound)
    #expect(workspace.current == .folder("SenzaBoard"))
    #expect(!workspace.isShowingBoard)
    #expect(vaultController.problems.contains(
        "SenzaBoard/NotaOrfana.md: «SenzaBoard» non contiene nessuna board, creane una e riprova"
    ))
    // The regression the GUI pair names (ADR-0025 §F8): the hand-off used to write a board named
    // after the folder. Nothing on this path writes one now.
    let written = try FileManager.default.contentsOfDirectory(
        atPath: vault.root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    )
    #expect(written.filter { $0.hasSuffix(".canvas") }.isEmpty)
    vaultController.close()
}

// MARK: - The sentence (`WorkspaceView.swift:215-220`, moved verbatim)

@Test func aUniqueBoardIsNoProblem() {
    let sentence = WorkspaceBoardResolver.placementProblem(
        for: "A/Nota.md", inFolder: "A", resolution: .unique(BoardPath(value: "A/x.canvas"))
    )

    #expect(sentence == nil)
}

@Test func anAmbiguousFolderIsToldToOpenOneBoardAndRetry() {
    let sentence = WorkspaceBoardResolver.placementProblem(
        for: "Ambiguo/NotaAmbigua.md", inFolder: "Ambiguo", resolution: .ambiguous
    )

    #expect(sentence == "Ambiguo/NotaAmbigua.md: «Ambiguo» contiene più di una board, aprine una e riprova")
}

@Test func aFolderWithNoBoardIsToldToCreateOneAndRetry() {
    let sentence = WorkspaceBoardResolver.placementProblem(
        for: "SenzaBoard/NotaOrfana.md", inFolder: "SenzaBoard", resolution: .notFound
    )

    #expect(sentence == "SenzaBoard/NotaOrfana.md: «SenzaBoard» non contiene nessuna board, creane una e riprova")
}

@Test func theVaultRootIsNamedInWordsRatherThanByAnEmptyPath() {
    let sentence = WorkspaceBoardResolver.placementProblem(
        for: "Nota.md", inFolder: "", resolution: .notFound
    )

    #expect(sentence == "Nota.md: la radice del vault non contiene nessuna board, creane una e riprova")
}
