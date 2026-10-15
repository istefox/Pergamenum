import AppKit
import Testing
@testable import Pergamenum

/// ADR-0029 §D7/§D8 (plan `2026-09-02-editor-wysiwyg-unification`, Task 5): a `TableGridView`
/// cell's edit, applied to the `GFMTable` it was reading from, and committed back to the
/// note's own source text as one atomic write.
///
/// `TableEdit.applied(to:)` is stubbed to the identity function and
/// `NoteTextView.Coordinator.commitTable(_:at:in:)` is stubbed to always refuse (Task 5,
/// tester) - every test that needs the coder's real behaviour is red until both land; the
/// two reload-guard tests and the two shape-refusal tests already pass, because "refuse" or
/// "leave unchanged" is the correct answer for all four with the stub already in place, the
/// same shape `Tests/GFMTableTests.swift`'s own header comment describes for Task 3.

/// `| a | b |` / `|---|---|` / `| 1 | 2 |` / `| 3 | 4 |` - two columns, two body rows,
/// every positive test below starts from the same shape so a failure is easy to compare
/// against its neighbour.
private func fixtureTable() -> GFMTable? {
    GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |", "| 3 | 4 |"][...])
}

@Suite struct TableEditApplication {
    @Test func editingABodyCellAndTheHeaderCellOverwritesOnlyThatOneCell() {
        guard let table = fixtureTable() else {
            Issue.record("fixture non parsata")
            return
        }

        let bodyEdited = TableEdit.cell(row: 0, column: 1, text: "9").applied(to: table)
        #expect(bodyEdited.header == ["a", "b"])
        #expect(bodyEdited.rows == [["1", "9"], ["3", "4"]])

        let headerEdited = TableEdit.cell(row: nil, column: 0, text: "x").applied(to: table)
        #expect(headerEdited.header == ["x", "b"])
        #expect(headerEdited.rows == [["1", "2"], ["3", "4"]])
    }

    @Test func addingARowInsertsAnEmptyOneAtTheRequestedPosition() {
        guard let table = fixtureTable() else {
            Issue.record("fixture non parsata")
            return
        }

        let afterFirst = TableEdit.addRow(after: 0).applied(to: table)
        #expect(afterFirst.rows == [["1", "2"], ["", ""], ["3", "4"]])

        let beforeEvery = TableEdit.addRow(after: nil).applied(to: table)
        #expect(beforeEvery.rows == [["", ""], ["1", "2"], ["3", "4"]])
    }

    @Test func removingARowDropsExactlyThatOne() {
        guard let table = fixtureTable() else {
            Issue.record("fixture non parsata")
            return
        }

        let edited = TableEdit.removeRow(0).applied(to: table)
        #expect(edited.rows == [["3", "4"]])
    }

    @Test func addingAColumnGrowsEveryRowIncludingTheHeaderByOneEmptyCell() {
        guard let table = fixtureTable() else {
            Issue.record("fixture non parsata")
            return
        }

        let edited = TableEdit.addColumn(after: 0).applied(to: table)
        #expect(edited.header == ["a", "", "b"])
        #expect(edited.alignments.count == 3)
        #expect(edited.rows == [["1", "", "2"], ["3", "", "4"]])
    }

    @Test func removingAColumnDropsThatCellFromEveryRowIncludingTheHeader() {
        guard let table = fixtureTable() else {
            Issue.record("fixture non parsata")
            return
        }

        let edited = TableEdit.removeColumn(1).applied(to: table)
        #expect(edited.header == ["a"])
        #expect(edited.alignments == [.leading])
        #expect(edited.rows == [["1"], ["3"]])
    }

    /// A refusal, not a crash: removing the table's last column would leave a grid with
    /// nothing to draw. Already passing with the identity stub - "leave the table
    /// unchanged" is the right answer either way.
    @Test func removingTheLastColumnLeavesTheTableUnchanged() {
        guard let table = GFMTable.parse(["| soltanto |", "|---|", "| 1 |"][...]) else {
            Issue.record("fixture non parsata")
            return
        }

        let edited = TableEdit.removeColumn(0).applied(to: table)
        #expect(edited == table)
    }

