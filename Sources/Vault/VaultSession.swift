import Foundation
import Observation

/// An open vault, with no user interface anywhere underneath it: the settings, the
/// vocabulary, the index, and the one path every write goes through.
///
/// Split out of `VaultController` by ADR-0007 §D3. Everything the app can do to a
/// vault used to live in extensions on a `@MainActor @Observable` type that imports
/// SwiftUI, so no headless process could call any of it - and re-implementing the
/// conventions in a second place is exactly what principle 5 forbids. This type is
/// what the CLI and the MCP server call; `VaultController` becomes the observable
/// facade over it and keeps only what the views have to watch.
///
/// `@Observable` rather than plain: the facade exposes this object's settings, index
/// and vocabulary straight through, and SwiftUI has to see a change to any of them.
/// `Observation` is a standard-library module and carries no interface framework with
/// it, so a command-line tool linking this file pays nothing for it.
///
/// `@MainActor` is isolation, not user interface. The views read `settings` and
/// `index` synchronously, so an `actor` is ruled out and a bare class would have to be
/// sent across the boundary on every `await rescan()`. A command-line tool runs its
/// entry point on the main actor and holds one of these exactly as the app does; the
/// consequence for the MCP server is that vault operations serialise, which for a
/// single vault with a second writer in it is the behaviour to want anyway.
@MainActor
@Observable
final class VaultSession {
    /// The vault root as it was opened, symlinks and all.
    ///
    /// Not resolved here: `NoteStore` resolves its own copy for the boundary check,
    /// and the watcher and the recents list both want the spelling the user gave.
    let root: URL
    let store: NoteStore
    /// Every note write's own history, always on (ADR-0011 D2) - unlike `journal`
    /// below, which a connector opts into for its own reason.
    @ObservationIgnored let history: NoteHistory
    /// Where a file's disk work happens now (ADR-0041 §D9, widened by ADR-0043 §D1 from
    /// "the disk work of a write" to "the disk work"): the boundary check, the atomic byte
    /// write or move or trash, the stat, the record derivation, the history write and the
    /// journal append, all in one actor hop. Built once in `init`, over the same `store`
    /// and `history` this session already owns.
    ///
    /// Not `private`: §D1 moved the move/trash/non-note-write primitives onto the actor
    /// too, and `VaultSession+Journal.swift`/`VaultSession+Watching.swift` call them
    /// directly, from a different file than this one.
    @ObservationIgnored let disk: VaultDisk
    /// Where the starred paths are read from and written back to (ADR-0012 D6).
    @ObservationIgnored let starredStore: StarredStore

    /// Test-only observability: incremented once per `starredStore.save` this session
    /// performs, wherever `VaultSession+Starred.swift` calls it. Per-instance - two tests
    /// each opening their own session cannot see each other's increments, and nothing in
    /// production reads it. Exists so `Tests/VaultBatchMoveTests.swift` can assert R-05's
    /// "one starred-file rewrite per batch, not per moved note" claim without instrumenting
    /// the file system (ADR-0041 §D8, Task 7).
    @ObservationIgnored var testOnlyStarredSaveCount = 0
    /// Where this vault's derived, per-machine state lives, resolved once at open
    /// (ADR-0017). `cacheURL` and `VaultController`'s `ThumbnailStore` both read it.
    @ObservationIgnored let state: VaultState

    /// The starred notes, as relative paths.
    ///
    /// Held here rather than read from disk on every draw: the note list asks whether a path is
    /// starred once per row.
    ///
    /// **Not `private(set)`, and the convention is the enforcement.** Every door onto this set is
    /// in `VaultSession+Starred.swift`, which is another file and so cannot write through a
    /// private setter - the same trade `VaultController.columns` makes for its own doors,
    /// documented here rather than checked by the compiler. Writing it from anywhere else means
    /// the file on disk and this set stop agreeing.
    var starred: Set<String> = []

    private(set) var settings: VaultSettings = .default
    private(set) var vocabulary: Vocabulary = .empty
    private(set) var index = IndexSnapshot()

    /// Problems worth showing: an unreadable note, a settings file that would not
    /// parse, a vocabulary that could not be loaded.
    private(set) var problems: [String] = []

