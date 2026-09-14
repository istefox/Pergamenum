import AppKit
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
    private let performSync: (String, PraticaWatcher.Trigger) async -> Void

    init(
        probe: @escaping () -> FullDiskAccessProbe.State,
        performSync: @escaping (String, PraticaWatcher.Trigger) async -> Void
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
        await performSync(praticaPath, kind)
    }

    // MARK: - What the pane shows (Task 6: R-23, R-24, R-26, R-32, R-33)

    /// Every pratica of the open vault, as the list column needs it. Rebuilt from the
    /// index by `load(from:)`, never held across a vault change.
    private(set) var pratiche: [PraticaListItem] = []

    /// The chosen pratica's folder path, which is also its list row's `.tag`.
    private(set) var selection: String?

    /// The chosen pratica's rows, oldest first (R-23) - already through
    /// `PraticaTimelineModel.ordered`, so the view scrolls to the end for the newest.
    private(set) var timeline: [PraticaTimelineEntry] = []

    /// What a row needs beyond `PraticaTimelineEntry` to draw itself expanded: the
    /// markdown body, the quoted history, the attachments and the pending flag.
    ///
    /// A side table rather than more fields on the entry: `PraticaTimelineEntry` is
    /// the tester-declared shape the ordering, filtering and lane rules are written
    /// against (ADR-0155), and widening it to carry a file's whole body would make
    /// every one of those pure functions carry a payload none of them reads.
    private(set) var details: [String: PraticaRowDetail] = [:]

    /// The three toolbar filters (R-32).
    var filter = PraticaTimelineFilter()

    /// Per window and never persisted (R-24). Here rather than as the timeline view's
    /// own `@State` because the expansion has to survive the view being rebuilt when
    /// the filter changes, and because Opt+click needs every visible id at once.
    var expansion = PraticaTimelineModel.ExpansionState()

    /// The pratica a sync is running for, and how far it has got (R-20's progress bar,
    /// screen 1a's «12 di 80 · Annulla»).
    private(set) var syncingPraticaPath: String?
    private(set) var syncProgress: PraticaSyncEngine.Progress?

    /// The last thing that went wrong, in Italian, for the pane to show. Cleared by
    /// the next successful load - a stale error over a working pane is worse than none.
    private(set) var problem: String?

    /// The per-vault ledger (`…/vaults/<id>/pratiche/ledger.json`, SPEC "Per-vault
    /// state"): `lastOpenedAt` is what the badge counts from, `importedMessageIDs`
    /// what a resumed sync skips.
    private(set) var ledger: PraticaLedger = .empty

    /// How many tray proposals each pratica has, which is the dot on its row (R-33).
    /// Derived from `trayProposals` by `updateTray(_:for:in:)`; empty here means no
    /// dot, never a wrong one.
    var trayCounts: [String: Int] = [:]

    /// R-30's «Da smistare» proposals, per pratica, as the last sync of that pratica
    /// found them. Held per pratica rather than for the selection alone so the dot on
    /// a row that is not open stays right (R-33).
    private(set) var trayProposals: [String: [PraticaTrayModel.PraticaTrayProposal]] = [:]

    /// The timeline row with key focus - what Backspace («Escludi») and the row
    /// commands act on. Per window like `expansion`, never persisted.
    var selectedEntryID: String?

    /// The three requests a command raises that need a surface of their own: a name to
    /// type, a destructive confirmation, and a regeneration to agree to. Held here
    /// rather than as `@State` in a row, which is culled by the `List` the moment it
    /// scrolls out of view - taking the half-typed name with it.
    var renameRequest: PraticaListItem?
    /// R-34's «Elimina pratica», the one alert in the whole feature.
    var deletionRequest: PraticaListItem?

    /// ADR §D21: one value that carries «acquiring the replacement» and «ready to show
    /// a diff» rather than two variables kept in sync (ADR-0024 §D2's rule) - the
    /// replacement for the old two-step `PraticaRegenerationRequest` confirmation.
    enum RegenerationState: Identifiable, Sendable {
        case preparing(notePath: String, subject: String)
        case ready(PraticaSyncEngine.RegenerationPlan)

        var id: String {
            switch self {
            case .preparing(let notePath, _): notePath
            case .ready(let plan): plan.id
            }
        }
    }

    /// «Rigenera…» set by `PraticaCommandActions.requestRegeneration` to `.preparing`,
    /// then to `.ready` once `prepareRegeneration` below resolves the diff - `nil`
    /// dismisses the sheet at any point.
    var regeneration: RegenerationState?

    /// §D21.1/§D21.3: acquires the replacement text and diffs it against what is on
    /// disk, without trashing or writing anything - wired by `PraticheController.live`
    /// to `PraticaLiveSync.prepareRegeneration`. `nil` means nothing is wired (a
    /// preview/test controller), and the sheet never opens.
    @ObservationIgnored var prepareRegeneration: (@MainActor (_ praticaPath: String, _ messageID: String) async -> Void)?

    /// §D21.2: commits an already-previewed `RegenerationPlan` and records the
    /// outcome in the ledger, answering whether it succeeded - wired by
    /// `PraticheController.live` to `PraticaLiveSync.commitRegeneration`.
    @ObservationIgnored var commitRegeneration: (@MainActor (_ plan: PraticaSyncEngine.RegenerationPlan) async -> Bool)?

    /// R-30: the strip a person collapsed stays collapsed until they open it again,
    /// for this window only.
    var isTrayCollapsed = false

    /// The chosen pratica's own proposals (R-30).
    var selectedTray: [PraticaTrayModel.PraticaTrayProposal] {
        guard let selection else { return [] }
        return trayProposals[selection] ?? []
    }

    /// What a finished sync found waiting for this pratica (R-30). Also refreshes the
    /// list, since the dot on a row is one of these counts.
    func updateTray(
        _ proposals: [PraticaTrayModel.PraticaTrayProposal],
        for praticaPath: String,
        in vault: VaultController
    ) {
        trayProposals[praticaPath] = proposals
        trayCounts[praticaPath] = proposals.count
        persistTrayCount(proposals.count, for: praticaPath, in: vault)
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
    }

    /// Writes the tray's own count into the ledger (`PraticaLedger.PraticaState.
    /// trayCount`, Task 9's widening).
    ///
    /// `trayCounts` alone lives for as long as this window does, and R-36 forbids
    /// `VaultAPI.pratiche(_:)` from opening the Mail store to recount: without this
    /// line a re-launched `perg`/`pergamenum-mcp` could only ever answer `0`, which
    /// reads as «niente da smistare» rather than as «nessuno ha ancora guardato».
    ///
    /// Skipped when nothing changed, so a sync that finds the same proposals again
    /// does not rewrite the file - and, for a pratica with no tray and no ledger entry
    /// yet, does not create one to say zero.
    private func persistTrayCount(_ count: Int, for praticaPath: String, in vault: VaultController) {
        guard let session = vault.session else { return }
        var state = ledger.byPraticaPath[praticaPath] ?? .empty
        guard state.trayCount != count else { return }
        state.trayCount = count
        ledger.byPraticaPath[praticaPath] = state
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    /// «Aggiungi» and «Ignora» both take the row off the strip at once: the write that
    /// makes it stay away has already happened, and a row that lingers until the next
    /// sync reads as a button that did nothing.
    func dismissTrayProposal(_ conversationID: Int, for praticaPath: String, in vault: VaultController) {
        let remaining = (trayProposals[praticaPath] ?? []).filter { $0.conversationID != conversationID }
        updateTray(remaining, for: praticaPath, in: vault)
    }

    /// `pratica.md`, `email/`, `allegati/` - the three names the sync engine already
    /// writes to (`PraticaSyncEngine`), spelled once on this side too.
    ///
    /// `nonisolated`: these are the folder's shape on disk, not observable state, and
    /// the readers below run off the main actor.
    nonisolated static let praticaFileName = "pratica.md"
    nonisolated static let messagesDirectoryName = "email"
    nonisolated static let attachmentsDirectoryName = "allegati"
    /// SPEC "Per-vault state": `…/vaults/<id>/pratiche/ledger.json`. Read from
    /// `PraticaLedger` rather than spelled again here: `VaultAPI.pratiche(_:)` resolves
    /// the same file from `Sources/Connector`, which cannot see this type at all.
    nonisolated static let stateDirectoryName = PraticaLedger.stateDirectoryName
    nonisolated static let ledgerFileName = PraticaLedger.fileName

    @ObservationIgnored private var mailStoreEvents: MailStoreEventStream?
    @ObservationIgnored private var windowKeyObserver: (any NSObjectProtocol)?
    /// The pending half of the FSEvents debounce: one task per burst, replaced by
    /// every new pulse (see `scheduleFSEventsFire(in:)`).
    @ObservationIgnored private var fsEventsFireTask: Task<Void, Never>?

    /// «Annulla» on the progress bar (R-11): filled by `live(vault:)` with the running
    /// engine's own cooperative `cancel()`, which takes effect at the next message
    /// boundary and never mid-write.
    ///
    /// A settable property rather than a third `init` parameter: `init(probe:
    /// performSync:)` is the tester-declared signature (ADR-0155) and widening it
    /// would break every test that builds this controller. `nil` means nothing is
    /// wired, and the button is disabled rather than lying about stopping a sync.
    @ObservationIgnored var requestSyncCancellation: (@MainActor () -> Void)?

    /// Asks the running sync to stop. The bar stays up until the engine actually
    /// returns - a progress bar that vanishes before the last write finished would
    /// claim a cancellation that has not happened yet.
    func cancelSync() {
        requestSyncCancellation?()
    }

    /// The chosen pratica's own list item, for the breadcrumb and the status pill.
    var selectedPratica: PraticaListItem? {
        guard let selection else { return nil }
        return pratiche.first { $0.id == selection }
    }

    /// The timeline as the filters leave it (R-32), still oldest-first.
    var filteredTimeline: [PraticaTimelineEntry] {
        PraticaTimelineModel.filtered(timeline, by: filter)
    }

    /// Every sender address the chosen pratica's messages carry, for the sender menu.
    /// Addresses and not display names: two people share a name far more often than
    /// they share a mailbox.
    var senderAddresses: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for entry in timeline {
            guard let address = details[entry.id]?.senderAddress, !address.isEmpty else { continue }
            if seen.insert(address.lowercased()).inserted { ordered.append(address) }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Reading the vault

    /// Rebuilds the list from the index and re-reads the ledger. Cheap enough to call
    /// from the pane's `.task` and after every sync: it walks the index this app
    /// already keeps, and reads exactly one JSON file.
    func load(from vault: VaultController) {
        guard let session = vault.session else {
            pratiche = []
            timeline = []
            details = [:]
            ledger = .empty
            return
        }
        ledger = PraticaLedger.load(from: Self.ledgerURL(for: session))
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
        if let selection, !pratiche.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        reloadTimeline(from: vault)
    }

    /// Choosing a row: reads its timeline and marks it opened, which is what makes the
    /// badge go out (R-33 - the count is "since `lastOpenedAt`").
    func select(_ praticaPath: String?, in vault: VaultController) {
        selection = praticaPath
        expansion = PraticaTimelineModel.ExpansionState()
        if let praticaPath { markOpened(praticaPath, in: vault) }
        reloadTimeline(from: vault)
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
    }

    func reloadTimeline(from vault: VaultController) {
        guard let selection, let root = vault.root else {
            timeline = []
            details = [:]
            return
        }
        let read = Self.readTimeline(
            praticaPath: selection,
            vaultRoot: root,
            // R-26: which messages have left Mail is ledger state, not something the
            // folder on disk can say - a message deleted from Mail keeps its file.
            notInStore: Set(ledger.byPraticaPath[selection]?.notInStore ?? [])
        )
        timeline = PraticaTimelineModel.ordered(read.entries)
        details = read.details
    }

    private func markOpened(_ praticaPath: String, in vault: VaultController) {
        guard let session = vault.session else { return }
        var state = ledger.byPraticaPath[praticaPath] ?? .empty
        state.lastOpenedAt = Date()
        ledger.byPraticaPath[praticaPath] = state
        // A ledger that will not save costs one badge, not a pratica: reported, never
        // thrown at the person reading their mail.
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
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

    // MARK: - What a running sync reports back

    func beginSync(_ praticaPath: String) {
        syncingPraticaPath = praticaPath
        syncProgress = nil
        problem = nil
    }

    func updateProgress(_ progress: PraticaSyncEngine.Progress) {
        syncProgress = progress
    }

    func endSync() {
        syncingPraticaPath = nil
        syncProgress = nil
    }

    func report(_ message: String) {
        problem = message
    }

    /// Records what a finished sync imported, so the next one resumes instead of
    /// starting over (R-11).
    ///
    /// `isCurrentVault` (`vault.session === session`, decided by the caller - this type
    /// holds no `VaultController` to check it itself) says whether `session` is still
    /// the live vault. When it is not, this reads and rewrites `session`'s OWN ledger
    /// file fresh from disk instead of `self.ledger`: that property tracks whichever
    /// vault is live right now, and merging a stale sync's outcome into a DIFFERENT
    /// vault's in-memory ledger before saving it back under `session`'s own path would
    /// write that other vault's entries into this one's file - a real cross-vault
    /// corruption, not a UI-only glitch.
    func recordSyncOutcome(
        _ outcome: PraticaSyncEngine.SyncOutcome, for praticaPath: String, session: VaultSession,
        isCurrentVault: Bool
    ) {
        let url = Self.ledgerURL(for: session)
        var sessionLedger = isCurrentVault ? ledger : PraticaLedger.load(from: url)
        var state = sessionLedger.byPraticaPath[praticaPath] ?? .empty
        state.lastSyncAt = Date()
        var imported = Set(state.importedMessageIDs)
        imported.formUnion(outcome.importedMessageIDs)
        state.importedMessageIDs = imported.sorted()
        // R-16: what this run found gone from Mail joins what earlier runs found, and
        // what it imported again leaves the list - a message that came back (a mailbox
        // put back, an archive re-indexed) gets its link back with it.
        var gone = Set(state.notInStore)
        gone.formUnion(outcome.noLongerInMail)
        gone.subtract(outcome.importedMessageIDs)
        state.notInStore = gone.sorted()
        // §D23.2: the §D3 bridge, keyed by Message-ID so a regeneration's fresh triple
        // replaces the stale one rather than appending a second - newest wins because
        // Mail renumbers ROWIDs on an index rebuild, and a stale ROWID is worse than
        // none (`forgetImportedMessage`'s own reason). Sorted because `PraticaLedger.save`
        // pretty-prints with `.sortedKeys`, so the file stays diffable by hand.
        var entriesByID = Dictionary(
            state.entries.map { ($0.messageID, $0) }, uniquingKeysWith: { _, new in new }
        )
        for entry in outcome.bridge { entriesByID[entry.messageID] = entry }
        state.entries = entriesByID.values.sorted { $0.messageID < $1.messageID }
        sessionLedger.byPraticaPath[praticaPath] = state
        do {
            try sessionLedger.save(to: url)
        } catch {
            if isCurrentVault {
                problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
            }
        }
        // The observable property is this controller's view of the LIVE vault - never
        // updated on behalf of a vault that is no longer the one open.
        if isCurrentVault {
            ledger = sessionLedger
            // ADR-0040 §D10/§D7.3: what this run's attachment repair pass could not
            // fix - a file it could not trash, a downgrade it could not write. Empty
            // on every healthy run.
            if !outcome.attachmentProblems.isEmpty {
                problem = [problem, outcome.attachmentProblems.joined(separator: "\n")]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            }
        }
    }

    /// «Rinomina» (R-34) moves the folder, and the ledger is keyed by the folder's
    /// path: without this the renamed pratica reads as one nobody has ever synced,
    /// and the next sync re-imports every message it already has on disk.
    ///
    /// The tray counts travel too, or the dot on the row goes out for no reason a
    /// person could name (R-33).
    func moveLedgerState(from oldPath: String, to newPath: String, in vault: VaultController) {
        guard oldPath != newPath else { return }
        if let state = ledger.byPraticaPath.removeValue(forKey: oldPath) {
            ledger.byPraticaPath[newPath] = state
        }
        if let proposals = trayProposals.removeValue(forKey: oldPath) {
            trayProposals[newPath] = proposals
        }
        if let count = trayCounts.removeValue(forKey: oldPath) {
            trayCounts[newPath] = count
        }
        if selection == oldPath { selection = newPath }
        guard let session = vault.session else { return }
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    /// §D23.4: Mail renumbered a followed conversation Mail's own way (a new
    /// `conversation_id` recovered from a member `Message-ID`'s still-known row) - the
    /// ledger's own triples have to be repointed too, or the next sync's
    /// `memberMessageIDs(forConversation:)` answers nothing for the new id and the
    /// pratica silently loses its recovery data one renumbering later.
    ///
    /// Declared here (ADR-0155 §D1); the coder wires the body (§D23.4's repointing,
    /// called from `PraticaLiveSync.runExclusive` before candidates are evaluated).
    func remapLedgerConversations(_ remap: [Int: Int], of praticaPath: String, in vault: VaultController) {
        guard !remap.isEmpty, var state = ledger.byPraticaPath[praticaPath] else { return }
        state.entries = state.entries.map { entry in
            guard let newID = remap[entry.conversationID] else { return entry }
            return PraticaLedger.Entry(
                messageID: entry.messageID, rowID: entry.rowID, conversationID: newID
            )
        }
        ledger.byPraticaPath[praticaPath] = state
        guard let session = vault.session else { return }
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    // MARK: - Paths

    static func ledgerURL(for session: VaultSession) -> URL {
        stateDirectory(for: session).appending(path: ledgerFileName, directoryHint: .notDirectory)
    }

    /// `…/vaults/<id>/pratiche/` - the copy of the Envelope Index and the ledger both
    /// live here (SPEC "Per-vault state"), never inside the vault.
    static func stateDirectory(for session: VaultSession) -> URL {
        session.state.directory.appending(path: stateDirectoryName, directoryHint: .isDirectory)
    }
}

/// What a timeline row needs beyond `PraticaTimelineEntry` (see `details`).
struct PraticaRowDetail: Equatable, Sendable {
    /// The file this row was read from, vault-relative - `email/<name>.md` for a
    /// message, `pratica.md` for a manual entry (which is one heading of it, ADR §D5).
    var notePath: String
    /// The markdown an expanded row renders through `MarkdownBlocksView` (R-27).
    var body: String
    /// The `<details>` block's own text, drawn under «Testo citato» when there is one.
    var quotedHistory: String?
    var signature: String?
    var attachments: [PraticaAttachmentRef]
    /// Over-threshold attachments, recorded rather than copied (R-10): a chip with no
    /// local file behind it.
    var storeReferences: [MessageDocument.StoreReference]
    /// `pergamenum-mail-body: pending` - the body has not been downloaded by Mail yet
    /// (R-15). The row dims and offers «Apri in Mail» instead of a body.
    var isPending: Bool
    var senderAddress: String?
    /// Attachment entries still waiting for their bytes (ADR-0040 §D8, R-08): the bare
    /// name, as `MessageDocument.MailFrontmatter.pendingAttachmentNames` reads it back -
    /// a chip with no file and no store path behind it at all. Declared last so every
    /// existing call site (which lists `attachments:` through `senderAddress:`
    /// positionally or by keyword) keeps compiling unchanged.
    var pendingAttachments: [String] = []
}

/// One attachment chip's file (R-10). `url` is absolute and may not exist: a copy that
/// failed leaves the wikilink in the message file, and a chip that says so is better
/// than a row that silently drops it.
struct PraticaAttachmentRef: Equatable, Sendable, Identifiable {
    var name: String
    var url: URL

    var id: String { name }
}

// MARK: - Reading the vault (pure, no `@MainActor` state)

extension PraticheController {
    struct TimelineRead: Sendable {
        var entries: [PraticaTimelineEntry]
        var details: [String: PraticaRowDetail]
    }

    /// Every pratica of the open vault: a folder holding a `pratica.md` whose
    /// frontmatter carries a readable `pergamenum-dossier` (R-01). The dossier and not
    /// the file name alone - a note called `pratica.md` that somebody wrote by hand is
    /// a note, not a pratica.
    static func listItems(
        in vault: VaultController,
        ledger: PraticaLedger,
        trayCounts: [String: Int],
        rootFolder: String
    ) -> [PraticaListItem] {
        let notes = vault.index.allNotes
        // The index names the candidates, the file decides. Reading the dossier off
        // `frontmatter.foreignKeys` looks equivalent and is not: the cache keeps no
        // `pergamenum-*` key, so every record a scan reused from it - all of them, from
        // the second scan of a vault onward - would answer "not a pratica" and empty
        // this list (`Dossier.parse(praticaFileAt:)`'s own note). Only the handful of
        // paths ending in `pratica.md` are opened, never the whole index.
        let root = vault.root
        let dossierNotes = notes.filter { note in
            guard note.relativePath.hasSuffix("/\(praticaFileName)"), let root else { return false }
            let url = root.appending(path: note.relativePath, directoryHint: .notDirectory)
            return Dossier.parse(praticaFileAt: url) != nil
        }
        let folders = Set(dossierNotes.map { folderPath(ofPraticaNote: $0.relativePath) })

        // One pass over the index rather than one filter per pratica: a vault with
        // thousands of notes and a dozen pratiche would otherwise walk the whole index
        // a dozen times on every load.
        var messagesByFolder: [String: [NoteRecord]] = [:]
        for note in notes {
            guard let separator = note.relativePath.range(of: "/\(messagesDirectoryName)/") else { continue }
            let folder = String(note.relativePath[..<separator.lowerBound])
            guard folders.contains(folder) else { continue }
            messagesByFolder[folder, default: []].append(note)
        }

        return dossierNotes.map { note in
            let folder = folderPath(ofPraticaNote: note.relativePath)
            let messages = messagesByFolder[folder] ?? []
            let lastOpenedAt = ledger.byPraticaPath[folder]?.lastOpenedAt
            return PraticaListItem(
                id: folder,
                title: (folder as NSString).lastPathComponent,
                client: clientName(ofPraticaFolder: folder, rootFolder: rootFolder),
                // The bare suffix, `active` when the note carries no `status-*` at all
                // - a pratica with no status is an open one, not an invisible one.
                status: note.frontmatter.tags.first { $0.namespace == .status }?.value ?? "active",
                lastActivity: max(note.modifiedAt, messages.map(\.modifiedAt).max() ?? .distantPast),
                // Counted on the message files' own write times rather than on their
                // header dates: what «new since you last looked» means here is what
                // arrived in the folder, and the index already knows that without
                // opening a single file. Never opened yet counts nothing - a pratica
                // created five minutes ago would otherwise announce its whole history
                // as unread.
                messagesSinceLastOpen: lastOpenedAt.map { since in
                    messages.filter { $0.modifiedAt > since }.count
                } ?? 0,
                hasNonEmptyTray: (trayCounts[folder] ?? 0) > 0
            )
        }
    }

    /// `01 Progetti/Rossi/Offerta/pratica.md` → `01 Progetti/Rossi/Offerta`.
    static func folderPath(ofPraticaNote relativePath: String) -> String {
        String(relativePath.dropLast(praticaFileName.count + 1))
    }

    /// SPEC "Sidebar": the client is the pratica folder's parent, under the configured
    /// root. A pratica sitting straight in the root has no client folder to take a
    /// name from, and says so rather than borrowing the root's name.
    static func clientName(ofPraticaFolder folder: String, rootFolder: String) -> String {
        let components = folder.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return unnamedClient }
        let parent = components[components.count - 2]
        return parent == rootFolder ? unnamedClient : parent
    }

    /// From `PraticaNaming`, which `Sources/Connector` can see and this file cannot be
    /// seen from: `VaultAPI.pratiche(_:)` says the same words for the same folder.
    static let unnamedClient = PraticaNaming.unnamedClient

    /// Reads one pratica's folder into timeline rows: every `email/*.md` through
    /// `MessageDocument.parse`, plus `pratica.md`'s own manual-entry headings.
    ///
    /// `nonisolated` and taking a `URL` rather than a `VaultController`: it touches no
    /// observable state, so it can move off the main actor the day a pratica gets big
    /// enough to need it.
    ///
    /// `notInStore` (plan Task 7/8's "R-16/R-26 gap left by batch 4", ADR follow-up
    /// "Task 5/6 implementation notes"): the `Message-ID`s
    /// `PraticaLedger.PraticaState.notInStore` records for this pratica, defaulted to
    /// `[]` so every existing call site keeps compiling unchanged. The tester declares
    /// the parameter; `readMessages` below is the RED stub - it still hardcodes
    /// `isInMail: true` and ignores it, so a test that seeds this set and expects
    /// `isInMail == false` fails on the assertion until the coder reads it for real.
    nonisolated static func readTimeline(
        praticaPath: String, vaultRoot: URL, notInStore: Set<String> = []
    ) -> TimelineRead {
        let folder = vaultRoot.appending(path: praticaPath, directoryHint: .isDirectory)
        var read = TimelineRead(entries: [], details: [:])
        readMessages(in: folder, praticaPath: praticaPath, notInStore: notInStore, into: &read)
        readManualEntries(in: folder, praticaPath: praticaPath, into: &read)
        return read
    }

    private nonisolated static func readMessages(
        in folder: URL, praticaPath: String, notInStore: Set<String>, into read: inout TimelineRead
    ) {
        let messages = folder.appending(path: messagesDirectoryName, directoryHint: .isDirectory)
        // ADR-0041 §D2: an attachment entry is a *name* out of a message note's
        // frontmatter, which is generated from an `.emlx` whose file name Apple Mail
        // chose - not trusted input. The boundary is rooted at `allegati/` rather than at
        // the vault, and deliberately so: `<pratica>/allegati/../../../secret.pdf`
        // standardises back to a path *inside* the vault root, so a vault-level check
        // would wave it through while it names a file this pratica does not own.
        let attachments = VaultBoundary(
            root: folder.appending(path: attachmentsDirectoryName, directoryHint: .isDirectory)
        )
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: messages.path(percentEncoded: false)
        )) ?? []

        for name in names.sorted() where name.hasSuffix(".md") {
            let url = messages.appending(path: name, directoryHint: .notDirectory)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let document = MessageDocument.parse(text)
            else { continue }

            let id = "\(praticaPath)/\(messagesDirectoryName)/\(name)"
            let sender = EmailHeaderParser.parseAddress(document.frontmatter.from)
            read.entries.append(PraticaTimelineEntry(
                id: id,
                kind: .message,
                date: PraticaTimelineModel.sortDate(of: document.frontmatter),
                direction: document.frontmatter.direction,
                senderDisplayName: sender?.displayText ?? document.frontmatter.from,
                senderAddress: sender?.address,
                subject: document.frontmatter.subject,
                bodyPreview: firstLine(of: document.newText),
                hasAttachments: !document.frontmatter.attachments.isEmpty
                    || !document.frontmatter.storeReferences.isEmpty,
                messageID: document.frontmatter.messageID,
                // R-16/R-26: the ledger's own outcome, never a locator miss (§D4). A
                // message the sync found gone from the store loses its link and gains
                // «non più in Mail» through
                // `PraticaTimelineModel.subjectLink(messageID:isInMail:)`; its files
                // are untouched, which is the whole of R-16.
                isInMail: !notInStore.contains(document.frontmatter.messageID)
            ))
            read.details[id] = PraticaRowDetail(
                notePath: id,
                body: document.newText,
                quotedHistory: document.quotedHistory,
                signature: document.signature,
                // A name the boundary refuses is omitted from the row rather than failing
                // the whole read: the other attachments, and the message itself, are
                // still worth showing.
                attachments: document.frontmatter.linkedAttachmentNames.compactMap { fileName in
                    guard let url = try? attachments.url(for: fileName) else { return nil }
                    return PraticaAttachmentRef(name: fileName, url: url)
                },
                storeReferences: document.frontmatter.storeReferences,
                isPending: document.frontmatter.body == .pending,
                senderAddress: sender?.address,
                pendingAttachments: document.frontmatter.pendingAttachmentNames
            )
        }
    }

    /// `pratica.md`'s manual entries: `## YYYY-MM-DD HH:MM <Kind> · <Controparte>` and
    /// everything under it up to the next heading (SPEC "Manual entries").
    ///
    /// Read-only here, deliberately: Task 7 owns writing them
    /// (`PraticaEntry.insert(kind:at:in:)`), and this pane never writes a text range
    /// of `pratica.md` - editing goes to the inspector (ADR §D5).
    private nonisolated static func readManualEntries(
        in folder: URL, praticaPath: String, into read: inout TimelineRead
    ) {
        let url = folder.appending(path: praticaFileName, directoryHint: .notDirectory)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let notePath = "\(praticaPath)/\(praticaFileName)"

        var current: (entry: PraticaTimelineEntry, body: [String])?
        // Disambiguates two manual entries whose heading shares the same
        // to-the-minute timestamp (`entryIDFormatter`'s own resolution) - without
        // this, the second overwrote the first's `read.details` entry and SwiftUI saw
        // two rows claiming one identity. The occurrence count is stable across
        // reloads: it is a function of position in the file, exactly like the
        // timestamp it disambiguates.
        var occurrencesByID: [String: Int] = [:]
        func flush() {
            guard let open = current else { return }
            let body = open.body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            var entry = open.entry
            entry.bodyPreview = firstLine(of: body)
            let occurrence = occurrencesByID[entry.id, default: 0]
            occurrencesByID[entry.id] = occurrence + 1
            if occurrence > 0 { entry.id += "-\(occurrence)" }
            read.entries.append(entry)
            read.details[entry.id] = PraticaRowDetail(
                notePath: notePath, body: body, quotedHistory: nil, signature: nil,
                attachments: [], storeReferences: [], isPending: false, senderAddress: nil
            )
            current = nil
        }

        for line in NoteDocument.parse(text).body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                if let heading = parseEntryHeading(line, praticaPath: praticaPath) { current = (heading, []) }
                continue
            }
            current?.body.append(line)
        }
        flush()
    }

    /// `## 2026-06-10 14:06 Telefonata · Mario Rossi`. Anything else under `##` is an
    /// ordinary heading of the note and is left alone.
    private nonisolated static func parseEntryHeading(
        _ line: String, praticaPath: String
    ) -> PraticaTimelineEntry? {
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3, let date = entryHeadingFormatter.date(from: "\(parts[0]) \(parts[1])")
        else { return nil }

        let tail = String(parts[2])
        let kind: PraticaTimelineEntry.Kind = tail.hasPrefix("Telefonata") ? .call : .note
        let counterpart = tail
            .components(separatedBy: " · ")
            .dropFirst()
            .joined(separator: " · ")

        return PraticaTimelineEntry(
            id: "\(praticaPath)#entry-\(entryIDFormatter.string(from: date))",
            kind: kind,
            date: date,
            direction: nil,
            senderDisplayName: counterpart,
            subject: tail,
            bodyPreview: "",
            hasAttachments: false,
            messageID: nil,
            isInMail: true
        )
    }

    /// `[[20260610_offerta.pdf]]` → `20260610_offerta.pdf`, alias form included.
    nonisolated static func attachmentFileName(fromWikilink wikilink: String) -> String {
        var name = wikilink.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[[") { name.removeFirst(2) }
        if name.hasSuffix("]]") { name.removeLast(2) }
        return name.components(separatedBy: "|").first ?? name
    }

    nonisolated static func firstLine(of text: String) -> String {
        text
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The dossier of one pratica, read from disk rather than from the index: a sync
    /// must act on the file as it is now, not as the last scan saw it.
    static func dossier(at praticaPath: String, vaultRoot: URL) -> Dossier? {
        Dossier.parse(praticaFileAt: vaultRoot
            .appending(path: praticaPath, directoryHint: .isDirectory)
            .appending(path: praticaFileName, directoryHint: .notDirectory))
    }

    /// `en_US_POSIX`, GMT and a fixed pattern: the heading is a file format, not a
    /// presentation, and a person whose Mac is set to another locale still has to be
    /// able to read their own pratica in Obsidian.
    ///
    /// The time zone matches `PraticaEntry.headingFormatter`'s, and has to: that is the
    /// formatter that *writes* the heading this one reads back, and a zone difference
    /// between them would shift every manual entry by the machine's own offset
    /// (`Tests/PraticaEntryTests.swift` pins the pattern and the locale of the pair).
    private nonisolated static let entryHeadingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// The timestamp the row's accessibility identifier carries
    /// (`pratiche-entry-<timestamp>`, UX-BLUEPRINT's checklist).
    ///
    /// GMT beside the two heading formatters above, and for the same reason: the id is
    /// derived from a heading's own digits, so a zone difference would give one entry
    /// two identifiers depending on where the Mac is standing.
    nonisolated static let entryIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()
}

// MARK: - The live wiring (`PergamenumApp`'s one `@State`)

extension PraticheController {
    /// The controller the running app holds: the real probe, the real sync engine, and
    /// the two automatic triggers armed by `startWatching(_:)`.
    ///
    /// A coordinator object rather than a closure capturing the controller: the two
    /// dependencies are `let`s handed to `init` (the tester's signature, ADR-0155), so
    /// the sync closure cannot capture a controller that does not exist yet.
    static func live(vault: VaultController) -> PraticheController {
        let coordinator = PraticaLiveSync(vault: vault)
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state() },
            performSync: { [coordinator] path, kind in await coordinator.run(praticaPath: path, kind: kind) }
        )
        coordinator.controller = controller
        controller.requestSyncCancellation = { [coordinator] in coordinator.cancel() }
        controller.prepareRegeneration = { [coordinator] praticaPath, messageID in
            await coordinator.prepareRegeneration(praticaPath: praticaPath, messageID: messageID)
        }
        controller.commitRegeneration = { [coordinator] plan in
            await coordinator.commitRegeneration(plan)
        }
        return controller
    }
}

