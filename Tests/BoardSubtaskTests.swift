import Foundation
import Testing
@testable import Pergamenum

// PG-260 (Audit Fable chain 7), R-15: a project parent living on a board reads its
// sub-tasks from that board, scoped by source path exactly as a note parent reads them
// from its note. Before, `IndexSnapshot.subtasks(of:)` looked only in `notes` and a board
// parent had no children at all.

private let board = "01 Progetti/Lavagna.canvas"
private let secondBoard = "01 Progetti/Seconda.canvas"

/// The tasks of one card, stamped with its node id the way the board scanner does.
private func card(_ text: String, on path: String, node: String) -> [TaskItem] {
    TaskParser.tasks(in: text, sourcePath: path).map { task in
        var task = task
        task.nodeID = node
        return task
    }
}

private func boardRecord(_ path: String, _ tasks: [TaskItem]) -> BoardTaskRecord {
    BoardTaskRecord(relativePath: path, tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-")
}

private func noteRecord(_ path: String, _ text: String) -> NoteRecord {
    NoteRecord(
        relativePath: path, title: String(path.dropLast(3)), frontmatter: .empty, linkTargets: [],
        tasks: TaskParser.tasks(in: text, sourcePath: path), modifiedAt: .distantPast,
        byteSize: 0, contentHash: "-"
    )
}

private func snapshot(notes: [NoteRecord], boards: [BoardTaskRecord]) -> IndexSnapshot {
    var index = IndexSnapshot()
    index.replaceAll(with: .init(records: notes, failures: [], boardTaskRecords: boards), duration: .zero)
    return index
}

/// A parent on `Lavagna.canvas` with two children on two of its cards, one of them done,
/// and three distractors carrying the same `^parent(1)` in a note and in a second board.
private func projectOnABoard() -> IndexSnapshot {
    snapshot(
        notes: [noteRecord("Altro.md", "- [ ] Un altro padre ^id(1)\n- [ ] Non è figlio della lavagna ^parent(1)")],
        boards: [
            boardRecord(
                board,
                card("- [ ] Padre sulla lavagna ^id(1)\n- [ ] Figlio uno ^parent(1)", on: board, node: "aaaa")
                    + card("- [x] Figlio due ^parent(1) @done(2026-08-20)", on: board, node: "bbbb")
            ),
            boardRecord(
                secondBoard,
                card("- [ ] Figlio di un'altra lavagna ^parent(1)", on: secondBoard, node: "cccc")
            ),
        ]
    )
}

private func boardParent(in index: IndexSnapshot) throws -> TaskItem {
    try #require(index.allTasks.first { $0.sourcePath == board && $0.localID == 1 })
}

@Test func aBoardParentListsItsChildrenFromItsBoard() throws {
    let index = projectOnABoard()
    let children = index.subtasks(of: try boardParent(in: index))

    #expect(children.map(\.text) == ["Figlio uno", "Figlio due"])
    #expect(children.allSatisfy { $0.sourcePath == board })
    #expect(Set(children.compactMap(\.nodeID)) == ["aaaa", "bbbb"])
}

@Test func aBoardParentsProgressCountsItsChildren() throws {
    let index = projectOnABoard()
    #expect(index.progress(ofProject: try boardParent(in: index)) == TaskProgress(done: 1, total: 2))
}

@Test func aBoardParentWithNoChildrenHasNone() throws {
    let index = snapshot(notes: [], boards: [boardRecord(board, card("- [ ] Da solo ^id(1)", on: board, node: "aaaa"))])
    let parent = try boardParent(in: index)

    #expect(index.subtasks(of: parent) == [])
    #expect(index.progress(ofProject: parent) == nil)
}

@Test func aParentWhoseBoardIsNotIndexedHasNone() throws {
    let index = projectOnABoard()
    // A parent handed in from a board the index never saw: no guess from another file.
    let stray = try #require(card("- [ ] Padre altrove ^id(1)", on: "Assente.canvas", node: "dddd").first)

    #expect(index.subtasks(of: stray) == [])
    #expect(index.progress(ofProject: stray) == nil)
}

@Test func theIndexAndTheProgettiGroupingAgreeOnABoardParent() throws {
    // The two restated rules (ADR-0021 D6) must not drift: the «Progetti» grouping rebuilds
    // the join from a flat list, the index answers it from its records.
    let index = projectOnABoard()
    let parent = try boardParent(in: index)
    let groups = TaskArrangement.groups(
        index.allTasks, options: TaskListOptions(grouping: .subtasks, sorting: .schedule)
    )
    let group = try #require(groups.first { group in
        if case .project(let groupParent, _) = group.kind { return groupParent.id == parent.id }
        return false
    })
    guard case .project(_, let progress) = group.kind else { return }

    #expect(Set(group.tasks.map(\.id)) == Set(index.subtasks(of: parent).map(\.id)))
    #expect(index.progress(ofProject: parent) == progress)
}