    /// Hashes this session itself wrote, keyed by path, tagged with the sequence the
    /// write landed at (ADR-0043 §D6/§D10, Task 7).
    ///
    /// A single `String` per path (this type's shape before this task) lost whichever
    /// write's hash was not the most recent one recorded on the main actor: two writes
    /// racing the same path before either's actor hop resumed left only the second
    /// hash behind, so a watcher callback for the first one's bytes had nothing to
    /// match and was reported as an external change. A list keeps every write's hash
    /// until a reconciliation actually observes it - pruned only then (§D6: dropping
    /// every entry at or below the matched sequence), never on a cap or a time window
    /// (ADR-0001 §D3.3 rejects both by name for exactly the edits they would lose).
    ///
    /// Appended *before* `write`'s actor hop, with a provisional sequence this session
    /// invents (`reserveProvisionalSequence()`), then corrected to the actor's own
    /// returned sequence once the hop resumes (`reconcileProvisionalSequence`) - never
    /// the other way around, or the window §D10 exists to close would reopen: a watcher
    /// racing the write must never find the file on disk before this session already
    /// holds its hash, under some sequence.
    var selfWrittenHashes: [String: [(sequence: UInt64, hash: String)]] = [:]

    /// Provisional sequence tags handed to a write's `selfWrittenHashes` entry before
    /// its actor hop resumes and the real sequence is known (§D10). Counts down from
    /// `UInt64.max` so a provisional tag can never collide with an actor-issued
    /// sequence, which counts up from 1 per path (`VaultDisk.nextSequence(for:)`).
    @ObservationIgnored private var nextProvisionalSequence: UInt64 = .max

    private func reserveProvisionalSequence() -> UInt64 {
        defer { nextProvisionalSequence -= 1 }
        return nextProvisionalSequence
    }

    /// Corrects a provisional entry to the sequence the actor actually stamped it
    /// with. A no-op if the entry is gone - a concurrent reconciliation already
    /// matched and pruned it by hash, which needs no correction to still be correct.
    private func reconcileProvisionalSequence(at path: String, provisional: UInt64, actual: UInt64) {
        guard var entries = selfWrittenHashes[path],
              let index = entries.firstIndex(where: { $0.sequence == provisional })
        else { return }
        entries[index].sequence = actual
        selfWrittenHashes[path] = entries
    }

    /// Rolls back a provisional entry a write never actually made it to disk with -
    /// `WriteRefusal` refuses before a byte moves, and a phantom hash for bytes that
    /// were never written would leak in `selfWrittenHashes` forever (no watcher event
    /// will ever match it, since it was never true).
    private func removeSelfWrittenEntry(at path: String, sequence: UInt64) {
        guard var entries = selfWrittenHashes[path] else { return }
        entries.removeAll { $0.sequence == sequence }
        if entries.isEmpty {
            selfWrittenHashes.removeValue(forKey: path)
        } else {
            selfWrittenHashes[path] = entries
        }
    }

    /// Highest `VaultDisk.DiskWriteOutcome.sequence` this session has applied to the
    /// index, per path (ADR-0041 §D11, Task 8).
    ///
    /// An `actor` serialises its own state but not the order its callers' continuations
    /// resume in, so two `write`s racing on the same path could otherwise apply to the
    /// index out of order. This is the bookkeeping the guard needs: an outcome whose
    /// `sequence` is not strictly greater than what is recorded here for its path must be
    /// dropped rather than applied. Test-visible (not `private`) because `apply(_:at:)`
    /// below - `VaultWriteOrderingTests`' seam for forcing that inversion deterministically
    /// - has to read and write it from outside this file.
    var appliedSequence: [String: UInt64] = [:]

    /// The copy of `vocabolari.json` shipped with the app, used to seed a vault that
    /// has none yet (SPEC §4.6).
    ///
    /// Injected because a command-line tool has no resource bundle to find it in: the
    /// app hands in `Bundle.pergamenumResources`, and a caller with nothing to offer
    /// passes nil and gets an empty vocabulary plus a recorded problem, rather than a
    /// crash or a silently wrong tag check.
    private let bundledVocabulary: URL?

