import AppKit
import Foundation
import Observation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4, §D8, §D10,
// §D11 and §D13, plan docs/plans/contenitore.md, Task 6 - R-04, R-08, R-23, R-24, R-26.
//
// App-only (§D14): ingest and extraction run only while the app is open.

/// The Contenitore pane's controller: the drop folder's watcher and ingest, the extraction
/// queue, and what the pane shows (the notices, the selection, the scope and the filter).
///
/// At app level, beside `PraticheController`, for the same reason: the watcher keeps importing
/// while another pane is on screen. `RootView` starts it for each open vault and each change of
/// Settings › Contenitore (`.task(id:)`), and nothing else does.
@MainActor
@Observable
final class ContenitoreController {
    /// How the pane lays out its documents (ADR-0071 §D11, the mockup's list and grid).
    enum Layout: String, Sendable {
        case list
        case grid
    }

    // MARK: - What the pane shows

    /// What the engine and the queue have to tell the person, each at most once (R-08, R-11,
    /// R-26). The strip above the list draws them; «Chiudi» dismisses one.
    private(set) var notices: [ContenitoreNotice] = []
    /// The selected document's scheda, a vault-relative path. Leaving one hands its inspector
    /// edit to `retireEditor()`, which saves it, so a description typed and not yet written
    /// survives a click on another row (`ContenitoreController+Editing.swift`).
    var selection: String? {
        didSet { if selection != oldValue { selectionChanged() } }
    }
    var scope: ContenitoreScope = .all
    var filter = ContenitoreFilter()
    var layout: Layout = .list
    /// When the last document was imported, for the footer's «ultimo import».
    private(set) var lastImportAt: Date?
    /// False while the drop folder cannot be listed (R-26), or was refused by validation.
    private(set) var isDropFolderReadable = true
    /// Why the stored drop folder was refused at `start()`, so the pane can say it instead of
    /// importing from a folder the settings tab would never have accepted (a hand edit).
    private(set) var dropFolderRefusal: ContenitoreSettings.DropFolderRefusal?
    /// The queue for the open vault, nil while isolated or with no vault.
    private(set) var queue: ContenitoreExtractionQueue?
    /// The inspector's edit of the selected scheda: the draft the person types into. Held here,
    /// not in the view, so it outlives the view and `QuitCoordinator` can settle it (ADR-0073).
    /// Internal, not `private(set)`: written only by `ContenitoreController+Editing.swift`.
    var editor: ContenitoreEditor?

    // MARK: - What the pane reads from memory rather than the disk

    /// Moves each time a cached extraction changes: the queue recorded one, an import or a
    /// session change dropped some. `extraction(sha256:)` reads it, so every view showing an
    /// extraction label or matching the search redraws. Internal, not `private(set)`: it is
    /// written only by `ContenitoreController+Caches.swift`, whose members own the caches.
    var extractionRevision = 0
    /// Moves when a pane verb changed the container folders (create, rename, move, trash);
    /// `containers()` keys on it with the index and scan generations. Internal for
    /// `ContenitoreController+Caches.swift`, like `extractionRevision`.
    var containerRevision = 0
    /// The extraction records and the container tree, read once and kept until an event
    /// changes them, so no `body` pass decodes JSON or walks the folder tree. Internal for
    /// `ContenitoreController+Caches.swift`, the only file that reads or writes it.
    @ObservationIgnored var caches = ContenitoreCaches()

    // MARK: - Requests the views present (Task 7)

    /// The scheda «Classifica…» is open on.
    var classifying: String?
    /// The scheda «Rinomina…» is open on.
    var renaming: String?
    /// The scheda «Sposta in…» is choosing a container for, from a surface with no submenu.
    var moving: String?
    /// The scheda «Sposta nel Cestino» is asking about.
    var trashing: String?
    /// The container «Nuovo sottocontenitore…» creates into, the root for a top-level one.
    var creatingContainerIn: String?
    /// Quick Look's presentation, driven by the spacebar and «Apri anteprima».
    var isPreviewing = false

