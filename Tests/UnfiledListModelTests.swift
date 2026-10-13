import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D1/§D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-01: the
// rows «Da classificare» lists, their order, the folder filter and where the selection goes once a
// row has been filed. One pure model; the view only draws it.
//
// Not tested, because the ADR and the SPEC do not state it: the direction of the `modifiedAt`
// tie-break ("then `modifiedAt`", ADR-0085 §D2, names no direction), where an undated row sits
// among dated ones, and the order of `folders(from:)`. The ties below are therefore built with
// equal modification times, and the folder list is compared as a set.

private typealias VaultTag = Pergamenum.Tag

private let inbox = VaultTag("status-inbox")!
private let note = VaultTag("type-note")!
private let topic = VaultTag("topic-x")!

private func day(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

private let sameInstant = Date(timeIntervalSince1970: 1_790_000_000)

private func record(
    _ path: String, date: String? = "2026-10-01", tags: [VaultTag] = [note, inbox],
    modifiedAt: Date = sameInstant, scheda: Bool = false
) -> NoteRecord {
    let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    var frontmatter = Frontmatter.empty
    frontmatter.date = date.map(day)
    frontmatter.tags = tags
    var result = NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: [],
        tasks: [], modifiedAt: modifiedAt, byteSize: 10, contentHash: "-"
    )
    if scheda {
        result.contenitore = ContenitoreFacts(
            fileName: "\(title).pdf", originalName: "Scansione.pdf", sha256: nil, colour: nil, rawColour: nil
        )
    }
    return result
}

// MARK: - Which notes are rows

@Test func onlyNotesCarryingStatusInboxAreRows() {
    let rows = UnfiledListModel.rows(from: [
        record("00 Inbox/Idea.md"),
        record("03 Risorse/Classificata.md", tags: [note, topic]),
        record("00 Inbox/Altra.md"),
    ], folder: nil)

    #expect(Set(rows.map(\.id)) == ["00 Inbox/Idea.md", "00 Inbox/Altra.md"]) // R-01
}

@Test func aRowCarriesTheFieldsTheListDraws() throws {
    let rows = UnfiledListModel.rows(
        from: [record("00 Inbox/Idea.md", date: "2026-10-03", modifiedAt: sameInstant)], folder: nil
    )

    let row = try #require(rows.first)
    #expect(row.id == "00 Inbox/Idea.md")
    #expect(row.title == "Idea")
    #expect(row.folder == "00 Inbox")
    #expect(row.date == day("2026-10-03"))
    #expect(row.modifiedAt == sameInstant)
    #expect(!row.isScheda)
}

@Test func aContenitoreSchedaIsListedAndMarkedAsOne() throws {
    let rows = UnfiledListModel.rows(from: [
        record("Contenitore/2026/20261001 Fattura.md", scheda: true),
        record("00 Inbox/Idea.md"),
    ], folder: nil)

    #expect(rows.count == 2) // R-01: schede included
    #expect(try #require(rows.first { $0.id == "Contenitore/2026/20261001 Fattura.md" }).isScheda)
    #expect(try #require(rows.first { $0.id == "00 Inbox/Idea.md" }).isScheda == false)
}

@Test func templatesAndEventNotesCarryingStatusInboxAreListedLikeAnyNote() {
    let rows = UnfiledListModel.rows(from: [
        record("Templates/Riunione.md"),
        record("Eventi/20261012 Riunione cliente.md"),
    ], folder: nil)

    #expect(rows.count == 2) // SPEC edge case: nothing exempts them
}

@Test func noRecordsGiveNoRows() {
    #expect(UnfiledListModel.rows(from: [], folder: nil).isEmpty)
    #expect(UnfiledListModel.rows(from: [record("A.md", tags: [note, topic])], folder: nil).isEmpty)
}

// MARK: - Order

@Test func rowsAreOrderedByDateNewestFirst() {
    let rows = UnfiledListModel.rows(from: [
        record("00 Inbox/Vecchia.md", date: "2026-09-01"),
        record("00 Inbox/Nuova.md", date: "2026-10-09"),
        record("00 Inbox/Media.md", date: "2026-09-20"),
    ], folder: nil)

    #expect(rows.map(\.title) == ["Nuova", "Media", "Vecchia"]) // R-01
}