    /// Same refusal, for the last body row.
    @Test func removingTheLastBodyRowLeavesTheTableUnchanged() {
        guard let table = GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |"][...]) else {
            Issue.record("fixture non parsata")
            return
        }

        let edited = TableEdit.removeRow(0).applied(to: table)
        #expect(edited == table)
    }
}

// MARK: - Alignment and sort (ADR-0087 §D11, plan N5 Task 1, R-41)

@Suite struct TableColumnEdits {
    @Test func alignChangesOneColumnsAlignmentAndNothingElse() throws { // R-41
        let table = try #require(fixtureTable())
        let edited = TableEdit.align(column: 1, .trailing).applied(to: table)
        #expect(edited.alignments == [.leading, .trailing])
        #expect(edited.header == table.header)
        #expect(edited.rows == table.rows)
    }

    @Test func aRightAlignedColumnSerialisesItsDelimiterRowWithTheTrailingColon() throws { // R-41
        let table = try #require(fixtureTable())
        let edited = TableEdit.align(column: 1, .trailing).applied(to: table)
        let lines = edited.serialised().components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[1] == "|---|--:|")
    }

    @Test func centerWritesTheCenteredDelimiter() throws { // R-41
        let table = try #require(fixtureTable())
        let edited = TableEdit.align(column: 0, .center).applied(to: table)
        #expect(edited.serialised().components(separatedBy: "\n")[1] == "|:-:|---|")
    }

    /// Setting the alignment a column already has is not an edit: the table comes back unchanged,
    /// so `commitTable` refuses it as a no-op and no empty undo step is recorded.
    @Test func aliningAColumnAsItAlreadyIsReturnsTheTableUnchanged() throws { // R-41
        let table = try #require(fixtureTable())
        #expect(TableEdit.align(column: 0, .leading).applied(to: table) == table)
    }

    @Test(arguments: [-1, 2, 7])
    func alignRefusesAColumnOutOfRange(_ column: Int) throws { // R-41
        let table = try #require(fixtureTable())
        #expect(TableEdit.align(column: column, .center).applied(to: table) == table)
    }

    private static func table(_ rows: [[String]]) throws -> GFMTable {
        let lines = ["| k | v |", "|---|---|"] + rows.map { "| \($0[0]) | \($0[1]) |" }
        let parsed = try #require(GFMTable.parse(lines[...]))
        // The fixture must read back as written, or the assertions below are about the parser.
        #expect(parsed.rows == rows)
        return parsed
    }

    @Test func sortOrdersBodyRowsByLocalizedStandardCompareSoTwoComesBeforeTen() throws { // R-41
        let table = try Self.table([["10", "a"], ["2", "b"], ["1", "c"]])
        #expect(TableEdit.sort(column: 0, ascending: true).applied(to: table).rows == [["1", "c"], ["2", "b"], ["10", "a"]])
        #expect(TableEdit.sort(column: 0, ascending: false).applied(to: table).rows == [["10", "a"], ["2", "b"], ["1", "c"]])
    }

    @Test func emptyCellsComeLastInBothDirections() throws { // R-41
        let lines = ["| k | v |", "|---|---|", "| 10 | a |", "|  | b |", "| 2 | c |"]
        let table = try #require(GFMTable.parse(lines[...]))
        #expect(table.rows[1] == ["", "b"], "the fixture's empty cell did not parse as empty")
        #expect(TableEdit.sort(column: 0, ascending: true).applied(to: table).rows.map(\.[0]) == ["2", "10", ""])
        #expect(TableEdit.sort(column: 0, ascending: false).applied(to: table).rows.map(\.[0]) == ["10", "2", ""])
    }

    @Test func theSortIsStableSoEqualKeysKeepTheirOrder() throws { // R-41
        let table = try Self.table([["b", "1"], ["a", "2"], ["b", "3"], ["a", "4"]])
        #expect(
            TableEdit.sort(column: 0, ascending: true).applied(to: table).rows
                == [["a", "2"], ["a", "4"], ["b", "1"], ["b", "3"]]
        )
        #expect(
            TableEdit.sort(column: 0, ascending: false).applied(to: table).rows
                == [["b", "1"], ["b", "3"], ["a", "2"], ["a", "4"]]
        )
    }

    @Test func sortLeavesTheHeaderAndTheRowCountAlone() throws { // R-41
        let table = try Self.table([["3", "x"], ["1", "y"], ["2", "z"]])
        let sorted = TableEdit.sort(column: 1, ascending: false).applied(to: table)
        #expect(sorted.header == table.header)
        #expect(sorted.alignments == table.alignments)
        #expect(sorted.rows.count == 3)
        #expect(sorted.rows.map(\.[1]) == ["z", "y", "x"])
    }

    @Test(arguments: [-1, 2, 9])
    func sortRefusesAColumnOutOfRange(_ column: Int) throws { // R-41
        let table = try Self.table([["3", "x"], ["1", "y"]])
        #expect(TableEdit.sort(column: column, ascending: true).applied(to: table) == table)
    }
}

