import XCTest

/// The Workspace pane starts empty - nothing highlighted in the board list, no board on
/// screen - until a board is actually clicked, the same way the note editor starts with
/// nothing open rather than with the last note pinned forever.
///
/// ADR-0024 ("One selection, one row, one meaning"). Plan
/// `docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md`, Task 6
/// (R-14): this file is the rewrite that task asks for. Every row is found by
/// `accessibilityIdentifier`, never by the words on it (`CLAUDE.md`) - the tree stopped
/// being a `Button` per row (ADR-0024 §D1/F5), so the two ported tests below substitute
/// `app.descendants(matching: .any).matching(identifier:)` for the old `app.buttons[...]`
/// lookup, and every new test follows the same rule from the start. No assertion in this
/// file reads `selectedFolder` or `hasOpenBoard` - both were removed from the production
/// code this plan's earlier tasks replaced (ADR-0024 §D4/§D6) and neither is a concept a
/// UI test, which only ever sees rendered rows and labels, could reach even by accident.
///
/// ADR-0025 ("A board is a file, a folder is a container") rewrites what the rows *are*
/// without touching how they are found: a folder and a `.canvas` are now two different
/// rows (§D2), so a folder that owns a board has both. That is the one assertion in this
/// file this chain deliberately reverses - the test named for §D2 below - and the five
/// added under it cover this chain's own requirements: creating a folder makes a row and
/// no board (R-01), two boards in one folder are two rows each opening its own (R-03), a
/// board row's context menu offers both mutating verbs (R-08), an empty folder has a row
/// (R-10), and a `.canvas` at the vault root has a top-level row while the root itself has
/// none (R-11).
final class WorkspaceOpenStateUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    // MARK: Fixture identity, named once so every step and every assertion agrees.

    /// A folder holding boards, directly under the root - since ADR-0025 §D2 the folder
    /// and each of its boards are rows of their own, so this one accounts for three.
    private let boardFolder = "Vibrofer"
    private let boardFile = "Vibrofer/Vibrofer.canvas"
    /// A second board in the **same** folder, under a name that is not the folder's - the
    /// R-03 target, and the shape the old "one board per folder, named after it" rule
    /// could not represent at all (ADR-0025 §D1).
    private let siblingBoardFile = "Vibrofer/Altro.canvas"
    /// A folder holding nothing whatsoever - the R-10 target: it has a row, and selecting
    /// it neither opens nor writes a board.
    private let emptyFolder = "Vuota"
    /// What the R-01 test types into the creation sheet. A plain name, so
    /// `NoteName.validate` raises nothing and the sheet's "Crea" is enabled: this test is
    /// about what the verb creates, not about what the field refuses.
    private let newFolderName = "Ricerca"
    /// A board nested two levels deep, inside the folder above - the R-02/R-03 target:
    /// selecting it must light exactly its own row, nowhere else in the tree.
    private let nestedBoardFile = "Vibrofer/Dettaglio/Dettaglio.canvas"
    /// A board-less grouping folder whose only content is a subfolder that owns a board
    /// (SPEC Decision 3 / ADR-0024 §D5) - the R-04/R-05 target: its row selects and opens
    /// nothing.
    private let groupingFolder = "Progetti"
    private let groupingChildBoardFile = "Progetti/Cliente/Cliente.canvas"
    /// Two folder-card nodes placed on the root board itself (review-triage-fix cycle 1,
    /// MAJOR finding: `BoardCardActions.enter` had no UI coverage at all). One points at
    /// `boardFolder`, which already holds two boards (`.ambiguous`); the other points at
    /// `emptyFolder`, which holds none (`.notFound`) - both existing fixtures above, not
    /// new ones.
    private let ambiguousFolderCardID = "folder-card-ambiguous"
    private let notFoundFolderCardID = "folder-card-notfound"

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "WorkspaceOpenStateUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try makeFixtureBoards()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        app.staticTexts["Workspace"].click()
        XCTAssertTrue(app.textFields["workspace-filter"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    // MARK: Row lookup - every one by identifier, never by the words on it (CLAUDE.md).

    /// The `.canvas` the fixture writes at the vault root. It is named after the vault
    /// only because the fixture writes it that way: since ADR-0025 §D1 no rule derives a
    /// board from a folder's name, and `CanvasStore.boardPath(forFolder:)` - what this
    /// comment used to point at - no longer exists.
    ///
    /// So this is an **ordinary top-level board row** (§D2), not the synthesized root row
    /// the tree used to fold a folder into: the vault root is the list itself and has no
    /// row at all. The identifier is unchanged, `workspace-board-<boardPath>`, which is
    /// exactly why every assertion below still resolves after that rewrite.
    private var rootBoardRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "workspace-board-\(vault.lastPathComponent).canvas").firstMatch
    }

    private func row(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var tree: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "workspace-tree").firstMatch
    }

    /// The rows in `workspace-tree` currently reporting the selected state, counted by
    /// the accessibility-label suffix ADR-0024 §D9 adds (`", aperta"` for an open board,
    /// `", selezionata"` for a selected board-less folder) - not by `isSelected`, per the
    /// plan's SPEC-claims table note on R-13: whether `.accessibilityAddTraits(.isSelected)`
    /// on custom `List` row content reaches XCUITest's trait on macOS is unverified here,
    /// so the label is the one thing an assertion may depend on.
    private var selectedRowsInTree: XCUIElementQuery {
        tree.descendants(matching: .any).matching(
            NSPredicate(format: "label ENDSWITH ', aperta' OR label ENDSWITH ', selezionata'")
        )
    }

    /// Waits for `identifier`'s own row to report the selected state, then asserts it is
    /// the *only* one doing so in `workspace-tree`.
    ///
    /// `XCUIElementQuery.count` is a single, unwaited snapshot - unlike
    /// `waitForExistence`, it does not poll. Counting straight after a click risks
    /// reading the tree a beat before SwiftUI's re-render (and the accessibility label it
    /// carries) has caught up, which is a timing gap in the assertion, not in the
    /// production code the click drives. Waiting for the one row this click is expected
    /// to select gives XCUITest's own retrying wait a chance to observe the settled
    /// state before the count below is taken as final.
    private func assertExactlyOneRowSelected(identifier: String, suffix: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = tree.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label ENDSWITH %@", identifier, suffix)
        ).firstMatch
        XCTAssertTrue(expected.waitForExistence(timeout: 5),
                      "la riga «\(identifier)» non riporta lo stato selezionato", file: file, line: line)
        XCTAssertEqual(selectedRowsInTree.count, 1,
                        "esattamente una riga dell'albero deve riportare lo stato selezionato", file: file, line: line)
    }

    // MARK: Ported (R-14) - same assertions as before, row lookup substituted for the row's new element type.

    func testThePaneOpensEmptyAndFillsInOnlyAfterAClick() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "il pane dovrebbe aprirsi senza nessuna board scelta")
        XCTAssertTrue(rootBoardRow.waitForExistence(timeout: 5))

        rootBoardRow.click()

        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists,
                        "lo stato vuoto dovrebbe sparire una volta aperta una board")
    }

    /// This is the test the SPEC's Decision 7 and R-10 contradict (plan, "Five things the
    /// SPEC says that are false or under-determined"): no open-board persistence exists in
    /// this app, and `5041d5c` shipped exactly the behaviour asserted here. It stays green.
    func testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists)

        app.staticTexts["Note"].click()
        XCTAssertTrue(app.staticTexts["Workspace"].waitForExistence(timeout: 5))
        app.staticTexts["Workspace"].click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "tornando sul pane la board aperta prima non dovrebbe essere rimasta")
    }

    // MARK: Reversed (ADR-0025 §D2) - a folder that owns a board is a row *beside* it.

    /// The one green assertion this chain deliberately inverts, and the reason it is worth
    /// saying so here rather than only in the plan: under ADR-0024 §D2 a folder owning a
    /// board was folded into that board's single row, so a `workspace-folder-` row for it
    /// was proof of a bug. ADR-0025 §D2 separates the two concepts - a folder is a
    /// container, a `.canvas` is a document - so the same folder now has a row of its own
    /// *and* one row per board inside it. Same lookups, opposite expectation.
    func testAFolderThatOwnsABoardIsARowBesideItsBoardsOwn_ADR0025_D2() throws {
        XCTAssertTrue(row(identifier: "workspace-folder-\(boardFolder)").waitForExistence(timeout: 5),
                      "«\(boardFolder)» è una cartella: deve avere una riga workspace-folder-* propria")

        // Its board's row is a row of its own, one level in - visible once the folder is
        // open, which is what a container row means.
        app.buttons["workspace-expand-all"].click()
        XCTAssertTrue(row(identifier: "workspace-board-\(boardFile)").waitForExistence(timeout: 5),
                      "manca la riga della board dentro «\(boardFolder)»")
    }

    // MARK: New (R-02/R-03) - selecting a nested board lights exactly its own row.

    func testSelectingANestedBoardLightsExactlyOneRowInTheTree_R02_R03() throws {
        app.buttons["workspace-expand-all"].click()

        let nested = row(identifier: "workspace-board-\(nestedBoardFile)")
        XCTAssertTrue(nested.waitForExistence(timeout: 5), "la board annidata non è comparsa dopo «Espandi tutto»")
        nested.click()

        assertExactlyOneRowSelected(identifier: "workspace-board-\(nestedBoardFile)", suffix: ", aperta")
    }

    // MARK: New (R-04) - a board-less folder's row closes the open board and selects only itself.

    func testClickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow_R04() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists, "la board radice avrebbe dovuto aprirsi")

        let grouping = row(identifier: "workspace-folder-\(groupingFolder)")
        XCTAssertTrue(grouping.waitForExistence(timeout: 5))
        grouping.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "selezionare una cartella senza board dovrebbe richiudere quella aperta")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(groupingFolder)", suffix: ", selezionata")
    }

    // MARK: New (R-05) - a board-less folder's row opens nothing and raises no sheet.

    func testClickingABoardLessFolderRowOpensNoBoardAndRaisesNoSheet_R05() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0)

        let grouping = row(identifier: "workspace-folder-\(groupingFolder)")
        XCTAssertTrue(grouping.waitForExistence(timeout: 5))
        grouping.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "nessuna board dovrebbe essersi aperta cliccando una cartella senza board")
        XCTAssertEqual(app.sheets.count, 0, "nessun foglio dovrebbe comparire per il solo click sulla riga")
    }

    // MARK: New (ADR-0025 R-01) - «Nuova cartella» makes a row and nothing else.

    /// R-01 read as an outcome rather than as a line of code: the deleted
    /// `try store.save(.empty, folder: created)` is invisible to a UI test, but the folder
    /// it used to write is not. The row appears, no board opens, and the directory on disk
    /// holds no `.canvas` - the third assertion is the one that would still fail if the
    /// board creation came back in some other place.
    func testCreatingAFolderMakesARowAndNoBoard_R01() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5))

        app.buttons["workspace-new-folder"].click()
        let sheet = app.descendants(matching: .any).matching(identifier: "workspace-new-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "il foglio di creazione non si è aperto")

        // Nothing is selected at this point, so the sheet's parent picker is seeded with
        // the vault root (`WorkspaceBrowser.target(for: nil)`) and the new folder lands at
        // the top level, where the assertion below looks for it.
        let field = app.textFields["workspace-new-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "manca il campo del nome nel foglio di creazione")
        field.click()
        // Return rather than the «Crea» button: the field's own `onSubmit` runs the same
        // confirmation, and a UI test does not reach a control by the words on it
        // (CLAUDE.md) - that button carries no identifier.
        field.typeText(newFolderName + "\r")

        XCTAssertTrue(row(identifier: "workspace-folder-\(newFolderName)").waitForExistence(timeout: 10),
                      "la cartella creata non ha una riga nell'albero")
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].exists,
                      "creare una cartella non deve aprire nessuna board")

        let created = vault.appending(path: newFolderName, directoryHint: .isDirectory)
        let contents = try FileManager.default.contentsOfDirectory(atPath: created.path(percentEncoded: false))
        XCTAssertEqual(contents.filter { $0.hasSuffix(".canvas") }, [],
                       "«Nuova cartella» non deve scrivere nessun .canvas dentro la cartella creata")
    }

    // MARK: New (ADR-0025 R-03) - two boards in one folder, two rows, each opening its own.

    func testTwoBoardsInOneFolderAreTwoRowsAndEachOpensItsOwn_R03() throws {
        app.buttons["workspace-expand-all"].click()

        let named = row(identifier: "workspace-board-\(boardFile)")
        let sibling = row(identifier: "workspace-board-\(siblingBoardFile)")
        XCTAssertTrue(named.waitForExistence(timeout: 5), "manca la riga di «\(boardFile)»")
        XCTAssertTrue(sibling.waitForExistence(timeout: 5),
                      "manca la riga di «\(siblingBoardFile)»: una cartella può contenere più board")

        named.click()
        assertExactlyOneRowSelected(identifier: "workspace-board-\(boardFile)", suffix: ", aperta")

        sibling.click()
        assertExactlyOneRowSelected(identifier: "workspace-board-\(siblingBoardFile)", suffix: ", aperta")
    }

    // MARK: New (ADR-0025 R-10) - an empty folder is a row, and stays empty when selected.

    func testAnEmptyFolderHasARowAndSelectingItWritesNothing_R10() throws {
        let empty = row(identifier: "workspace-folder-\(emptyFolder)")
        XCTAssertTrue(empty.waitForExistence(timeout: 5),
                      "una cartella senza board non ha riga: prima di ADR-0025 §D2 era invisibile")
        empty.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "selezionare una cartella vuota non deve aprire nessuna board")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(emptyFolder)", suffix: ", selezionata")

        let folder = vault.appending(path: emptyFolder, directoryHint: .isDirectory)
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        XCTAssertEqual(contents.filter { $0.hasSuffix(".canvas") }, [],
                       "selezionare una cartella vuota non deve materializzare una board dentro di essa")
    }

    // MARK: New (ADR-0025 R-11) - a .canvas at the vault root is a top-level row, and the root is not.

    func testARootLevelCanvasIsATopLevelRowAndTheRootItselfHasNone_R11() throws {
        XCTAssertTrue(rootBoardRow.waitForExistence(timeout: 5),
                      "un .canvas nella radice del vault deve avere una riga di primo livello")
        // The vault root is the list, not a row in it (ADR-0025 §D2): a synthesized root
        // would carry the folder identifier of the empty path.
        XCTAssertFalse(row(identifier: "workspace-folder-").exists,
                       "non deve esistere nessuna riga sintetizzata per la radice del vault")

        rootBoardRow.click()
        assertExactlyOneRowSelected(identifier: "workspace-board-\(vault.lastPathComponent).canvas",
                                    suffix: ", aperta")
    }

    // MARK: New (ADR-0025 R-08) - a board row's context menu carries both mutating verbs.

    /// The menu entries are found on `app.menuItems`, by title, and that is not a lapse
    /// from `CLAUDE.md`'s "never by the words on it": a `.contextMenu`'s entries are
    /// `NSMenuItem`s rendered **outside** the accessibility hierarchy of the row that owns
    /// them (ADR-0025 F11), so `descendants(matching:)` under
    /// `workspace-board-<path>` finds nothing at all no matter what identifier the
    /// `Button` carries. `TimeBlockUITests.insertTimeBlockFromMenu` reaches its own entry
    /// the same way, for the same reason.
    ///
    /// The titles are the production strings verbatim, ellipsis character included
    /// (`WorkspaceBrowser.swift`'s row menu: «Rinomina…», «Elimina…»).
    func testABoardRowsContextMenuOffersRenameAndDelete_R08() throws {
        XCTAssertTrue(rootBoardRow.waitForExistence(timeout: 5))
        // Neither verb is in the menu bar, so an entry found after the right click was
        // raised by the right click - without this the assertions below would pass on any
        // menu that happened to be open.
        XCTAssertFalse(app.menuItems["Rinomina…"].exists, "«Rinomina…» era già raggiungibile prima del click destro")

        rootBoardRow.rightClick()

        let rename = app.menuItems["Rinomina…"].firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5),
                      "manca «Rinomina…» nel menu contestuale della riga board")
        let delete = app.menuItems["Elimina…"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5),
                      "manca «Elimina…» nel menu contestuale della riga board")

        // Dismissed rather than acted on: this test is about the menu being offered, and a
        // menu left open would still be up when the next assertion, or the next test's
        // first click, went looking for a row underneath it.
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: New (review-triage-fix cycle 1, MAJOR finding) - `BoardCardActions.enter`
    // (ADR-0025 §D5): a folder card's double click resolves through the same
    // `WorkspaceBoardResolver.board(inFolder:among:)` the tree row and the breadcrumb use,
    // and only its `.unique` branch had ever been exercised before this pair.

    func testDoubleClickingAnAmbiguousFolderCardClosesTheBoardAndSelectsTheFolder() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists, "la board radice avrebbe dovuto aprirsi")

        let card = row(identifier: "canvas-node-\(ambiguousFolderCardID)")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "manca la card cartella per «\(boardFolder)»")
        card.doubleClick()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "una cartella ambigua non deve aprire nessuna board")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(boardFolder)", suffix: ", selezionata")
    }

    func testDoubleClickingAFolderCardWithNoBoardsClosesTheBoardAndSelectsTheFolder() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists, "la board radice avrebbe dovuto aprirsi")

        let card = row(identifier: "canvas-node-\(notFoundFolderCardID)")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "manca la card cartella per «\(emptyFolder)»")
        card.doubleClick()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "una cartella senza board non deve aprire nessuna board")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(emptyFolder)", suffix: ", selezionata")
    }

    // MARK: New (review-triage-fix cycle 1, MAJOR finding) - `BoardTopBar.open(ancestor:)`
    // (ADR-0025 §D5): the breadcrumb's own `.ambiguous`/`.notFound` branch, reusing the
    // multi-board and board-less-parent fixtures already in this file (`boardFolder` holds
    // two boards directly, `groupingFolder` holds none directly) rather than adding new ones.
    // The ancestor segment is a plain SwiftUI `Button(crumb.title)` with no identifier of
    // its own (`BoardChrome.swift`); its title is the folder's own name, data this fixture
    // wrote rather than app prose that could be reworded, the same distinction
    // `WorkspaceIntegrationUITests.taskRow(containing:)` already relies on.

    func testClickingAnAmbiguousBreadcrumbAncestorSelectsTheFolderInsteadOfABoard() throws {
        app.buttons["workspace-expand-all"].click()
        let nested = row(identifier: "workspace-board-\(nestedBoardFile)")
        XCTAssertTrue(nested.waitForExistence(timeout: 5), "la board annidata non è comparsa dopo «Espandi tutto»")
        nested.click()
        assertExactlyOneRowSelected(identifier: "workspace-board-\(nestedBoardFile)", suffix: ", aperta")

        // Index 1: the trail is ["Workspace", boardFolder, "Dettaglio", nestedBoardFile's own
        // name] - `nestedBoardFile` nests one folder below `boardFolder`, so `boardFolder`
        // is always the first ancestor segment after the root (PG-081: identifier, not label,
        // per CLAUDE.md's "never find a control by the words on it").
        let ancestor = app.buttons["breadcrumb-crumb-1"].firstMatch
        XCTAssertTrue(ancestor.waitForExistence(timeout: 5), "manca il segmento breadcrumb «\(boardFolder)»")
        ancestor.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "un antenato ambiguo nel breadcrumb non deve aprire una board")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(boardFolder)", suffix: ", selezionata")
    }

    func testClickingANotFoundBreadcrumbAncestorSelectsTheFolderInsteadOfABoard() throws {
        app.buttons["workspace-expand-all"].click()
        let nested = row(identifier: "workspace-board-\(groupingChildBoardFile)")
        XCTAssertTrue(nested.waitForExistence(timeout: 5), "la board del gruppo non è comparsa dopo «Espandi tutto»")
        nested.click()
        assertExactlyOneRowSelected(identifier: "workspace-board-\(groupingChildBoardFile)", suffix: ", aperta")

        // Index 1: the trail is ["Workspace", groupingFolder, "Cliente", groupingChildBoardFile's
        // own name] - `groupingChildBoardFile` nests one folder below `groupingFolder`, so
        // `groupingFolder` is always the first ancestor segment after the root (PG-081:
        // identifier, not label, per CLAUDE.md's "never find a control by the words on it").
        let ancestor = app.buttons["breadcrumb-crumb-1"].firstMatch
        XCTAssertTrue(ancestor.waitForExistence(timeout: 5), "manca il segmento breadcrumb «\(groupingFolder)»")
        ancestor.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "un antenato senza board nel breadcrumb non deve aprire una board")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(groupingFolder)", suffix: ", selezionata")
    }

    // MARK: Fixture

    /// Real folders and files on disk before the app ever launches: a `.canvas` in the
    /// vault root itself (what the two ported tests click, and R-11's target), a folder
    /// holding two boards under different names (`boardFolder`, `boardFile`,
    /// `siblingBoardFile` - R-03), a board nested two levels inside it
    /// (`nestedBoardFile`), a board-less grouping folder whose only content is a subfolder
    /// that owns a board (`groupingFolder` / `groupingChildBoardFile`) - the shape SPEC
    /// Decision 3 and ADR-0024 §D5 both require a selectable, non-opening row for - and a
    /// folder holding nothing at all (`emptyFolder`, R-10).
    ///
    /// The root `.canvas` is not optional here, but the reason has changed with the model:
    /// it is no longer a root row the tree synthesizes when the file happens to exist, it
    /// is simply a board file, and a board file is a row because it is a file
    /// (ADR-0025 §D1/§D2). Remove it and the two ported tests have no board to open -
    /// nothing else about the tree changes, because the vault root is the list rather than
    /// a row in it. Both tests are ported unchanged in intent from `5041d5c`, where "click
    /// the root row" always meant "open the board", so the fixture keeps giving them one.
    ///
    /// The empty folder is created directly rather than as some board's parent: a folder
    /// that exists only on disk, named by nothing, is exactly the row `CanvasStore
    /// .allFolders()` was added to find.
    private func makeFixtureBoards() throws {
        let rootBoardFile = "\(vault.lastPathComponent).canvas"
        // The root board alone carries the two folder-card nodes the double-click tests
        // above need; every other board file stays the plain empty canvas the rest of this
        // file's fixtures have always used.
        try writeBoard(rootCanvas, at: rootBoardFile)
        for boardPath in [boardFile, siblingBoardFile, nestedBoardFile, groupingChildBoardFile] {
            try writeBoard(Self.emptyCanvas, at: boardPath)
        }
        try FileManager.default.createDirectory(
            at: vault.appending(path: emptyFolder, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func writeBoard(_ contents: String, at boardPath: String) throws {
        let url = vault.appending(path: boardPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let emptyCanvas = """
    { "nodes": [], "edges": [] }
    """

    /// `emptyCanvas` plus the two folder cards the double-click tests above open: one
    /// pointing at `boardFolder` (two boards inside it, `.ambiguous`), one at `emptyFolder`
    /// (none, `.notFound`). A computed property rather than another `static let`, since it
    /// has to read `boardFolder`/`emptyFolder` off `self` rather than duplicate their value.
    private var rootCanvas: String {
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
}
