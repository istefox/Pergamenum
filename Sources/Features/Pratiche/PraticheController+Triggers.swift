import AppKit
import Foundation

extension PraticheController {
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
        await performSync(praticaPath, kind)
    }

    // MARK: - Triggers (R-17), as the running app arms them

    /// Installs the two automatic sources the app can arm without a timer: the window
    /// becoming key, and FSEvents under the Mail store. Idempotent - the pane calls it
    /// every time it appears.
    ///
    /// From the pane and not from `PergamenumApp`'s scene on purpose: nothing reads a
    /// person's mail store until they have gone to Pratiche at least once in this
    /// session, and the plan's budget for `PergamenumApp.swift` is one `@State` plus
    /// two `.environment` injections.
    func startWatching(_ vault: VaultController) {
        if windowKeyObserver == nil {
            windowKeyObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor [weak self] in await self?.syncAll(in: vault, kind: .windowKey) }
            }
        }
        if mailStoreEvents == nil {
            let stream = MailStoreEventStream(root: MailStoreLocation.resolve()) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Records the pulse on every watcher; nothing fires yet, since
                    // `PraticaWatcher` reads the deadline against the same instant.
                    await self.syncAll(in: vault, kind: .fsEvents)
                    self.scheduleFSEventsFire(in: vault)
                }
            }
            stream.start()
            mailStoreEvents = stream
        }
    }

    /// The other half of the FSEvents debounce (R-17). `trigger(_:kind:eligibility:now:)`
    /// only records the pulse and reads `isFSEventsFireDue` against the same `now`, so
    /// something has to come back once `PraticaWatcher.fsEventsDebounce` has elapsed -
    /// before this, no FSEvents pulse ever led to a sync. Every pulse cancels the
    /// previous task, which is what makes a burst of Mail writes one sync rather than
    /// ten.
    private func scheduleFSEventsFire(in vault: VaultController) {
        fsEventsFireTask?.cancel()
        fsEventsFireTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PraticaWatcher.fsEventsDebounce))
            guard !Task.isCancelled, let self else { return }
            await self.fireDueFSEventsPulses(in: vault)
        }
    }

    /// Syncs every pratica whose recorded pulse has come due as of `now`, consuming the
    /// pulse so a later check waits for a new one. `now` is injectable for the same
    /// reason `trigger`'s is: the tests do not sleep.
    func fireDueFSEventsPulses(in vault: VaultController, now: Date = Date()) async {
        fullDiskAccessState = probe()
        guard fullDiskAccessState == .granted else { return }
        var fired = false
        for pratica in pratiche {
            // R-17 read at fire time, not from what the watcher was last told, and not
            // from `pratica` as captured by this loop's own enumeration either: that
            // snapshot was taken once, before this function's first `await`, so an
            // earlier iteration's `await performSync` can let another MainActor task
            // close a LATER pratica in between - re-read its CURRENT status from
            // `self.pratiche` right before deciding, or that later iteration would
            // still see it as open and sync it automatically.
            guard let current = pratiche.first(where: { $0.id == pratica.id }) else { continue }
            guard var watcher = watchersByPraticaPath[current.id] else { continue }
            let eligibility = Self.eligibility(of: current)
            watcher.refreshEligibility(eligibility)
            guard eligibility == .automatic, watcher.isFSEventsFireDue(now: now) else {
                watchersByPraticaPath[current.id] = watcher
                continue
            }
            watcher.consumeFSEventsPulse()
            watchersByPraticaPath[current.id] = watcher
            fired = true
            await performSync(current.id, .fsEvents)
        }
        if fired { load(from: vault) }
    }

    /// One pass over every pratica, each with its own eligibility (R-17): the closed
    /// ones are told `.manualOnly`, which is also what teaches their watcher to refuse
    /// a later FSEvents pulse.
    func syncAll(in vault: VaultController, kind: PraticaWatcher.Trigger) async {
        for pratica in pratiche {
            await trigger(pratica.id, kind: kind, eligibility: Self.eligibility(of: pratica))
        }
        load(from: vault)
    }

    /// «Aggiorna ora» - the one path a closed pratica syncs through (R-17).
    func refreshNow(_ praticaPath: String, in vault: VaultController) async {
        let eligibility = pratiche.first { $0.id == praticaPath }.map(Self.eligibility(of:)) ?? .automatic
        await trigger(praticaPath, kind: .manualRefresh, eligibility: eligibility)
        load(from: vault)
    }

    static func eligibility(of pratica: PraticaListItem) -> PraticaWatcher.Eligibility {
        PraticheSidebarGrouping.isClosed(status: pratica.status) ? .manualOnly : .automatic
    }
}