/// The pure serialization rule behind `PraticaLiveSync.run(praticaPath:)` - the same
/// `PraticaWatcher` precedent (this file, R-17): extracted so a scheduling rule is
/// testable without the real async work (Mail store copy, SQLite read, file writes)
/// behind it.
///
/// `PraticaLiveSync` runs one sync at a time system-wide (`running`, and the
/// controller's own single `syncingPraticaPath`, both track exactly one). Before this
/// existed, two `run(praticaPath:)` calls overlapping across an `await` suspension
/// each assigned `running` and each `defer`-cleared it, so the earlier sync became
/// uncancellable and its own cleanup could fire after a *later* sync had already
/// taken over the shared reference.
struct SyncRunQueue: Equatable {
    private(set) var isRunning = false
    private(set) var pending: [String] = []

    /// A path asks to run. `nil` means it was queued, not started - the caller must
    /// not begin work. A non-`nil` result is always `path` itself, echoed back so the
    /// call site reads as "the path to actually run", not as a bare permission bit.
    mutating func request(_ path: String) -> String? {
        guard !isRunning else {
            if !pending.contains(path) { pending.append(path) }
            return nil
        }
        isRunning = true
        return path
    }

    /// The active run just finished. `nil` means the queue is empty - the caller
    /// stops and the whole coordinator goes idle. A non-`nil` result is the next path
    /// to run immediately, with `isRunning` still `true`.
    mutating func finished() -> String? {
        guard !pending.isEmpty else {
            isRunning = false
            return nil
        }
        return pending.removeFirst()
    }

