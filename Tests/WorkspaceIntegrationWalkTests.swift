import Foundation
import Testing
@testable import Pergamenum

// Plan `docs/plans/ui-suite-replacement.md` Task 5, PR 1, ADR-0053 §D2: no seam, no production
// change. Converts `UITests/WorkspaceIntegrationUITests.swift:75`,
// `testWorkspaceBrowserBoardDashboardAndProjectSubtasksSurviveARestartAndARescan`, the R-16 walk of
// ADR-0021: a board that carries two notes, a project task with two sub-tasks on different due
// dates, the board assigned to the project task, the "Progetti" grouping, then a relaunch and a full
// index rebuild.
//
// The walk is driven on `VaultSession`, with no window: the same calls the composer and the picker
// make (`captureTask`, `TaskDraft.subtask(of:)`, `apply(.workspace(_:), to:)`), read back through the
// same queries the tray and the task pane read (`WorkspaceReferences.notes(in:)`,
// `tasks(assignedToWorkspace:)`, `subtasks`/`progress(ofProject:)` behind `TaskArrangement`'s
// `.subtasks` grouping). A relaunch is a second `VaultSession` over the same vault and state
// directory; "Rigenera indice" is `rescan()`, and a cleared cache is `clearCache()`.
//
// Wiring lost, with no in-process cover (R-08, R-13): that the Workspace pane and the board's tray
// draw those numbers (`board-assigned-tasks-header`, `board-referenced-note-*`, the `task-project-
// group` progress label), that the composer sheet, the "Aggiungi sotto-task" menu item and the
// "Collega una board…" picker reach `captureTask`/`apply`, that `TasksView` re-mounts on "Tutti", and
// that the app itself quits and relaunches. Integration :153 stays a GUI test (the path menu and
// `.onChange(of: vault.pendingWorkspacePlacement)`); :166 is converted in `WorkspaceEnterFolderTests`.
//
// A characterisation test: it passes on the code as it stands and has no red of its own. It asserts
// the empty state before each write, so an assertion that would hold on a vault where nothing was
// done fails.

private enum Walk {
    static let boardFile = "Vibrofer/Vibrofer.canvas"
    static let boardName = "Vibrofer.canvas"
    static let noteA = "Vibrofer/DocumentoBrief.md"
    static let noteB = "Vibrofer/DocumentoContratto.md"
    static let parent = "Progetto EMEA rilancio sito"
    static let childOne = "Bozza contratto fornitore"
    static let childTwo = "Firma contratto fornitore"