    /// `stateBase` has no default, and that is the point: `.claude/test-cmd` runs the
    /// unit suite at the end of every turn, and a resolver that defaulted to the real
    /// Application Support directory would have the suite writing into
    /// `~/Library/Application Support/it.stefer.pergamenum/` the first time a test
    /// forgot to override it - the same failure `RecentVaults.volatile()` exists to
    /// prevent, now with files instead of defaults. `VaultController` and
    /// `VaultResolution` pass `try VaultState.applicationSupportBase()`; the tests
    /// pass a temporary one (ADR-0017).
    init(root: URL, stateBase: URL, bundledVocabulary: URL? = nil) {
        self.root = root
        self.store = NoteStore(root: root)
        self.bundledVocabulary = bundledVocabulary

        // Settings first, because the vault id lives in them and `state` needs it
        // resolved before anything that reads from it is built.
        let loaded = Self.readSettings(in: root)
        let identity = Self.resolveIdentity(settings: loaded.settings, root: root)
        self.settings = identity.settings
        self.problems = loaded.problems + identity.problems
        self.state = VaultState(id: identity.id, base: stateBase)

        self.history = NoteHistory(directory: state.history)
        self.disk = VaultDisk(store: store, history: history)
        self.starredStore = StarredStore(root: root)

        problems.append(contentsOf: state.migrateIfNeeded(from: privateDirectory, root: root))

        loadVocabulary()
        starred = starredStore.load()
    }

    // MARK: Reading and writing

    func read(_ relativePath: String) throws -> (record: NoteRecord, text: String) {
        try store.read(relativePath)
    }