    /// «Annulla» (R-11): drops every request left waiting behind the one actually
    /// cancelled, so an interrupted sync is not silently followed by a queued one.
    /// Never touches `isRunning` - the active run's own `finished()` call is still
    /// what ends it, once its (cancelled) `runExclusive` returns.
    mutating func cancelPending() {
        pending.removeAll()
    }
}

/// Runs one pratica's real sync: publishes a copy of the Envelope Index, evaluates the
/// membership rule against it, and hands the candidates to `PraticaSyncEngine`.
///
/// Everything that touches Mail's own files happens inside one detached task
/// (`prepare(...)` below) and returns `Sendable` values: the SQLite connection never
/// leaves it, and the copy - 355 MB on this Mac - is never made on the main actor
/// (`MailStoreCopy.publish`'s own instruction).
@MainActor
final class PraticaLiveSync {
    weak var controller: PraticheController?
    private let vault: VaultController
    /// The engine of the sync currently running, or `nil` between syncs.
    private var running: PraticaSyncEngine?
    /// The pure serialization rule behind `run(praticaPath:)` - see `SyncRunQueue`'s
    /// own doc for why concurrent triggers must not run `runExclusive` concurrently.
    private var queue = SyncRunQueue()
    /// What a queued request needs once it is finally dequeued: which vault it
    /// belongs to, and which trigger asked for it (:976's fix - a queued
    /// `.automatic` request must recheck the pratica's CURRENT eligibility at
    /// dequeue time, since "closed while another sync ran" is exactly the window
    /// where that eligibility can change under it; `.manualRefresh` never rechecks,
    /// per R-17's "closed pratiche sync only through «Aggiorna ora»").
    private struct QueuedRequest {
        var session: VaultSession
        var kind: PraticaWatcher.Trigger
    }

