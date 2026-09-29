import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D6, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-01, R-02.
//
// `allTasks` is today's formula computed on every read: notes then boards, each in path order.
// These pins hold it to that formula after a whole replacement and after every kind of
// single-file update, so storing the list (Task 2) cannot change its content or its order; and
// they hold every sidebar badge to the length of its own list, so counting in one pass cannot
// drift from the list a view draws.

private func taskNote(_ path: String, _ text: String) -> NoteRecord {
    NoteRecord(
        relativePath: path, title: String(path.split(separator: "/").last?.dropLast(3) ?? ""),
        frontmatter: .empty, linkTargets: [], tasks: TaskParser.tasks(in: text, sourcePath: path),
        modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

private func taskBoard(_ path: String, _ text: String) -> BoardTaskRecord {
    let tasks = TaskParser.tasks(in: text, sourcePath: path).map { task in
        var task = task
        task.nodeID = "0000000000000001"
        return task
    }
    return BoardTaskRecord(relativePath: path, tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-")
}

/// The formula `allTasks` answers with today, read from the snapshot's own stores.
private func referenceTasks(_ index: IndexSnapshot) -> [TaskItem] {
    index.notes.values.sorted { $0.relativePath < $1.relativePath }.flatMap(\.tasks)
        + index.boardTasks.values.sorted { $0.relativePath < $1.relativePath }.flatMap(\.tasks)
}

private let pinNotes = [
    taskNote("M/Beta.md", "- [ ] Chiamare >2026-09-05\n- [x] Preventivo !2026-09-03"),
    taskNote("C/Gamma.md", "Nessun task qui."),
    taskNote("P/Presse.md", "- [ ] Disegno #project-presse !2026-09-12\n- [ ] Ordine >2026-09-01"),
    taskNote("D/Delta.md", "- [ ] Senza data\n- [ ] Scaduto !2026-08-30\n- [ ] Presto >2026-09-09 !2026-09-11"),
]

private let pinBoards = [
    taskBoard("Z/Lavagna.canvas", "- [ ] Sulla lavagna >2026-09-06\n- [ ] Da fare"),
    taskBoard("A/Prima.canvas", "- [ ] Primo sulla board #project-presse"),
]

private func pinSnapshot() -> IndexSnapshot {
    var index = IndexSnapshot()
    index.replaceAll(with: .init(records: pinNotes, failures: [], boardTaskRecords: pinBoards), duration: .zero)
    return index
}

@Test func theTaskListFollowsTheFormulaThroughEveryKindOfUpdate() {
    var index = pinSnapshot()
    #expect(index.allTasks == referenceTasks(index))
    #expect(!index.allTasks.isEmpty)

    // A note's first task.
    index.update(taskNote("C/Gamma.md", "- [ ] Nuovo >2026-09-04"), at: "C/Gamma.md")
    #expect(index.allTasks == referenceTasks(index))
    #expect(index.allTasks.contains { $0.text.contains("Nuovo") })

    // A note's last task goes.
    index.update(taskNote("M/Beta.md", "Nessun task."), at: "M/Beta.md")
    #expect(index.allTasks == referenceTasks(index))
    #expect(!index.allTasks.contains { $0.sourcePath == "M/Beta.md" })

    // A note goes.
    index.update(nil, at: "D/Delta.md")
    #expect(index.allTasks == referenceTasks(index))
    #expect(!index.allTasks.contains { $0.sourcePath == "D/Delta.md" })

    // A note whose path sorts first, then one whose path sorts last.
    index.update(taskNote("0/Primo.md", "- [ ] In testa"), at: "0/Primo.md")
    #expect(index.allTasks == referenceTasks(index))
    #expect(index.allTasks.first?.sourcePath == "0/Primo.md")
    index.update(taskNote("zz/Ultimo.md", "- [ ] In coda"), at: "zz/Ultimo.md")
    #expect(index.allTasks == referenceTasks(index))
    // Boards still come after every note.
    #expect(index.allTasks.last?.sourcePath == "Z/Lavagna.canvas")

    // A whole replacement again.
    index.replaceAll(with: .init(records: pinNotes, failures: [], boardTaskRecords: pinBoards), duration: .zero)
    #expect(index.allTasks == referenceTasks(index))
}

private let pinDays: [CalendarDate] = (1...16).compactMap { day in
    CalendarDate(iso: String(format: "2026-08-%02d", day + 15))
} + (1...14).compactMap { day in
    CalendarDate(iso: String(format: "2026-09-%02d", day))
}

@Test(arguments: [0, 7])
func everyBadgeEqualsTheLengthOfItsList(rolloverDays: Int) {
    var index = pinSnapshot()
    index.update(taskNote("C/Gamma.md", "- [ ] Nuovo >2026-09-04\n- [x] Fatto oggi"), at: "C/Gamma.md")
    for day in pinDays {
        let counts = index.taskCounts(on: day, rolloverDays: rolloverDays)
        #expect(counts.count == IndexSnapshot.TaskView.allCases.count)
        for view in IndexSnapshot.TaskView.allCases {
            let rolled = view == .today ? index.rolledOverTasks(on: day, daysBack: rolloverDays).count : 0
            #expect(counts[view] == index.tasks(for: view, on: day).count + rolled, "\(view) on \(day)")
        }
    }
}
