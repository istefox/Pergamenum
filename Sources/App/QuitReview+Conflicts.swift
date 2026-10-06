import Foundation

// PG-336, ADR-0089: the two conflict items of the quit review - a conflicted Workspace board and
// a conflicted diary day - their words (§D3), what an answer covers (§D4) and where a cancel goes
// (§D6). Only the quit passes them (§D1): the vault switch and «Chiudi la colonna» never do.

extension QuitReview {
    /// The open board, conflicted, as the question showed it (ADR-0089 §D1).
    struct Board: Equatable, Sendable {
        let path: String
        let document: CanvasDocument

        /// The board's file name without `.canvas`, as the sidebar lists it.
        var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

        /// How the question names the board when it is the only item.
        var singularPhrase: String { "alla board «\(name)»" }
        /// The board's line in the question's list.
        var listLine: String { "la board «\(name)»" }

        /// Why the board is in the question; `saveLabel` is the alert's own. `staying` is
        /// interpolated mid-sentence, so it must read as a clause like the quit's
        /// «Pergamenum resta aperto» - any other caller re-checks the grammar.
        func sentence(saveLabel: String, staying: String) -> String {
            "La board «\(name)» è cambiata anche su disco: con «\(saveLabel)» \(staying) "
                + "per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
        }

        /// The problem line recorded when the quit is cancelled with this board left.
        var leftProblem: String { "Uscita annullata: \(listLine) ha un conflitto di salvataggio non risolto" }
    }

    /// The diary day, conflicted, as the question showed it (ADR-0089 §D1).
    struct DiaryDay: Equatable, Sendable {
        let day: CalendarDate
        let prose: String
        let entries: [DiaryEntry]

        /// «del giorno» rather than «dell'11»: the date is the diary header's own form.
        private var named: String { "diario del giorno \(day.italianForm)" }

        /// How the question names the day when it is the only item.
        var singularPhrase: String { "al \(named)" }
        /// The day's line in the question's list.
        var listLine: String { "il \(named)" }

        /// Why the day is in the question; `saveLabel` is the alert's own. `staying` has the
        /// same constraint as `Board.sentence(saveLabel:staying:)`'s.
        func sentence(saveLabel: String, staying: String) -> String {
            "Il \(named) è cambiato anche su disco: con «\(saveLabel)» \(staying) "
                + "per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
        }

        /// The problem line recorded when the quit is cancelled with this day left.
        var leftProblem: String { "Uscita annullata: \(listLine) ha un conflitto di salvataggio non risolto" }
    }

    /// Where a cancel takes the person (ADR-0089 §D6).
    enum Reveal: Equatable, Sendable {
        case board, note(NoteTab.ID?), diary, scheda(String?)
    }

    /// What an answer did not cover (ADR-0089 §D4): ADR-0073 §D7's uncovered notes, plus a
    /// board or diary day that is conflicted now and was not, or not in this form, in the
    /// snapshot the question showed.
    struct Uncovered: Equatable, Sendable {
        let notes: [Entry]
        let board: Board?
        let diary: DiaryDay?

        var isEmpty: Bool { notes.isEmpty && board == nil && diary == nil }

        /// The first item left, in §D6's order; a note is always named by its tab.
        func firstReveal() -> Reveal? {
            QuitReview.firstReveal(board: board, notes: notes, diary: diary, schede: [], namingTab: true)
        }
    }

    /// What `now` holds that this snapshot's answer did not cover (ADR-0089 §D4). A board or day
    /// gone from `now` - resolved, or no longer open - is never uncovered.
    func uncoveredWork(in now: QuitReview) -> Uncovered {
        Uncovered(
            notes: uncovered(in: now),
            board: now.board == board ? nil : now.board,
            diary: now.diary == diary ? nil : now.diary
        )
    }

    /// Where a cancel of this review goes: the item the question names first (§D6).
    func firstReveal(namingTab: Bool) -> Reveal? {
        Self.firstReveal(board: board, notes: entries, diary: diary, schede: schede, namingTab: namingTab)
    }

    /// The one place the items' order lives (ADR-0089 §D6, gate G1): the board, the notes, the
    /// diary, then the Contenitore schede. The board comes first because showing any other pane
    /// destroys its controller, and with it the edits the question protected. `copy(for:)`
    /// lists the items in this same order, so a cancel shows the item the question named first.
    /// `namingTab: false` is «Annulla»'s `reveal(nil)` (ADR-0073 §D7).
    static func firstReveal(
        board: Board?, notes: [Entry], diary: DiaryDay?, schede: [Scheda], namingTab: Bool
    ) -> Reveal? {
        if board != nil { return .board }
        if let first = notes.first { return .note(namingTab ? first.tabID : nil) }
        if diary != nil { return .diary }
        if let first = schede.first { return .scheda(first.path) }
        return nil
    }
}

extension WorkspaceController {
    /// The open board as a quit item, when its save is conflicted (ADR-0089 §D2). A pending
    /// board is no item: the settle writes it.
    var quitConflict: QuitReview.Board? {
        guard case .conflicted = saveState, !board.isEmpty else { return nil }
        return QuitReview.Board(path: board, document: document)
    }
}

extension DiaryController {
    /// The diary day as a quit item, when its save is conflicted (ADR-0089 §D2). A pending day
    /// is no item: the diary phase writes it.
    var quitConflict: QuitReview.DiaryDay? {
        guard case .conflicted = saveState else { return nil }
        return QuitReview.DiaryDay(day: day, prose: prose, entries: entries)
    }
}