    /// Which vault (and trigger) a QUEUED path belongs to, recorded at the moment it
    /// was asked for. `praticaPath` is vault-relative: a request queued while vault A
    /// is open and only dequeued after a switch to vault B would otherwise resolve
    /// A's path against B's folder tree. `run(praticaPath:kind:)` drops a dequeued
    /// request whose recorded session no longer matches the live one instead of
    /// running it.
    private var queuedRequests: [String: QueuedRequest] = [:]

    /// Held between `prepareRegeneration` and `commitRegeneration` (ADR §D21.2):
    /// `PraticaSyncEngine.commitRegeneration(_:)` only writes, it never re-opens the
    /// reader, so the same actor instance that produced the plan is what commits it.
    private var regenerationEngine: PraticaSyncEngine?

    /// «Annulla» (R-11). Cooperative and asynchronous by nature: the engine observes
    /// it at its next message boundary, so everything already written stays complete.
    /// Also drops every queued request: an interrupted sync should not be silently
    /// followed by the ones a burst of triggers left waiting behind it.
    func cancel() {
        queue.cancelPending()
        queuedRequests.removeAll()
        guard let running else { return }
        Task { await running.cancel() }
    }

    init(vault: VaultController) {
        self.vault = vault
    }

    /// Every trigger funnels through here (SPEC "Full Disk Access" / R-17/R-18).
    /// Concurrent triggers - a window activation and an FSEvents pulse landing while
    /// this actor is suspended inside a previous sync's `await` - are serialized
    /// through `queue` instead of running `runExclusive` concurrently, since
    /// `running` and the controller's `syncingPraticaPath` each track exactly one
    /// sync at a time.
    func run(praticaPath: String, kind: PraticaWatcher.Trigger) async {
        guard let session = vault.session else { return }
        guard let toRun = queue.request(praticaPath) else {
            queuedRequests[praticaPath] = Self.coalesce(
                queuedRequests[praticaPath], with: QueuedRequest(session: session, kind: kind)
            )
            return
        }
        var current = toRun
        var currentSession = session
        var currentKind = kind
        while true {
            if vault.session === currentSession, isStillEligible(current, kind: currentKind) {
                await runExclusive(praticaPath: current)
            }
            guard let next = queue.finished() else { break }
            current = next
            let queued = queuedRequests.removeValue(forKey: next)
            currentSession = queued?.session ?? currentSession
            currentKind = queued?.kind ?? currentKind
        }
    }

