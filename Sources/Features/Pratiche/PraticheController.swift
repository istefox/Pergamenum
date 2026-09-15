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

    /// The three toolbar filters (R-32).
    var filter = PraticaTimelineFilter()

    /// Per window and never persisted (R-24). Here rather than as the timeline view's
    /// own `@State` because the expansion has to survive the view being rebuilt when
    /// the filter changes, and because Opt+click needs every visible id at once.
    var expansion = PraticaTimelineModel.ExpansionState()

    /// The pratica a sync is running for, and how far it has got (R-20's progress bar,
    /// screen 1a's «12 di 80 · Annulla»).
    ///
    /// Not `private(set)`, on this property and every other one down to `ledger`
    /// below: `PraticheController+Ledger.swift` is an extension of this class in a
    /// separate file, and reads and writes all of them from `beginSync`, `endSync`,
    /// `updateProgress`, `report`, `recordSyncOutcome`, `moveLedgerState` and
    /// `remapLedgerConversations`.
    var syncingPraticaPath: String?
    var syncProgress: PraticaSyncEngine.Progress?

    /// The last thing that went wrong, in Italian, for the pane to show. Cleared by
    /// the next successful load - a stale error over a working pane is worse than none.
    var problem: String?

    /// The per-vault ledger (`…/vaults/<id>/pratiche/ledger.json`, SPEC "Per-vault
    /// state"): `lastOpenedAt` is what the badge counts from, `importedMessageIDs`
    /// what a resumed sync skips.
    var ledger: PraticaLedger = .empty

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
}
