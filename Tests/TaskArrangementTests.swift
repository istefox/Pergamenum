import Foundation
import Testing
@testable import Pergamenum

// The controls of the task views (ADR-0013 §D6). The menu itself is a screenshot; what is
// checked here is everything under it that can be wrong without looking wrong: a sort that is
// not stable, a group that swallows the tasks with nothing to group by, a stored preference
// that does not survive the round trip.

private func task(
    _ line: String, in path: String = "01 Progetti/Presse idrauliche.md", at index: Int = 0
) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: path, lineIndex: index)!
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