    /// :976's recheck. `.manualRefresh` ignores `Eligibility` entirely, same as
    /// `PraticheController.trigger(_:kind:eligibility:)` does for the immediate path -
    /// a queued «Aggiorna ora» must still run even if the pratica closed while it
    /// waited. Every other trigger kind is only queued because it was `.automatic`
    /// when first asked for (`PraticheController.trigger` never queues a request that
    /// didn't already pass that check), so what changed is whether it STILL is -
    /// re-read the live `pratiche` list rather than trusting the stale decision.
    /// A pratica no longer found (deleted, or the vault moved on) runs rather than
    /// silently drops: closing the request instead of running it once more is a much
    /// smaller cost than a dropped result nobody asked for a second time.
    private func isStillEligible(_ praticaPath: String, kind: PraticaWatcher.Trigger) -> Bool {
        Self.shouldRunQueuedRequest(
            kind: kind,
            currentEligibility: controller?.pratiche.first { $0.id == praticaPath }.map(PraticheController.eligibility(of:))
        )
    }

    /// The pure decision behind `isStillEligible`, extracted the same way `SyncRunQueue`
    /// was extracted from this same function's earlier body (this file's own header
    /// comment) - so the rule is testable without the async work, the real `pratiche`
    /// list, or a live `PraticheController` at all. `currentEligibility == nil` means
    /// the pratica could not be found in the live list; treated the same as "run it",
    /// per `isStillEligible`'s own doc.
    nonisolated static func shouldRunQueuedRequest(
        kind: PraticaWatcher.Trigger, currentEligibility: PraticaWatcher.Eligibility?
    ) -> Bool {
        guard kind != .manualRefresh else { return true }
        guard let currentEligibility else { return true }
        return currentEligibility == .automatic
    }

