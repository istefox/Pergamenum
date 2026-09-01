import Foundation
import Testing
@testable import Pergamenum

// The controls of the task views (ADR-0013 §D6). The menu itself is a screenshot; what is
// checked here is everything under it that can be wrong without looking wrong: a sort that is
// not stable, a group that swallows the tasks with nothing to group by, a stored preference
// that does not survive the round trip.
//
// Extended for ADR-0021 ("A task carries its Workspace and its place in a project as caret
// markers in its own line, and nothing new is stored anywhere else"), §D6. Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 8: the
// "Progetti" `.subtasks` grouping, and the R-10 regression guard on the five groupings and
// five `TaskView`s that already existed.

private func task(
    _ line: String, in path: String = "01 Progetti/Presse idrauliche.md", at index: Int = 0
) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: path, lineIndex: index)!
}

/// The parent task of a "Progetti" group, `nil` for a plain one - reading through
/// `TaskGroup.Kind` the same way production code does, rather than a shortcut this
/// file alone would rely on.
private func projectParent(of group: TaskGroup) -> TaskItem? {
    if case .project(let parent, _) = group.kind { return parent }
    return nil
}

@Test func groupingByNoteUsesTheNoteTitleAndSortsAlphabetically() {
    let tasks = [
        task("- [ ] Disegno", in: "01 Progetti/Presse idrauliche.md", at: 0),
        task("- [ ] Capitolato", in: "02 Clienti/Vibrofer.md", at: 1),
        task("- [ ] Offerta", in: "02 Clienti/Vibrofer.md", at: 2),
    ]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .note, sorting: .text)
    )

    #expect(groups.map(\.title) == ["Presse idrauliche", "Vibrofer"])
    #expect(groups[1].tasks.map(\.text) == ["Capitolato", "Offerta"])
}

@Test func starredNotesFloatToTheTopWithoutDisturbingTheRest() {
    let tasks = [
        task("- [ ] Alfa", in: "A.md", at: 0),
        task("- [ ] Beta", in: "B.md", at: 1),
        task("- [ ] Zeta", in: "Z.md", at: 2),
    ]

    let groups = TaskArrangement.groups(
        tasks,
        options: TaskListOptions(grouping: .note, sorting: .text),
        priorityPaths: ["Z.md"]
    )

    // Z first because it is starred; A and B keep the alphabetical order they had.
    #expect(groups.map(\.title) == ["Z", "A", "B"])
}

@Test func theTasksWithNothingToGroupByGoLast() {
    let tasks = [
        task("- [ ] Senza progetto", at: 0),
        task("- [ ] Con progetto #project-presse", at: 1),
    ]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .project, sorting: .text)
    )

    #expect(groups.map(\.title) == ["project-presse", TaskArrangement.noneTitle])
}

@Test func groupingByDayNamesTheWeekdayAndTheDate() {
    let tasks = [task("- [ ] Sopralluogo >2026-08-17", at: 0)]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .schedule, sorting: .schedule)
    )

    // 17 August 2026 is a Monday, and the heading says so in the form the day view uses.
    #expect(groups.map(\.title) == ["lunedì 17/08/2026"])
}

@Test func sortingBySchedulePutsTheHourInsideTheDayAndTheUndatedLast() {
    let tasks = [
        task("- [ ] Terzo", at: 0),
        task("- [ ] Secondo >2026-08-17 15:00", at: 1),
        task("- [ ] Primo >2026-08-17 09:00", at: 2),
        task("- [ ] Quarto >2026-08-18", at: 3),
    ]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .none, sorting: .schedule)
    )

    #expect(groups.count == 1)
    #expect(groups[0].title.isEmpty)
    #expect(groups[0].tasks.map(\.text) == ["Primo", "Secondo", "Quarto", "Terzo"])
}

@Test func sortingByDeadlinePutsWhatHasNoDeadlineLast() {
    let tasks = [
        task("- [ ] Nessuna", at: 0),
        task("- [ ] Tardi !2026-09-10", at: 1),
        task("- [ ] Presto !2026-08-20", at: 2),
    ]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .none, sorting: .deadline)
    )

    #expect(groups[0].tasks.map(\.text) == ["Presto", "Tardi", "Nessuna"])
}

