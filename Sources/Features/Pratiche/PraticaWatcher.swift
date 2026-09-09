import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-17.
//
// The three automatic triggers (SPEC "Sync algorithm", Architecture table's
// `PraticaWatcher` row) collapse to one pure decision per trigger kind, so a test
// drives the window-key throttle and the FSEvents debounce with an injected `now`
// instead of a real sleep (dispatch REPO FACTS: "take an injectable clock/now so the
// tests do not sleep"). The real FSEvents stream / window-key notification / Timer
// wrapping this in `Sources/Features/Pratiche/PraticheController.swift` is the
// coder's body; this type is the boundary that makes the scheduling rules testable
// without either.
struct PraticaWatcher: Equatable, Sendable {
    /// What caused this check (SPEC "Sync algorithm" + Architecture table).
    enum Trigger: Equatable, Sendable {
        case vaultOpen
        case windowKey
        case fsEvents
        /// «Aggiorna ora» - the one trigger that ignores `Eligibility` entirely
        /// (R-17: "closed pratiche sync only through «Aggiorna ora»").
        case manualRefresh
    }

    /// `status-active`/`status-waiting` are `.automatic`; `status-archived`/
    /// `status-final` are `.manualOnly` - only `.manualRefresh` reaches them (R-17).
    enum Eligibility: Equatable, Sendable {
        case automatic
        case manualOnly
    }

    static let windowKeyThrottle: TimeInterval = 60
    static let fsEventsDebounce: TimeInterval = 10

    private(set) var lastWindowKeySyncAt: Date?
    private(set) var pendingFSEventsFireAt: Date?

    init(lastWindowKeySyncAt: Date? = nil, pendingFSEventsFireAt: Date? = nil) {
        self.lastWindowKeySyncAt = lastWindowKeySyncAt
        self.pendingFSEventsFireAt = pendingFSEventsFireAt
    }

    /// `.vaultOpen` and `.manualRefresh` fire immediately, subject only to
    /// `eligibility` - `.manualRefresh` ignores it altogether (R-17).
    ///
    /// Tester-declared boundary (ADR-0155 §D1), stubbed to the wrong-but-safe
    /// default `true` regardless of input, which is what keeps every red test below
    /// red rather than crashing: the coder's body is the actual eligibility switch.
    func decideImmediateTrigger(_ trigger: Trigger, eligibility: Eligibility, now: Date) -> Bool {
        true
    }

    /// The window-key trigger: an eligible pratica syncs once, then is throttled for
    /// `windowKeyThrottle` seconds (R-17) - `mutating` because a real sync updates
    /// `lastWindowKeySyncAt` so the next call within the window answers `false`.
    ///
    /// Stubbed the same wrong-but-safe way as `decideImmediateTrigger`.
    mutating func decideWindowKeyTrigger(eligibility: Eligibility, now: Date) -> Bool {
        true
    }

    /// Records an FSEvents pulse: the fire time is `now + fsEventsDebounce`, and a
    /// later pulse before that time replaces it rather than adding a second one
    /// (debounce, not throttle) - so a burst of writes to `~/Library/Mail` collapses
    /// into one sync.
    ///
    /// Stubbed as a no-op: `pendingFSEventsFireAt` never actually moves, which is
    /// what keeps `isFSEventsFireDue` red below (nothing is ever scheduled).
    mutating func registerFSEventsPulse(now: Date) {
    }

    /// Whether a previously registered FSEvents pulse's debounce window has elapsed
    /// as of `now` - the caller polls this instead of sleeping for real.
    ///
    /// Stubbed to `false` always, the wrong-but-safe complement of
    /// `registerFSEventsPulse`'s no-op above.
    func isFSEventsFireDue(now: Date) -> Bool {
        false
    }
}
