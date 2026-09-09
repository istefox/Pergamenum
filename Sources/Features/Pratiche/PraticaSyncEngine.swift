import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D14, §D15, §D18.
//
// App-only: `Sources/Features/Pratiche/**` is not in `sharedSources` (Project.swift),
// so `perg`/`pergamenum-mcp` never compile this file and never learn the Mail store
// exists any more than they already do through `Sources/Core/Email/**` (ADR §D19).
// Free, therefore, to hold a `VaultSession` write hop and `@MainActor` isolation.

/// Runs one pratica's sync (SPEC "Sync algorithm"): reads the published index copy
/// and the live `.emlx` tree, decodes each candidate message, writes it atomically,
/// and reports progress as it goes. The connection and every decode happen inside
/// this actor (ADR §D14); only the finished note text crosses to `@MainActor`, once
/// per message, through the `write` closure this actor was handed at `init` - the
/// same hop `VaultSession.write` already is everywhere else in this app.
///
/// TESTER NOTE (ADR-0155 §D1): every method below is a declared boundary with a
/// stub body. None of it opens a connection, reads an `.emlx`, computes a SHA-256, or
/// writes a byte - `sync(_:)` always answers "nothing done", `cancel()` only flips a
/// flag nothing reads yet, and `progressStream()` yields nothing. This keeps
/// `Tests/PraticaSyncTests.swift`'s red assertions red for the right reason (missing
/// behaviour) rather than for the wrong one (a missing symbol, or a crash). The coder
/// fills in every body; the signatures, the request/outcome shapes and the actor
/// isolation are the contract this batch is fixing.
actor PraticaSyncEngine {
    /// One `sync(_:)` call's request (SPEC "Sync algorithm").
    struct SyncRequest: Sendable {
        /// Vault-relative path of the pratica folder, e.g.
        /// `"01 Progetti/Rossi/Offerta 2026"` - `email/` and `allegati/` are resolved
        /// under it.
        var praticaFolder: String
        var dossier: Dossier
        /// Already rule-evaluated (`MembershipRule.candidates(...).messages`),
        /// newest-first is not assumed here - `PraticaSyncPlan.workItems` re-derives
        /// the order and resolves §D15's mailbox duplicates before anything is
        /// written.
        var candidates: [MailMessageRow]
        /// `Message-ID`s this pratica has already written, from the ledger - what
        /// makes a resumed sync after a cancellation pick up only what is missing
        /// (R-11).
        var onDisk: Set<String>
        var settings: PraticheSettings
    }

    /// What one `sync(_:)` call did, for the caller that records it in the ledger and
    /// updates the tray.
    struct SyncOutcome: Equatable, Sendable {
        /// Vault-relative paths of every file this run actually finished writing
        /// (`.md`, `.eml`, and `allegati/*` alike), in the order they were written -
        /// R-11: only ever files that are complete, never a partial one.
        var writtenFiles: [String]
        /// `Message-ID`s successfully imported this run - what the caller appends to
        /// `PraticaLedger.PraticaState.importedMessageIDs`.
        var importedMessageIDs: [String]
        /// `Message-ID`s this run found imported before but whose row is now gone
        /// from the store (R-16) - the caller marks these "not in Mail" in the
        /// ledger; their files are never touched.
        var noLongerInMail: [String]
        /// Vault-relative paths of `pending` files this run rewrote because the body
        /// had since arrived (R-15) - the only files a sync ever rewrites unasked.
        var regeneratedPendingFiles: [String]
        /// `true` when `cancel()` stopped this run before every candidate was
        /// processed - `writtenFiles`/`importedMessageIDs` still hold everything
        /// finished before the boundary where cancellation was observed (R-11).
        var cancelled: Bool

        static let empty = SyncOutcome(
            writtenFiles: [], importedMessageIDs: [], noLongerInMail: [],
            regeneratedPendingFiles: [], cancelled: false
        )
    }

    /// One event per message boundary (SPEC "Sync algorithm": "emit progress
    /// (n/total)") - what a UI progress bar and this batch's cancellation tests both
    /// subscribe to.
    struct Progress: Equatable, Sendable {
        var completed: Int
        var total: Int
    }

    /// `mailStoreURL` is a published generation's `Envelope Index`
    /// (`MailStoreCopy.PublishResult`, or a fixture's `MailStoreFixture.Built.indexURL`
    /// in a test) - opened lazily, inside this actor, on the first `sync(_:)` call.
    /// `vaultRoot` is the open vault's own root; attachments and `.eml` are written
    /// directly under it (they are not notes, so they never go through `write`).
    /// `write` is the single `@MainActor` hop to `VaultSession.write` every finished
    /// message's `.md` note goes through (ADR §D14).
    init(
        mailStoreURL: URL,
        vaultRoot: URL,
        write: @escaping @Sendable @MainActor (_ text: String, _ relativePath: String) throws -> Void
    ) {
        self.mailStoreURL = mailStoreURL
        self.vaultRoot = vaultRoot
        self.write = write
    }

    private let mailStoreURL: URL
    private let vaultRoot: URL
    private let write: @Sendable @MainActor (_ text: String, _ relativePath: String) throws -> Void
    private var cancelled = false
    private var progressContinuation: AsyncStream<Progress>.Continuation?

    /// Runs the sync algorithm end to end for one pratica. Cancellation (`cancel()`)
    /// is checked once per message boundary, never mid-message, which is what makes
    /// "everything written is complete" true regardless of when it is called
    /// (R-11).
    func sync(_ request: SyncRequest) async throws -> SyncOutcome {
        // STUB: does not open `mailStoreURL`, does not call `PraticaSyncPlan
        // .workItems`, does not read a single `.emlx`, and never calls `write`.
        .empty
    }

    /// Cooperative: takes effect at the next message boundary inside `sync(_:)`, not
    /// immediately and not mid-write (R-11, ADR §D14).
    func cancel() {
        cancelled = true
    }

    /// One `Progress` per finished message, terminated when the in-flight `sync(_:)`
    /// call returns (or immediately, when none is running) - a test drains this to
    /// call `cancel()` at a precise message boundary rather than racing a sleep
    /// against the actor.
    func progressStream() -> AsyncStream<Progress> {
        // STUB: finishes immediately - no `sync(_:)` call ever reports through this
        // yet.
        AsyncStream { continuation in continuation.finish() }
    }
}
