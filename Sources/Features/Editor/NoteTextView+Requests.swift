import AppKit

// The one-shot request bookkeeping `updateNSView` keeps between passes (ADR-0074 §D2).

/// The last focus, scroll and match-jump requests, the last replacement batch, the last note
/// path and the last outline entry, with one claim method per request.
///
/// **Two orders are load-bearing.** Every claim compares first and records second, so a request
/// that repeats is refused. The replacement batch is the exception on purpose: `apply(_:to:)`
/// records it through `recordReplacements(_:)` *before* it validates it (PG-093), so a batch
/// refused for a stale range is still remembered and never replayed.
@MainActor
final class RequestLedger {
    /// Held for ADR-0074 §D3's uniform shape (every controller receives the provider at `init`)
    /// and unused today: every claim takes the value it compares as a parameter, read by its
    /// caller. A future read goes through it at the moment of use.
    private let parent: () -> NoteTextView?

    /// The focus request already honoured, so the cursor is not stolen back on
    /// every subsequent update.
    private(set) var lastFocusRequest = 0
    /// The same, for the index's jumps: without it every later view update would
    /// scroll back to the last heading clicked.
    private(set) var lastScrollRequest = 0
    /// And for the find bar's, which is a location rather than a counter: the stepper
    /// moves between matches and it is arriving at a *different* one that scrolls.
    private(set) var lastMatchLocation: Int?
    /// The replacements batch already applied, so a `updateNSView` pass that runs again
    /// before `onReplacementsApplied()`'s `pendingReplacements = nil` has propagated back
    /// down does not replay the same edits a second time against text they already
    /// changed (PG-093: an Outline nest/move applied twice this way, its second pass
    /// deleting and re-inserting ranges that no longer meant what they meant when
    /// computed, corrupting the note). Compared by value, not identity - two genuinely
    /// distinct requests never compute the same ranges and text, since `OutlineMove`
    /// already refuses a move that would be a no-op.
    private(set) var lastAppliedReplacements: [NSRange] = []
    private(set) var lastAppliedReplacementTexts: [String] = []
    /// The note path `updateNSView` last saw, so it can tell a genuine note switch
    /// apart from the same note's content changing externally (issue #188 fix 2): this
    /// view is one persistent instance per editor column, never rebuilt per note, so
    /// there is no other signal available for "this is a different note now."
    private(set) var lastNotePath: String?
    /// The index entry the caret was last reported to be in. Kept so the callback
    /// fires when it *changes*, not on every arrow key.
    private(set) var lastOutlineEntry: Int??

    init(parent: @escaping () -> NoteTextView?) {
        self.parent = parent
    }

    /// Whether `request` is new; records it when it is.
    func claimFocus(_ request: Int) -> Bool {
        guard request != lastFocusRequest else { return false }
        lastFocusRequest = request
        return true
    }

    func claimScroll(_ request: Int) -> Bool {
        guard request != lastScrollRequest else { return false }
        lastScrollRequest = request
        return true
    }

    /// Consumed by location, so stepping onto a different match scrolls and every other view
    /// update does not. Nil when the bar closes, so reopening on the same match scrolls again.
    func claimMatchJump(to location: Int?) -> Bool {
        guard location != lastMatchLocation else { return false }
        lastMatchLocation = location
        return true
    }

    /// Whether `path` differs from the one last seen - a note switch - recording it either way.
    func claimNotePath(_ path: String?) -> Bool {
        let isNew = path != lastNotePath
        lastNotePath = path
        return isNew
    }

    func claimOutlineEntry(_ entry: Int?) -> Bool {
        guard lastOutlineEntry != .some(entry) else { return false }
        lastOutlineEntry = entry
        return true
    }

    /// Whether this exact batch (by value: same ranges, same replacement text, same order)
    /// is the one `apply(_:to:)` last recorded - see `lastAppliedReplacements`' doc comment.
    func alreadyApplied(_ replacements: [(range: NSRange, text: String)]) -> Bool {
        replacements.map(\.range) == lastAppliedReplacements
            && replacements.map(\.text) == lastAppliedReplacementTexts
    }

    /// Remembers `replacements` as applied. Called by `apply(_:to:)` before it checks a single
    /// range, never after (PG-093).
    func recordReplacements(_ replacements: [(range: NSRange, text: String)]) {
        lastAppliedReplacements = replacements.map(\.range)
        lastAppliedReplacementTexts = replacements.map(\.text)
    }
}