@Test func equalDatesAndTimesFallBackToTheTitle() {
    let rows = UnfiledListModel.rows(from: [
        record("00 Inbox/Beta.md"), record("00 Inbox/Alfa.md"), record("00 Inbox/Gamma.md"),
    ], folder: nil)

    #expect(rows.map(\.title) == ["Alfa", "Beta", "Gamma"]) // ADR-0085 §D2: then title
}

@Test func theDateOutranksTheModificationTime() {
    let later = sameInstant.addingTimeInterval(86_400)
    let rows = UnfiledListModel.rows(from: [
        record("00 Inbox/Toccata.md", date: "2026-09-01", modifiedAt: later),
        record("00 Inbox/Recente.md", date: "2026-10-01", modifiedAt: sameInstant),
    ], folder: nil)

    #expect(rows.map(\.title) == ["Recente", "Toccata"])
}

// MARK: - The folder filter

@Test func aFolderFilterKeepsOnlyThatFoldersRows() {
    let records = [
        record("00 Inbox/Idea.md"), record("00 Inbox/Altra.md"), record("03 Risorse/Terza.md"),
    ]

    #expect(Set(UnfiledListModel.rows(from: records, folder: "00 Inbox").map(\.title)) == ["Idea", "Altra"])
    #expect(UnfiledListModel.rows(from: records, folder: "03 Risorse").map(\.title) == ["Terza"])
    #expect(UnfiledListModel.rows(from: records, folder: "Mai esistita").isEmpty)
    #expect(UnfiledListModel.rows(from: records, folder: nil).count == 3)
}

@Test func foldersAreCountedByHowManyCapturesTheyHold() {
    let folders = UnfiledListModel.folders(from: [
        record("00 Inbox/Idea.md"), record("00 Inbox/Altra.md"), record("03 Risorse/Terza.md"),
        record("03 Risorse/Gia classificata.md", tags: [note, topic]),
    ])

    let counts = Dictionary(uniqueKeysWithValues: folders.map { ($0.folder, $0.count) })
    #expect(counts == ["00 Inbox": 2, "03 Risorse": 1]) // R-01: classified notes are not counted
    #expect(folders.count == 2)
}

@Test func withNothingToClassifyTheFolderListIsEmptyAndTheControlHides() {
    #expect(UnfiledListModel.folders(from: []).isEmpty) // R-01: "hides when empty"
    #expect(UnfiledListModel.folders(from: [record("A.md", tags: [note, topic])]).isEmpty)
}

// MARK: - Where the selection goes

private func rowsForSelection() -> [UnfiledListModel.Row] {
    UnfiledListModel.rows(from: [
        record("00 Inbox/Prima.md", date: "2026-10-03"),
        record("00 Inbox/Seconda.md", date: "2026-10-02"),
        record("00 Inbox/Terza.md", date: "2026-10-01"),
    ], folder: nil)
}

@Test func afterFilingARowTheSelectionMovesToTheOneThatFollowedIt() {
    let rows = rowsForSelection()

    #expect(UnfiledListModel.selection(after: "00 Inbox/Prima.md", in: rows) == "00 Inbox/Seconda.md")
    #expect(UnfiledListModel.selection(after: "00 Inbox/Seconda.md", in: rows) == "00 Inbox/Terza.md")
}

@Test func afterFilingTheLastRowTheSelectionMovesToThePreviousOne() {
    #expect(UnfiledListModel.selection(after: "00 Inbox/Terza.md", in: rowsForSelection()) == "00 Inbox/Seconda.md")
}

@Test func afterFilingTheOnlyRowThereIsNoSelection() {
    let rows = UnfiledListModel.rows(from: [record("00 Inbox/Sola.md")], folder: nil)

    #expect(UnfiledListModel.selection(after: "00 Inbox/Sola.md", in: rows) == nil)
    #expect(UnfiledListModel.selection(after: "x.md", in: []) == nil)
}