    /// :1001's fix. The same path can already sit in `queuedRequests` when a second
    /// trigger asks for it (`SyncRunQueue.request` only dedupes `queue.pending` by
    /// path, never by trigger kind) - an unconditional overwrite let a later automatic
    /// trigger silently downgrade an earlier `.manualRefresh`'s stored kind, so
    /// `shouldRunQueuedRequest` would then treat an explicit «Aggiorna ora» as
    /// revocable if the pratica closed before it dequeued. `.manualRefresh`, once
    /// recorded, is sticky: nothing coalesced afterwards can un-record it - UNLESS the
    /// incoming request belongs to a DIFFERENT session (:1059's fix on top of :1001's
    /// own): sticking with the old session's `QueuedRequest` wholesale would keep
    /// `run(praticaPath:kind:)`'s later `vault.session === currentSession` check
    /// comparing against a vault nobody has open any more, silently dropping a genuine
    /// refresh queued for the SAME path in the vault that is open now. A session
    /// change always wins outright, same as an empty queue slot.
    private nonisolated static func coalesce(_ existing: QueuedRequest?, with incoming: QueuedRequest) -> QueuedRequest {
        guard let existing, existing.session === incoming.session,
            Self.coalescedKind(existing: existing.kind, incoming: incoming.kind) == existing.kind
        else { return incoming }
        return existing
    }

    /// The pure decision behind `coalesce`, extracted the same way `shouldRunQueuedRequest`
    /// was - testable with no `QueuedRequest`, no session, no controller. `existing == nil`
    /// means nothing was queued yet, so the incoming kind always wins.
    nonisolated static func coalescedKind(
        existing: PraticaWatcher.Trigger?, incoming: PraticaWatcher.Trigger
    ) -> PraticaWatcher.Trigger {
        guard let existing, existing == .manualRefresh else { return incoming }
        return existing
    }

    private struct Prepared: Sendable {
        var indexURL: URL
        /// R-30/§D22.3: `snapshot.unfollowed` already carries every conversation
        /// touching a counterpart inside the proposal window, followed or not - one
        /// snapshot serves both `MembershipRule.candidates` (rule 3 reads it through
        /// `everyMessage(in:)`) and `MembershipRule.trayCandidates` (merges it with
        /// `conversations`), so there is no second field to keep in step with this one.
        var snapshot: MembershipStoreSnapshot
        /// §D23.3/§D23.4: `old → new` for every followed conversation `prepare` found
        /// renumbered this run - defaulted empty so every existing construction site
        /// keeps compiling (ADR-0155 §D1; the coder fills the detection in `prepare`).
        var conversationRemap: [Int: Int] = [:]
        /// §D23.5: followed conversations whose every known member has vanished from
        /// the store - reported through `controller.report(_:)`, never removed from
        /// the dossier (R-14).
        var unrecoverableConversations: [Int] = []
        /// §D24.4: `false` when the store's schema has no queryable `recipients`
        /// table - reported through `controller.report(_:)` once per sync, since a
        /// store in that shape silently reduces the tray and the keyword arm to
        /// sender-only matching.
        var recipientsUnsupported: Bool = false
    }

    /// What `prepare(...)` answers. Not a `Result`: the failure side is the Italian
    /// sentence the banner shows, and a `String` is not an `Error` - wrapping it in one
    /// would buy nothing, since nothing here is thrown or caught.
    private enum Preparation: Sendable {
        case ready(Prepared)
        case failed(String)
    }

    private func runExclusive(praticaPath: String) async {
        guard let controller, let session = vault.session, let root = vault.root else { return }
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            return
        }

        let settings = vault.settings.pratiche
        let stateDirectory = PraticheController.stateDirectory(for: session)
        let state = controller.ledger.byPraticaPath[praticaPath] ?? .empty
        let onDisk = Set(state.importedMessageIDs)
        let mailRoot = MailStoreLocation.resolve()
        // R-30/SPEC "Membership rule": the window the tray proposes inside, and the
        // conversations somebody else's pratica already follows - read here, on the
        // main actor, because both come from state this object is not allowed to touch
        // from the detached task below.
        let now = Date()
        let window = now.addingTimeInterval(-Double(settings.proposalWindowDays) * 86_400)...now
        let claimed = Self.conversationsClaimedByOtherPratiche(
            than: praticaPath, among: controller.pratiche, vaultRoot: root
        )

        controller.beginSync(praticaPath)
        defer { controller.endSync() }

        let outcome = await Task.detached(priority: .utility) {
            Self.prepare(
                mailRoot: mailRoot, stateDirectory: stateDirectory,
                dossier: dossier, ledgerEntries: state.entries, proposalWindow: window
            )
        }.value

        let prepared: Prepared
        switch outcome {
        case .ready(let value): prepared = value
        case .failed(let message):
            controller.report(message)
            return
        }