    // MARK: - Dependencies

    /// True under `-disableContenitore YES` or inside the unit-test host: the controller then
    /// never lists, creates or moves anything, so neither the UI suite nor `.claude/test-cmd`'s
    /// run can take files out of the person's real drop folder. `RecordingsController`'s shape.
    let isIsolated: Bool
    let vault: VaultController
    @ObservationIgnored let pasteboard: NSPasteboard
    /// «Apri» and «Mostra nel Finder» leave the app through these two, so a test can run every
    /// command, from every surface, without launching a viewer or the Finder.
    @ObservationIgnored var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var revealFiles: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    /// Internal for `ContenitoreController+RouteAndSettings.swift`, which resolves the drop folder.
    @ObservationIgnored let home: URL
    @ObservationIgnored private let today: () -> CalendarDate
    @ObservationIgnored private let extractor: any TextExtracting
    /// The one timer (plan Task 6): the second observation of a file still changing. Nil in a
    /// test, which drives `observe()` itself.
    @ObservationIgnored private let followUpDelay: Duration?
    @ObservationIgnored private let watchesDropFolder: Bool

    @ObservationIgnored private var engine: ContenitoreIngestEngine?
    @ObservationIgnored private var watcher: DropFolderEventStream?
    @ObservationIgnored private var followUp: Task<Void, Never>?
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var sessionID: ObjectIdentifier?
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var observeAgain = false
    /// Bumped by every `stop()`, so a `start()` that woke from its `await` can tell it was
    /// replaced while it slept.
    @ObservationIgnored private var startGeneration = 0
    /// Editors handed off by a selection change that still had something to write, kept until
    /// they settle so the quit can wait for them too.
    @ObservationIgnored var retiredEditors: [ContenitoreEditor] = []
    /// The folder the watcher is armed on, recorded even when a test turns the stream off.
    @ObservationIgnored private(set) var watchedFolder: URL?
    /// Awaited between an observation and the moment its report is applied. A named seam in
    /// ADR-0046 §D2's sense and nothing else: a test suspends an observation there to restart
    /// the controller mid-flight. The app never sets it.
    @ObservationIgnored var observationGate: (@MainActor () async -> Void)?

    init(
        vault: VaultController,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        today: @escaping () -> CalendarDate = { CalendarDate.today },
        extractor: any TextExtracting,
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        isTestHost: Bool = VaultState.isRunningUnderTest,
        followUpDelay: Duration? = .seconds(2),
        watchesDropFolder: Bool = true
    ) {
        self.vault = vault
        self.home = home
        self.today = today
        self.extractor = extractor
        self.pasteboard = pasteboard
        self.isIsolated = defaults.bool(forKey: "disableContenitore") || isTestHost
        self.followUpDelay = followUpDelay
        self.watchesDropFolder = watchesDropFolder
    }

    /// The controller the running app holds: the system extractor, the real home folder and the
    /// general pasteboard.
    static func live(vault: VaultController) -> ContenitoreController {
        ContenitoreController(vault: vault, extractor: SystemTextExtractor())
    }

    // MARK: - Lifecycle

