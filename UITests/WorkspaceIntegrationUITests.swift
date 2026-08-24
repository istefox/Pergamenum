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
        let row = app.staticTexts[title]
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
    private func assertAssignedTasksHeaderCount(_ expected: Int) {
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Task assegnati a questa board: \(expected)"))
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
    private func assertProjectGroupExists(done: Int, total: Int) {
        let group = app.descendants(matching: .any).matching(identifier: "task-project-group").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10), "il gruppo «Progetti» non è comparso")

        let progress = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "\(done) di \(total) completati"))
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
    }

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

    /// The board `CanvasStore.boardPath(forFolder:)` expects at `Vibrofer/Vibrofer
    /// .canvas`, carrying the two notes as `.file` cards - `WorkspaceReferences.notes
    /// (in:)` (ADR-0021 D8) reads exactly this shape.
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