        var effectiveDossier = dossier
        // §D23.4: repoint the ledger and the dossier together, before candidates are
        // evaluated, so this run already imports through the renumbered id rather than
        // waiting for a later sync to notice.
        if !prepared.conversationRemap.isEmpty {
            controller.remapLedgerConversations(prepared.conversationRemap, of: praticaPath, in: vault)
            let notePath = PraticaCommandActions.praticaNotePath(of: praticaPath)
            do {
                var document = NoteDocument.parse(try session.read(notePath).text)
                let before = document
                if var updated = Dossier.parse(document.frontmatter.foreignKeys) {
                    for index in updated.conversations.indices {
                        if let newID = prepared.conversationRemap[updated.conversations[index]] {
                            updated.conversations[index] = newID
                        }
                    }
                    // Collapse a duplicate a remap can create (two old ids folding into
                    // one new one) while preserving first-seen position - the order a
                    // person followed things in (`PraticaTrayModel.following`'s own reason).
                    var seen: Set<Int> = []
                    updated.conversations = updated.conversations.filter { seen.insert($0).inserted }
                    document.frontmatter.foreignKeys = Dossier.merging(updated, into: document.frontmatter.foreignKeys)
                    if document != before {
                        // ADR-0041 Task 8: `VaultSession.write` gained an async overload
                        // this dispatch declares; `runExclusive` was already `async` for
                        // unrelated reasons, so Swift's overload resolution now requires
                        // this call to be awaited. Mechanical only - no behaviour change,
                        // the awaited overload's stub body is today's synchronous write
                        // called as-is.
                        try await session.write(document.serialized(), to: notePath)
                    }
                    effectiveDossier = updated
                }
            } catch {
                controller.report("«\(notePath)» non è stato aggiornato: \(error.localizedDescription)")
            }
        }
        if !prepared.unrecoverableConversations.isEmpty {
            controller.report(
                "Una conversazione seguita non è più ricostruibile in Mail: \(prepared.unrecoverableConversations.count)."
            )
        }
        if prepared.recipientsUnsupported {
            controller.report(
                "L'indice di Mail non espone i destinatari: la vaschetta vede solo i messaggi ricevuti."
            )
        }

        // §D22.3: two evaluations, and the second is proved to be the last - rule 3
        // skips an id already in `dossier.conversations`, so once every auto-followed
        // id from the first pass is written into `effectiveDossier`, a second pass
        // auto-follows nothing new. This lets a keyword match import the whole thread
        // in the run that found it, not just the one matching message.
        var candidates = MembershipRule.candidates(
            dossier: effectiveDossier, store: prepared.snapshot, onDisk: onDisk
        )
        if !candidates.autoFollowedConversations.isEmpty {
            for conversation in candidates.autoFollowedConversations {
                effectiveDossier = PraticaTrayModel.following(conversationID: conversation, in: effectiveDossier)
            }
            await DossierWriter.update(at: praticaPath, session: session) { $0 = effectiveDossier }
            candidates = MembershipRule.candidates(
                dossier: effectiveDossier, store: prepared.snapshot, onDisk: onDisk
            )
        }
        let engine = PraticaSyncEngine(mailStoreURL: prepared.indexURL, vaultRoot: root) { text, path in
            _ = try await session.write(text, to: path)
        }
        // Kept for the duration of this one sync and cleared after it: «Annulla» has
        // an engine to reach only while there is a sync to stop.
        running = engine
        defer { running = nil }
        let progress = Task { @MainActor [weak controller] in
            for await step in await engine.progressStream() { controller?.updateProgress(step) }
        }
        defer { progress.cancel() }

        do {
            let result = try await engine.sync(PraticaSyncEngine.SyncRequest(
                praticaFolder: praticaPath,
                dossier: effectiveDossier,
                candidates: candidates.messages,
                onDisk: onDisk,
                settings: settings
            ))
            // The vault open when this run started may no longer be the one open now
            // (a person can switch vaults mid-sync): the files above were written
            // through the SESSION captured at the top of this function, which is
            // correct, and so is this ledger write - `recordSyncOutcome` takes the
            // captured `session` explicitly and persists into ITS OWN ledger file
            // regardless of what is live, so a vault switch mid-sync can never leave a
            // completed import unrecorded OR bleed into whatever vault is live now.
            controller.recordSyncOutcome(
                result, for: praticaPath, session: session, isCurrentVault: vault.session === session
            )
        } catch {
            guard vault.session === session else { return }
            controller.report("Sincronizzazione non riuscita: \(error.localizedDescription)")
        }

        guard vault.session === session else { return }

