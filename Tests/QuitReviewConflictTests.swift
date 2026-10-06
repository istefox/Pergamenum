import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D1/D3/D4/D6, plan Task 1: the two conflict items of the quit review, the
// words that name them, the order a cancel reveals them in and what an answer covers. Pure:
// columns are built by hand and the items by memberwise init, no vault. `tab`, `boardItem` and
// `diaryItem` live in `QuitTestSupport.swift`; R-08 (what an answer covers) is in
// `QuitReviewCoverageTests.swift`.

private func column(_ tabs: [NoteTab]) -> EditorColumn {
    var column = EditorColumn()
    column.tabs = tabs
    column.activeID = tabs.first?.id
    return column
}

private let boardSentenceSalva =
    "La board «Bacheca» è cambiata anche su disco: con «Salva» Pergamenum resta aperto per farti "
    + "scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
private let diarySentenceSalva =
    "Il diario del giorno 11/08/2026 è cambiato anche su disco: con «Salva» Pergamenum resta aperto "
    + "per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
private let boardSentenceSalvaTutto = boardSentenceSalva.replacingOccurrences(
    of: "«Salva»", with: "«Salva tutto»"
)
private let diarySentenceSalvaTutto = diarySentenceSalva.replacingOccurrences(
    of: "«Salva»", with: "«Salva tutto»"
)

private func paragraphs(_ copy: QuitReview.Copy) -> [String] {
    copy.informative.components(separatedBy: "\n\n")
}

// MARK: R-01, R-02: an item makes the review non-empty

@Test func aReviewWithOnlyABoardIsNotEmpty() {
    let review = QuitReview(columns: [], board: boardItem())

    #expect(!review.isEmpty)
    #expect(review.board == boardItem())
    #expect(review.diary == nil)
    #expect(review.entries.isEmpty)
}

@Test func aReviewWithOnlyADiaryDayIsNotEmpty() {
    let review = QuitReview(columns: [], diary: diaryItem())

    #expect(!review.isEmpty)
    #expect(review.diary == diaryItem())
    #expect(review.board == nil)
    #expect(review.entries.isEmpty)
}

@Test func aReviewBuiltWithNeitherItemKeepsBothNilAndTodaysIsEmpty() {
    let empty = QuitReview(columns: [column([])])
    #expect(empty.board == nil)
    #expect(empty.diary == nil)
    #expect(empty.isEmpty)

    let withNote = QuitReview(columns: [column([tab("A.md")])])
    #expect(withNote.board == nil)
    #expect(withNote.diary == nil)
    #expect(!withNote.isEmpty)
}

@Test func theBoardNameIsTheFileNameWithoutTheExtension() {
    #expect(boardItem(path: "Clienti/Bacheca.canvas").name == "Bacheca")
    #expect(boardItem(path: "Bacheca.canvas").name == "Bacheca")
}

// MARK: R-04: the words

@Test func aLoneBoardIsNamedAndAsksWithSalva() {
    let copy = QuitReview(columns: [], board: boardItem()).copy

    #expect(copy.message == "Salvare le modifiche alla board «Bacheca» prima di uscire?")
    #expect(copy.saveLabel == "Salva")
    #expect(copy.discardLabel == "Non salvare")
    #expect(copy.cancelLabel == "Annulla")
    #expect(paragraphs(copy).contains(boardSentenceSalva))
}

@Test func aLoneDiaryDayIsNamedAndAsksWithSalva() {
    let copy = QuitReview(columns: [], diary: diaryItem()).copy

    #expect(copy.message == "Salvare le modifiche al diario del giorno 11/08/2026 prima di uscire?")
    #expect(copy.saveLabel == "Salva")
    #expect(paragraphs(copy).contains(diarySentenceSalva))
}

@Test func theBoardAndDiarySentencesNameTheSaveLabelOfTheAlert() {
    let copy = QuitReview(columns: [column([tab("A.md")])], board: boardItem(), diary: diaryItem()).copy

    #expect(copy.saveLabel == "Salva tutto")
    #expect(paragraphs(copy).contains(boardSentenceSalvaTutto))
    #expect(paragraphs(copy).contains(diarySentenceSalvaTutto))
}

@Test func theCountedMessageJoinsBoardNotesAndDiaryAsAListWithE() {
    let review = QuitReview(
        columns: [column([tab("A.md"), tab("B.md")])], board: boardItem(), diary: diaryItem()
    )

    #expect(review.copy.message == "Salvare le modifiche a 1 board, 2 note e 1 diario prima di uscire?")
    #expect(review.copy.saveLabel == "Salva tutto")
}

@Test func theCountedMessageWithAllFourKindsJoinsThemInTheItemOrder() {
    let review = QuitReview(
        columns: [column([tab("A.md"), tab("B.md")])],
        vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"],
        board: boardItem(), diary: diaryItem()
    )

    #expect(
        review.copy.message
            == "Salvare le modifiche a 1 board, 2 note, 1 diario e 1 scheda prima di uscire?"
    )
}

