import Foundation

/// What a person answers when quitting, or switching vault, would drop unsaved note tabs
/// (PG-326, #693, ADR-0073 §D2). Foundation only: the alert that shows it is AppKit and lives
/// in its own file, so this stays unit-testable.
enum UnsavedNotesChoice: Equatable, Sendable {
    case saveAll, discard, cancel
}

/// The question, as data: which notes are unsaved and how the alert words it.
struct UnsavedNotesPrompt: Equatable, Sendable {
    /// At most this many titles are listed; the rest are counted ("e altre K").
    static let listedTitleLimit = 8

    /// Every unsaved note's title, one per note, in first-appearance order. All of them, not
    /// the capped list: `message` counts from here, and the cap is a matter of display only
    /// (`listedTitles`).
    let titles: [String]

    /// Nil when no tab is dirty: there is nothing to ask.
    ///
    /// Counts **notes, not tabs** (ADR-0073 §D2): two tabs on one path are one note with
    /// unsaved changes, and listing it twice would read as two.
    init?(tabs: [NoteTab]) {
        var seen = Set<String>()
        let titles = tabs
            .filter { seen.insert($0.note.relativePath).inserted }
            .map(\.note.title)
        guard !titles.isEmpty else { return nil }
        self.titles = titles
    }

    /// The alert's headline. The singular and the plural are part of the contract.
    var message: String {
        titles.count == 1
            ? "C'è una nota con modifiche non salvate"
            : "Ci sono \(titles.count) note con modifiche non salvate"
    }

    /// The titles, then what happens to edits nobody saves.
    var informativeText: String {
        listedTitles + "\n\nSe non le salvi, le modifiche andranno perse."
    }

    /// One title per line, at most `listedTitleLimit` of them, then how many more. Shared by
    /// the question and by the report that follows a failed save, so the two list alike.
    var listedTitles: String {
        let listed = titles.prefix(Self.listedTitleLimit).map { "«\($0)»" }
        let more = titles.count - listed.count
        switch more {
        case ..<1: return listed.joined(separator: "\n")
        case 1: return (listed + ["e un'altra"]).joined(separator: "\n")
        default: return (listed + ["e altre \(more)"]).joined(separator: "\n")
        }
    }
}

/// How the app asks and reports, injected so a test can answer without a window.
struct UnsavedNotesPresenter {
    var ask: @MainActor (UnsavedNotesPrompt) -> UnsavedNotesChoice
    var reportUnsaved: @MainActor (UnsavedNotesPrompt?) -> Void
}
