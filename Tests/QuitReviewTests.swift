import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D1/§D2/§D7, plan Task 1: the snapshot quitting asks about, the words it asks
// with, and what an answer covers. Pure: columns are built by hand, no vault.

private func tab(
    _ path: String, title: String? = nil, text: String = "modificato", saved: String = "originale",
    pending: VaultSession.ExternalChange.Content? = nil
) -> NoteTab {
    NoteTab(note: VaultController.OpenNote(
        relativePath: path,
        title: title ?? (path as NSString).deletingPathExtension,
        text: text,
        savedText: saved,
        externalChangePending: pending
    ))
}

private func column(_ tabs: [NoteTab]) -> EditorColumn {
    var column = EditorColumn()
    column.tabs = tabs
    column.activeID = tabs.first?.id
    return column
}

// MARK: Entries (R-01, R-07)

@Test func entriesAreTheDirtyTabsOfBothColumnsInColumnThenTabOrder() {
    let left = [tab("A.md"), tab("Pulita.md", text: "uguale", saved: "uguale"), tab("B.md")]
    let right = [tab("C.md")]

    let review = QuitReview(columns: [column(left), column(right)])

    #expect(review.entries.map(\.relativePath) == ["A.md", "B.md", "C.md"])
    #expect(review.entries.map(\.tabID) == [left[0].id, left[2].id, right[0].id])
    #expect(review.entries.first?.text == "modificato")
    #expect(!review.isEmpty)
}

@Test func aCleanTabAndAnEmptyColumnContributeNothing() {
    let review = QuitReview(columns: [column([tab("A.md", text: "x", saved: "x")]), column([])])

    #expect(review.entries.isEmpty)
    #expect(review.isEmpty)
}

@Test func bothKindsOfPendingChangeMarkAnEntryConflicted() {
    let review = QuitReview(columns: [column([
        tab("A.md", pending: .text("da disco")),
        tab("B.md", pending: .deleted),
        tab("C.md"),
    ])])

    #expect(review.entries.map(\.isConflicted) == [true, true, false])
    #expect(review.saveCandidates.map(\.relativePath) == ["C.md"])
}

// MARK: The words (R-02)

@Test func oneNoteIsNamedAndSavedWithSalva() {
    let copy = QuitReview(columns: [column([tab("Progetti/Nexion.md", title: "Nexion")])]).copy

    #expect(copy.message == "Salvare le modifiche a «Nexion» prima di uscire?")
    #expect(copy.saveLabel == "Salva")
    #expect(copy.discardLabel == "Non salvare")
    #expect(copy.cancelLabel == "Annulla")
    #expect(!copy.informative.contains("cambiata anche su disco"))
}

@Test func theSameNoteInBothColumnsIsOneNote() {
    let copy = QuitReview(columns: [
        column([tab("A.md", text: "sinistra")]),
        column([tab("A.md", text: "destra")]),
    ]).copy

    #expect(copy.message == "Salvare le modifiche a «A» prima di uscire?")
    #expect(copy.saveLabel == "Salva")
}

@Test func severalNotesAreCountedByPathAndListed() {
    let copy = QuitReview(columns: [
        column([tab("A.md"), tab("B.md")]),
        column([tab("A.md", text: "altro")]),
    ]).copy

    #expect(copy.message == "Salvare le modifiche a 2 note prima di uscire?")
    #expect(copy.saveLabel == "Salva tutto")
    #expect(copy.informative.contains("«A»"))
    #expect(copy.informative.contains("«B»"))
}

@Test func theListStopsAtEightTitles() {
    let tabs = (1...11).map { tab("Nota \($0).md") }
    let copy = QuitReview(columns: [column(tabs)]).copy

    #expect(copy.message == "Salvare le modifiche a 11 note prima di uscire?")
    #expect(copy.informative.contains("«Nota 8»"))
    #expect(!copy.informative.contains("«Nota 9»"))
    #expect(copy.informative.contains("e altre 3"))
}