@Test func aBoardAndOneNoteAreCountedAsTwoParts() {
    let review = QuitReview(columns: [column([tab("A.md")])], board: boardItem())

    #expect(review.copy.message == "Salvare le modifiche a 1 board e 1 nota prima di uscire?")
    #expect(review.copy.saveLabel == "Salva tutto")
}

@Test func aDiaryDayAndASchedaAreCountedAsTwoParts() {
    let review = QuitReview(
        columns: [], vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"], diary: diaryItem()
    )

    #expect(review.copy.message == "Salvare le modifiche a 1 diario e 1 scheda prima di uscire?")
}

@Test func aNoteAndASchedaKeepTodaysCountedMessageByteForByte() {
    let review = QuitReview(
        columns: [column([tab("A.md")])], vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"]
    )

    #expect(review.copy.message == "Salvare le modifiche a 1 nota e 1 scheda prima di uscire?")
}

@Test func theListLinesFollowTheItemOrderBoardNotesDiarySchede() {
    let review = QuitReview(
        columns: [column([tab("A.md", title: "Titolo")])],
        vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"],
        board: boardItem(), diary: diaryItem()
    )

    let first = paragraphs(review.copy).first
    #expect(
        first == "la board «Bacheca»\n«Titolo»\nil diario del giorno 11/08/2026\n«20260314 Fattura»"
    )
}

@Test func theSentencesFollowTheItemOrderBoardNotesDiarySchede() throws {
    let review = QuitReview(
        columns: [column([tab("A.md", title: "Titolo")])],
        vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"],
        board: boardItem(), diary: diaryItem()
    )
    let all = paragraphs(review.copy)

    let board = try #require(all.firstIndex(of: boardSentenceSalvaTutto))
    let diary = try #require(all.firstIndex(of: diarySentenceSalvaTutto))
    let scheda = try #require(all.firstIndex { $0.contains("La scheda «20260314 Fattura»") })
    #expect(board < diary)
    #expect(diary < scheda)
}

@Test func aConflictedNoteSentenceSitsBetweenTheBoardsAndTheDiarys() throws {
    var conflicted = tab("A.md", title: "Titolo")
    conflicted.note.externalChangePending = .text("da disco")
    let review = QuitReview(columns: [column([conflicted])], board: boardItem(), diary: diaryItem())
    let all = paragraphs(review.copy)

    let board = try #require(all.firstIndex(of: boardSentenceSalvaTutto))
    let note = try #require(all.firstIndex { $0.contains("«Titolo» è cambiata anche su disco") })
    let diary = try #require(all.firstIndex(of: diarySentenceSalvaTutto))
    #expect(board < note)
    #expect(note < diary)
}

@Test func theEightLineLimitCoversTheWholeListAndACutOffItemKeepsItsSentence() {
    let tabs = (1...8).map { tab("Nota \($0).md") }
    let review = QuitReview(columns: [column(tabs)], diary: diaryItem())
    let copy = review.copy

    #expect(copy.message == "Salvare le modifiche a 8 note e 1 diario prima di uscire?")
    #expect(copy.informative.contains("«Nota 8»"))
    #expect(!copy.informative.contains("la board"))
    #expect(copy.informative.contains("e altre 1"))
    #expect(!paragraphs(copy)[0].contains("il diario del giorno 11/08/2026"))
    #expect(paragraphs(copy).contains(diarySentenceSalvaTutto))
}

@Test func aDirtyTabOnTheDayFileAndTheDiaryItemAreBothNamed() {
    let review = QuitReview(
        columns: [column([tab("Diario/20260811.md", title: "20260811")])], diary: diaryItem()
    )
    let copy = review.copy

    #expect(copy.message == "Salvare le modifiche a 1 nota e 1 diario prima di uscire?")
    #expect(copy.informative.contains("«20260811»"))
    #expect(copy.informative.contains("il diario del giorno 11/08/2026"))
}

@Test func theVaultSwitchAndColumnCloseWordsAreUnchangedWithoutTheItems() {
    let review = QuitReview(columns: [column([tab("Progetti/Nexion.md", title: "Nexion")])])

    let switching = review.copy(for: .vaultSwitch)
    #expect(switching.message == "Salvare le modifiche a «Nexion» prima di aprire un'altra cartella note?")
    #expect(switching.informative.contains("Aprendo un'altra cartella note senza salvare"))
    let closing = review.copy(for: .columnClose)
    #expect(closing.message == "Salvare le modifiche a «Nexion» prima di chiudere la colonna?")
    #expect(closing.informative.contains("Chiudendo la colonna senza salvare"))
    #expect(!switching.informative.contains("board"))
    #expect(!closing.informative.contains("diario"))
}

// MARK: R-06: the problem lines

@Test func theBoardsProblemLineIsFrozen() {
    #expect(
        boardItem().leftProblem
            == "Uscita annullata: la board «Bacheca» ha un conflitto di salvataggio non risolto"
    )
}

@Test func theDiaryDaysProblemLineIsFrozen() {
    #expect(
        diaryItem().leftProblem
            == "Uscita annullata: il diario del giorno 11/08/2026 ha un conflitto di salvataggio non risolto"
    )
}

