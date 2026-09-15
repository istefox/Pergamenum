import CryptoKit
import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D14, §D15, §D18.
//
// App-only: `Sources/Features/Pratiche/**` is not in `sharedSources` (Project.swift),
// so `perg`/`pergamenum-mcp` never compile this file and never learn the Mail store
// exists any more than they already do through `Sources/Core/Email/**` (ADR §D19).
// Free, therefore, to hold a `VaultSession` write hop and `@MainActor` isolation, and
// to reach for `CryptoKit` for R-10's SHA-256.

/// Runs one pratica's sync (SPEC "Sync algorithm"): reads the published index copy
/// and the live `.emlx` tree, decodes each candidate message, writes it atomically,
/// and reports progress as it goes. The connection and every decode happen inside
/// this actor (ADR §D14); only the finished note text crosses to `@MainActor`, once
/// per message, through the `write` closure this actor was handed at `init` - the
/// same hop `VaultSession.write` already is everywhere else in this app.
actor PraticaSyncEngine {
    /// `mailStoreURL` is a published generation's `Envelope Index`
    /// (`MailStoreCopy.PublishResult`, or a fixture's `MailStoreFixture.Built.indexURL`
    /// in a test) - opened lazily, inside this actor, on the first `sync(_:)` call.
    /// `vaultRoot` is the open vault's own root; attachments and `.eml` are written
    /// directly under it (they are not notes, so they never go through `write`).
    /// `write` is the single `@MainActor` hop to `VaultSession.write` every finished
    /// message's `.md` note goes through (ADR §D14).
    ///
    /// `expecting` (ADR-0043 §D8, Task 9) carries the hash the two read-modify-write
    /// patches below (`repairCorruptAttachments`, `commit`'s row-4 branch) read before
    /// composing their patch, or `nil` for a full render composed from Mail rather than
    /// from the file on disk (§D8 excludes that case by name).
    init(
        mailStoreURL: URL,
        vaultRoot: URL,
        write: @escaping @Sendable @MainActor (
            _ text: String, _ relativePath: String, _ expecting: String?
        ) async throws -> Void
    ) {
        self.mailStoreURL = mailStoreURL
        self.vaultRoot = vaultRoot
        self.boundary = VaultBoundary(root: vaultRoot)
        self.write = write
    }

    /// Back-compat overload for a caller with no "before" to compare, or one that
    /// predates the `expecting:` precondition and wants every write unconditional -
    /// `expecting` is `nil` on every call this engine makes through it. Kept so a
    /// pre-existing two-argument `write` closure (this engine's own test doubles
    /// included) keeps compiling unchanged; the engine's own internals always call the
    /// three-argument `write` above.
    init(
        mailStoreURL: URL,
        vaultRoot: URL,
        write: @escaping @Sendable @MainActor (_ text: String, _ relativePath: String) async throws -> Void
    ) {
        self.init(mailStoreURL: mailStoreURL, vaultRoot: vaultRoot) { text, relativePath, _ in
            try await write(text, relativePath)
        }
    }

    private let mailStoreURL: URL
    private let vaultRoot: URL
    /// The only way this engine turns `request.praticaFolder` - a folder name that
    /// reaches it from a caller, not from a walk - into a directory it reads or writes
    /// (ADR-0041 §D2).
    ///
    /// Not `private`: `PraticaSyncEngine+Paths.swift`'s `directory(_:of:)` and
    /// `PraticaSyncEngine+Messages.swift`'s `regenerationPreview(_:messageID:rowID:)`
    /// are extensions of this actor in separate files, and read it.
    let boundary: VaultBoundary
    /// `async` since ADR-0041 Task 8: the closure's body calls `VaultSession.write`'s
    /// actor-hop overload. Every call site already says `await` regardless - crossing
    /// from this actor to the closure's `@MainActor` isolation required it before this
    /// change too - so nothing at the three call sites (`:398`, `:878`, `:906`) changes
    /// shape, only their third argument.
    ///
    /// Not `private`: `PraticaSyncEngine+Folder.swift`'s `repairCorruptAttachments(
    /// request:folder:outcome:)` and `PraticaSyncEngine+Messages.swift`'s `commit(_:
    /// request:folder:outcome:)` are extensions of this actor in separate files, and
    /// call it.
    let write: @Sendable @MainActor (
        _ text: String, _ relativePath: String, _ expecting: String?
    ) async throws -> Void
    /// Not `private(set)`'s getter: `PraticaSyncEngine+Folder.swift`'s
    /// `repairCorruptAttachments(request:folder:outcome:)` and `PraticaSyncEngine+
    /// Messages.swift`'s `regeneratePending(request:reader:folder:outcome:)` are
    /// extensions of this actor in separate files, and read it at their own
    /// per-message cancellation boundary - the setter stays `private`, since only
    /// `sync(_:)` and `cancel()` above ever assign it.
    private(set) var cancelled = false
    private var progressChannel: (
        stream: AsyncStream<Progress>,
        continuation: AsyncStream<Progress>.Continuation
    )?
    /// Opened on the first `sync(_:)` and kept: the connection is an `OpaquePointer`
    /// and never leaves this actor (ADR §D14).
    private var reader: MailStoreReader?

    /// Runs the sync algorithm end to end for one pratica. Cancellation (`cancel()`)
    /// is checked once per message boundary, never mid-message, which is what makes
    /// "everything written is complete" true regardless of when it is called
    /// (R-11).
    func sync(_ request: SyncRequest) async throws -> SyncOutcome {
        cancelled = false
        defer { finishProgress() }

        let reader = try openedReader()
        let items = PraticaSyncPlan.workItems(
            dossier: request.dossier,
            candidates: request.candidates,
            onDisk: request.onDisk,
            settings: request.settings
        )
        var outcome = SyncOutcome.empty
        var folder = try folderContext(of: request)
        // ADR-0040 §D7.3: a file the scan above could not trash, reported once here -
        // never silently retried, and its link was never touched.
        outcome.attachmentProblems.append(contentsOf: folder.attachmentTrashFailures)
        // §D7: repairs any corrupt file the scan just trashed before anything else in
        // this run reads `folder`, so a fresh copy of the same attachment can resolve
        // in the very same sync (see the main loop's `hasPendingAttachments` guard).
        try await repairCorruptAttachments(request: request, folder: &folder, outcome: &outcome)

        for (offset, item) in items.enumerated() {
            // `decodeAndCommit` (PraticaSyncEngine+Messages.swift) is what stands in
            // for `prepare`+`commit` at this call site: both take or return
            // `PreparedMessage`, `fileprivate` on ADR §D4's own instruction, and
            // unreachable by name from this file.
            guard try await decodeAndCommit(
                item.row, request: request, reader: reader, folder: &folder, outcome: &outcome
            ) else {
                break
            }
            emit(Progress(completed: offset + 1, total: items.count))
        }

        guard !cancelled else { return outcome }

        // SPEC "Sync algorithm", the two passes after the loop.
        try await regeneratePending(request: request, reader: reader, folder: &folder, outcome: &outcome)
        outcome.noLongerInMail = noLongerInMail(request: request, reader: reader)
        return outcome
    }

    /// Cooperative: takes effect at the next message boundary inside `sync(_:)`, not
    /// immediately and not mid-write (R-11, ADR §D14).
    func cancel() {
        cancelled = true
    }

    /// One `Progress` per finished message, terminated when the in-flight `sync(_:)`
    /// call returns - a test drains this to call `cancel()` at a precise message
    /// boundary rather than racing a sleep against the actor.
    ///
    /// Buffered from the moment the channel exists rather than from the moment
    /// somebody iterates it: a caller that starts `sync(_:)` in one task and
    /// subscribes from another would otherwise lose whichever events landed in
    /// between, which is exactly the boundary a cancellation is aimed at. A stream
    /// asked for while no sync is running stays open until the next one ends.
    func progressStream() -> AsyncStream<Progress> {
        channel().stream
    }

    // MARK: - Progress channel

    private func channel() -> (
        stream: AsyncStream<Progress>,
        continuation: AsyncStream<Progress>.Continuation
    ) {
        if let progressChannel { return progressChannel }
        let created = AsyncStream<Progress>.makeStream(of: Progress.self, bufferingPolicy: .unbounded)
        progressChannel = created
        return created
    }

    private func emit(_ progress: Progress) {
        channel().continuation.yield(progress)
    }

    private func finishProgress() {
        progressChannel?.continuation.finish()
        progressChannel = nil
    }

    // MARK: - The store

    /// Not `private`: `PraticaSyncEngine+Messages.swift`'s `regenerationPreview(_:
    /// messageID:rowID:)` is an extension of this actor in a separate file, and calls
    /// this alongside `sync(_:)` above, in this same file.
    func openedReader() throws -> MailStoreReader {
        if let reader { return reader }
        let opened = try MailStoreReader(storeURL: mailStoreURL)
        reader = opened
        return opened
    }

    /// R-16: an already-imported message that this run's candidate set no longer
    /// carries, and that the index cannot resolve either, is gone from Mail. Its files
    /// are never touched - only the link goes.
    ///
    /// The index is asked first (`message_global_data.message_id_header`, ADR §D3)
    /// precisely so that a caller which hands over a candidate list with the imported
    /// messages already subtracted does not turn every message it ever imported into
    /// «non più in Mail».
    private func noLongerInMail(request: SyncRequest, reader: MailStoreReader) -> [String] {
        let surfaced = Set(request.candidates.compactMap(\.messageID))
        return request.onDisk.subtracting(surfaced).sorted().filter { messageID in
            if case .found = reader.row(forMessageID: messageID) { return false }
            return true
        }
    }
}
