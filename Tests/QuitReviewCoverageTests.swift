import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D4, plan Task 1: what an answer covers - a conflicted board or diary day in
// the snapshot the question showed against the one there now. Pure, like
// `QuitReviewConflictTests.swift`, from which it was split; `tab`, `boardItem` and `diaryItem`
// live in `QuitTestSupport.swift`.

private func column(_ tabs: [NoteTab]) -> EditorColumn {
    var column = EditorColumn()
    column.tabs = tabs
    column.activeID = tabs.first?.id
    return column
}

private func node(_ id: String, _ text: String) -> CanvasNode {
    CanvasNode(id: id, kind: .text(text), x: 0, y: 0, width: 100, height: 60)
}

// MARK: R-08: what an answer covers

@Test func theSameBoardInTheSnapshotAndNowIsCovered() {
    let snapshot = QuitReview(columns: [], board: boardItem())
    let now = QuitReview(columns: [], board: boardItem())

    #expect(snapshot.uncoveredWork(in: now).board == nil)
    #expect(snapshot.uncoveredWork(in: now).isEmpty)
}

@Test func aBoardAbsentFromTheSnapshotAndPresentNowIsUncovered() {
    let snapshot = QuitReview(columns: [column([tab("A.md")])])
    let now = QuitReview(columns: [column([tab("A.md")])], board: boardItem())

    #expect(snapshot.uncoveredWork(in: now).board == boardItem())
    #expect(!snapshot.uncoveredWork(in: now).isEmpty)
}

@Test func aBoardWhoseDocumentDiffersIsUncovered() {
    let snapshot = QuitReview(columns: [], board: boardItem())
    let changed = boardItem(nodes: [node("a", "uno"), node("b", "due")])
    let now = QuitReview(columns: [], board: changed)

    #expect(snapshot.uncoveredWork(in: now).board == changed)
}

@Test func aBoardWhosePathDiffersIsUncovered() {
    let snapshot = QuitReview(columns: [], board: boardItem())
    let other = boardItem(path: "Altra.canvas")

    #expect(snapshot.uncoveredWork(in: QuitReview(columns: [], board: other)).board == other)
}

@Test func aBoardInTheSnapshotAndGoneNowYieldsNothing() {
    let snapshot = QuitReview(columns: [], board: boardItem())
    let now = QuitReview(columns: [])

    #expect(snapshot.uncoveredWork(in: now).board == nil)
    #expect(snapshot.uncoveredWork(in: now).isEmpty)
}

@Test func theSameDiaryDayIsCovered() {
    let entry = DiaryEntry(startMinutes: 540, durationMinutes: 60, title: "Sopralluogo")
    let snapshot = QuitReview(columns: [], diary: diaryItem(entries: [entry]))
    let now = QuitReview(columns: [], diary: diaryItem(entries: [entry]))

    #expect(snapshot.uncoveredWork(in: now).diary == nil)
}

@Test func aDiaryWhoseProseChangedIsUncovered() {
    let snapshot = QuitReview(columns: [], diary: diaryItem())
    let changed = diaryItem(prose: "Frase mia.\nAltro.")

    #expect(snapshot.uncoveredWork(in: QuitReview(columns: [], diary: changed)).diary == changed)
}

@Test func aDiaryWhoseEntriesChangedIsUncovered() {
    let entry = DiaryEntry(startMinutes: 540, durationMinutes: 60, title: "Sopralluogo")
    let snapshot = QuitReview(columns: [], diary: diaryItem(entries: [entry]))
    let changed = diaryItem(entries: [entry, DiaryEntry(startMinutes: 600, durationMinutes: 30, title: "Altro")])

    #expect(snapshot.uncoveredWork(in: QuitReview(columns: [], diary: changed)).diary == changed)
}

@Test func aDiaryWhoseDayChangedIsUncovered() throws {
    let snapshot = QuitReview(columns: [], diary: diaryItem())
    let other = try #require(CalendarDate(iso: "2026-08-12"))
    let changed = diaryItem(day: other)

    #expect(snapshot.uncoveredWork(in: QuitReview(columns: [], diary: changed)).diary == changed)
}

@Test func aDiaryAbsentFromTheSnapshotAndPresentNowIsUncovered() {
    let snapshot = QuitReview(columns: [])
    let now = QuitReview(columns: [], diary: diaryItem())

    #expect(snapshot.uncoveredWork(in: now).diary == diaryItem())
}

@Test func aDiaryInTheSnapshotAndGoneNowYieldsNothing() {
    let snapshot = QuitReview(columns: [], diary: diaryItem())

    #expect(snapshot.uncoveredWork(in: QuitReview(columns: [])).diary == nil)
}

@Test func uncoveredNotesAreExactlyWhatUncoveredInReturns() {
    let snapshot = QuitReview(columns: [column([tab("A.md", text: "uno")])])
    let now = QuitReview(columns: [column([tab("A.md", text: "due"), tab("B.md")])])

    #expect(!snapshot.uncovered(in: now).isEmpty)
    #expect(snapshot.uncoveredWork(in: now).notes == snapshot.uncovered(in: now))
}