@Test func theSortIsStableWhenTwoTasksShareTheirKey() {
    // Same day, same hour, same text: without the tie-break on the id these two could swap
    // between two redraws of a list nothing had changed.
    let tasks = (0..<6).map { task("- [ ] Uguale >2026-08-17", at: $0) }
    let options = TaskListOptions(grouping: .none, sorting: .schedule)

    let first = TaskArrangement.groups(tasks, options: options)[0].tasks.map(\.id)
    let second = TaskArrangement.groups(tasks.reversed(), options: options)[0].tasks.map(\.id)

    #expect(first == second)
}

// MARK: - "Progetti", the `.subtasks` grouping (ADR-0021 D6, R-08, R-10). Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 8.
//
// `TaskArrangement.groups`'s `.subtasks` arm is a signature-only placeholder as of this
// commit (`Sources/Core/Tasks/TaskListOptions.swift`): every test below naming `.subtasks`
// is expected to fail red on its assertions, not to fail to compile - the coder's Task 8
// work fills in the bucketing on `(sourcePath, parentLocalID)` these tests already encode
// as assertions. The two tests further down that exercise `.none`/`.note`/`.project`/
// `.schedule`/`.deadline` and the five `TaskView`s are regression guards (R-10) and are
// expected to already be green: adding a case to an exhaustive switch does not touch the
// arms that were already there.

@Test func subtasksGroupsOneParentPerGroupWithChildrenIndentedAndProgress() {
    let parent = task("- [ ] Ristrutturazione ^id(1)", at: 0)
    let doneChild = task("- [x] Preventivo ^parent(1)", at: 1)
    let openChild = task("- [ ] Sopralluogo ^parent(1)", at: 2)

    let groups = TaskArrangement.groups(
        [parent, doneChild, openChild],
        options: TaskListOptions(grouping: .subtasks, sorting: .text)
    )

    #expect(groups.count == 1)
    #expect(groups[0].kind == .project(parent: parent, progress: TaskProgress(done: 1, total: 2)))
    #expect(groups[0].tasks.map(\.text) == ["Preventivo", "Sopralluogo"])
}

@Test func subtasksTasksWithNeitherIDNorParentLandInSenzaLast() {
    let parent = task("- [ ] Progetto ^id(1)", at: 0)
    let child = task("- [ ] Fase ^parent(1)", at: 1)
    let lone = task("- [ ] Nota sparsa", at: 2)

    let groups = TaskArrangement.groups(
        [parent, child, lone],
        options: TaskListOptions(grouping: .subtasks, sorting: .text)
    )

    // The project group first, "Senza" trailing - the existing rule of `grouped(_:by:)`
    // that every other grouping already relies on.
    #expect(groups.count == 2)
    #expect(groups.last?.title == TaskArrangement.noneTitle)
    #expect(groups.last?.tasks.map(\.text) == ["Nota sparsa"])
    #expect(groups.last?.kind == .plain)
}

@Test func subtasksIDsAreNoteLocalTwoNotesEachWithIDOneProduceTwoGroups() {
    // The D2 assertion at the arrangement level: `^id(1)` in `A.md` and `^id(1)` in `B.md`
    // are two different tasks, so a global-id mistake here would silently merge two
    // unrelated projects the moment two notes both reached one sub-task.
    let parentA = task("- [ ] Progetto A ^id(1)", in: "A.md", at: 0)
    let childA = task("- [ ] Fase A ^parent(1)", in: "A.md", at: 1)
    let parentB = task("- [ ] Progetto B ^id(1)", in: "B.md", at: 0)
    let childB = task("- [ ] Fase B ^parent(1)", in: "B.md", at: 1)

    let groups = TaskArrangement.groups(
        [parentA, childA, parentB, childB],
        options: TaskListOptions(grouping: .subtasks, sorting: .text)
    )

    #expect(groups.count == 2)
    #expect(Set(groups.map(\.id)) == Set([parentA.id, parentB.id]))
    #expect(groups.first { projectParent(of: $0)?.sourcePath == "A.md" }?.tasks.map(\.text) == ["Fase A"])
    #expect(groups.first { projectParent(of: $0)?.sourcePath == "B.md" }?.tasks.map(\.text) == ["Fase B"])
}