// MARK: - Committing back to the note (ADR-0029 §D7/§D8)

@MainActor
@Suite struct TableCommit {
    private static let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
    /// "prima\n" is six characters; the header paragraph starts right after it.
    private static let headerOffset = 6

    /// **Red on purpose.** `commitTable` is stubbed to always return `false` (Task 5,
    /// tester), so this is red until the coder's real write path lands - the one that
    /// matters most, since it is what makes a structural table edit exactly one `Cmd+Z`
    /// (D7), on `NoteTextView+EmbedCaret.swift`'s `replaceAtomically` mechanism (ADR-0019
    /// §D7's precedent).
    @Test func commitTableRewritesTheTableSourceAsOneAtomicUndoStep() {
        let fixture = EmbedEditorFixtures.editor(
            text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator

        let committed = coordinator.commitTable(
            .cell(row: 0, column: 0, text: "9"), at: Self.headerOffset, in: textView
        )
        #expect(committed, "il commit di una cella su una tabella valida deve riuscire")
        #expect(
            textView.string.contains("| 9 | 2 |"),
            "la cella modificata non compare nel testo sorgente dopo il commit"
        )

        textView.undoManager?.undo()
        #expect(
            textView.string == Self.note,
            "un solo Cmd+Z deve riportare la nota intera al testo di partenza"
        )
    }

    /// D8's reload guard: the table this offset once named has been rewritten to a
    /// different shape (a third column appeared) by the time the commit runs. Already
    /// passing with the stub - refusing is the only correct answer either way.
    @Test func aTableReplacedWithADifferentShapeUnderTheGridRefusesTheCommit() {
        let fixture = EmbedEditorFixtures.editor(
            text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator

        textView.string = "prima\n| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\ndopo\n"

        let committed = coordinator.commitTable(
            .cell(row: 0, column: 0, text: "9"), at: Self.headerOffset, in: textView
        )
        #expect(!committed, "una tabella di forma diversa non deve accettare la modifica")
    }

    /// D8's reload guard, the other direction: an edit above the table shifted its header
    /// away from the offset this cell's edit still names.
    @Test func aTableMovedByAnEarlierEditRefusesTheCommitAtTheStaleOffset() {
        let fixture = EmbedEditorFixtures.editor(
            text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator

        textView.string = "prima ancora\n" + Self.note

        let committed = coordinator.commitTable(
            .cell(row: 0, column: 0, text: "9"), at: Self.headerOffset, in: textView
        )
        #expect(!committed, "una tabella spostata non deve accettare la modifica al vecchio offset")
    }
}

// MARK: - R-06/R-07: the insert skeleton is itself a valid, empty table

@Suite struct TableInsertSkeleton {
    /// Already green: `EditorCommand.table` and `GFMTable.parse` are both real (Task 1 and
    /// Task 3), so this is a regression guard rather than a red test - if a later change to
    /// either one stops the skeleton parsing as a table, this is what notices.
    @Test func theSlashMenuSkeletonParsesAsAOneByTwoEmptyTable() {
        let lines = EditorCommand.table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let table = GFMTable.parse(lines[...]) else {
            Issue.record("lo scheletro di EditorCommand.table non è più una tabella valida")
            return
        }
        #expect(table.header == ["Colonna", "Colonna"])
        #expect(table.rows == [["", ""]])
    }
}
