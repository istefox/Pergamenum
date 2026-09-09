import Foundation
import Observation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-17, R-18; ADR §D17.
//
// The observable facade over the Pratiche pane (SPEC Architecture table). Only the
// two triggers/isolation concerns land here for this task (R-17, R-18); the list,
// timeline and tray state the same table names are Task 6's `PraticaTimelineModel`
// and Task 7's tray/command types.
//
// `DayController`/`RecordingsController`'s shape: dependencies are injected closures
// (`probe`, `performSync`), never a concrete `MailStoreReader` or `VaultSession`, so
// this can be driven with no window and no real Mail store, the same way
// `Tests/RecordingsControllerTests.swift` drives `RecordingsController` with
// `FakePlaudService`.
@MainActor
@Observable
final class PraticheController {
    /// Whether the store was readable at the last probe (R-18). `.granted` at
    /// `init`, from the very first probe - there is no "unknown" state, since the
    /// probe never blocks and is cheap to repeat.
    private(set) var fullDiskAccessState: FullDiskAccessProbe.State

    /// One `PraticaWatcher` per pratica path (R-17): the throttle/debounce state is
    /// per pratica, not shared, since a window-key sync of pratica A must not
    /// silence pratica B's own trigger due within the window.
    private(set) var watchersByPraticaPath: [String: PraticaWatcher] = [:]

    private let probe: () -> FullDiskAccessProbe.State
    private let performSync: (String) async -> Void

    init(
        probe: @escaping () -> FullDiskAccessProbe.State,
        performSync: @escaping (String) async -> Void
    ) {
        self.probe = probe
        self.performSync = performSync
        self.fullDiskAccessState = probe()
    }

    /// Every automatic and manual trigger funnels through here (SPEC "Full Disk
    /// Access": "the probe is repeated per trigger" - R-18's "no restart required").
    /// Re-probes first; a sync only ever runs when the store is readable and
    /// `PraticaWatcher` (R-17's throttle/debounce/eligibility rules) agrees.
    func trigger(
        _ praticaPath: String,
        kind: PraticaWatcher.Trigger,
        eligibility: PraticaWatcher.Eligibility,
        now: Date = Date()
    ) async {
        fullDiskAccessState = probe()
        guard fullDiskAccessState == .granted else { return }

        var watcher = watchersByPraticaPath[praticaPath] ?? PraticaWatcher()
        let shouldSync: Bool
        switch kind {
        case .vaultOpen, .manualRefresh:
            shouldSync = watcher.decideImmediateTrigger(kind, eligibility: eligibility, now: now)
        case .windowKey:
            shouldSync = watcher.decideWindowKeyTrigger(eligibility: eligibility, now: now)
        case .fsEvents:
            watcher.registerFSEventsPulse(now: now)
            shouldSync = watcher.isFSEventsFireDue(now: now)
        }
        watchersByPraticaPath[praticaPath] = watcher

        guard shouldSync else { return }
        await performSync(praticaPath)
    }
}
