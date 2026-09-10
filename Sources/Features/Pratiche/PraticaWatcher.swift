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

    /// The last `Eligibility` this watcher was told, and the whole of how R-17's
    /// closed-pratica rule reaches the FSEvents path.
    ///
    /// Neither `registerFSEventsPulse(now:)` nor `isFSEventsFireDue(now:)` takes an
    /// `Eligibility` - a pulse is a fact about `~/Library/Mail`, not about one
    /// pratica's status - so the status has to be remembered from the triggers that do
    /// carry it. `PraticheController.trigger(_:kind:eligibility:now:)` passes one on
    /// every `.vaultOpen`/`.windowKey`/`.manualRefresh`, and the controller's vault-open
    /// pass reaches **every** pratica, closed ones included, so a watcher has been told
    /// its pratica's status before any pulse can be observed in the running app.
    ///
    /// `.automatic` until told otherwise: a watcher exists for a pratica the app is
    /// watching, and defaulting the other way would silence the ordinary case for a
    /// caller that reached the FSEvents path first.
    private var lastKnownEligibility: Eligibility = .automatic

    init(lastWindowKeySyncAt: Date? = nil, pendingFSEventsFireAt: Date? = nil) {
        self.lastWindowKeySyncAt = lastWindowKeySyncAt
        self.pendingFSEventsFireAt = pendingFSEventsFireAt
    }

    /// `.vaultOpen` and `.manualRefresh` fire immediately, subject only to
    /// `eligibility` - `.manualRefresh` ignores it altogether (R-17).
    ///
    /// Non-`mutating` by the tester's signature, so this one records nothing: the
    /// eligibility a later FSEvents pulse reads comes from `decideWindowKeyTrigger`
    /// and from `PraticheController`'s own vault-open pass over every pratica.
    func decideImmediateTrigger(_ trigger: Trigger, eligibility: Eligibility, now: Date) -> Bool {
        // «Aggiorna ora» is the one escape hatch a closed pratica has (R-17): it
        // answers `true` whatever the status says.
        guard trigger != .manualRefresh else { return true }
        return eligibility == .automatic
    }

    /// The window-key trigger: an eligible pratica syncs once, then is throttled for
    /// `windowKeyThrottle` seconds (R-17) - `mutating` because a real sync updates
    /// `lastWindowKeySyncAt` so the next call within the window answers `false`.
    ///
    /// Only a call that actually fires moves the mark. Recording a throttled call too
    /// would slide the window forward on every window activation, and a person moving
    /// between apps would never reach a sync at all.
    mutating func decideWindowKeyTrigger(eligibility: Eligibility, now: Date) -> Bool {
        lastKnownEligibility = eligibility
        guard eligibility == .automatic else { return false }
        if let last = lastWindowKeySyncAt, now.timeIntervalSince(last) < Self.windowKeyThrottle {
            return false
        }
        lastWindowKeySyncAt = now
        return true
    }

    /// Records an FSEvents pulse: the fire time is `now + fsEventsDebounce`, and a
    /// later pulse before that time replaces it rather than adding a second one
    /// (debounce, not throttle) - so a burst of writes to `~/Library/Mail` collapses
    /// into one sync.
    ///
    mutating func registerFSEventsPulse(now: Date) {
        pendingFSEventsFireAt = now.addingTimeInterval(Self.fsEventsDebounce)
    }

    /// Whether a previously registered FSEvents pulse's debounce window has elapsed
    /// as of `now` - the caller polls this instead of sleeping for real.
    ///
    /// The eligibility gate sits here and not in `registerFSEventsPulse` on purpose:
    /// a pulse recorded before the pratica's status was known must still refuse to
    /// fire once it is known (R-17), while the pulse itself stays a true fact about
    /// the mail store either way.
    func isFSEventsFireDue(now: Date) -> Bool {
        guard lastKnownEligibility == .automatic, let fireAt = pendingFSEventsFireAt else {
            return false
        }
        return now >= fireAt
    }

    /// Clears the pulse once its sync has run, so `isFSEventsFireDue` waits for a new
    /// pulse rather than answering `true` at every later check.
    mutating func consumeFSEventsPulse() {
        pendingFSEventsFireAt = nil
    }

    /// Updates the cached eligibility `isFSEventsFireDue` gates on, from a caller that
    /// already has the live truth (`PraticheController.fireDueFSEventsPulses`, reading
    /// `Self.eligibility(of:)` fresh every fire check). Without this, a pratica closed
    /// then reopened stays stuck refusing FSEvents pulses forever: nothing besides
    /// `decideWindowKeyTrigger` ever moves `lastKnownEligibility`, and a window-key
    /// trigger is not guaranteed to land between the reopen and the next pulse.
    mutating func refreshEligibility(_ eligibility: Eligibility) {
        lastKnownEligibility = eligibility
    }
}