@Test func aTitleSharedByTwoPathsShowsThePath() {
    let copy = QuitReview(columns: [column([
        tab("Clienti/Riunione.md", title: "Riunione"),
        tab("Fornitori/Riunione.md", title: "Riunione"),
        tab("Altro.md", title: "Altro"),
    ])]).copy

    #expect(copy.informative.contains("«Clienti/Riunione.md»"))
    #expect(copy.informative.contains("«Fornitori/Riunione.md»"))
    #expect(copy.informative.contains("«Altro»"))
}

@Test func theSamePathInTwoVaultsIsTwoNotes() {
    var foreign = tab("Nexion.md", title: "Nexion")
    foreign.previousVaultRoot = URL(filePath: "/tmp/cartella-a", directoryHint: .isDirectory)
    let review = QuitReview(columns: [column([foreign]), column([tab("Nexion.md", title: "Nexion")])])

    let copy = review.copy

    #expect(review.notes.count == 2)
    #expect(copy.message == "Salvare le modifiche a 2 note prima di uscire?")
    // Only the previous vault's copy is reported as not saved here, and it is told apart.
    #expect(copy.informative.contains("«Nexion.md (cartella-a)» è di una cartella note aperta prima"))
    #expect(!copy.informative.contains("«Nexion.md» è di una cartella"))
    #expect(copy.informative.contains("«Nexion.md (cartella-a)»\n«Nexion.md»"))
}

@Test func theSamePathTwiceInOneForeignVaultIsOneNote() {
    let root = URL(filePath: "/tmp/cartella-a", directoryHint: .isDirectory)
    var first = tab("Nexion.md", title: "Nexion")
    var second = tab("Nexion.md", title: "Nexion")
    first.previousVaultRoot = root
    second.previousVaultRoot = root

    #expect(QuitReview(columns: [column([first]), column([second])]).notes.count == 1)
}

@Test func aConflictedNoteIsNamedInTheInformativeText() {
    let copy = QuitReview(columns: [column([tab("A.md", pending: .text("x")), tab("B.md")])]).copy

    #expect(copy.informative.contains(
        "«A» è cambiata anche su disco: Pergamenum resta aperto per farti scegliere quale versione tenere."
    ))
    #expect(!copy.informative.contains("«B» è cambiata"))
}

// MARK: What an answer covers (R-08)

@Test func anUnchangedSnapshotIsCovered() {
    let columns = [column([tab("A.md"), tab("B.md")])]
    let asked = QuitReview(columns: columns)

    #expect(asked.uncovered(in: QuitReview(columns: columns)).isEmpty)
}

@Test func aTabWhoseTextChangedIsUncovered() {
    var columns = [column([tab("A.md"), tab("B.md")])]
    let asked = QuitReview(columns: columns)
    columns[0].tabs[1].note.text = "digitato dopo la risposta"

    let uncovered = asked.uncovered(in: QuitReview(columns: columns))

    #expect(uncovered.map(\.tabID) == [columns[0].tabs[1].id])
}

@Test func aNewlyDirtyTabIsUncovered() {
    var columns = [column([tab("A.md"), tab("B.md", text: "x", saved: "x")])]
    let asked = QuitReview(columns: columns)
    columns[0].tabs[1].note.text = "y"

    #expect(asked.uncovered(in: QuitReview(columns: columns)).map(\.relativePath) == ["B.md"])
}

@Test func aTabThatWentCleanIsNotUncovered() {
    var columns = [column([tab("A.md"), tab("B.md")])]
    let asked = QuitReview(columns: columns)
    columns[0].tabs[0].note.savedText = columns[0].tabs[0].note.text

    #expect(asked.uncovered(in: QuitReview(columns: columns)).isEmpty)
}

// MARK: The cap (R-09)

@Test func theNoteSaveCapIsTenSeconds() {
    #expect(QuitReview.noteSaveCap == .seconds(10))
}