    /// Starts watching the open vault's drop folder: builds the engine and the queue, enqueues
    /// every document with no finished extraction (an interrupted one included, ADR-0071 §D8),
    /// runs the catch-up observation, which creates a missing drop folder, and arms the
    /// watcher. Calling it again restarts from scratch with the current settings.
    ///
    /// A restart can arrive while this one is suspended (a vault or drop-folder change during an
    /// import), so every `await` is followed by a check that this start is still the current one
    /// (`startGeneration`, and the engine it built); a start that was replaced returns without
    /// arming anything, and the newer start's observation is run by the one still in flight.
    func start() async {
        stop()
        let generation = startGeneration
        guard !isIsolated else { return }
        guard let session = vault.session else {
            await releaseSession()
            return
        }
        if sessionID != ObjectIdentifier(session) {
            await releaseSession()
            guard generation == startGeneration else { return }
            sessionID = ObjectIdentifier(session)
        }

        // The queue outlives a restart on the same vault, so two restarts never leave two
        // extractions running at once; `releaseSession()` drops it with the vault.
        let queue = self.queue ?? makeQueue(for: session)
        self.queue = queue
        enqueueUnfinishedExtractions(in: session, on: queue)
        drain()

        let settings = session.settings.contenitore
        dropFolderRefusal = ContenitoreSettings.validateDropFolder(
            settings.dropFolder, vaultRoot: session.root, home: home
        )
        guard dropFolderRefusal == nil else {
            isDropFolderReadable = false
            return
        }
        let engine = ContenitoreIngestEngine(
            session: session, settings: settings, home: home, today: today,
            onImported: { [weak self] path in self?.imported(path) }
        )
        self.engine = engine
        await observe()
        // Not `Task.isCancelled`: a cancelled `.task` whose id did not change is a view that went
        // away, and the drop folder keeps being watched while the app runs. What decides is
        // whether a newer start or a stop replaced this one.
        guard generation == startGeneration, self.engine === engine else { return }
        startWatching(settings.resolvedDropFolder(home: home))
    }

    /// Stops the watcher, the follow-up and the engine. The queue finishes what it has and stays
    /// for the next `start()` on the same vault; `releaseSession()` drops it with the vault.
    func stop() {
        startGeneration += 1
        watcher?.stop()
        watcher = nil
        watchedFolder = nil
        followUp?.cancel()
        followUp = nil
        engine = nil
        observeAgain = false
    }

    /// Runs one observation of the drop folder and applies what it reports. A call arriving
    /// while one runs is not lost: the running one observes once more when it ends, on whichever
    /// engine is current by then. A restart during an observation replaces the engine, and the
    /// observation still in flight belongs to the old one: its report is dropped and the new
    /// engine is observed in its place.
    @discardableResult
    func observe() async -> IngestReport {
        guard engine != nil else { return IngestReport() }
        guard !isObserving else {
            observeAgain = true
            return IngestReport()
        }
        isObserving = true
        defer { isObserving = false }

        var report = IngestReport()
        repeat {
            observeAgain = false
            guard let current = engine else { break }
            let step = await current.observe()
            await observationGate?()
            guard engine === current else {
                observeAgain = engine != nil
                continue
            }
            apply(step)
            report.imported += step.imported
            report.waiting = step.waiting
            report.notices += step.notices
        } while observeAgain
        if !report.waiting.isEmpty, engine != nil { scheduleFollowUp() }
        return report
    }

    /// Removes one notice from the strip.
    func dismiss(_ notice: ContenitoreNotice) {
        notices.removeAll { $0 == notice }
    }

    /// «Riprova» on a failed import: a fresh engine forgets the files it declined, so the next
    /// observation tries them again.
    func retryImports(after notice: ContenitoreNotice) async {
        dismiss(notice)
        await start()
    }

    /// «Riprova» on a failed extraction: the document named `fileName` goes back on the queue.
    func retryExtraction(of fileName: String) {
        dismiss(.extractionFailed(file: fileName))
        guard let session = vault.session, let queue else { return }
        let lowered = fileName.lowercased()
        for record in session.index.schede(underRoot: root) where record.contenitore?.fileName.lowercased() == lowered {
            enqueue(record.relativePath, in: session, on: queue)
        }
        drain()
    }

    // MARK: - Pieces

    private func apply(_ report: IngestReport) {
        report.notices.forEach(raise)
        let unreadable = report.notices.contains(.unreadableDropFolder)
        if unreadable {
            isDropFolderReadable = false
        } else if let folder = resolvedDropFolder,
                  (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) != nil {
            isDropFolderReadable = true
            dismiss(.unreadableDropFolder)
        }
    }

    private func raise(_ notice: ContenitoreNotice) {
        guard !notices.contains(notice) else { return }
        notices.append(notice)
    }

