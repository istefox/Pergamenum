import Foundation

/// What quitting has to ask about: every note tab with unsaved changes, in every column
/// (ADR-0073 §D1), and the words the question uses (§D2).
///
/// Pure and Foundation-only, so the whole decision is testable without AppKit: the
/// coordinator builds one before asking, again after the answer and again before letting the
/// app go, and compares them (§D7). In `Sources/App` rather than `Sources/Core` because it
/// reads `NoteTab`, which is app-only, and no connector needs it (§D9).
struct QuitReview: Equatable, Sendable {
    /// One dirty tab as the question showed it.
    struct Entry: Equatable, Sendable {
        let tabID: NoteTab.ID
        let relativePath: String
        let title: String
        /// The text the tab held when the snapshot was taken: what «Non salvare» covers.
        let text: String
        /// The conflict banner is waiting (`externalChangePending`, `.text` or `.deleted`):
        /// the bulk save never writes this tab (§D5).
        let isConflicted: Bool
        /// The tab was opened from another vault than the one open now: the bulk save never
        /// writes it (§D5, departure 13).
        let isFromPreviousVault: Bool
        /// The root the tab belongs to when `isFromPreviousVault`, else nil: two tabs with the
        /// same relative path are the same note only when they share it.
        let previousVaultRoot: URL?
    }

    /// A Contenitore scheda whose inspector edit is owed and did not reach disk: the scheda is
    /// no longer at its path (PG-341), or it is but the edit's last write failed (PG-373). The
    /// question names it like a note, so its «Non salvare» lets the app go; «Salva» retries the
    /// write, and one that cannot land cancels the quit and brings the pane back, and the next
    /// Cmd+Q offers the choice again.
    struct Scheda: Equatable, Sendable {
        /// Why the edit did not reach disk, which decides what the question says about it.
        enum Problem: Equatable, Sendable {
            /// The scheda is no longer at its path: no write can land.
            case gone
            /// The scheda is there and its write failed: «Salva» retries it.
            case writeFailed
        }

        let path: String
        var problem: Problem = .gone

        /// The scheda's file name without `.md`, as the pane lists it.
        var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    /// The person's answer to the question.
    enum Answer: Equatable, Sendable {
        case save, discard, cancel
    }

    /// The words of the question (§D2). Decided here rather than in the alert, the shape
    /// `ConflictBannerCopy` already has.
    struct Copy: Equatable, Sendable {
        let message: String
        let informative: String
        let saveLabel: String
        let discardLabel: String
        let cancelLabel: String
    }

    /// The fail-safe cap on the note saves (§D6): elapsed, it cancels the quit, never
    /// completes it.
    static let noteSaveCap: Duration = .seconds(10)
    /// How many titles the question lists before «e altre K».
    static let listedTitleLimit = 8

    /// Every dirty tab, column order then tab order.
    let entries: [Entry]
    /// Every Contenitore scheda whose owed edit was not written (PG-341, PG-373), the vanished
    /// ones first. Only the quit passes any: a vault switch and a column close never reach the
    /// Contenitore.
    let schede: [Scheda]
    /// The open Workspace board when its save is in conflict (PG-336, ADR-0089 §D1). Only the
    /// quit passes one.
    let board: Board?
    /// The diary day when its save is in conflict (PG-336, ADR-0089 §D1). Only the quit passes
    /// one.
    let diary: DiaryDay?

    init(
        columns: [EditorColumn],
        vanishedSchede: [String] = [],
        failedSchede: [String] = [],
        board: Board? = nil,
        diary: DiaryDay? = nil
    ) {
        self.board = board
        self.diary = diary
        schede = vanishedSchede.map { Scheda(path: $0, problem: .gone) }
            + failedSchede.map { Scheda(path: $0, problem: .writeFailed) }
        entries = columns.flatMap { column in
            column.tabs.compactMap { tab -> Entry? in
                guard tab.note.hasUnsavedChanges else { return nil }
                return Entry(
                    tabID: tab.id,
                    relativePath: tab.note.relativePath,
                    title: tab.note.title,
                    text: tab.note.text,
                    isConflicted: tab.note.externalChangePending != nil,
                    isFromPreviousVault: tab.isFromPreviousVault,
                    previousVaultRoot: tab.previousVaultRoot
                )
            }
        }
    }

    var isEmpty: Bool { entries.isEmpty && schede.isEmpty && board == nil && diary == nil }

    /// The entries «Salva tutto» may write: every one that is neither conflicted nor from a
    /// previous vault.
    var saveCandidates: [Entry] { entries.filter { !$0.isConflicted && !$0.isFromPreviousVault } }

