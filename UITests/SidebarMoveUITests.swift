import XCTest

/// Drag-and-drop reorganization of both sidebar trees: `ADR-0026` ("A row is dragged into
/// a folder, and several rows are chosen first"), plan
/// `2026-08-27-drag-and-drop-board-files-into-workspace.md`, Task 7.
///
/// Every row is found by `accessibilityIdentifier`, never by the words on it (`CLAUDE.md`),
/// with the one documented exception this repository already carries and this file inherits
/// rather than reinvents: a SwiftUI `.contextMenu`'s (and a nested `Menu`'s) entries are
/// `NSMenuItem`s rendered **outside** the accessibility hierarchy of the row that owns them
/// (`WorkspaceOpenStateUITests.testABoardRowsContextMenuOffersRenameAndDelete_R08`'s own
/// comment, ADR-0025 F11), so `app.menuItems[title]` is the only lookup that reaches them at
/// all - the titles asserted on are the production strings verbatim.
///
/// Two things this file is built around, both read out of ADR-0026 before a line was written:
///
/// - **The menu is the deterministic half.** «Sposta in ▸» is a second rendering of the same
///   drag (§D9), added specifically because no test in this repository had ever driven a
///   `.draggable` → `.dropDestination` pasteboard drag before this chain.
/// - **The drag half was spiked first**, per Task 7's own instruction, with a throwaway test
///   doing `row.press(forDuration: 0.4, thenDragTo: folderRow)` in the Workspace tree, run five
///   separate times through `scripts/uitests.sh`. It passed 5/5 - that call did start and
///   complete a real `NSDraggingSession` against a folder row's
///   `.dropDestination(for: VaultItemDrag.self)`. On macOS 27 that exact call stopped
///   delivering a drag at all (PG-162); `dragTo(_:pressing:)` (`DragSupport.swift`) says why.
///
/// Every row this file interacts with sits at the vault's own top level. That is a fixture
/// choice, not a limitation of what the feature can do: `WorkspaceRow`'s chevron carries no
/// `accessibilityIdentifier` of its own (`WorkspaceRow.swift`'s own comment on `chevron`
/// records that a throwaway probe was needed even to establish its tap-vs-double-tap behaviour
/// by hand), so a row nested under a *collapsed* folder cannot be reached by identifier without
/// first clicking that exact pixel - a fragility this file has no reason to take on when every
/// requirement below is provable with root-level fixtures instead. Where a row's *destination*
/// after a move needs to be read back through the UI (R-01) this file reuses
/// `WorkspaceIntegrationUITests.openBoard()`'s own trick: typing into the filter field switches
/// the browser to `flatList`, which draws every match flat regardless of expand state.
///
/// Known gap, not tested here on purpose (told to this file rather than discovered by it):
/// `NoteListPane.performMove` reports a collision through `VaultController.recordProblem`
/// only - there is no `.alert` on the Note pane the way `WorkspaceBrowser` has
/// `sidebar-move-conflict`. R-07 is therefore driven against the **Workspace** tree, where the
/// alert is real, not against the Note sidebar.
///
/// R-02, R-04, R-05, R-10, R-11 and all four R-15 drag scenarios retired here per the
/// UI-suite-replacement census (stage 3, Task 6): R-03 and R-06 had already converted to
/// unit tests in stage 2 (`VaultController.moveNote`, `canMove(to:)`). What is left is what
/// stayed genuinely GUI-only: the deterministic menu path for a single row (R-01), the
/// `.alert`-to-`NSAlert` conflict bridge (R-07), and the window's own `UndoManager` (R-12).
/// The four synthesized drags were also the most exposed to the machine (PG-180: 13
/// failures in 20 with the pointer disturbed, 30/30 clean on an untouched Mac); drag and
/// drop is left with no cover at all after this, a loss named rather than hidden.
final class SidebarMoveUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-disablePlaud", "YES",
                               "-disableUpdater", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10), "il vault non si è aperto")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    // MARK: R-01 - a board row's «Sposta in ▸ B» moves the file, the tree reflects it with no rescan

    func testMovingABoardRowViaTheMenuMovesTheFileAndTheTreeShowsItAtItsNewLocation_R01() throws {
        openWorkspace()
        let row = workspaceRow("workspace-board-Board.canvas")
        moveViaMenu(row, to: "Target")

        XCTAssertTrue(waitForFile(vault.appending(path: "Target/Board.canvas"), toExist: true),
                     "Board.canvas non è comparso in Target/")
        XCTAssertTrue(waitForFile(vault.appending(path: "Board.canvas"), toExist: false),
                     "Board.canvas è ancora nella radice")

        // No relaunch, no explicit rescan: typing into the filter is the only action
        // taken between the move above and this check, and it switches the browser to
        // `flatList`, which draws every match flat regardless of what is expanded -
        // `WorkspaceIntegrationUITests.openBoard()`'s own technique.
        let filter = app.textFields["workspace-filter"]
        filter.click()
        filter.typeText("Board")
        let moved = workspaceRow("workspace-board-Target/Board.canvas")
        XCTAssertTrue(moved.waitForExistence(timeout: 5),
                     "la riga non compare sotto Target senza un rescan manuale")
        XCTAssertFalse(workspaceRow("workspace-board-Board.canvas").exists,
                       "la vecchia riga alla radice è ancora nell'albero")
    }

    // MARK: R-07 - a collision is refused, named in a dialog, and changes nothing on disk

    /// BUG found while writing this test, reported rather than worked around silently:
    /// `WorkspaceBrowser.swift`'s `.alert(...) { message: { Text(conflict.message)
    /// .accessibilityIdentifier("sidebar-move-conflict") } }` never reaches the
    /// accessibility tree under that identifier. macOS bridges a SwiftUI `.alert` to a
    /// native `NSAlert`, and the button stays a real, individually-identified control
    /// (`sidebar-move-conflict-ok` resolves exactly as declared) while the informative
    /// text is converted to a plain string for `NSAlert.informativeText` - the
    /// `Text.accessibilityIdentifier` modifier has nothing left to attach to by the time
    /// that happens, and the rendered `StaticText` carries an AppKit-synthesized
    /// identifier (`_NS:58` at the run this was found in) instead. Confirmed by dumping
    /// `app.debugDescription` at the point of failure - the `Sheet` element itself,
    /// its two `StaticText`s and the `OK` button are all present and correctly worded,
    /// only the declared identifier on the message is unreachable. This is a
    /// SwiftUI/AppKit `.alert` bridging limitation, not a coding slip a different call
    /// shape can trivially route around within the current `.alert(...) { } message: { }`
    /// API - reported to the coder/architect rather than fixed here.
    ///
    /// The assertion below still proves what R-07 asks (the conflicting name is shown)
    /// by reading the `Sheet`'s own static text content directly, the same kind of
    /// exception this file's header already documents for `.contextMenu` entries: there
    /// is no identifier-based path to this content, so this is what "shown to the user"
    /// can be verified by.
    func testMovingIntoAFolderThatAlreadyHoldsTheNameShowsTheConflictAndLeavesTheFileInPlace_R07() throws {
        openWorkspace()
        let row = workspaceRow("workspace-board-Board.canvas")
        moveViaMenu(row, to: "Collide")

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "il dialogo di conflitto non è comparso")
        let conflictText = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS[c] %@", "Collide/Board.canvas")
        ).firstMatch
        XCTAssertTrue(conflictText.waitForExistence(timeout: 5),
                      "il nome in conflitto non è mostrato nel dialogo")
        app.buttons["sidebar-move-conflict-ok"].click()

        XCTAssertTrue(waitForFile(vault.appending(path: "Board.canvas"), toExist: true),
                     "Board.canvas è stata spostata nonostante il rifiuto")
        let collidingFile = vault.appending(path: "Collide/Board.canvas")
        let contents = try? String(contentsOf: collidingFile, encoding: .utf8)
        XCTAssertEqual(contents, Self.collideMarker, "il file già presente in Collide/ è stato sovrascritto")
    }

    // MARK: R-12 - Cmd+Z restores every moved item in one step, Cmd+Shift+Z reapplies

    func testUndoAfterAMenuMoveRestoresBothInOneStepAndRedoReappliesIt_R12() throws {
        openWorkspace()
        let rowA = workspaceRow("workspace-board-UndoA.canvas")
        let rowB = workspaceRow("workspace-board-UndoB.canvas")
        XCTAssertTrue(rowA.waitForExistence(timeout: 5))
        XCTAssertTrue(rowB.waitForExistence(timeout: 5))
        rowA.click()
        cmdClick(rowB)
        moveViaMenu(rowA, to: "Target")

        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoA.canvas"), toExist: true))
        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoB.canvas"), toExist: true))

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(waitForFile(vault.appending(path: "UndoA.canvas"), toExist: true),
                     "UndoA.canvas non è tornata al suo posto con Cmd+Z")
        XCTAssertTrue(waitForFile(vault.appending(path: "UndoB.canvas"), toExist: true),
                     "UndoB.canvas non è tornata al suo posto con Cmd+Z: l'annullamento non è stato un unico passo")
        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoA.canvas"), toExist: false))
        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoB.canvas"), toExist: false))

        app.typeKey("z", modifierFlags: [.command, .shift])

        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoA.canvas"), toExist: true),
                     "Cmd+Shift+Z non ha riapplicato lo spostamento")
        XCTAssertTrue(waitForFile(vault.appending(path: "Target/UndoB.canvas"), toExist: true))
    }

    // MARK: Navigation

    private func openWorkspace() {
        app.staticTexts["Workspace"].click()
        XCTAssertTrue(app.textFields["workspace-filter"].waitForExistence(timeout: 10),
                     "il browser del Workspace non si è aperto")
    }

    private func workspaceRow(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func cmdClick(_ element: XCUIElement) {
        XCUIElement.perform(withKeyModifiers: .command) { element.click() }
    }

    /// Right-clicks `row`, opens the «Sposta in ▸» submenu it carries, and clicks the
    /// entry for `destination` (`""` for «(radice)»).
    ///
    /// `app.menuItems[title]` rather than `accessibilityIdentifier`: a `.contextMenu`'s
    /// (and a nested `Menu`'s) entries are `NSMenuItem`s outside the row's own
    /// accessibility hierarchy, so there is no identifier here to find them by -
    /// `WorkspaceOpenStateUITests`'s own «Rinomina…»/«Elimina…» lookups are the same
    /// exception for the same reason.
    private func moveViaMenu(
        _ row: XCUIElement, to destination: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), "riga assente", file: file, line: line)
        row.rightClick()
        let moveMenu = app.menuItems["Sposta in"]
        XCTAssertTrue(moveMenu.waitForExistence(timeout: 5), "manca il menu «Sposta in»", file: file, line: line)
        moveMenu.click()
        let label = destination.isEmpty ? "(radice)" : destination
        let target = app.menuItems[label]
        XCTAssertTrue(target.waitForExistence(timeout: 5),
                     "manca la voce «\(label)» nel menu «Sposta in»", file: file, line: line)
        target.click()
    }

    // MARK: Reading the result off disk

    private func waitForFile(_ url: URL, toExist expected: Bool, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected
    }

    // MARK: Fixture

    private static let boardFixture = """
    { "nodes": [], "edges": [] }
    """

    private static let collideMarker = "ALREADY-HERE"

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "SidebarMoveUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        for folder in ["Collide", "Target"] {
            try FileManager.default.createDirectory(
                at: vault.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }

        // R-01 / R-07 / R-12's boards, every one at the vault's own top level (see the
        // file header).
        for board in ["Board.canvas", "UndoA.canvas", "UndoB.canvas"] {
            try Self.boardFixture.write(
                to: vault.appending(path: board, directoryHint: .notDirectory),
                atomically: true, encoding: .utf8
            )
        }
        // R-07's collision partner: same file name as the root-level `Board.canvas`.
        try Self.collideMarker.write(
            to: vault.appending(path: "Collide/Board.canvas", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        try writeNote("Note", at: "Note.md")
    }

    private func writeNote(_ title: String, at relativePath: String) throws {
        let note = """
        ---
        date: 2026-08-27
        tags:
          - type-nota
        ---

        # \(title)

        Corpo della nota \(title).
        """
        try note.write(
            to: vault.appending(path: relativePath, directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