    /// A boundary violation answers `false`, not a thrown error (ADR-0041 §D2, Task 2's
    /// tester-declared policy for the four `Bool`/`URL?`-returning call sites): "does this
    /// path exist inside the vault" is a question a caller-supplied string can only answer
    /// truthfully from inside the vault.
    func exists(_ relativePath: String) -> Bool {
        guard let url = try? store.url(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// What a write did, for a caller that has to react to it.
    ///
    /// Every write in the app was followed by the same four lines: write the file,
    /// record the hash, update the index, and put an open editor back in step. The
    /// first three are this type's business and happen below; the fourth is the
    /// facade's, and this is what tells it which note changed and to what.
    struct WriteResult: Equatable, Sendable {
        let path: String
        let text: String
    }

    /// How a write ended, for the callers that have more than one way to fail.
    ///
    /// A `Bool` flattened cases that call for different responses - a task line that
    /// moved under us leaves the index behind and wants a rescan, a day with no blocks
    /// and no note wants nothing at all, and neither is the same as a file that would
    /// not open. Each case here exists because some caller has to tell it apart.
    enum WriteOutcome: Sendable {
        case written(WriteResult)
        /// Nothing needed doing, and that is a success.
        case unchanged
        /// The file no longer matches what the index said; a rescan is due.
        case stale
        case failed

        /// What was written, when something was.
        var result: WriteResult? {
            if case .written(let result) = self { return result }
            return nil
        }

        /// Whether the caller got what it asked for, which `unchanged` also is.
        var succeeded: Bool {
            switch self {
            case .written, .unchanged: true
            case .stale, .failed: false
            }
        }
    }

    /// Records what every write replaced, when a caller has asked for a net.
    ///
    /// Nil for the app, which is the point: a person editing their own note in their
    /// own editor does not need an undo log beside the file. A connector writing on
    /// behalf of a model does (ADR-0007 §D6), and it sets this.
    @ObservationIgnored var journal: WriteJournal?

    /// What the journal records as the cause. Set by the caller before it writes.
    @ObservationIgnored var journalCommand = ""

    /// The gesture currently open, if one is (ADR-0016 §D1).
    ///
    /// Every write made while this is set carries it, which is what lets `undo` reverse a
    /// rename as one thing instead of as a burst of unrelated writes. Opened and closed only by
    /// `transaction(_:_:)` in `VaultSession+Journal`; nothing else assigns it.
    @ObservationIgnored var currentOperation: String?

    /// When true, writes are computed and not performed.
    ///
    /// The alternative was a `preview` variant of every write, which is two code paths
    /// for one behaviour and the second one drifts. This way `--dry-run` exercises the
    /// same arithmetic, the same conventions and the same refusals as the real thing,
    /// and stops one line short of the disk.
    @ObservationIgnored var isDryRun = false

    /// Records a problem for the UI to show without interrupting what the user is
    /// doing. Used where the failure is recoverable by retrying.
    func recordProblem(_ message: String) {
        problems.append(message)
    }

    func clearProblems() {
        problems.removeAll()
    }

    // MARK: Scanning

    /// Full rebuild from disk. Cheap by design, and the answer to any doubt about the
    /// index being stale (SPEC §12, "rigenera indice").
    func rescan() async {
        let clock = ContinuousClock()
        let start = clock.now
        let cacheURL = cacheURL
        let cache = IndexCache(url: cacheURL)
        let cached = cache.load()
        let cachedBoardTasks = cache.loadBoardTasks()
        let root = root

        let outcome = await Task.detached(priority: .userInitiated) {
            var scanner = VaultScanner(root: root)
            scanner.cached = cached
            scanner.cachedBoardTasks = cachedBoardTasks
            return scanner.scan()
        }.value
        index.replaceAll(with: outcome, duration: clock.now - start)

        // Written after the index is in place: the cache is an optimisation, and the
        // app must be usable whether or not it can be saved (SPEC §12).
        let records = outcome.records
        let boardTaskRecords = outcome.boardTaskRecords
        let problem: String = await Task.detached(priority: .utility) {
            IndexCache(url: cacheURL).save(records, boardTasks: boardTaskRecords)
        }.value
        if !problem.isEmpty { problems.append("cache: \(problem)") }
    }

    /// Empties the cache (ADR-0017: beside the vault, not inside `.pergamenum/`) and
    /// rebuilds the index from the vault (SPEC §12, Avanzate › svuota cache).
    func clearCache() async {
        IndexCache(url: cacheURL).clear()
        await rescan()
    }

    // MARK: Vault-private files

    var privateDirectory: URL {
        root.appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
    }

    private var cacheURL: URL {
        state.cacheFile
    }

    /// A fresh `WriteJournal` resolved against this vault's state directory, for every
    /// call site that used to rebuild `WriteJournal(root: root)` by hand (ADR-0017).
    /// `WriteJournal` itself carries no cached state worth reusing across calls - it
    /// reads and appends straight from disk - so a computed property that builds a new
    /// value each time is exactly as cheap as the type it wraps, and it is the one
    /// place `state.journal` has to be spelled out.
    var journalOnDisk: WriteJournal {
        WriteJournal(directory: state.journal)
    }

    /// Applies a settings change and writes `settings.json` back.
    ///
    /// Written immediately rather than on close: a setting that survives only a clean
    /// quit is a setting the user cannot rely on.
    func updateSettings(_ change: (inout VaultSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated

        do {
            try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated)
                .write(to: privateDirectory.appending(path: VaultLayout.settingsFile), options: .atomic)
        } catch {
            problems.append("\(VaultLayout.settingsFile): \(error.localizedDescription)")
        }
    }

    /// Loads the vocabulary replica from the vault, seeding it from the bundled copy
    /// the first time (SPEC §4.6).
    private func loadVocabulary() {
        let url = privateDirectory.appending(path: VaultLayout.vocabularyFile)

        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard let bundled = bundledVocabulary else {
                // Two different situations, and telling them apart matters: the app
                // shipping without its copy is a broken build, while a command-line
                // tool never had one to begin with and is working as designed on a
                // vault that has no replica yet (ADR-0007 §D2).
                problems.append(
                    """
                    nessun vocabolario: \(VaultLayout.privateDirectory)/\(VaultLayout.vocabularyFile) \
                    non esiste e questo processo non ha una copia da cui crearlo; \
                    le regole sui tag non verranno applicate
                    """
                )
                return
            }
            do {
                try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: url)
            } catch {
                problems.append("vocabolari.json could not be created: \(error.localizedDescription)")
                return
            }
        }

        do {
            vocabulary = try JSONDecoder().decode(Vocabulary.self, from: try Data(contentsOf: url))
        } catch {
            vocabulary = .empty
            problems.append("\(VaultLayout.vocabularyFile): \(error.localizedDescription)")
        }
    }

