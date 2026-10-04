import XCTest

/// The editor hand-off to the Workspace from a folder whose board cannot be named
/// (ADR-0025 §D5, §F8). The R-16 walk of ADR-0021 this file used to carry runs in
/// process now, in `Tests/WorkspaceIntegrationWalkTests.swift`.
///
/// `-disableCalendar YES`, every control found by `accessibilityIdentifier`, and the
/// throwaway vault opened through the plist-array form of `-recentVaults` - the same
/// three rules `CLAUDE.md` records for every UI-test file in this suite.
final class WorkspaceIntegrationUITests: PergamenumUITestCase {
    // MARK: Fixture identity, named once so every step and every assertion agrees.

    /// A folder holding two boards directly (review-triage-fix cycle 1, MAJOR finding:
    /// `WorkspaceView.placePendingNote` had no UI coverage for its `.ambiguous`/`.notFound`
    /// miss branch) - the `WorkspaceBoardResolver.board(inFolder:among:)` `.ambiguous` case.
    private let ambiguousFolder = "Ambiguo"
    private let ambiguousNoteTitle = "NotaAmbigua"
    private let ambiguousNotePath = "Ambiguo/NotaAmbigua.md"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeVault()
    }

    // MARK: New (review-triage-fix cycle 1, MAJOR finding) - `WorkspaceView.placePendingNote`
    // (ADR-0025 §D5, §F8): the editor hand-off's own `.ambiguous`/`.notFound` branch, the
    // third of the three `WorkspaceBoardResolver.board(inFolder:among:)` call sites with no
    // UI coverage. This test also confirms the branch's `vault.recordProblem` call, the one
    // effect the navigation assertion alone would not prove - read back from
    // Impostazioni → Avanzate → Problemi (`SettingsView.swift`), the only place `vault
    // .problems` is drawn. Opening Impostazioni through Cmd+, and finding its tab by
    // `identifier:` is the pattern `NoteTreeAndShortcutsUITests` already uses for the same
    // scene, not a new one invented here.
    //
    // The Workspace pane is opened **before** "Apri nel Workspace" is clicked, deliberately:
    // `WorkspaceView`'s only listener is `.onChange(of: vault.pendingWorkspacePlacement)`
    // (`WorkspaceView.swift`), which SwiftUI fires on a transition the view is alive to see,
    // never on a value already non-nil when the view mounts. Clicking the Inserisci command
    // from the Note pane first, then switching panes, would set the flag on a `WorkspaceView`
    // that does not exist yet and lose the hand-off entirely - not what this test is testing.
    // The Inserisci menu itself needs no pane of its own: it is a scene-level `Commands` menu
    // gated only on `vault.openNote != nil`, unaffected by which pane is visible.

    func testSendingANoteFromAnAmbiguousFolderToTheWorkspaceSelectsTheFolderAndRecordsAProblem() throws {
        launch()
        openPane("pane-notes")
        openNoteInEditor(titled: ambiguousNoteTitle)
        openPane("pane-workspace")

        app.menuBars.menuItems["Apri nel Workspace"].click()

        assertFolderSelected(ambiguousFolder)
        try assertNoBoardWasWritten(in: ambiguousFolder, otherThan: ["A.canvas", "B.canvas"])
        assertProblemRecorded(containing: ambiguousNotePath)
    }

    // MARK: Launch

    private func launch() {
        launchApp()
        waitForMainWindow(timeout: 15)
    }

    // MARK: Panes

    private func openPane(_ itemID: String) {
        // By the row's own `sidebar-<id>` identifier (`RootView.row(_:)`, PG-265), not by
        // its words: a pane's own breadcrumb bar draws the same bare pane name as its root
        // segment when nothing is open in it (`VaultTopBar`/`BoardChrome`), and a lookup by
        // words collides with it the moment that pane is also the one active at launch.
        let row = sidebarRow(itemID)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "manca la riga «sidebar-\(itemID)»")
        row.click()
    }

    // MARK: Editor hand-off (review-triage-fix cycle 1)

    /// Filters the Note pane down to one note and opens it - "Apri nel Workspace"
    /// (`MenuCommands.swift`'s Inserisci menu) is `.disabled(vault.openNote == nil)`, so the
    /// note has to really be open, not merely selected. `note-filter` is the Note pane's own
    /// equivalent of the Workspace browser's `workspace-filter`. The row itself carries no
    /// identifier (`NoteListPane.flatList`'s `Text(note.title)`), so it is matched on
    /// `value`, the same substitution `DesignAndReadingUITests.text(withValue:)` uses for a
    /// plain `Text` on macOS - the title is content this fixture wrote, not app prose.
    private func openNoteInEditor(titled title: String) {
        let filter = app.textFields["note-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 8), "il filtro delle note non è comparso")
        filter.click()
        filter.typeText(title)

        let row = app.staticTexts.matching(NSPredicate(format: "value == %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "la nota «\(title)» non è nell'elenco filtrato")
        row.click()
    }

    /// Opens Impostazioni through the standard system shortcut and reads a recorded problem
    /// back off Avanzate → Problemi. Cmd+, plus `.matching(identifier:)` for the tab is the
    /// same pattern `NoteTreeAndShortcutsUITests.testTheSettingsPaneListsEveryCommandAndCan
    /// PutOneBack` already uses to reach the Scorciatoie tab of this same scene - the settings
    /// window's own title comes from the system, so neither test names it.
    private func assertProblemRecorded(containing text: String) {
        app.typeKey(",", modifierFlags: .command)
        let advancedTab = app.descendants(matching: .any).matching(identifier: "Avanzate").firstMatch
        XCTAssertTrue(advancedTab.waitForExistence(timeout: 10), "la scheda Avanzate non è comparsa")
        advancedTab.click()

        let problem = app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", text)).firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 8), "nessun problema registrato contiene «\(text)»")
    }

    /// `placePendingNote`'s guard branch selects the folder rather than a board
    /// (`workspace.select(folder.isEmpty ? nil : .folder(folder))`), which is what puts
    /// `, selezionata` on the folder row's accessibility label - the same ADR-0024 §D9
    /// mechanism `WorkspaceOpenStateUITests.assertExactlyOneRowSelected` reads.
    private func assertFolderSelected(_ folder: String) {
        let selected = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label ENDSWITH ', selezionata'", "workspace-folder-\(folder)")
        ).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 8), "la cartella «\(folder)» non risulta selezionata")
    }

    /// The regression this test guards against by name (ADR-0025 §F8): the hand-off used to
    /// open a board named after the folder, writing one where none existed. `expectedCanvases`
    /// is the fixture's own board list for that folder, unaffected by the hand-off if the
    /// guard held; the same on-disk check `WorkspaceOpenStateUITests`'s R-10 test uses.
    private func assertNoBoardWasWritten(in folder: String, otherThan expectedCanvases: Set<String>) throws {
        let directory = vault.appending(path: folder, directoryHint: .isDirectory)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        XCTAssertEqual(Set(contents.filter { $0.hasSuffix(".canvas") }), expectedCanvases,
                       "l'hand-off dell'editor non deve scrivere una nuova board in «\(folder)»")
    }

    // MARK: Fixture

    /// Two boards directly inside `ambiguousFolder` (`.ambiguous`) and the note the test
    /// sends from it - the editor hand-off's own miss fixture.
    private func makeVault() throws {
        try makeTemporaryVault(prefix: "WorkspaceIntegrationUITest")
        try FileManager.default.createDirectory(
            at: vault.appending(path: ambiguousFolder, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Self.emptyCanvas.write(
            to: vault.appending(path: "\(ambiguousFolder)/A.canvas", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try Self.emptyCanvas.write(
            to: vault.appending(path: "\(ambiguousFolder)/B.canvas", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try writeNote(at: ambiguousNotePath, title: ambiguousNoteTitle)
    }

    private static let emptyCanvas = """
    { "nodes": [], "edges": [] }
    """

    private func writeNote(at relativePath: String, title: String) throws {
        let note = """
        ---
        date: 2026-08-24
        tags:
          - type-nota
        ---

        # \(title)
        """
        try note.write(
            to: vault.appending(path: relativePath, directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
