import XCTest

/// R-16 end to end: the Workspace browser, a board's dashboard, a project task with
/// two sub-tasks, the Workspace and note assignments, and the "Progetti" grouping -
/// walked in one pass, then proven to survive a quit and a full index rebuild.
///
/// ADR-0021 ("A task carries its Workspace and its place in a project as caret
/// markers in its own line, and nothing new is stored anywhere else"). Plan
/// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 10.
///
/// `-disableCalendar YES`, every control found by `accessibilityIdentifier`, and the
/// throwaway vault opened through the plist-array form of `-recentVaults` - the same
/// three rules `CLAUDE.md` records for every UI-test file in this suite. Two things
/// are new to this file and are called out where they bite:
///
/// - **A mid-test relaunch.** No existing file quits and relaunches the app inside one
///   test; `-stateBase` and the vault both live on disk under paths this file controls
///   and are never deleted between the two launches, so the second one reopens
///   whatever the first left behind - which is the whole of what "survives a restart"
///   means here.
/// - **Re-selecting the project task between the two sub-task insertions.**
///   `VaultController.selectedTask` is a snapshot, not a live reference, and nothing
///   refreshes it after a capture (`rescheduleSelectedTask` is the one place that
///   does, and this is not it). The first "Aggiungi sotto-task" adds `^id(N)` to the
///   parent's own line when it had none, so the cached snapshot this file would
///   otherwise still be holding no longer matches what `TaskParser.insertingSubtask`
///   reads back off disk, and its staleness guard - `lines[parent.lineIndex] ==
///   parent.rawLine`, exact - refuses the second insertion rather than silently
///   misplacing it. Clicking the row again between the two reads the current line
///   back before the second command runs. See the report handed to the orchestrator
///   alongside this file for the reproduction with nothing worked around.
final class WorkspaceIntegrationUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    // MARK: Fixture identity, named once so every step and every assertion agrees.

    private let boardFolder = "Vibrofer"
    private let boardFile = "Vibrofer/Vibrofer.canvas"
    private let noteAPath = "Vibrofer/DocumentoBrief.md"
    private let noteBPath = "Vibrofer/DocumentoContratto.md"
    private let noteASearch = "DocumentoBrief"
    private let noteBSearch = "DocumentoContratto"

    private let parentText = "Progetto EMEA rilancio sito"
    private let childOneText = "Bozza contratto fornitore"
    private let childTwoText = "Firma contratto fornitore"

    /// A folder holding two boards directly (review-triage-fix cycle 1, MAJOR finding:
    /// `WorkspaceView.placePendingNote` had no UI coverage for its `.ambiguous`/`.notFound`
    /// miss branch) - the `WorkspaceBoardResolver.board(inFolder:among:)` `.ambiguous` case.
    private let ambiguousFolder = "Ambiguo"
    private let ambiguousNoteTitle = "NotaAmbigua"
    private let ambiguousNotePath = "Ambiguo/NotaAmbigua.md"

    /// A folder holding no board at all - the `.notFound` case of the same resolver call.
    private let orphanFolder = "SenzaBoard"
    private let orphanNoteTitle = "NotaOrfana"
    private let orphanNotePath = "SenzaBoard/NotaOrfana.md"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    func testWorkspaceBrowserBoardDashboardAndProjectSubtasksSurviveARestartAndARescan() throws {
        launch()

        // MARK: 1. Open the Workspace browser, select the board, read its two panels.

        openPane("Workspace")
        openBoard()
        // Read from the board's own document (R-06), populated by the fixture and
        // independent of anything a task does - true before a single task exists.
        assertReferencedNotesShowBothFixtureNotes()
        // Nothing assigned yet (R-05): the count in the header says so.
        assertAssignedTasksHeaderCount(0)

        // MARK: 2. A project task with two sub-tasks on different due dates.

        openPane("Attività")
        captureParentTask()
        selectTaskRow(containing: parentText)
        addSubtask(text: childOneText, dueInDays: 3)
        // See the header comment: the parent's own line changed underneath the
        // selection the moment it gained `^id(N)`, and re-clicking the row is what
        // reads that change back before the second sub-task is composed.
        selectTaskRow(containing: parentText)
        addSubtask(text: childTwoText, dueInDays: 10)

        // MARK: 3. Assign the board and two notes to the project task.

        selectTaskRow(containing: parentText)
        assignWorkspace()
        selectTaskRow(containing: parentText)
        linkNote(search: noteASearch)
        selectTaskRow(containing: parentText)
        linkNote(search: noteBSearch)

        // MARK: 4. "Progetti": the group expands with its progress indicator.

        selectGrouping("Progetti")
        assertProjectGroupExists(done: 0, total: 2)

        // The board's own tray now lists what R-05 promised it would, from the same
        // in-memory index the assignment just updated - no rescan needed for this.
        openPane("Workspace")
        openBoard()
        assertAssignedTasksHeaderCount(1)
        assertAssignedTaskRow(containing: parentText)

        // MARK: 5. Quit, relaunch, force a full index rebuild: everything survives.

        app.terminate()
        launch()
        rebuildIndex()

        openPane("Workspace")
        openBoard()
        assertReferencedNotesShowBothFixtureNotes()
        assertAssignedTasksHeaderCount(1)
        assertAssignedTaskRow(containing: parentText)

        openPane("Attività")
        selectGrouping("Progetti")
        assertProjectGroupExists(done: 0, total: 2)
    }

    // MARK: New (review-triage-fix cycle 1, MAJOR finding) - `WorkspaceView.placePendingNote`
    // (ADR-0025 §D5, §F8): the editor hand-off's own `.ambiguous`/`.notFound` branch, the
    // third of the three `WorkspaceBoardResolver.board(inFolder:among:)` call sites with no
    // UI coverage. Both tests also confirm the branch's `vault.recordProblem` call, the one
    // effect neither of them would prove by the navigation assertion alone - read back from
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
    // that does not exist yet and lose the hand-off entirely - not what this pair is testing.
    // The Inserisci menu itself needs no pane of its own: it is a scene-level `Commands` menu
    // gated only on `vault.openNote != nil`, unaffected by which pane is visible.

    func testSendingANoteFromAnAmbiguousFolderToTheWorkspaceSelectsTheFolderAndRecordsAProblem() throws {
        launch()
        openPane("Note")
        openNoteInEditor(titled: ambiguousNoteTitle)
        openPane("Workspace")

        app.menuBars.menuItems["Apri nel Workspace"].click()

        assertFolderSelected(ambiguousFolder)
        try assertNoBoardWasWritten(in: ambiguousFolder, otherThan: ["A.canvas", "B.canvas"])
        assertProblemRecorded(containing: ambiguousNotePath)
    }

    func testSendingANoteFromAFolderWithNoBoardsToTheWorkspaceSelectsTheFolderAndRecordsAProblem() throws {
        launch()
        openPane("Note")
        openNoteInEditor(titled: orphanNoteTitle)
        openPane("Workspace")

        app.menuBars.menuItems["Apri nel Workspace"].click()

        assertFolderSelected(orphanFolder)
        try assertNoBoardWasWritten(in: orphanFolder, otherThan: [])
        assertProblemRecorded(containing: orphanNotePath)
    }

    // MARK: Launch

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 15), "il vault non si è aperto")
    }

    // MARK: Panes

    private func openPane(_ title: String) {
        // Scoped to the sidebar (`RootView`'s `"root-sidebar"`, 2026-08-28 recovery
        // checkpoint), not to the whole app: a pane's own breadcrumb bar draws the same
        // bare pane name as its root segment when nothing is open in it
        // (`VaultTopBar`/`BoardChrome`), and an app-wide lookup by words collides with
        // it the moment that pane is also the one active at launch.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "root-sidebar"))
            .staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "manca la sezione «\(title)»")
        row.click()
    }

    // MARK: 1. Workspace browser and board dashboard

    /// Filters the browser down to the one board the fixture carries and opens it.
    /// `WorkspaceView` is torn down and rebuilt every time the pane is left and
    /// returned to (`RootView`'s `switch pane` creates it fresh), so this is called
    /// again on every visit rather than once.
    private func openBoard() {
        let filter = app.descendants(matching: .any).matching(identifier: "workspace-filter").firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10), "il browser del Workspace non si è aperto")
        filter.click()
        filter.typeText(boardFolder)

        let row = app.descendants(matching: .any).matching(identifier: "workspace-board-\(boardFile)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "la board «\(boardFolder)» non è nell'elenco filtrato")
        row.click()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "board-tray").firstMatch.waitForExistence(timeout: 10),
            "il pannello della board non si è aperto"
        )
    }

    private func assertReferencedNotesShowBothFixtureNotes() {
        for path in [noteAPath, noteBPath] {
            let row = app.descendants(matching: .any).matching(identifier: "board-referenced-note-\(path)").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "la nota «\(path)» non è nelle NOTE REFERENZIATE")
        }
    }

    /// `BoardTray.assignedTasks`' header carries the count in its own accessibility
    /// label (`"Task assegnati a questa board: N"`), which is data rather than prose
    /// that might be reworded - a legitimate thing to assert on directly.
    ///
    /// Matched on `value`, not `label`: on macOS, `.accessibilityLabel(_:)` applied to a
    /// plain `Text` is exposed through `AXValue`, not `AXTitle`/`AXLabel` - confirmed by
    /// reading the failing run's exported UI-hierarchy attachment, which showed
    /// `identifier: 'board-assigned-tasks-header', value: Task assegnati a q...` with no
    /// `label:` at all. `label ==` never matches a `StaticText` for this reason; `value ==`
    /// does. `assertProjectGroupExists` below hit the identical shape for the same reason.
    private func assertAssignedTasksHeaderCount(_ expected: Int) {
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@", "Task assegnati a questa board: \(expected)"))
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "l'intestazione TASK ASSEGNATI non conta \(expected)")
    }

    private func assertAssignedTaskRow(containing text: String) {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "assigned-task-", text))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "«\(text)» non è nella sezione TASK ASSEGNATI della board")
    }

    // MARK: 2. Capture, and the two sub-tasks

    private func toolbarButton(_ label: String, timeout: TimeInterval = 8) -> XCUIElement {
        let element = app.toolbars.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "manca il pulsante «\(label)»")
        return element
    }

    private func captureParentTask() {
        toolbarButton("Cattura rapida").click()
        let field = app.textFields["task-composer-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "il composer del task principale non si è aperto")
        field.click()
        field.typeText(parentText)
        app.buttons["task-composer-create"].click()
        XCTAssertFalse(
            app.textFields["task-composer-text"].waitForExistence(timeout: 3),
            "il composer del task principale è rimasto aperto"
        )
    }

    /// "Tutti" is the one of the five views with no date filter (`IndexSnapshot
    /// .tasks(for:)`'s `.all` case returns every open task, unlike `.inbox` or
    /// `.upcoming`), so it is the one place both the un-dated parent and the two
    /// due-only children are ever on screen together. `TasksView` resets its own
    /// `view` to `.today` every time the pane is rebuilt, and `followLastCapture()`
    /// moves it again after every write this test makes - so this is called before
    /// every row lookup rather than once.
    private func focusAllTasksView() {
        let tutti = app.staticTexts["Tutti"]
        XCTAssertTrue(tutti.waitForExistence(timeout: 8), "manca la vista «Tutti»")
        tutti.click()
    }

    /// A task row carries no per-task identifier of its own (`TasksView.row` sets the
    /// same `"task-row"` on every one of them, unlike `TaskPanelRow`'s
    /// `"\(identifierPrefix)-\(task.id)"` one file over) - see this file's report to
    /// the orchestrator. Matched on its combined accessibility label instead, which
    /// carries `task.text` verbatim: this is content this test itself wrote, not
    /// prose the app could reword, so it does not fall under `CLAUDE.md`'s "a control
    /// must never be found by the words on it".
    private func taskRow(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "task-row", text))
            .firstMatch
    }

    private func selectTaskRow(containing text: String) {
        focusAllTasksView()
        let row = taskRow(containing: text)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "manca la riga del task «\(text)»")
        row.click()
    }

    private func addSubtask(text: String, dueInDays days: Int) {
        app.menuBars.menuItems["Aggiungi sotto-task"].click()

        let parentRow = app.descendants(matching: .any).matching(identifier: "task-composer-parent").firstMatch
        XCTAssertTrue(parentRow.waitForExistence(timeout: 8), "il composer non mostra il task padre")

        let field = app.textFields["task-composer-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "il composer del sotto-task non si è aperto")
        field.click()
        field.typeText(text)

        app.buttons["task-composer-due"].click()
        let dueField = app.textFields["due-panel-field"]
        XCTAssertTrue(dueField.waitForExistence(timeout: 8), "manca il campo Scadenza del sotto-task")
        dueField.click()
        // Typed directly rather than picked off a calendar grid: `DateEntry.parse`
        // reads a bare ISO date, and typing it sidesteps whether the panel's default
        // month view reaches ten days out, which for "fra 10 giorni" crosses into the
        // next month more often than not.
        dueField.typeText(iso(daysFromToday: days) + "\r")

        app.buttons["task-composer-create"].click()
        XCTAssertFalse(
            app.textFields["task-composer-text"].waitForExistence(timeout: 3),
            "il composer del sotto-task «\(text)» è rimasto aperto - il padre selezionato era forse quello vecchio"
        )
    }

    // MARK: 3. Assigning the Workspace and linking two notes

    private func assignWorkspace() {
        toolbarButton("Assegna a un Workspace").click()
        let list = app.descendants(matching: .any).matching(identifier: "workspace-picker-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 8), "il picker del Workspace non si è aperto")

        let row = app.descendants(matching: .any).matching(identifier: "workspace-picker-row-\(boardFile)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "la board «\(boardFolder)» non è nel picker")
        row.click()

        XCTAssertTrue(list.waitForNonExistence(timeout: 8), "il picker del Workspace non si è chiuso dopo l'assegnazione")
    }

    private func linkNote(search title: String) {
        toolbarButton("Collega nota o board").click()
        let field = app.textFields["quick-switcher-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "il quick switcher per collegare una nota non si è aperto")
        field.typeText(title + "\r")
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), "il quick switcher è rimasto aperto dopo la scelta")
    }

    // MARK: Editor hand-off (review-triage-fix cycle 1)

    /// Filters the Note pane down to one note and opens it - "Apri nel Workspace"
    /// (`MenuCommands.swift`'s Inserisci menu) is `.disabled(vault.openNote == nil)`, so the
    /// note has to really be open, not merely selected. `note-filter` is the Note pane's own
    /// equivalent of `openBoard()`'s `workspace-filter` above. The row itself carries no
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

    /// The regression this pair guards against by name (ADR-0025 §F8): the hand-off used to
    /// open a board named after the folder, writing one where none existed. `expectedCanvases`
    /// is the fixture's own board list for that folder, unaffected by the hand-off if the
    /// guard held; the same on-disk check `WorkspaceOpenStateUITests`'s R-01/R-10 tests use.
    private func assertNoBoardWasWritten(in folder: String, otherThan expectedCanvases: Set<String>) throws {
        let directory = vault.appending(path: folder, directoryHint: .isDirectory)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        XCTAssertEqual(Set(contents.filter { $0.hasSuffix(".canvas") }), expectedCanvases,
                       "l'hand-off dell'editor non deve scrivere una nuova board in «\(folder)»")
    }

    // MARK: 4. "Progetti" grouping

    private func selectGrouping(_ title: String) {
        // Applied to whichever view is current, and `TasksView` defaults to `.today`
        // on every fresh mount - including the one after the relaunch, where nothing
        // else in this file has clicked a row yet to land on "Tutti" first. Without
        // this, the second half of the walk would set "Progetti" on a view none of
        // this fixture's tasks are ever in, and read an empty result as a lost state
        // instead of as its own mistake.
        focusAllTasksView()

        let menu = app.windows.firstMatch.descendants(matching: .any)
            .matching(identifier: "task-grouping-menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "manca il menu di raggruppamento")
        menu.click()

        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 8), "manca la voce «\(title)» nel menu di raggruppamento")
        item.click()
    }

    /// The progress indicator's accessibility label is the exact spoken form the UX
    /// blueprint binds (`"N di M completati"`, not the bare `"N/M"` a screen reader
    /// would otherwise read as a date) - asserted on directly rather than approximated,
    /// since this is the one place in the whole walk that string is a contract rather
    /// than incidental copy.
    ///
    /// Matched on `value`, not `label` - see `assertAssignedTasksHeaderCount` above for
    /// why: `.accessibilityLabel(_:)` on a plain `Text` surfaces as `AXValue` on macOS.
    private func assertProjectGroupExists(done: Int, total: Int) {
        let group = app.descendants(matching: .any).matching(identifier: "task-project-group").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10), "il gruppo «Progetti» non è comparso")

        let progress = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@", "\(done) di \(total) completati"))
            .firstMatch
        XCTAssertTrue(
            progress.waitForExistence(timeout: 8),
            "l'indicatore di avanzamento non legge «\(done) di \(total) completati»"
        )

        XCTAssertTrue(taskRow(containing: childOneText).waitForExistence(timeout: 8), "il primo sotto-task non è nel gruppo espanso")
        XCTAssertTrue(taskRow(containing: childTwoText).waitForExistence(timeout: 8), "il secondo sotto-task non è nel gruppo espanso")
    }

    // MARK: 5. Restart and rescan

    private func rebuildIndex() {
        // Two menus carry this exact title - File and Vista both call
        // `vault.rescan()` verbatim - so `firstMatch` rather than a bare subscript,
        // the same reason `DesignAndReadingUITests` needs it for a theme offered in
        // two pickers at once. Either one does the same rebuild.
        app.menuBars.menuItems["Rigenera indice"].firstMatch.click()
        // `vault.rescan()` runs on a `Task`, off the click; the assertions that follow
        // all poll with their own timeout, but the scan needs a moment to start before
        // the first one would otherwise catch the pre-rescan state and call it a pass.
        Thread.sleep(forTimeInterval: 1.5)
    }

    // MARK: Dates

    /// In the machine's own zone, like `ComposerUITests`' own copy: in GMT this names
    /// yesterday for the two hours after local midnight, and the app does not.
    private func iso(daysFromToday days: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    // MARK: Fixture

    /// One folder, one board, two notes already placed on it - the board and the two
    /// notes this walk assigns and links are set up before the app ever opens, so R-05
    /// and R-06 both have something real to read from the first step onward.
    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "WorkspaceIntegrationUITest-\(UUID().uuidString)")
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: vault.appending(path: boardFolder, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)

        try Self.canvasFixture.write(
            to: vault.appending(path: boardFile, directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try writeNote(at: noteAPath, title: noteASearch)
        try writeNote(at: noteBPath, title: noteBSearch)

        // Two boards directly inside `ambiguousFolder` (`.ambiguous`), none inside
        // `orphanFolder` (`.notFound`) - the editor hand-off tests' own miss fixtures.
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

        try FileManager.default.createDirectory(
            at: vault.appending(path: orphanFolder, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try writeNote(at: orphanNotePath, title: orphanNoteTitle)
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

    /// The board this file writes at `Vibrofer/Vibrofer.canvas` and reaches by that path
    /// alone: since ADR-0025 §D1 a board is addressed by its own file path and nothing
    /// derives one from the folder's name (`CanvasStore.boardPath(forFolder:)`, what this
    /// comment used to name, is deleted). The name matching the folder's is now incidental
    /// - the row `openBoard()` clicks is `workspace-board-Vibrofer/Vibrofer.canvas`, which
    /// is the path, and would be the same identifier under any other file name.
    ///
    /// It carries the two notes as `.file` cards - `WorkspaceReferences.notes(in:)`
    /// (ADR-0021 D8) reads exactly this shape.
    private static let canvasFixture = """
    {
      "nodes": [
        { "id": "aaaa000000000001", "type": "file", "file": "Vibrofer/DocumentoBrief.md",
          "x": 0, "y": 0, "width": 240, "height": 80 },
        { "id": "bbbb000000000002", "type": "file", "file": "Vibrofer/DocumentoContratto.md",
          "x": 300, "y": 0, "width": 240, "height": 80 }
      ],
      "edges": []
    }
    """
}