    /// Re-imports the closed vocabularies from the harness-system checkout and writes
    /// the replica back into the vault.
    func importConventions(from repository: URL) {
        let conventions = repository.appending(path: "convenzioni", directoryHint: .isDirectory)
        let tagURL = conventions.appending(path: "tag.md")
        let namingURL = conventions.appending(path: "naming.md")

        guard let tagDocument = try? String(contentsOf: tagURL, encoding: .utf8),
              let namingDocument = try? String(contentsOf: namingURL, encoding: .utf8)
        else {
            problems.append(
                "convenzioni/tag.md or naming.md could not be read at "
                    + repository.path(percentEncoded: false)
            )
            return
        }

        let result = HarnessImporter.parse(tagDocument: tagDocument, namingDocument: namingDocument)
        problems.append(contentsOf: result.problems.map { "import: \($0)" })
        guard result.problems.isEmpty else { return }

        var imported = result.vocabulary
        // Says where the tables came from and when, and that this file is a replica.
        // Without it the first import silently deleted the only warning against
        // hand-editing what harness-system owns (SPEC §1, principle 5).
        imported.note = """
            Replica of the closed tables of harness-system, imported from \
            \(repository.path(percentEncoded: false)) on \(CalendarDate.today). \
            The repo is the source of truth: when a convention changes, re-run \
            "Importa convenzioni…" rather than editing this file.
            """
        vocabulary = imported

        let url = privateDirectory.appending(path: VaultLayout.vocabularyFile)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(imported).write(to: url, options: .atomic)
        } catch {
            problems.append("vocabolari.json could not be written: \(error.localizedDescription)")
        }
    }
}

// MARK: - ADR-0043 §D1 - the one door onto the index
//
// The old single-record index-refresh helper used to be this door and was reachable,
// unguarded, from five call sites (§D1's own count). Deleted rather than kept as a
// forwarder, for the reason ADR-0041
// §D1 already gave about the vault boundary: a guard a caller may route around is a guard
// the next call site will route around, not out of malice but by omission. `apply` lives
// here - the same file `index` is declared in - because `index`'s setter is `private`, and
// this is the one function anywhere in the module allowed to call it.
extension VaultSession {
    /// Applies every mutation whose sequence is strictly newer than what this path already
    /// has, dropping the rest rather than letting an out-of-order continuation move a row
    /// backwards (§D11, widened to every writer by §D1). Returns how many were newer.
    @discardableResult
    func apply(_ mutations: [VaultDisk.IndexMutation]) -> Int {
        var applied = 0
        for mutation in mutations {
            guard mutation.sequence > appliedSequence[mutation.path, default: 0] else { continue }
            appliedSequence[mutation.path] = mutation.sequence
            index.update(mutation.record, at: mutation.path)
            applied += 1
        }
        return applied
    }
}