    /// The entries of `now` that this snapshot's answer did not cover (§D7): a dirty tab whose
    /// `(tab id, text)` is not in this snapshot. A tab that went clean is not in `now` at all,
    /// so it is never uncovered.
    func uncovered(in now: QuitReview) -> [Entry] {
        now.entries.filter { entry in
            !entries.contains { $0.tabID == entry.tabID && $0.text == entry.text }
        }
    }

    /// What closing a column does once the question about its dirty tabs was answered
    /// (PG-335).
    enum CloseDecision: Equatable, Sendable {
        case close
        /// The column stays open. `unresolved` is what the answer did not cover - a failed
        /// save, a conflicted tab the save never writes, text typed meanwhile - and is empty for
        /// «Annulla», which covers nothing and asks for nothing to be shown.
        case keepOpen(unresolved: [Entry])
    }

    /// Decides a column close on the column as it is **after** the answer ran (`now`), never
    /// on this snapshot alone (ADR-0043 §D7). «Salva» covers nothing it did not save: the
    /// column closes only when `now` has no dirty tab left. «Non salvare» covers what the
    /// question showed (`uncovered(in:)`), the quit's own rule.
    func closeDecision(after answer: Answer, now: QuitReview) -> CloseDecision {
        let unresolved: [Entry]
        switch answer {
        case .cancel: return .keepOpen(unresolved: [])
        case .save: unresolved = now.entries
        case .discard: unresolved = uncovered(in: now)
        }
        return unresolved.isEmpty ? .close : .keepOpen(unresolved: unresolved)
    }

    // MARK: The words

    /// One note per distinct (vault, path), in the order the entries first name it. A note open
    /// in both columns is one note (§D2: N counts notes, not tabs); it is conflicted when any of
    /// its tabs is. The same relative path in two vaults is two notes: a previous vault's
    /// `Nexion.md` is not the open vault's.
    struct Note: Equatable, Sendable {
        let relativePath: String
        let title: String
        let previousVaultRoot: URL?
        var isConflicted: Bool
        var isFromPreviousVault: Bool

        fileprivate func isSameNote(as other: Note) -> Bool {
            relativePath == other.relativePath && previousVaultRoot?.vaultKey == other.previousVaultRoot?.vaultKey
        }
    }

    var notes: [Note] {
        var result: [Note] = []
        for entry in entries {
            if let index = result.firstIndex(where: {
                $0.relativePath == entry.relativePath
                    && $0.previousVaultRoot?.vaultKey == entry.previousVaultRoot?.vaultKey
            }) {
                result[index].isConflicted = result[index].isConflicted || entry.isConflicted
                result[index].isFromPreviousVault =
                    result[index].isFromPreviousVault || entry.isFromPreviousVault
            } else {
                result.append(
                    Note(
                        relativePath: entry.relativePath, title: entry.title,
                        previousVaultRoot: entry.previousVaultRoot,
                        isConflicted: entry.isConflicted, isFromPreviousVault: entry.isFromPreviousVault
                    )
                )
            }
        }
        return result
    }

    /// How a note is named in the question: its title, or its path when another note in the
    /// question has the same title; a previous vault's copy of a path the question also names
    /// for another vault carries its folder's name too, so the two lines are told apart.
    static func displayName(of note: Note, among notes: [Note]) -> String {
        let others = notes.filter { !$0.isSameNote(as: note) }
        let sharesPath = others.contains { $0.relativePath == note.relativePath }
        if sharesPath {
            guard let root = note.previousVaultRoot else { return note.relativePath }
            return "\(note.relativePath) (\(root.lastPathComponent))"
        }
        let sharesTitle = others.contains { $0.title == note.title }
        return sharesTitle ? note.relativePath : note.title
    }

    /// What the question is asked before: quitting (ADR-0073), another notes folder replacing
    /// the open one (PG-334), or «Chiudi la colonna» (PG-335). Same review, same answers,
    /// different words.
    enum Occasion: Equatable, Sendable {
        case quit, vaultSwitch, columnClose
    }

    /// The quit's words.
    var copy: Copy { copy(for: .quit) }