        // After the import and not before it: a conversation this run has just started
        // following is no longer a proposal, and the tray would otherwise offer back
        // what the person just accepted.
        let followed = PraticheController.dossier(at: praticaPath, vaultRoot: root) ?? effectiveDossier
        let tray = MembershipRule.trayCandidates(
            dossier: followed,
            store: prepared.snapshot,
            window: window,
            claimedByOtherPratiche: claimed
        )
        controller.updateTray(
            PraticaTrayModel.proposals(from: tray, ownAddresses: Set(settings.ownAddresses)),
            for: praticaPath, in: vault
        )
    }

    // MARK: - «Rigenera» (ADR §D21)

    /// §D21.1: publishes a fresh store copy, then asks the engine to acquire the
    /// replacement text and diff it - nothing is trashed or written yet. The engine is
    /// kept in `regenerationEngine` for `commitRegeneration` below, since it is the
    /// one thing that must not be re-derived between preview and commit.
    func prepareRegeneration(praticaPath: String, messageID: String) async {
        guard let controller, let session = vault.session, let root = vault.root else { return }
        let settings = vault.settings.pratiche
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            controller.regeneration = nil
            return
        }
        let state = controller.ledger.byPraticaPath[praticaPath] ?? .empty
        let onDisk = Set(state.importedMessageIDs)
        // §D3: the ledger's own bridge, for a message the fresh index copy cannot
        // resolve by `Message-ID` on its own.
        let rowID = state.entries.first { $0.messageID == messageID }?.rowID
        let mailRoot = MailStoreLocation.resolve()
        let stateDirectory = PraticheController.stateDirectory(for: session)

        let generation: URL
        switch MailStoreCopy.publish(from: mailRoot, into: stateDirectory) {
        case .published(let url), .unchanged(let url):
            generation = url
        case .mailIsWriting:
            controller.report("Mail sta scrivendo nel suo archivio: riprova fra qualche secondo.")
            controller.regeneration = nil
            return
        case .storeMissing:
            controller.report("Nessun archivio di Mail trovato in \(mailRoot.path(percentEncoded: false)).")
            controller.regeneration = nil
            return
        }
        let indexURL = generation.appending(path: "Envelope Index", directoryHint: .notDirectory)

        let engine = PraticaSyncEngine(mailStoreURL: indexURL, vaultRoot: root) { text, path in
            _ = try await session.write(text, to: path)
        }
        regenerationEngine = engine

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: praticaPath, dossier: dossier, candidates: [], onDisk: onDisk, settings: settings
        )
        do {
            let plan = try await engine.regenerationPreview(request, messageID: messageID, rowID: rowID)
            guard vault.session === session else { return }
            controller.regeneration = .ready(plan)
        } catch {
            guard vault.session === session else { return }
            controller.regeneration = nil
            controller.report(Self.regenerationFailureMessage(error))
        }
    }

    /// §D21.2: commits an already-previewed plan through the same engine instance that
    /// produced it, then records the outcome in the ledger exactly as an ordinary sync
    /// would (`isRegeneration` routes it into `regeneratedPendingFiles`, never
    /// `importedMessageIDs` - `PraticaSyncEngine.commit`'s own rule). `false` on
    /// failure, so the caller can put the trashed files back.
    func commitRegeneration(_ plan: PraticaSyncEngine.RegenerationPlan) async -> Bool {
        guard let controller, let session = vault.session, let engine = regenerationEngine else {
            controller?.report("Rigenerazione non riuscita: il motore di sincronizzazione non è più disponibile.")
            return false
        }
        do {
            let outcome = try await engine.commitRegeneration(plan)
            controller.recordSyncOutcome(
                outcome, for: plan.praticaFolder, session: session, isCurrentVault: vault.session === session
            )
            return true
        } catch {
            guard vault.session === session else { return false }
            controller.report(Self.regenerationFailureMessage(error))
            return false
        }
    }

    private static func regenerationFailureMessage(_ error: Error) -> String {
        guard let failure = error as? PraticaSyncEngine.RegenerationFailure else {
            return "Rigenerazione non riuscita: \(error.localizedDescription)"
        }
        switch failure {
        case .rowNotFound:
            return "Il messaggio non è stato trovato nell'indice di Mail."
        case .notInStore:
            return "Il messaggio non è più in Mail: non c'è nulla da cui rigenerarlo."
        case .notDecodable:
            return "Il messaggio non è stato letto correttamente da Mail."
        case .fileMissing:
            return "Il file della nota non è stato trovato nel vault."
        }
    }

    /// R-13's `claimedByOtherPratiche`: every conversation any *other* pratica already
    /// follows, read from the files rather than from the index, for the same reason
    /// `PraticheController.dossier(at:vaultRoot:)` does - a sync acts on the dossier as
    /// it is now, not as the last scan saw it.
    private static func conversationsClaimedByOtherPratiche(
        than praticaPath: String, among pratiche: [PraticaListItem], vaultRoot: URL
    ) -> Set<Int> {
        var claimed: Set<Int> = []
        for pratica in pratiche where pratica.id != praticaPath {
            guard let dossier = PraticheController.dossier(at: pratica.id, vaultRoot: vaultRoot)
            else { continue }
            claimed.formUnion(dossier.conversations)
        }
        return claimed
    }

    /// The whole Mail-touching half, off the main actor. A named failure rather than an
    /// optional: «Mail sta scrivendo» and «nessun archivio di Mail» are different
    /// sentences and only one of them is worth a second attempt (ADR §D2).
    private nonisolated static func prepare(
        mailRoot: URL, stateDirectory: URL, dossier: Dossier, ledgerEntries: [PraticaLedger.Entry],
        proposalWindow: ClosedRange<Date>
    ) -> Preparation {
        let generation: URL
        switch MailStoreCopy.publish(from: mailRoot, into: stateDirectory) {
        case .published(let url), .unchanged(let url):
            generation = url
        case .mailIsWriting:
            return .failed("Mail sta scrivendo nel suo archivio: riprova fra qualche secondo.")
        case .storeMissing:
            return .failed("Nessun archivio di Mail trovato in \(mailRoot.path(percentEncoded: false)).")
        }

        let indexURL = generation.appending(path: "Envelope Index", directoryHint: .notDirectory)
        guard let reader = try? MailStoreReader(storeURL: indexURL) else {
            return .failed("La copia dell'indice di Mail non si è aperta.")
        }

        // `messagesByID` first (§D23.3): recovery below resolves against it, so it must
        // exist before the conversation loop that may need it.
        var messagesByID: [String: MailMessageRow] = [:]
        // The ledger's own triples first (ADR §D3): they are what resolves an id the
        // index cannot answer for on its own.
        for messageID in Set(dossier.included).union(ledgerEntries.map(\.messageID)) {
            if case .found(let row) = reader.row(forMessageID: messageID) {
                messagesByID[messageID] = row
            }
        }

        // §D23.3/R-14: an empty result for a followed conversation is only evidence of
        // renumbering when this pratica has actually imported from it - nothing
        // imported means nothing to re-derive, and a conversation whose every message
        // a person deleted is not a bug to report.
        var conversations: [Int: [MailMessageRow]] = [:]
        var remap: [Int: Int] = [:]
        var unrecoverable: [Int] = []
        let resolved = MembershipStoreSnapshot(conversations: [:], messagesByID: messagesByID)
        for conversation in dossier.conversations {
            let rows = reader.messages(inConversation: conversation)
            guard rows.isEmpty else { conversations[conversation] = rows; continue }
            let members = ledgerEntries.filter { $0.conversationID == conversation }.map(\.messageID)
            guard !members.isEmpty else { conversations[conversation] = []; continue }
            switch MembershipRule.recoverConversationID(knownMemberMessageIDs: members, store: resolved) {
            case .recovered(let recovered) where recovered != conversation:
                remap[conversation] = recovered
                conversations[recovered] = reader.messages(inConversation: recovered)
            case .recovered:
                conversations[conversation] = []
            case .unrecoverable:
                unrecoverable.append(conversation)
            }
        }

        // R-30: the counterpart query the tray is made of
        // (`MailStoreReader.conversations(counterpart:within:)`, written for exactly
        // this), asked once per counterpart and folded into one map - two counterparts
        // in one conversation are one proposal, not two.
        var unfollowed: [Int: [MailMessageRow]] = [:]
        for address in dossier.counterparts {
            for conversation in reader.conversations(counterpart: address, within: proposalWindow) {
                unfollowed[conversation.conversationID] = conversation.messages
            }
        }

        return .ready(Prepared(
            indexURL: indexURL,
            snapshot: MembershipStoreSnapshot(
                conversations: conversations, messagesByID: messagesByID, unfollowed: unfollowed
            ),
            conversationRemap: remap,
            unrecoverableConversations: unrecoverable,
            recipientsUnsupported: !reader.supportsRecipients()
        ))
    }
}

/// FSEvents under the Mail store, the third automatic trigger (R-17).
///
/// `VaultWatcher`'s shape without its `.md` filter - what changes here is `.emlx`
/// files and the Envelope Index's WAL, never a note. One callback per coalesced burst;
/// the debounce that turns a burst into one sync is `PraticaWatcher`'s, not this
/// object's.
private final class MailStoreEventStream: @unchecked Sendable {
    /// Longer than `VaultWatcher`'s 0.2 s: nothing here is waiting for a keystroke to
    /// appear on screen, and Mail writes in long bursts while it fetches.
    private static let latency: CFTimeInterval = 2

    /// `VaultWatcher.Sink`'s counterpart, and for the same reason: this stream was handed
    /// `self` as a bare, non-owning pointer, which ties the callback's context to nothing
    /// and leaves a callback arriving after teardown reading freed memory. That is the
    /// use-after-free the vault watcher was crashing on, copied here when this type was
    /// written in its shape. Same fix: an explicit `+1` on a separate context object,
    /// given up from `queue` after invalidation. See `VaultWatcher.Sink` for the evidence.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var onChange: (@Sendable () -> Void)?

        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

        func cancel() {
            lock.lock()
            onChange = nil
            lock.unlock()
        }

        func fire() {
            lock.lock()
            let deliver = onChange
            lock.unlock()
            deliver?()
        }
    }

    private let root: URL
    private let queue = DispatchQueue(label: "it.stefer.pergamenum.pratiche-mailstore")
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    /// The `+1` on the live `Sink`, given up in `stop()` from `queue`.
    private var sinkInfo: UnsafeMutableRawPointer?

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.root = root
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let info = Unmanaged.passRetained(Sink(onChange: onChange)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().fire()
        }

        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        guard let created else {
            Unmanaged<Sink>.fromOpaque(info).release()
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        sinkInfo = info
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        guard let info = sinkInfo else { return }
        sinkInfo = nil
        Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().cancel()
        // Serial queue, FIFO: every callback already running or enqueued has returned
        // before this gives up the last reference.
        queue.async { Unmanaged<Sink>.fromOpaque(info).release() }
    }
}
