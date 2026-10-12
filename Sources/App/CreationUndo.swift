import Foundation

// PG-387 (N4), ADR-0085 §D9, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 - R-16.

/// The «Nota creata · Annulla» offer made after a pane-host creation, and the decision whether
/// «Annulla» may trash the note. Pure: the controller supplies the clock, the hash and the tab.
enum CreationUndo {
    /// How long the offer lives, in seconds.
    static let window: TimeInterval = 10

    struct Offer: Equatable, Sendable {
        let path: String
        let createdHash: String
        let expiresAt: Date
    }

    enum Decision: Equatable, Sendable {
        case trashed
        case expired
        case unsaved
        case changed
        case failed(String)

        /// The sentence the strip shows when «Annulla» refused, nil when it did what was asked
        /// or when the offer had simply ended.
        var sentence: String? {
            switch self {
            case .trashed, .expired: nil
            case .unsaved: "La nota ha modifiche non salvate: non eliminata."
            case .changed: "La nota è cambiata dopo la creazione: non eliminata."
            case .failed(let reason): reason
            }
        }
    }

    /// The offer for a creation that just landed: its path, the hash of the bytes it wrote, and
    /// the end of the window.
    static func offer(for result: VaultSession.WriteResult, at now: Date) -> Offer {
        Offer(
            path: result.path, createdHash: NoteStore.hash(Data(result.text.utf8)),
            expiresAt: now.addingTimeInterval(window)
        )
    }

    /// Whether the offer may still be acted on. `currentHash` is the file's hash now, nil when it
    /// is gone.
    ///
    /// In this order: the window, then the person's unsaved work, then the file - a note written
    /// into since its creation is the person's, not the creation's, and is never trashed by it.
    static func decide(_ offer: Offer, now: Date, currentHash: String?, tabIsDirty: Bool) -> Decision {
        guard now < offer.expiresAt else { return .expired }
        if tabIsDirty { return .unsaved }
        guard let currentHash else { return .failed("La nota non c'è più.") }
        return currentHash == offer.createdHash ? .trashed : .changed
    }
}
