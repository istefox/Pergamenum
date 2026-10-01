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

    init(columns: [EditorColumn]) {
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

    var isEmpty: Bool { entries.isEmpty }

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

    /// What the question is asked before: quitting (ADR-0073), or another notes folder
    /// replacing the open one (PG-334). Same review, same answers, different words.
    enum Occasion: Equatable, Sendable {
        case quit, vaultSwitch
    }

    /// The quit's words.
    var copy: Copy { copy(for: .quit) }

    func copy(for occasion: Occasion) -> Copy {
        let notes = notes
        let names = notes.map { Self.displayName(of: $0, among: notes) }
        let before: String
        let losing: String
        let staying: String
        switch occasion {
        case .quit:
            before = "prima di uscire?"
            losing = "Uscendo senza salvare, le modifiche vanno perse."
            staying = "Pergamenum resta aperto"
        case .vaultSwitch:
            before = "prima di aprire un'altra cartella note?"
            losing = "Aprendo un'altra cartella note senza salvare, le modifiche vanno perse."
            staying = "La cartella note resta aperta"
        }
        var paragraphs: [String] = []
        let message: String
        let saveLabel: String
        if notes.count == 1, let name = names.first {
            message = "Salvare le modifiche a «\(name)» \(before)"
            saveLabel = "Salva"
        } else {
            message = "Salvare le modifiche a \(notes.count) note \(before)"
            saveLabel = "Salva tutto"
            var listed = names.prefix(Self.listedTitleLimit).map { "«\($0)»" }
            if names.count > Self.listedTitleLimit {
                listed.append("e altre \(names.count - Self.listedTitleLimit)")
            }
            paragraphs.append(listed.joined(separator: "\n"))
        }
        paragraphs.append(losing)
        for (note, name) in zip(notes, names) where note.isConflicted {
            paragraphs.append(
                "«\(name)» è cambiata anche su disco: "
                    + "\(staying) per farti scegliere quale versione tenere."
            )
        }
        for (note, name) in zip(notes, names) where note.isFromPreviousVault {
            paragraphs.append(
                "«\(name)» è di una cartella note aperta prima e non viene salvata in questa: "
                    + "\(staying) se scegli di salvare."
            )
        }
        return Copy(
            message: message,
            informative: paragraphs.joined(separator: "\n\n"),
            saveLabel: saveLabel,
            discardLabel: "Non salvare",
            cancelLabel: "Annulla"
        )
    }
}