@Test func subtasksOrphanedParentStillAppearsInSenzaRatherThanVanishing() {
    // SPEC edge case: "the sub-task still appears ungrouped in the flat Attività views."
    // No task in this note carries `^id(9)`, so `^parent(9)` names nothing. A real project
    // (`^id(1)` with one child) sits alongside it, so a bucketing bug that dumped
    // everything into one heading - the same failure a single-task fixture could not have
    // caught - would show up as a wrong `groups.count` or a child under the wrong parent.
    let parent = task("- [ ] Progetto ^id(1)", at: 0)
    let child = task("- [ ] Fase ^parent(1)", at: 1)
    let orphan = task("- [ ] Fase senza padre ^parent(9)", at: 2)

    let groups = TaskArrangement.groups(
        [parent, child, orphan], options: TaskListOptions(grouping: .subtasks, sorting: .text)
    )

    #expect(groups.count == 2)
    let senza = groups.first { $0.title == TaskArrangement.noneTitle }
    #expect(senza?.tasks.map(\.text) == ["Fase senza padre"])
    #expect(senza?.kind == .plain)
    let project = groups.first { projectParent(of: $0) != nil }
    #expect(project.flatMap(projectParent) == parent)
    #expect(project?.tasks.map(\.text) == ["Fase"])
}

@Test func subtasksOrderingIsStableWhenTheChildrenTieOnTheirSortKey() {
    // The same shape as `theSortIsStableWhenTwoTasksShareTheirKey` above, for the new
    // grouping: without the tie-break on the id, six same-text children could reorder
    // between two redraws of the same list.
    let parent = task("- [ ] Progetto ^id(1)", at: 0)
    let children = (0..<6).map { task("- [ ] Uguale ^parent(1)", at: $0 + 1) }
    let options = TaskListOptions(grouping: .subtasks, sorting: .text)

    let first = TaskArrangement.groups([parent] + children, options: options)[0]
        .tasks.map(\.id)
    let second = TaskArrangement.groups([parent] + children.reversed(), options: options)[0]
        .tasks.map(\.id)

    #expect(first == second)
}

@Test func theFiveExistingGroupingsAreUnaffectedByTheSubtasksAddition() {
    // R-10: adding `.subtasks` must not perturb `.none`, `.note`, `.project`, `.schedule`
    // or `.deadline` - the `TaskArrangement.groups` switch grew a case, it was not
    // rewritten. Tasks below carry ADR-0021 markers on purpose, so a `.subtasks`-only bug
    // that leaked into the sort key or the heading of another grouping would show here.
    let tasks = [
        task("- [ ] Disegno ^id(1)", in: "01 Progetti/Presse idrauliche.md", at: 0),
        task(
            "- [ ] Capitolato ^parent(1) #project-presse >2026-08-17 !2026-08-20",
            in: "02 Clienti/Vibrofer.md", at: 1
        ),
        task("- [ ] Offerta ^[[vibrofer-emea.canvas]]", in: "02 Clienti/Vibrofer.md", at: 2),
    ]

    #expect(
        TaskArrangement.groups(tasks, options: TaskListOptions(grouping: .none, sorting: .text))
            .flatMap(\.tasks).map(\.text) == ["Capitolato", "Disegno", "Offerta"]
    )
    #expect(
        TaskArrangement.groups(tasks, options: TaskListOptions(grouping: .note, sorting: .text))
            .map(\.title) == ["Presse idrauliche", "Vibrofer"]
    )
    #expect(
        TaskArrangement.groups(tasks, options: TaskListOptions(grouping: .project, sorting: .text))
            .map(\.title) == ["project-presse", TaskArrangement.noneTitle]
    )
    #expect(
        TaskArrangement.groups(
            tasks, options: TaskListOptions(grouping: .schedule, sorting: .schedule)
        ).map(\.title) == ["lunedì 17/08/2026", TaskArrangement.noneTitle]
    )
    #expect(
        TaskArrangement.groups(
            tasks, options: TaskListOptions(grouping: .deadline, sorting: .deadline)
        ).map(\.title) == ["giovedì 20/08/2026", TaskArrangement.noneTitle]
    )
}