    /// The items are named in `firstReveal(board:notes:diary:schede:namingTab:)`'s order - the
    /// board, the notes, the diary, the schede (ADR-0089 §D6) - in the list and in the sentences
    /// alike, so a cancel shows the item the question named first.
    func copy(for occasion: Occasion) -> Copy {
        let notes = notes
        let noteNames = notes.map { Self.displayName(of: $0, among: notes) }
        let lines = [board?.listLine].compactMap { $0 } + noteNames.map { "«\($0)»" }
            + [diary?.listLine].compactMap { $0 } + schede.map { "«\($0.name)»" }
        let words = Self.words(for: occasion)
        let before = words.before
        let losing = words.losing
        let staying = words.staying
        var paragraphs: [String] = []
        let message: String
        let saveLabel: String
        if lines.count == 1, let line = lines.first {
            let phrase = board?.singularPhrase ?? diary?.singularPhrase ?? "a \(line)"
            message = "Salvare le modifiche \(phrase) \(before)"
            saveLabel = "Salva"
        } else {
            let counts = Self.counted(
                boards: board == nil ? 0 : 1, notes: notes.count, diaries: diary == nil ? 0 : 1,
                schede: schede.count
            )
            message = "Salvare le modifiche a \(counts) \(before)"
            saveLabel = "Salva tutto"
            var listed = Array(lines.prefix(Self.listedTitleLimit))
            if lines.count > Self.listedTitleLimit {
                listed.append("e altre \(lines.count - Self.listedTitleLimit)")
            }
            paragraphs.append(listed.joined(separator: "\n"))
        }
        paragraphs.append(losing)
        paragraphs += sentences(noteNames: noteNames, saveLabel: saveLabel, staying: staying)
        return Copy(
            message: message,
            informative: paragraphs.joined(separator: "\n\n"),
            saveLabel: saveLabel,
            discardLabel: "Non salvare",
            cancelLabel: "Annulla"
        )
    }

    /// One sentence per item that needs one, in the items' order: the board, the conflicted and
    /// the foreign notes, the diary, the schede.
    private func sentences(noteNames: [String], saveLabel: String, staying: String) -> [String] {
        let notes = notes
        var result: [String] = []
        if let board { result.append(board.sentence(saveLabel: saveLabel, staying: staying)) }
        for (note, name) in zip(notes, noteNames) where note.isConflicted {
            result.append(
                "«\(name)» è cambiata anche su disco: "
                    + "\(staying) per farti scegliere quale versione tenere."
            )
        }
        for (note, name) in zip(notes, noteNames) where note.isFromPreviousVault {
            result.append(
                "«\(name)» è di una cartella note aperta prima e non viene salvata in questa: "
                    + "\(staying) se scegli di salvare."
            )
        }
        if let diary { result.append(diary.sentence(saveLabel: saveLabel, staying: staying)) }
        for (scheda, name) in zip(schede, schede.map(\.name)) {
            result.append(Self.sentence(for: scheda, named: name, saveLabel: saveLabel))
        }
        return result
    }

    /// Why a scheda's edit is in the question: its file is gone (PG-341), or its write failed
    /// and «Salva» tries it again (PG-373).
    private static func sentence(for scheda: Scheda, named name: String, saveLabel: String) -> String {
        switch scheda.problem {
        case .gone:
            "La scheda «\(name)» non è più al suo posto e la sua modifica non può essere salvata: "
                + "«Non salvare» la scarta."
        case .writeFailed:
            "La modifica alla scheda «\(name)» non si è potuta salvare: "
                + "«\(saveLabel)» riprova, «Non salvare» la scarta."
        }
    }

    /// What changes with the occasion: what the question is asked before, what not saving
    /// loses, and what stays open while a conflict or a foreign tab waits.
    private struct Words {
        let before: String
        let losing: String
        let staying: String
    }

    private static func words(for occasion: Occasion) -> Words {
        switch occasion {
        case .quit:
            Words(
                before: "prima di uscire?",
                losing: "Uscendo senza salvare, le modifiche vanno perse.",
                staying: "Pergamenum resta aperto"
            )
        case .vaultSwitch:
            Words(
                before: "prima di aprire un'altra cartella note?",
                losing: "Aprendo un'altra cartella note senza salvare, le modifiche vanno perse.",
                staying: "La cartella note resta aperta"
            )
        case .columnClose:
            Words(
                before: "prima di chiudere la colonna?",
                losing: "Chiudendo la colonna senza salvare, le modifiche vanno perse.",
                staying: "La colonna resta aperta"
            )
        }
    }

    /// «3 note», «2 schede», «1 nota e 1 scheda», «1 board, 2 note e 1 diario»: what the question
    /// counts when it names more than one thing, in the items' order (ADR-0089 §D3).
    private static func counted(boards: Int, notes: Int, diaries: Int, schede: Int) -> String {
        let parts = [
            boards > 0 ? "\(boards) board" : nil,
            notes > 0 ? "\(notes) \(notes == 1 ? "nota" : "note")" : nil,
            diaries > 0 ? "\(diaries) \(diaries == 1 ? "diario" : "diari")" : nil,
            schede > 0 ? "\(schede) \(schede == 1 ? "scheda" : "schede")" : nil,
        ].compactMap { $0 }
        guard parts.count > 1, let last = parts.last else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " e " + last
    }
}
