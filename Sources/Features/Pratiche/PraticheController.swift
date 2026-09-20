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
    ///
    /// Not `private(set)`, on this property and every other one down to `performSync`
    /// below: `PraticheController+Triggers.swift` is an extension of this class in a
    /// separate file, and reads and writes all of them from `trigger`, `startWatching`,
    /// `scheduleFSEventsFire` and `fireDueFSEventsPulses`.
    var fullDiskAccessState: FullDiskAccessProbe.State

    /// One `PraticaWatcher` per pratica path (R-17): the throttle/debounce state is
    /// per pratica, not shared, since a window-key sync of pratica A must not
    /// silence pratica B's own trigger due within the window.
    var watchersByPraticaPath: [String: PraticaWatcher] = [:]

    let probe: () -> FullDiskAccessProbe.State
    let performSync: (String, PraticaWatcher.Trigger) async -> Void

    init(
        probe: @escaping () -> FullDiskAccessProbe.State,
        performSync: @escaping (String, PraticaWatcher.Trigger) async -> Void
    ) {
        self.probe = probe
        self.performSync = performSync
        self.fullDiskAccessState = probe()
    }

    // MARK: - What the pane shows (Task 6: R-23, R-24, R-26, R-32, R-33)

    /// Every pratica of the open vault, as the list column needs it. Rebuilt from the
    /// index by `load(from:)`, never held across a vault change.
    ///
    /// Not `private(set)`, on this property and every other one down to `details`
    /// below: `PraticheController+Ledger.swift` is an extension of this class in a
    /// separate file, and reads and writes all of them from `load`, `select` and
    /// `reloadTimeline`.
    var pratiche: [PraticaListItem] = []

    /// The chosen pratica's folder path, which is also its list row's `.tag`.
    var selection: String?

    /// The chosen pratica's rows, oldest first (R-23) - already through
    /// `PraticaTimelineModel.ordered`, so the view scrolls to the end for the newest.
    var timeline: [PraticaTimelineEntry] = []

    /// What a row needs beyond `PraticaTimelineEntry` to draw itself expanded: the
    /// markdown body, the quoted history, the attachments and the pending flag.
    ///
    /// A side table rather than more fields on the entry: `PraticaTimelineEntry` is
    /// the tester-declared shape the ordering, filtering and lane rules are written
    /// against (ADR-0155), and widening it to carry a file's whole body would make
    /// every one of those pure functions carry a payload none of them reads.
    var details: [String: PraticaRowDetail] = [:]

    /// ADR-0049 (pratica/message links), Task 5 - R-04: the selected pratica's own
    /// links, parsed but not resolved (resolution happens where it is drawn,
    /// `PratichePane+Links.swift`'s own rule, since it costs an index lookup and
    /// nothing more). Loaded by `reloadTimeline(from:)`, the same beat `timeline`/
    /// `details` are - which is also what `PraticaCommandActions.reload()` calls
    /// after every link write, so a write refreshes this for free.
    var links: PraticaLinks = .empty

    /// The three toolbar filters (R-32).
    var filter = PraticaTimelineFilter()

    /// Per window and never persisted (R-24). Here rather than as the timeline view's
    /// own `@State` because the expansion has to survive the view being rebuilt when
    /// the filter changes, and because Opt+click needs every visible id at once.
    var expansion = PraticaTimelineModel.ExpansionState()

    /// The pratica a sync is running for, and how far it has got (R-20's progress bar,
    /// screen 1a's «12 di 80 · Annulla»).
    ///
    /// Not `private(set)`, on this property and every other one down to `problem`
    /// below (`ledger`, right after it, is the exception and says why):
    /// `PraticheController+Ledger.swift` is an extension of this class in a
    /// separate file, and reads and writes all of them from `beginSync`, `endSync`,
    /// `updateProgress`, `report`, `recordSyncOutcome`, `moveLedgerState` and
    /// `remapLedgerConversations`.
    var syncingPraticaPath: String?
    var syncProgress: PraticaSyncEngine.Progress?

    /// «Rigenera…»'s own in-flight marker (ADR §D21) - the regeneration-side twin of
    /// `syncingPraticaPath` just above, needed because nothing here serializes
    /// concurrent regenerations against each other the way `SyncRunQueue` serializes
    /// ordinary syncs (review round 2, MINOR 2's root cause: a sync and a regeneration
    /// for the SAME pratica can be in flight at once). A set rather than a second
    /// optional for that reason. Wider than `regeneration`'s own nil/non-nil below: that
    /// goes `nil` the instant `PraticaCommandActions.confirmRegeneration` starts
    /// trashing files, before the async commit (and its own `recordSyncOutcome`)
    /// actually runs - exactly the window `moveLedgerState` needs covered so a
    /// relocation mid-regeneration still leaves a `praticaPathRedirects` entry (MINOR 1).
    /// Set by `beginRegeneration`, released by `endRegeneration`/`dismissRegeneration`.
    var regeneratingPraticaPaths: Set<String> = []

    /// The last thing that went wrong, in Italian, for the pane to show. Cleared by
    /// the next successful load - a stale error over a working pane is worse than none.
    var problem: String?

    /// The per-vault ledger (`…/vaults/<id>/pratiche/ledger.json`, SPEC "Per-vault
    /// state"): `lastOpenedAt` is what the badge counts from, `importedMessageIDs`
    /// what a resumed sync skips.
    ///
    /// `private(set)`, unlike every property above it (ADR-0052 §D2): this is saved back over a
    /// file nothing else can rebuild, so the one way to change it is `updateLedger(_:_:)`, which
    /// checks `ledgerOrigin` first and cannot be skipped by the next writer. That door sits at the
    /// foot of THIS file and not beside the rest of the ledger code in `PraticheController+Ledger
    /// .swift`, because Swift confines a `private(set)` setter to the declaring file and a stored
    /// property cannot live in an extension. Two other places in this repo hit the same wall and
    /// kept an internal setter (`VaultController.pinnedTags`, and this property until ADR-0052);
    /// the wall is real only when the door has to live in another file.
    private(set) var ledger: PraticaLedger = .empty

    /// Which ledger file `ledger` was read from (ADR-0052 §D1) - what makes «this memory is the
    /// vault I am about to write into» a fact rather than an assumption.
    private(set) var ledgerOrigin: LedgerOrigin = .none

    /// R-04: the unreadable ledger files already reported this session, so one sentence goes out per
    /// file however many writers run. A later successful read of a file takes it off again.
    @ObservationIgnored private var reportedUnreadableLedgers: Set<URL> = []

    /// A pratica path some in-flight caller captured before a relocation moved its
    /// ledger key elsewhere, mapped to where that key sits now. `moveLedgerState`
    /// populates one entry per key currently claimed by `syncingPraticaPath` or
    /// `regeneratingPraticaPaths` - never for a key nothing is racing, which is what
    /// used to make this grow across every relocation in a session (review round 2,
    /// MINOR 1). `recordSyncOutcome` reads (never removes - MINOR 2) it to fold a stale
    /// outcome into the pratica's CURRENT key instead of resurrecting the pre-move one
    /// (`PraticaLiveSync+Run.swift`'s `runExclusive` captures its `praticaPath` before
    /// two `await`s - ADR-0043 §D7's "a precondition evaluated before an `await` is a
    /// filter, not a guard" shape, found by review). The whole map is dropped in one go
    /// once nothing is in flight anywhere to still need any entry in it
    /// (`pruneRedirectsIfIdle`). Not `private(set)`: `PraticheController+Ledger.swift`
    /// reads and writes it from `moveLedgerState`, `recordSyncOutcome`, `endRegeneration`
    /// and `pruneRedirectsIfIdle`.
    var praticaPathRedirects: [String: String] = [:]

    /// The deletion twin of `praticaPathRedirects` just above (ADR-0026 §D7's 2026-09-19
    /// amendment, PG-169): a pratica path a sync or regeneration holds, whose folder was
    /// trashed while it was still in flight. `forgetLedgerState` records a key here only for
    /// a path `syncingPraticaPath` or `regeneratingPraticaPaths` actually claims at that
    /// moment - a deletion with nothing running records nothing, since nothing will ever read
    /// it. `praticaPath(continuing:)` refuses a path found here with `.praticaTrashed`, and
    /// `recordSyncOutcome` writes nothing for it, which is what stops a finishing run from
    /// putting back the ledger key the trash just removed. Dropped per path when the run that
    /// claimed it ends and nothing else still claims that path (`dropTombstoneIfUnclaimed`,
    /// ADR-0052 §D6), and cleared in one go with the redirect map once nothing at all is in
    /// flight (`pruneRedirectsIfIdle`). Not `private(set)`: `PraticheController+Ledger
    /// .swift` reads and writes it from `forgetLedgerState`, the private resolver behind
    /// `praticaPath(continuing:)`/`recordSyncOutcome`/`endRegeneration`, and `load(from:)`.
    var forgottenPraticaPaths: Set<String> = []

    /// How many tray proposals each pratica has, which is the dot on its row (R-33).
    /// Derived from `trayProposals` by `updateTray(_:for:in:)`; empty here means no
    /// dot, never a wrong one.
    var trayCounts: [String: Int] = [:]

    /// R-30's «Da smistare» proposals, per pratica, as the last sync of that pratica
    /// found them. Held per pratica rather than for the selection alone so the dot on
    /// a row that is not open stays right (R-33).
    ///
    /// Not `private(set)`: `PraticheController+Ledger.swift` is an extension of this
    /// class in a separate file, and reads and writes it from `updateTray` and
    /// `moveLedgerState`.
    var trayProposals: [String: [PraticaTrayModel.PraticaTrayProposal]] = [:]

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
        /// `praticaPath` (review round 2): the only way `dismissRegeneration`/
        /// `endRegeneration` can release this attempt's claim on
        /// `regeneratingPraticaPaths` before a plan even exists to read
        /// `praticaFolder` from.
        case preparing(notePath: String, subject: String, praticaPath: String)
        case ready(PraticaSyncEngine.RegenerationPlan)

        var id: String {
            switch self {
            case .preparing(let notePath, _, _): notePath
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

    /// Not `private`, on this property and every other one down to `fsEventsFireTask`
    /// below: `PraticheController+Triggers.swift` is an extension of this class in a
    /// separate file, and reads and writes all of them from `startWatching` and
    /// `scheduleFSEventsFire`.
    @ObservationIgnored var mailStoreEvents: MailStoreEventStream?
    @ObservationIgnored var windowKeyObserver: (any NSObjectProtocol)?
    /// The pending half of the FSEvents debounce: one task per burst, replaced by
    /// every new pulse (see `scheduleFSEventsFire(in:)`).
    @ObservationIgnored var fsEventsFireTask: Task<Void, Never>?

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

    /// Round-4 review, §4: a relocation - or, since PG-169, a trash - mid-sync must stop the
    /// ENGINE too, not only guard the ledger/UI consumers downstream of it - without this,
    /// the engine keeps writing into the vacated folder for the rest of the run. Whether
    /// the path the run captured moved or went to the Trash does not change what the engine
    /// has to do, so one closure serves both. Same shape and justification as
    /// `requestSyncCancellation` just above: a settable property, not a third `init`
    /// parameter, so it cannot break `init(probe:performSync:)` (ADR-0155). `nil` means
    /// nothing is wired, and a relocation or trash runs with nothing to stop. Wired by
    /// `live(vault:)` to `PraticaLiveSync.stopForVanishedPath()`, called from
    /// `moveLedgerState` and `forgetLedgerState` - deliberately NOT the same closure as
    /// `requestSyncCancellation`, which also drops every queued request for OTHER
    /// pratiche that have nothing to do with this one.
    @ObservationIgnored var requestSyncStopForVanishedPath: (@MainActor () -> Void)?

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

    /// R-06: the inspector's aggregate "note collegate" list - `links.notes` plus
    /// every message's own `linkedNote` (`details[...].linkedNote`), unioned and
    /// de-duplicated by title. `details` is a dictionary, so its iteration order is
    /// not stable; a title reached only through a message is appended after the
    /// general ones, sorted, and each row's `messagePaths` is sorted too - both for
    /// the same reason, a deterministic result rather than one that happens to match
    /// on a given run.
    var aggregatedNoteLinks: [PraticaAggregatedNoteLink] {
        var messagePathsByTitle: [String: [String]] = [:]
        var messageOnlyTitles: Set<String> = []
        for detail in details.values {
            guard let raw = detail.linkedNote, case let .wikilink(title)? = PraticaLinkReference(parsing: raw)
            else { continue }
            messagePathsByTitle[title, default: []].append(detail.notePath)
            if !links.notes.contains(title) { messageOnlyTitles.insert(title) }
        }
        let order = links.notes + messageOnlyTitles.sorted()
        return order.map { title in
            PraticaAggregatedNoteLink(title: title, messagePaths: (messagePathsByTitle[title] ?? []).sorted())
        }
    }
}

// MARK: - The ledger's one door (ADR-0052)

// Here, in the file that declares `ledger`, and not beside the rest of the ledger code: a
// `private(set)` setter is visible to this file's extensions and to nothing else (see `ledger`).

extension PraticheController {
    /// Which ledger file the in-memory `ledger` was read from (§D1). One enum rather than a `URL?`
    /// beside an `isWritable: Bool` that could disagree (ADR-0024 §D2's rule).
    enum LedgerOrigin: Equatable, Sendable {
        /// Nothing read yet, or no vault open.
        case none
        /// Read from this file: decoded, or absent and therefore writable (a first write creates it).
        case loaded(URL)
        /// This file is there and could not be read: `ledger` is empty and nothing is saved over it.
        case unreadable(URL)

        /// The file the memory came from, compared by `URL` equality against the target's. Both
        /// sides come from `PraticheController.ledgerURL(for:)` off the same `session.state.directory`,
        /// so the comparison is stable; a caller that standardised or resolved symlinks on one side
        /// only would make every write look like a change of vault.
        var url: URL? {
            switch self {
            case .none: nil
            case .loaded(let url), .unreadable(let url): url
            }
        }

        /// False only for `.unreadable`.
        var allowsSaving: Bool {
            switch self {
            case .none, .loaded: true
            case .unreadable: false
            }
        }
    }

    /// Which vault's ledger a write is for (§D2). A `VaultSession?` and never a `VaultController`:
    /// `recordSyncOutcome` is handed a session and a flag by its caller and holds no controller.
    enum LedgerTarget {
        /// The vault being shown, `nil` when none is open. Goes through the marker: memory that did
        /// not come from this vault's file is replaced by it first.
        case live(VaultSession?)
        /// A session that is no longer the live one (a sync that outlived a vault switch): its own
        /// file, read fresh and written back, never `ledger` and never `ledgerOrigin`.
        case stale(VaultSession)
    }

    /// What `updateLedger(_:_:)` did with a change.
    enum LedgerWrite: Equatable {
        case saved
        /// The change left the ledger as it was, so nothing was written.
        case unchanged
        /// Applied in memory; there was no vault to save it under.
        case notPersisted
        /// The file is unreadable (§D3): applied in memory for the live vault, dropped for a stale
        /// one, saved nowhere.
        case refused
        /// The save threw: memory holds the change, the file does not.
        case failed
    }

    /// The only way to change the ledger (§D2). It resolves the file the write is for, checks the
    /// marker and re-reads (and resets the vault-scoped state) when memory did not come from that
    /// file, refuses a file it could not read (§D3), applies `change`, and saves only what really
    /// differs. A writer is the closure it always was, with no knowledge of loading or saving.
    ///
    /// `change` is applied to a copy and never to `&ledger`: two writers touch other properties of
    /// `self` from inside it (`forgottenPraticaPaths`, `praticaPathRedirects`), which while `ledger`
    /// is held inout is an exclusivity trap, and the copy is also what makes «did anything change»
    /// answerable. A writer that also touches sibling state calls this FIRST (§D8): the door can
    /// reset that state, and the reverse order would put back what a vault change had just cleared.
    @discardableResult
    func updateLedger(_ target: LedgerTarget, _ change: (inout PraticaLedger) -> Void) -> LedgerWrite {
        switch target {
        case .stale(let session):
            return updateStaleLedger(at: Self.ledgerURL(for: session), change)
        case .live(let session):
            let url = session.map(Self.ledgerURL(for:))
            ensureLedgerLoaded(from: url)
            var updated = ledger
            change(&updated)
            guard ledgerOrigin.allowsSaving else {
                // Still applied in memory (§D3): a badge goes out and a count shows, and nothing
                // becomes durable. The marker's contract is «this memory came from that file»,
                // never «this memory equals that file» - a failed save already broke the latter.
                ledger = updated
                return .refused
            }
            guard updated != ledger else { return .unchanged }
            ledger = updated
            guard let url else { return .notPersisted }
            // A ledger that will not save costs one badge, not a pratica: reported, never
            // thrown at the person reading their mail.
            do {
                try updated.save(to: url)
                return .saved
            } catch {
                problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
                return .failed
            }
        }
    }

    /// Re-reads `session`'s ledger file (`nil`: no vault is open) and adopts it - always, where the
    /// door re-reads only when the marker differs; what `load(from:)` calls. It resets the
    /// vault-scoped state when the marker named a DIFFERENT file, or when there is no vault at all,
    /// and never for a re-read of the same one: `load(from:)` runs after every pratica command, and
    /// resetting there would wipe the tray on every rename. `.none` to a file is a first load, not a
    /// change of vault, and resets nothing either.
    func reloadLedger(for session: VaultSession?) {
        reloadLedger(from: session.map(Self.ledgerURL(for:)))
    }

    private func reloadLedger(from url: URL?) {
        if url == nil || (ledgerOrigin.url != nil && ledgerOrigin.url != url) {
            resetVaultScopedState()
        }
        adoptLedger(from: url)
    }

    /// The marker check (§D1): memory that already came from `url` is left alone - which includes
    /// `.none` with no vault, and an `.unreadable` marker, which keeps refusing until a
    /// `load(from:)` finds the file readable.
    private func ensureLedgerLoaded(from url: URL?) {
        guard ledgerOrigin.url != url else { return }
        reloadLedger(from: url)
    }

    /// Reads `url` into `ledger` and records where it came from. A file that is absent adopts an
    /// empty, writable ledger (R-03: a first write is a creation, not a refusal); one that is there
    /// and unreadable adopts an empty ledger that is never saved (§D3) and is reported once.
    private func adoptLedger(from url: URL?) {
        guard let url else {
            ledger = .empty
            ledgerOrigin = .none
            return
        }
        switch PraticaLedger.read(from: url) {
        case .loaded(let onDisk):
            ledger = onDisk
            ledgerOrigin = .loaded(url)
            reportedUnreadableLedgers.remove(url)
        case .missing:
            ledger = .empty
            ledgerOrigin = .loaded(url)
            reportedUnreadableLedgers.remove(url)
        case .unreadable:
            ledger = .empty
            ledgerOrigin = .unreadable(url)
            reportUnreadableLedger(url)
        }
    }

    /// `.stale`'s half of the door: `url`'s own file read fresh, changed, written back, and neither
    /// `ledger` nor `ledgerOrigin` ever touched - they describe the live vault alone. A save failure
    /// stays unreported here, as it was before the door existed: `problem` is the live pane's, and
    /// this write is not for the live vault.
    private func updateStaleLedger(at url: URL, _ change: (inout PraticaLedger) -> Void) -> LedgerWrite {
        var stored: PraticaLedger
        switch PraticaLedger.read(from: url) {
        case .loaded(let onDisk):
            stored = onDisk
            reportedUnreadableLedgers.remove(url)
        case .missing:
            stored = .empty
            reportedUnreadableLedgers.remove(url)
        case .unreadable:
            reportUnreadableLedger(url)
            return .refused
        }
        let before = stored
        change(&stored)
        guard stored != before else { return .unchanged }
        do {
            try stored.save(to: url)
            return .saved
        } catch {
            return .failed
        }
    }

    /// R-04: one sentence naming the file, the first time it is found unreadable and not again
    /// until a read of it has succeeded.
    private func reportUnreadableLedger(_ url: URL) {
        guard reportedUnreadableLedgers.insert(url).inserted else { return }
        problem = "Il registro delle pratiche non è leggibile e non verrà sovrascritto: "
            + "\(url.path(percentEncoded: false)). Ripara o elimina il file."
    }

    /// What belongs to the vault that was open and to no other (§D5): the list, the tray, the
    /// per-pratica throttle marks, the selection and everything read for it. Without this a pratica
    /// path that exists in two vaults (`01 Progetti/Tifone` is not an unusual name) inherits vault A's
    /// badge, proposals and window-key throttle.
    ///
    /// Deliberately NOT cleared, and the part a future reader will be tempted to «complete»:
    /// - `praticaPathRedirects` and `forgottenPraticaPaths`, and `syncingPraticaPath`,
    ///   `regeneratingPraticaPaths`, `regeneration`: an in-flight run owns them and `endSync`/
    ///   `endRegeneration` release them. A writer reaches this reset in the middle of a run (a controller
    ///   that never loaded, plus a sync finishing), and clearing a tombstone there would resurrect the
    ///   key the trash had just removed.
    /// - `problem` and `fullDiskAccessState`: not per vault.
    /// - `mailStoreEvents`, `windowKeyObserver`, `fsEventsFireTask`: per Mail store and per controller,
    ///   armed once by `startWatching(_:)`, which only the Pratiche pane calls - tearing them down here
    ///   would leave both automatic triggers disarmed until the pane was next opened. What
    ///   `watchersByPraticaPath` holds is pure throttle bookkeeping (`PraticaWatcher` is a struct of
    ///   dates), so emptying it IS stopping those watchers.
    ///
    /// `selection` is cleared by assignment and not through `select(nil, in:)`, which marks a pratica
    /// opened, rebuilds the list and reloads the timeline, all against the vault being left.
    private func resetVaultScopedState() {
        pratiche = []
        trayProposals = [:]
        trayCounts = [:]
        watchersByPraticaPath = [:]
        selection = nil
        selectedEntryID = nil
        expansion = PraticaTimelineModel.ExpansionState()
        timeline = []
        details = [:]
        links = .empty
    }
}