/// One note holding the given task lines, indexed - the shape `Tests/RolloverTests.swift`
/// and `Tests/TaskMarkerTests.swift` already use, reused here so the view-filter guard
/// below can call the real `IndexSnapshot.tasks(for:on:)` rather than assume its behaviour.
private func indexed(_ body: String, path: String = "01 Progetti/Pergamenum.md") -> IndexSnapshot {
    let tasks = body.components(separatedBy: "\n").enumerated().compactMap { index, line in
        TaskParser.parse(line: line, sourcePath: path, lineIndex: index)
    }
    var frontmatter = Frontmatter.empty
    frontmatter.tags = [Tag("type-note")!]
    let record = NoteRecord(
        relativePath: path, title: "Pergamenum", frontmatter: frontmatter, linkTargets: [],
        tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
    var snapshot = IndexSnapshot()
    snapshot.update(record, at: path)
    return snapshot
}

@Test func theFiveTaskViewsStillReturnSubtasksAlongsideEverythingElse() {
    // R-10's other half, spelled out rather than assumed: `IndexSnapshot.tasks(for:on:)` is
    // untouched by this task, and a sub-task must satisfy the same five view filters as any
    // other task - the grouping axis (`TaskArrangement`) and the view axis
    // (`IndexSnapshot.TaskView`) stay independent (ADR-0013 §D6). Day and offsets mirror the
    // proven fixture in `Tests/TaskTests.swift`'s `sortsTasksIntoTheFiveViews`.
    let day = CalendarDate(iso: "2026-08-11")!
    let index = indexed("""
        - [ ] Progetto ^id(1)
        - [ ] Senza data ^parent(1)
        - [ ] Oggi >2026-08-11 ^parent(1)
        - [ ] Fra tre giorni >2026-08-14 ^parent(1)
        - [ ] Di progetto #project-pergamenum ^parent(1)
        """)

    #expect(index.tasks(for: .inbox, on: day).map(\.text).contains("Senza data"))
    #expect(index.tasks(for: .today, on: day).map(\.text).contains("Oggi"))
    #expect(index.tasks(for: .upcoming, on: day).map(\.text).contains("Fra tre giorni"))
    #expect(index.tasks(for: .byProject, on: day).map(\.text).contains("Di progetto"))
    #expect(index.tasks(for: .all, on: day).count == 5)
}

@Test func theFiveViewsOpenOnTheirOwnControls() {
    // §D6 exists because these differ: a shared setting would make every switch between Oggi
    // and Tutti a re-setting.
    #expect(IndexSnapshot.TaskView.today.defaultListOptions.grouping == .none)
    #expect(IndexSnapshot.TaskView.today.defaultListOptions.sorting == .schedule)
    #expect(IndexSnapshot.TaskView.all.defaultListOptions.grouping == .note)
    #expect(IndexSnapshot.TaskView.upcoming.defaultListOptions.grouping == .schedule)
    #expect(IndexSnapshot.TaskView.byProject.defaultListOptions.grouping == .project)
    #expect(IndexSnapshot.TaskView.inbox.defaultListOptions.grouping == .none)
    // Every view opens expanded, which is what the list has always drawn.
    #expect(IndexSnapshot.TaskView.allCases.allSatisfy { $0.defaultListOptions.density == .expanded })
}

// MARK: - "Per Workspace", the `.workspace` grouping (R-08, R-09).

@Test func workspaceGroupingUsesTheFullPathWhenTheBoardNameIsUnique() {
    let tasks = [task("- [ ] Offerta ^[[vibrofer-emea.canvas]]", at: 0)]

    let groups = TaskArrangement.groups(
        tasks,
        options: TaskListOptions(grouping: .workspace, sorting: .text),
        boards: ["02 Clienti/Vibrofer/vibrofer-emea.canvas"]
    )

    #expect(groups.map(\.title) == ["02 Clienti/Vibrofer/vibrofer-emea.canvas"])
}

@Test func workspaceGroupingUsesTheBareNameWhenTheBoardNameIsAmbiguous() {
    let first = task("- [ ] Offerta A ^[[board.canvas]]", at: 0)
    let second = task("- [ ] Offerta B ^[[board.canvas]]", at: 1)

    let groups = TaskArrangement.groups(
        [first, second],
        options: TaskListOptions(grouping: .workspace, sorting: .text),
        boards: ["Alfa/board.canvas", "Beta/board.canvas"]
    )

    #expect(groups.count == 1)
    #expect(groups[0].title == "board.canvas")
    #expect(groups[0].tasks.map(\.text) == ["Offerta A", "Offerta B"])
}

@Test func workspaceGroupingUsesTheBareNameWhenTheBoardIsOrphaned() {
    let tasks = [task("- [ ] Offerta ^[[sparita.canvas]]", at: 0)]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .workspace, sorting: .text), boards: []
    )

    #expect(groups.map(\.title) == ["sparita.canvas"])
}