    /// The board the GUI walk writes: the two notes as `.file` cards, which is the shape
    /// `WorkspaceReferences.notes(in:)` reads (ADR-0021 D8).
    static let canvas = """
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

    static func note(titled title: String) -> String {
        "---\ndate: 2026-08-24\ntags:\n  - type-nota\n---\n\n# \(title)\n"
    }
}

@MainActor
private func openSession(root: URL, stateBase: URL) async -> VaultSession {
    let session = VaultSession(
        root: root,
        stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

/// The record is the file (SPEC §3): the walk stored nothing but the caret markers of ADR-0021 in the
/// note it captured into - `^id(N)` and `^[[board.canvas]]` on the parent, `^parent(N)` on each child.
private func expectTheCaretMarkersOnDisk(in root: URL) throws {
    let capture = try String(
        contentsOf: root.appending(path: VaultSession.TaskDestination.inboxPath), encoding: .utf8
    )
    let lines = capture.split(separator: "\n").map(String.init)
    let parentLine = try #require(lines.first { $0.contains(Walk.parent) })
    #expect(parentLine.contains("^id(1)") && parentLine.contains("^[[\(Walk.boardName)]]"), "\(parentLine)")
    for child in [Walk.childOne, Walk.childTwo] {
        let line = try #require(lines.first { $0.contains(child) })
        #expect(line.contains("^parent(1)"), "\(line)")
    }
}

/// What the walk leaves, asked the way the app asks it. Called after every stage that has to agree.
@MainActor
private func expectTheWalkedState(in session: VaultSession, today: CalendarDate, stage: String) {
    let index = session.index

    // The board's tray: "Task assegnati a questa board: 1", the parent's own row (R-05).
    let assigned = index.tasks(assignedToWorkspace: Walk.boardName)
    #expect(assigned.map(\.text) == [Walk.parent], "\(stage): task assegnati alla board")

    // "Progetti" over "Tutti", the way `TasksView` applies it: the view's own sorting, the grouping
    // switched to `.subtasks`.
    var options = IndexSnapshot.TaskView.all.defaultListOptions
    options.grouping = .subtasks
    let groups = TaskArrangement.groups(index.tasks(for: .all, on: today), options: options)
    let projects = groups.filter { group in
        if case .project = group.kind { return true }
        return false
    }
    #expect(projects.count == 1, "\(stage): gruppi Progetti")
    guard let group = projects.first, case .project(let head, let progress) = group.kind else { return }
    #expect(head.text == Walk.parent, "\(stage): testata del gruppo")
    // The progress label the GUI read as «0 di 2 completati».
    #expect(progress == TaskProgress(done: 0, total: 2), "\(stage): avanzamento")
    #expect(Set(group.tasks.map(\.text)) == [Walk.childOne, Walk.childTwo], "\(stage): sotto-task del gruppo")
    #expect(group.tasks.first { $0.text == Walk.childOne }?.due == today.adding(days: 3), "\(stage): scadenza uno")
    #expect(group.tasks.first { $0.text == Walk.childTwo }?.due == today.adding(days: 10), "\(stage): scadenza due")
    #expect(index.progress(ofProject: head) == progress, "\(stage): avanzamento dall'indice")
}

@MainActor
@Test func aBoardsNotesAProjectWithTwoSubtasksAndItsAssignedBoardSurviveARelaunchAndAFullRebuild() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let stateBase = vault.stateBase
    try vault.write(Walk.canvas, to: Walk.boardFile)
    try vault.write(Walk.note(titled: "DocumentoBrief"), to: Walk.noteA)
    try vault.write(Walk.note(titled: "DocumentoContratto"), to: Walk.noteB)
    let today = CalendarDate.today
    let session = await openSession(root: root, stateBase: stateBase)

    // 1. The board's dashboard. The referenced notes come from the board's own document (R-06),
    // true before a single task exists; nothing is assigned yet (R-05).
    let document = try CanvasStore(root: root).load(board: Walk.boardFile)
    #expect(WorkspaceReferences.notes(in: document) == [Walk.noteA, Walk.noteB])
    #expect(session.index.tasks(assignedToWorkspace: Walk.boardName).isEmpty)

    // 2. A project task with two sub-tasks on different due dates.
    let captured = await session.captureTask(VaultSession.TaskDraft(text: Walk.parent))
    #expect(captured != nil, "il task principale non è stato scritto: \(session.problems)")
    var parent = try #require(session.index.allTasks.first { $0.text == Walk.parent })
    #expect(parent.localID == nil)

    var first = VaultSession.TaskDraft.subtask(of: parent)
    first.text = Walk.childOne
    first.due = today.adding(days: 3)
    let firstWritten = await session.captureTask(first)
    #expect(firstWritten != nil, "il primo sotto-task non è stato scritto: \(session.problems)")

    // The parent's own line gained `^id(N)` the moment its first sub-task landed (ADR-0021 D9), so
    // the snapshot taken above is stale: reading it back is what re-selecting the row did in the
    // GUI walk. `TaskComposerTests` pins the refusal a stale one gets.
    parent = try #require(session.index.allTasks.first { $0.text == Walk.parent })
    #expect(parent.localID == 1)

    var second = VaultSession.TaskDraft.subtask(of: parent)
    second.text = Walk.childTwo
    second.due = today.adding(days: 10)
    let secondWritten = await session.captureTask(second)
    #expect(secondWritten != nil, "il secondo sotto-task non è stato scritto: \(session.problems)")

    // 3. Assign the board to the project task, by the file name the picker writes.
    parent = try #require(session.index.allTasks.first { $0.text == Walk.parent })
    let assignment = await session.apply(.workspace(WorkspaceBoardResolver.fileName(of: Walk.boardFile)), to: parent)
    guard case .written = assignment else {
        Issue.record("l'assegnazione della board non è stata scritta: \(session.problems)")
        return
    }

    // 4. "Progetti" and the tray, from the in-memory index the writes just updated: no rescan yet.
    expectTheWalkedState(in: session, today: today, stage: "prima del riavvio")

    try expectTheCaretMarkersOnDisk(in: root)

    // 5. Quit, relaunch, force a full index rebuild: everything survives. A relaunch is a new session
    // over the same vault and the same state directory, so it reads whatever the first left behind.
    let relaunched = await openSession(root: root, stateBase: stateBase)
    expectTheWalkedState(in: relaunched, today: today, stage: "dopo il riavvio")
    #expect(WorkspaceReferences.notes(in: try CanvasStore(root: root).load(board: Walk.boardFile))
        == [Walk.noteA, Walk.noteB])

    // "Rigenera indice" is `rescan()`. The first scan of the relaunch saved the cache, so this one
    // reads the caret markers back out of it.
    await relaunched.rescan()
    #expect(relaunched.index.reusedFromCache > 0, "la seconda scansione non ha usato la cache")
    expectTheWalkedState(in: relaunched, today: today, stage: "dopo Rigenera indice")

    // And with the cache emptied, from the files alone.
    await relaunched.clearCache()
    #expect(relaunched.index.reusedFromCache == 0, "clearCache ha lasciato righe dalla cache")
    expectTheWalkedState(in: relaunched, today: today, stage: "dopo aver svuotato la cache")
}