// MARK: R-05: where a cancel goes (G1: board, notes, diary, schede)

private let scheda = QuitReview.Scheda(path: "Contenitore/2026/20260314 Fattura.md")

@Test func theBoardIsRevealedFirstWhateverElseIsOwed() {
    let tabs = [tab("A.md")]
    let review = QuitReview(
        columns: [column(tabs)], vanishedSchede: [scheda.path], board: boardItem(), diary: diaryItem()
    )

    #expect(review.firstReveal(namingTab: false) == .board)
    #expect(review.firstReveal(namingTab: true) == .board)
    #expect(
        QuitReview.firstReveal(
            board: boardItem(), notes: review.entries, diary: diaryItem(), schede: review.schede,
            namingTab: false
        ) == .board
    )
}

@Test func notesComeBeforeTheDiary() {
    let tabs = [tab("A.md"), tab("B.md")]
    let review = QuitReview(columns: [column(tabs)], diary: diaryItem())

    #expect(review.firstReveal(namingTab: false) == .note(nil))
    #expect(review.firstReveal(namingTab: true) == .note(tabs[0].id))
    #expect(
        QuitReview.firstReveal(
            board: nil, notes: review.entries, diary: diaryItem(), schede: [], namingTab: false
        ) == .note(nil)
    )
    #expect(
        QuitReview.firstReveal(
            board: nil, notes: review.entries, diary: diaryItem(), schede: [], namingTab: true
        ) == .note(tabs[0].id)
    )
}

@Test func theDiaryComesBeforeTheSchede() {
    let review = QuitReview(columns: [], vanishedSchede: [scheda.path], diary: diaryItem())

    #expect(review.firstReveal(namingTab: false) == .diary)
    #expect(review.firstReveal(namingTab: true) == .diary)
}

@Test func schedeAloneRevealTheFirstSchedaPath() {
    let review = QuitReview(columns: [], vanishedSchede: [scheda.path, "Contenitore/2026/Altra.md"])

    #expect(review.firstReveal(namingTab: false) == .scheda(scheda.path))
    #expect(
        QuitReview.firstReveal(
            board: nil, notes: [], diary: nil, schede: review.schede, namingTab: false
        ) == .scheda(scheda.path)
    )
}

@Test func aBoardAloneIsRevealedAndADiaryAloneIsRevealed() {
    #expect(QuitReview(columns: [], board: boardItem()).firstReveal(namingTab: false) == .board)
    #expect(QuitReview(columns: [], diary: diaryItem()).firstReveal(namingTab: false) == .diary)
}

@Test func anEmptyReviewRevealsNothing() {
    #expect(QuitReview(columns: []).firstReveal(namingTab: false) == nil)
    #expect(QuitReview(columns: []).firstReveal(namingTab: true) == nil)
    #expect(
        QuitReview.firstReveal(board: nil, notes: [], diary: nil, schede: [], namingTab: true) == nil
    )
}

@Test func theQuestionsFirstItemIsTheItemACancelReveals() {
    // R-05's last sentence: the list names the same item first that the cancel shows.
    let review = QuitReview(
        columns: [column([tab("A.md", title: "Titolo")])], board: boardItem(), diary: diaryItem()
    )

    #expect(review.firstReveal(namingTab: false) == .board)
    #expect(paragraphs(review.copy).first?.hasPrefix("la board «Bacheca»") == true)

    let noBoard = QuitReview(columns: [column([tab("A.md", title: "Titolo")])], diary: diaryItem())
    #expect(noBoard.firstReveal(namingTab: false) == .note(nil))
    #expect(paragraphs(noBoard.copy).first?.hasPrefix("«Titolo»") == true)
}

@Test func uncoveredWorkRevealsInTheSameOrderAndAlwaysNamesTheTab() {
    let entries = QuitReview(columns: [column([tab("A.md")])]).entries
    let entry = entries[0]

    #expect(
        QuitReview.Uncovered(notes: entries, board: boardItem(), diary: diaryItem()).firstReveal() == .board
    )
    #expect(
        QuitReview.Uncovered(notes: entries, board: nil, diary: diaryItem()).firstReveal()
            == .note(entry.tabID)
    )
    #expect(QuitReview.Uncovered(notes: [], board: nil, diary: diaryItem()).firstReveal() == .diary)
    #expect(QuitReview.Uncovered(notes: [], board: nil, diary: nil).firstReveal() == nil)
}

@Test func uncoveredIsEmptyOnlyWhenNothingIsInIt() {
    let entries = QuitReview(columns: [column([tab("A.md")])]).entries

    #expect(QuitReview.Uncovered(notes: [], board: nil, diary: nil).isEmpty)
    #expect(!QuitReview.Uncovered(notes: entries, board: nil, diary: nil).isEmpty)
    #expect(!QuitReview.Uncovered(notes: [], board: boardItem(), diary: nil).isEmpty)
    #expect(!QuitReview.Uncovered(notes: [], board: nil, diary: diaryItem()).isEmpty)
}