@Test func workspaceGroupingPutsUnassignedTasksUnderNessunWorkspaceRatherThanSenza() {
    let tasks = [
        task("- [ ] Assegnato ^[[vibrofer-emea.canvas]]", at: 0),
        task("- [ ] Non assegnato", at: 1),
    ]

    let groups = TaskArrangement.groups(
        tasks,
        options: TaskListOptions(grouping: .workspace, sorting: .text),
        boards: ["Vibrofer/vibrofer-emea.canvas"]
    )

    #expect(groups.map(\.title) == ["Vibrofer/vibrofer-emea.canvas", TaskArrangement.noWorkspaceTitle])
    #expect(groups.last?.tasks.map(\.text) == ["Non assegnato"])
}

@Test func workspaceGroupingWithNoBoardsAtAllPutsEverythingUnderNessunWorkspace() {
    let tasks = [task("- [ ] Primo", at: 0), task("- [ ] Secondo", at: 1)]

    let groups = TaskArrangement.groups(
        tasks, options: TaskListOptions(grouping: .workspace, sorting: .text), boards: []
    )

    #expect(groups.count == 1)
    #expect(groups[0].title == TaskArrangement.noWorkspaceTitle)
    #expect(groups[0].tasks.map(\.text) == ["Primo", "Secondo"])
}

@Test func theStoredControlsSurviveTheRoundTrip() {
    let map = [
        IndexSnapshot.TaskView.all.rawValue:
            TaskListOptions(grouping: .note, sorting: .text, density: .compact),
        IndexSnapshot.TaskView.today.rawValue:
            TaskListOptions(grouping: .none, sorting: .schedule),
    ]

    let restored = TaskListOptions.map(fromJSON: TaskListOptions.json(of: map))

    #expect(restored == map)
}

@Test func aStoredControlWrittenByAnOlderVersionKeepsWhatItHas() {
    // One key missing, the other two set: the decoder falls back per key rather than throwing
    // the whole entry away, which is the contract `VaultSettings` keeps for the same reason.
    let json = #"{"all":{"grouping":"project","sorting":"deadline"}}"#

    let restored = TaskListOptions.map(fromJSON: json)

    #expect(restored["all"]?.grouping == .project)
    #expect(restored["all"]?.sorting == .deadline)
    #expect(restored["all"]?.density == .expanded)
}

@Test func rubbishInTheStoredControlsReadsAsEmptyRatherThanCrashing() {
    #expect(TaskListOptions.map(fromJSON: "").isEmpty)
    #expect(TaskListOptions.map(fromJSON: "non è json").isEmpty)
}