// MARK: - ADR-0041 Task 8 / ADR-0043 §D2, §D5 - the one write door
//
// ADR-0041 §D9 added this as the **async** overload beside a synchronous `write(_:to:)`,
// the two resolved by whether the call site said `await`. ADR-0043 §D2 deleted the
// synchronous one: two doors onto the same file meant two ordering regimes, and the
// sequence guard below can only be relied on if every write comes through the actor. The
// cost is the cascade that deletion forced - `async` all the way out to the SwiftUI
// actions and the connectors' front ends - which is this chain's Tasks 1 to 3.
extension VaultSession {
    /// The async door onto the write ADR-0041 §D9 describes: the disk work - the boundary
    /// check, the atomic write, the stat, the record derivation, the history write and the
    /// journal append - happens in one hop on `disk`, an actor. Everything that has to
    /// happen on the main actor *before* that hop still does: the dry-run short-circuit
    /// (ADR-0007 §D6), and the hash recorded into `selfWrittenHashes` (§D10 - before the
    /// file can exist, so a watcher callback can never observe a write whose hash this
    /// session has not already recorded).
    ///
    /// **§D5:** this door no longer reads `existing` on the main actor before the hop - that
    /// read and the suspension after it is exactly Race 2 (ADR-0043 §"Race 2"), two
    /// overlapping writes recording the same journal "before". Only what the main actor
    /// alone knows - the command, the operation id, the entry id and timestamp - travels
    /// across, as a `JournalDescriptor`, built only when a journal is armed (the actor
    /// never reads a file nobody is going to journal). `VaultDisk.write` reads the current
    /// bytes itself, immediately before writing the new ones, inside the same isolation.
    ///
    /// **§D8, Task 9:** `expecting`, when not nil, is the hash the caller's `text` was
    /// derived from. The actor compares it against the file's current bytes - the read
    /// §D5 already performs, so this costs nothing extra - and throws `WriteRefusal`
    /// without writing a byte when they differ, rather than silently clobbering a change
    /// it never saw (ADR-0007 §D6: a write that did nothing and said nothing is the
    /// failure mode the guardrails exist to prevent). `nil` (the default) keeps every
    /// pre-existing call site's shape: no precondition, an unconditional write.
    @discardableResult
    func write(_ text: String, to relativePath: String, expecting: String? = nil) async throws -> WriteResult {
        // ADR-0007 §D6's first guardrail: a dry run must never reach the actor.
        guard !isDryRun else { return WriteResult(path: relativePath, text: text) }

        // §D10: computed on the main actor, before the hop - the file cannot exist yet at
        // this point, so an FSEvents callback can never observe a write whose hash this
        // session has not already recorded. Tagged with a provisional sequence (Task 7):
        // the real one is the actor's to give, and only once it resumes.
        let hash = NoteStore.hash(Data(text.utf8))
        let provisional = reserveProvisionalSequence()
        selfWrittenHashes[relativePath, default: []].append((sequence: provisional, hash: hash))

        var journalDescriptor: VaultDisk.JournalDescriptor?
        if journal != nil {
            let now = Date()
            journalDescriptor = VaultDisk.JournalDescriptor(
                entryID: WriteJournal.makeID(at: now),
                timestamp: now,
                command: journalCommand,
                operation: currentOperation
            )
        }

        // Unconditional and scoped to notes (ADR-0011 D2): the decision stays on the main
        // actor, only the writing itself moves into the actor.
        let recordsHistory = relativePath.hasSuffix(".md")

        do {
            let outcome = try await disk.write(
                text, to: relativePath,
                precomputedHash: hash,
                expecting: expecting,
                journalDescriptor: journalDescriptor,
                journal: journal,
                recordsHistory: recordsHistory
            )

            // §D11/§D1: an outcome whose sequence is not newer than what this session
            // already applied for this path is dropped rather than moving the index
            // backwards.
            reconcileProvisionalSequence(at: relativePath, provisional: provisional, actual: outcome.mutation.sequence)
            apply([outcome.mutation])
            // The write happened; the net or the hash agreement did not. Say so rather
            // than pretending otherwise.
            if let problem = outcome.journalProblem { recordProblem(problem) }
            return WriteResult(path: relativePath, text: text)
        } catch {
            // The write never reached disk (most often `WriteRefusal`): the provisional
            // hash never became true and must not linger - nothing will ever match it.
            removeSelfWrittenEntry(at: relativePath, sequence: provisional)
            throw error
        }
    }
}

// MARK: - ADR-0043 §D8 - the optional expected-hash precondition

extension VaultSession {
    /// Thrown by `write(_:to:expecting:)` when the caller's `expecting` hash no longer
    /// matches the file's current bytes: the read that produced `text` straddled a
    /// suspension, somebody else wrote in between, and this write refuses rather than
    /// silently discarding that edit.
    enum WriteRefusal: Error, CustomStringConvertible, Equatable {
        case movedOn(String)

        var description: String {
            switch self {
            case .movedOn(let path):
                "«\(path)» è cambiato da quando questa scrittura è partita, non lo tocco"
            }
        }
    }
}