    /// The engine wrote a scheda: queue its document for extraction.
    private func imported(_ schedaPath: String) {
        lastImportAt = Date()
        guard let session = vault.session else { return }
        if let sha256 = session.index.note(at: schedaPath)?.contenitore?.sha256 { forgetExtraction(sha256: sha256) }
        guard let queue else { return }
        enqueue(schedaPath, in: session, on: queue)
        drain()
    }

    /// Queues every document whose extraction is not finished. Reads the status only, through
    /// the controller's cache, so a restart never decodes an extracted text and the first row
    /// pass after it is answered from memory.
    private func enqueueUnfinishedExtractions(in session: VaultSession, on queue: ContenitoreExtractionQueue) {
        for record in session.index.schede(underRoot: session.settings.contenitore.root) {
            guard let sha256 = record.contenitore?.sha256 else { continue }
            if extractionStatus(sha256: sha256)?.isFinished == true { continue }
            enqueue(record.relativePath, in: session, on: queue)
        }
    }

    private func enqueue(_ schedaPath: String, in session: VaultSession, on queue: ContenitoreExtractionQueue) {
        guard let sha256 = session.index.note(at: schedaPath)?.contenitore?.sha256,
              let companion = session.companion(ofScheda: schedaPath),
              let url = try? session.store.url(for: companion)
        else { return }
        queue.enqueue(sha256: sha256, url: url)
    }

    private func drain() {
        guard let queue else { return }
        drainTask = Task { await queue.drain() }
    }

    private func scheduleFollowUp() {
        guard let followUpDelay, followUp == nil else { return }
        followUp = Task { [weak self] in
            try? await Task.sleep(for: followUpDelay)
            guard !Task.isCancelled else { return }
            self?.followUp = nil
            await self?.observe()
        }
    }

    private func startWatching(_ folder: URL) {
        watchedFolder = folder
        guard watchesDropFolder else { return }
        let stream = DropFolderEventStream(folder: folder) { [weak self] in
            Task { @MainActor in await self?.observe() }
        }
        stream.start()
        watcher = stream
    }

    private func makeQueue(for session: VaultSession) -> ContenitoreExtractionQueue {
        let queue = ContenitoreExtractionQueue(store: session.extractedTexts, extractor: extractor)
        queue.onFailed = { [weak self] url in self?.raise(.extractionFailed(file: url.lastPathComponent)) }
        queue.onRecorded = { [weak self] sha256, record in self?.recordExtraction(record, sha256: sha256) }
        return queue
    }

    /// Ends the previous vault's hold on this controller: its queue can no longer raise a notice
    /// or record an extraction here (a job it was on may still finish, into its own store).
    private func detachQueue() {
        queue?.onFailed = nil
        queue?.onRecorded = nil
        queue = nil
    }

    /// The open vault is gone or another one is open: settles the inspector's unsaved edit (it
    /// writes to the session it was read from), then forgets everything the old vault left -
    /// the queue, the notices, the selection, the scope and filter, the presented requests and
    /// the caches - so none of it shows in, or is raised into, the next one. An edit whose write
    /// failed cannot follow the old session, so it is named as a problem of the vault now open
    /// rather than dropped without a word (nothing is shown when no vault is open).
    private func releaseSession() async {
        detachQueue()
        await settleEditing()
        for owed in [editor].compactMap({ $0 }) + retiredEditors where !owed.isSettled {
            vault.recordProblem(Self.lostEditSentence(for: owed.schedaPath))
        }
        editor = nil
        retiredEditors = []
        sessionID = nil
        notices = []
        selection = nil
        scope = .all
        filter = ContenitoreFilter()
        lastImportAt = nil
        isDropFolderReadable = true
        dropFolderRefusal = nil
        (classifying, renaming, moving, trashing, creatingContainerIn) = (nil, nil, nil, nil, nil)
        isPreviewing = false
        caches = ContenitoreCaches()
        extractionRevision += 1
        containerRevision += 1
    }
}
