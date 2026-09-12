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
        /// The one message an explicit «Rigenera» (§D6's second exception) may
        /// rewrite. `nil` for every ordinary sync, which is what keeps §D6's guard
        /// absolute everywhere else (ADR §D21).
        ///
        /// Defaulted, and declared last, so every existing `SyncRequest(...)` call
        /// site (production and test) keeps compiling unchanged.
        var regenerating: String? = nil
    }

    /// What one `sync(_:)` call did, for the caller that records it in the ledger and
    /// updates the tray.
    struct SyncOutcome: Equatable, Sendable {
        /// Vault-relative path of every message **note** this run finished writing, in
        /// the order they were written - R-11: only ever files that are complete,
        /// never a partial one.
        ///
        /// One entry per message, not one per file: an `.eml` sidecar (R-09) and a
        /// copied attachment (R-10) are parts of the message this list already names,
        /// and counting them would make "how much did this run import" depend on the
        /// retention setting and on how many files the sender happened to attach.
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
        /// §D3's bridge triples for every message this run wrote - a fresh import and a
        /// regeneration alike, since a regeneration is exactly when a stale ROWID gets
        /// corrected. A row Mail did not thread (`conversationID == nil`) produces no
        /// triple: there is no conversation for R-14 to re-derive.
        ///
        /// Declared here (ADR-0155 §D1); `commit` does not append to it yet - that is
        /// the coder's job (ADR §D23.1).
        var bridge: [PraticaLedger.Entry]
        /// Note paths whose attachment list this run amended - a pending entry that
        /// resolved, or a corrupt file that was trashed and downgraded (ADR-0040 §D5,
        /// §D7). Never a full rewrite: `regeneratedPendingFiles` keeps its exact
        /// ADR-0036 meaning, a `pending` body that arrived, and nothing is added to it
        /// by this fix.
        ///
        /// Defaulted and declared last (ADR-0040 §D10), so every existing
        /// construction site, production and test, keeps compiling unchanged.
        var resolvedAttachmentFiles: [String] = []
        /// Sentences for the pane's `problem` line: a file that could not be trashed, a
        /// downgrade that could not be written (ADR-0040 §D7.3). Empty on every
        /// healthy run.
        var attachmentProblems: [String] = []

        static let empty = SyncOutcome(
            writtenFiles: [], importedMessageIDs: [], noLongerInMail: [],
            regeneratedPendingFiles: [], cancelled: false, bridge: []
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
        write: @escaping @Sendable @MainActor (_ text: String, _ relativePath: String) async throws -> Void
    ) {
        self.mailStoreURL = mailStoreURL
        self.vaultRoot = vaultRoot
        self.boundary = VaultBoundary(root: vaultRoot)
        self.write = write
    }

    private let mailStoreURL: URL
    private let vaultRoot: URL
    /// The only way this engine turns `request.praticaFolder` - a folder name that
    /// reaches it from a caller, not from a walk - into a directory it reads or writes
    /// (ADR-0041 §D2).
    private let boundary: VaultBoundary
    /// `async` since ADR-0041 Task 8: the closure's body calls `VaultSession.write`'s
    /// actor-hop overload. Every call site already says `await` regardless - crossing
    /// from this actor to the closure's `@MainActor` isolation required it before this
    /// change too - so nothing at the three call sites (`:394`, `:848`, `:871`) changes.
    private let write: @Sendable @MainActor (_ text: String, _ relativePath: String) async throws -> Void
    private var cancelled = false
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
            // Decoding happens first and writes nothing: it is the window during which
            // a `cancel()` sent from outside gets queued on this actor.
            let prepared = prepare(item.row, request: request, reader: reader, folder: folder)
            // ADR §D14: cancellation is observed at the write boundary, never
            // mid-message. The yields are what let a queued `cancel()` actually run -
            // an actor only services another job while the job it is running is
            // suspended, and everything above this line is synchronous.
            await Task.yield()
            await Task.yield()
            if cancelled {
                outcome.cancelled = true
                break
            }
            if let prepared {
                try await commit(prepared, request: request, folder: &folder, outcome: &outcome)
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

    private func openedReader() throws -> MailStoreReader {
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

    // MARK: - What is already in the folder

    /// One message file already on disk, and what it says about itself - R-08's
    /// collision rule and §D6's "never rewrite" both need the recorded `Message-ID`,
    /// not just the name.
    private struct ExistingMessage {
        var fileName: String
        var document: MessageDocument
        /// The file's raw text, as read from disk - ADR-0040 §D6: a patch is compared
        /// against this so `commit` needs no second read, and the no-op rule (a patch
        /// identical to what is already there is never written) has something to
        /// compare against.
        var text: String
    }

    /// Everything the folder already holds that a decision this run makes depends on.
    private struct FolderContext {
        var messagesByID: [String: ExistingMessage] = [:]
        /// Every `.md` name in `email/` with the `Message-ID` it carries (empty when
        /// the file is not a message file) - `PraticaNaming.uniqueMessageFileName`'s
        /// own input.
        var takenNoteNames: [(fileName: String, messageID: String)] = []
        var attachmentNameByDigest: [String: String] = [:]
        var takenAttachmentNames: Set<String> = []
        /// ADR-0040 §D7: names this scan trashed for failing `AttachmentIntegrity` -
        /// free for a retry to reuse (never in `takenAttachmentNames`, never digested
        /// into `attachmentNameByDigest`, R-11/R-12). `repairCorruptAttachments` turns
        /// each into a pending entry on the message(s) that still link it, right after
        /// this scan and before the main loop reads `messagesByID`.
        var corruptAttachmentNames: Set<String> = []
        /// §D7.3 sentences for a corrupt file this run could not move to the Trash -
        /// merged into `outcome.attachmentProblems` by the caller. Its link is left
        /// alone precisely because it is here: an orphan link to a file that could not
        /// be removed is worse than a link to a file that is merely still broken.
        var attachmentTrashFailures: [String] = []
    }

    private func folderContext(of request: SyncRequest) throws -> FolderContext {
        var context = FolderContext()

        let emailDirectory = try directory("email", of: request)
        for name in Self.fileNames(in: emailDirectory) where name.hasSuffix(".md") {
            let url = emailDirectory.appending(path: name, directoryHint: .notDirectory)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let document = MessageDocument.parse(text)
            context.takenNoteNames.append((name, document?.frontmatter.messageID ?? ""))
            guard let document else { continue }
            context.messagesByID[document.frontmatter.messageID] = ExistingMessage(
                fileName: name, document: document, text: text
            )
        }

        let allegatiDirectory = try directory("allegati", of: request)
        for name in Self.fileNames(in: allegatiDirectory) {
            let url = allegatiDirectory.appending(path: name, directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: url) else {
                context.takenAttachmentNames.insert(name)
                continue
            }
            // ADR-0040 §D7.1: the verdict is taken before the digest, so a corrupt
            // file's SHA-256 never enters `attachmentNameByDigest` (R-12) - the same
            // ordering `prepare`'s own attachment loop already uses.
            let verdict = AttachmentIntegrity.verdict(of: data, named: name, contentType: nil)
            guard verdict == .usable else {
                var trashedURL: NSURL?
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                    // Free for the retry to reuse - never taken, never digested.
                    context.corruptAttachmentNames.insert(name)
                } catch {
                    // §D7.3: a file that could not be removed keeps its name taken and
                    // its link intact - only the failure is reported.
                    context.takenAttachmentNames.insert(name)
                    context.attachmentTrashFailures.append(
                        "Non è stato possibile spostare «\(name)» nel Cestino: \(error.localizedDescription)"
                    )
                }
                continue
            }
            context.takenAttachmentNames.insert(name)
            // First name wins, in the sorted order above: two identical files already
            // in the folder are a state this app did not create, and linking to the
            // same one of them every run beats linking to whichever the file system
            // listed first today.
            let digest = Self.digest(of: data)
            if context.attachmentNameByDigest[digest] == nil {
                context.attachmentNameByDigest[digest] = name
            }
        }
        return context
    }

    /// ADR-0040 §D7: the second half of the repair pass - turns each corrupt
    /// attachment's link into a pending entry on every message that still carries it,
    /// right after the scan that found it and before the main loop reads `folder`, so
    /// a message whose attachment both breaks and gets a fresh copy from Mail in the
    /// same run resolves in that one sync.
    private func repairCorruptAttachments(
        request: SyncRequest,
        folder: inout FolderContext,
        outcome: inout SyncOutcome
    ) async throws {
        guard !folder.corruptAttachmentNames.isEmpty else { return }

        // Sorted Message-IDs: a deterministic order for a deterministic outcome, the
        // same reason `fileNames(in:)` sorts.
        for messageID in folder.messagesByID.keys.sorted() {
            guard let existing = folder.messagesByID[messageID] else { continue }
            let corruptLinks = Set(existing.document.frontmatter.linkedAttachmentNames)
                .intersection(folder.corruptAttachmentNames)
            guard !corruptLinks.isEmpty else { continue }

            // ADR §D14: the same per-message cancellation boundary as
            // `regeneratePending` and the main loop.
            await Task.yield()
            if cancelled {
                outcome.cancelled = true
                return
            }

            var entries = existing.document.frontmatter.attachments
            for name in corruptLinks {
                guard let index = entries.firstIndex(of: MessageDocument.attachmentEntry(linking: name))
                else { continue }
                entries[index] = MessageDocument.attachmentEntry(pending: name)
            }
            guard let patchedText = MessageAttachmentPatch.applying(entries: entries, to: existing.text)
            else { continue }
            // §D6's no-op rule, reused for the repair patch: nothing to write means
            // nothing written.
            guard patchedText != existing.text else { continue }

            let notePath = "\(request.praticaFolder)/email/\(existing.fileName)"
            try await write(patchedText, notePath)

            var updatedDocument = existing.document
            updatedDocument.frontmatter.attachments = entries
            folder.messagesByID[messageID] = ExistingMessage(
                fileName: existing.fileName, document: updatedDocument, text: patchedText
            )
            outcome.resolvedAttachmentFiles.append(notePath)
        }
    }

    // MARK: - One message, decoded

    /// `fileprivate` for the same reason as `PreparedMessage` below, which holds an
    /// array of these.
    fileprivate struct PreparedAttachment: Sendable {
        var fileName: String
        var bytes: Data
        var digest: String
    }

    /// `Sendable`: holds only value types (ADR §D21) - what lets a `RegenerationPlan`
    /// carry one across the `actor` boundary unopened.
    ///
    /// `fileprivate`, not `private`: `RegenerationPlan.prepared` below is itself
    /// `fileprivate` (ADR §D21's "declared in the same file, so `fileprivate` reaches
    /// it"), and a `fileprivate` stored property cannot have a strictly-`private`
    /// type - the compiler rejects that as inconsistent access. Still invisible
    /// outside this file either way.
    fileprivate struct PreparedMessage: Sendable {
        var messageID: String
        var fileName: String
        var noteText: String
        var document: MessageDocument
        /// The RFC 822 bytes to keep beside the note (R-09), `nil` when retention is
        /// off and always `nil` for a `pending` message (§D18).
        var originalBytes: Data?
        var attachments: [PreparedAttachment]
        var attachmentNameByDigest: [String: String]
        var takenAttachmentNames: Set<String>
        /// R-15: this file exists and says `body: pending`, and the body has arrived.
        var isRegeneration: Bool
        /// §D3's bridge: the index ROWID and Mail's own `conversation_id` for this
        /// message, carried through to `commit` so it can append the triple `outcome.bridge`
        /// records (ADR §D23.1). `conversationID` is `nil` for a row Mail did not thread.
        var rowID: Int
        var conversationID: Int?
    }

    /// Reads and decodes one message. Writes nothing, and answers `nil` for every
    /// reason this run must leave the message alone: no `.emlx` to read, no
    /// `Message-ID` to key it by, or a file already on disk that §D6 forbids
    /// rewriting.
    private func prepare(
        _ row: MailMessageRow,
        request: SyncRequest,
        reader: MailStoreReader,
        folder: FolderContext
    ) -> PreparedMessage? {
        guard let emlxURL = locate(row, reader: reader),
              let container = try? EMLXReader.read(contentsOf: emlxURL)
        else { return nil }

        let headers = EmailHeaderParser.parse(Self.headerText(of: container.rfc822))
        // The row's own id first: it is what `onDisk`, the ledger and
        // `PraticaSyncPlan`'s dedup all key on. The header is the fallback for a row
        // read straight out of the index, which carries none (ADR §D3).
        guard let messageID = row.messageID ?? headers.messageID.map({ "<\($0)>" })
        else { return nil }
        // «Escludi» enforced a second time, now that the id is known: a row read
        // straight out of the index carries no `Message-ID`, so
        // `MembershipRule.candidates` could not match it against `dossier.excluded`
        // and let it through. Without this check every excluded message came back on
        // the next sync.
        guard !request.dossier.excluded.contains(messageID) else { return nil }

        let isPending = container.bodyState == .pending
        let existing = folder.messagesByID[messageID]
        if let existing {
            // §D6: a file already on disk is rewritten for one of three reasons - it was
            // written `pending` and the body has since arrived (R-15), this is the one
            // message an explicit «Rigenera» named (ADR §D21.1), or it carries at least
            // one pending attachment entry (ADR-0040 §D3/§D5) - which narrows this guard
            // rather than removing it: every other message stays untouched.
            let isRequestedRegeneration = request.regenerating == messageID
            let hasPendingAttachments = !existing.document.frontmatter.pendingAttachmentNames.isEmpty
            guard isRequestedRegeneration
                || (existing.document.frontmatter.body == .pending && !isPending)
                || hasPendingAttachments
            else { return nil }
        }

        let date = headers.date ?? row.dateSent ?? row.dateReceived ?? .distantPast
        let calendarDate = CalendarDate(date)
        let subject = headers.subject ?? row.subject ?? ""
        let ownAddresses = Set(request.settings.ownAddresses)
        let carbonCopies = Self.addresses(of: "cc", in: headers)
        let direction = MessageDocument.direction(from: headers.from, ownAddresses: ownAddresses)
        let counterpart = MessageDocument.counterpart(
            direction: direction, from: headers.from, to: headers.to, cc: carbonCopies,
            ownAddresses: ownAddresses
        )

        var attachmentNameByDigest = folder.attachmentNameByDigest
        var takenAttachmentNames = folder.takenAttachmentNames
        var writes: [PreparedAttachment] = []
        var links: [String] = []
        // ADR-0040 §D3: placed names for parts `AttachmentIntegrity` rejected -
        // never hashed, never written, never handed to `place`.
        var pendingAttachmentNames: [String] = []
        var storeReferences: [MessageDocument.StoreReference] = []
        var newText: String
        var quotedHistory: String?
        var signature: String?

        if isPending {
            // R-15: a placeholder, never an empty body - a file with nothing in it
            // reads as a message that said nothing.
            newText = Self.pendingPlaceholder
        } else {
            let parts = MIMEDecoder.decode(container.rfc822)
            var body = Self.bodyText(of: parts)
            for (ordinal, part) in parts.enumerated() {
                switch part.kind {
                case .attachment(let filename):
                    let name = filename ?? Self.unnamedAttachment
                    let bytes = part.decodedData ?? Data()
                    // ADR-0040 §D2/§D3, R-01/R-02/R-12: the verdict is taken once, before
                    // the threshold comparison, and governs both the copy branch and the
                    // store-reference branch (R-07, Task 5) - never place, never digest,
                    // never a `StoreReference`, for anything but `.usable`.
                    let verdict = AttachmentIntegrity.verdict(
                        of: bytes, named: name, contentType: part.contentType
                    )
                    guard verdict == .usable else {
                        pendingAttachmentNames.append(
                            PraticaNaming.attachmentFileName(date: calendarDate, name: name)
                        )
                        continue
                    }
                    if bytes.count > Self.thresholdBytes(request.settings) {
                        // R-10: recorded where it really lives, never copied.
                        storeReferences.append(MessageDocument.StoreReference(
                            name: name,
                            size: bytes.count,
                            storePath: Self.storePath(
                                of: name, at: emlxURL, rowID: row.rowID, part: ordinal + 1
                            )
                        ))
                        continue
                    }
                    let placed = Self.place(
                        bytes, named: name, date: calendarDate,
                        nameByDigest: &attachmentNameByDigest, taken: &takenAttachmentNames
                    )
                    if let write = placed.write { writes.append(write) }
                    links.append(placed.fileName)

                case .inlineImage(let contentID):
                    let bytes = part.decodedData ?? Data()
                    let name = part.filename ?? "\(contentID).png"
                    // ADR-0040 §D9: integrity first, `isDecorative` second - a corrupt
                    // image's dimensions are unreadable, so `isDecorative` would already
                    // answer `false` (its own "never drop on a guess" rule) and place it.
                    let verdict = AttachmentIntegrity.verdict(
                        of: bytes, named: name, contentType: part.contentType
                    )
                    guard verdict == .usable else {
                        pendingAttachmentNames.append(
                            PraticaNaming.attachmentFileName(date: calendarDate, name: name)
                        )
                        // Same removal the decorative branch below performs, so the body
                        // never ends up with an embed pointing nowhere.
                        body = body.replacingOccurrences(of: "cid:\(contentID)", with: "")
                        continue
                    }
                    guard !InlineImageClassifier.isDecorative(bytes) else {
                        // R-10: a signature logo is not an attachment. The reference
                        // goes with it, or the body keeps a `cid:` pointing nowhere.
                        body = body.replacingOccurrences(of: "cid:\(contentID)", with: "")
                        continue
                    }
                    let placed = Self.place(
                        bytes, named: name, date: calendarDate,
                        nameByDigest: &attachmentNameByDigest, taken: &takenAttachmentNames
                    )
                    if let write = placed.write { writes.append(write) }
                    // Embedded rather than listed: an inline image belongs where the
                    // sender put it (SPEC "Edge cases"). The whole Markdown image
                    // construct `HTMLTextReducer.appendImage` wrote - `![alt](cid:…)`,
                    // brackets and parens included - is replaced, not just the `cid:`
                    // reference inside it: replacing the reference alone left the
                    // image syntax around it in place, so the wikilink embed landed
                    // wrapped in `![alt](…)` instead of standing on its own.
                    let escapedContentID = NSRegularExpression.escapedPattern(for: contentID)
                    while let range = body.range(
                        of: #"!\[[^\]]*\]\(cid:\#(escapedContentID)\)"#,
                        options: .regularExpression
                    ) {
                        body.replaceSubrange(range, with: "![[\(placed.fileName)]]")
                    }
                    // A bare `cid:` reference outside the Markdown image construct (a second
                    // mention, or one the HTML reducer emitted unwrapped) still names the same
                    // placed attachment - point it there too, or the embed above is replaced
                    // while this one is silently dropped from the rendered note.
                    body = body.replacingOccurrences(of: "cid:\(contentID)", with: "![[\(placed.fileName)]]")

                case .textPlain, .textHTML:
                    continue
                }
            }
            let split = QuoteSplitter.split(body)
            newText = split.newText
            quotedHistory = split.quotedHistory
            signature = split.signature
        }

        let fileName: String
        if let existing {
            // R-15's regeneration is in place: the same file, so a link to it from
            // anywhere else in the vault survives the body's arrival.
            fileName = existing.fileName
        } else {
            fileName = PraticaNaming.uniqueMessageFileName(
                date: calendarDate,
                time: Self.time(of: date),
                counterpart: counterpart?.displayText ?? Self.unknownCounterpart,
                subject: subject,
                messageID: messageID,
                existing: folder.takenNoteNames
            )
        }
        let baseName = (fileName as NSString).deletingPathExtension
        // §D18: a pending message has no complete RFC 822 bytes to keep, so it gets no
        // `.eml` and no `pergamenum-mail-original`, whatever retention says.
        let keepsOriginal = request.settings.keepOriginalEML && !isPending

        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: Self.frontmatterSchemaVersion,
                messageID: messageID,
                conversationID: row.conversationID,
                direction: direction,
                date: date,
                received: row.dateReceived,
                from: headers.from.map(Self.headerForm) ?? row.sender ?? "",
                to: headers.to.map(Self.headerForm),
                cc: carbonCopies.map(Self.headerForm),
                subject: subject,
                // ADR-0040 §D3: linked entries in their existing order, then pending
                // ones - `body` stays `isPending ? .pending : .complete` unchanged, so a
                // message with some usable and some not-yet-usable parts is `.complete`
                // (R-04).
                attachments: links.map(MessageDocument.attachmentEntry(linking:))
                    + pendingAttachmentNames.map(MessageDocument.attachmentEntry(pending:)),
                storeReferences: storeReferences,
                body: isPending ? .pending : .complete,
                original: keepsOriginal ? "\(baseName).eml" : nil
            ),
            newText: newText,
            quotedHistory: quotedHistory,
            signature: signature
        )

        return PreparedMessage(
            messageID: messageID,
            fileName: fileName,
            noteText: MessageDocument.render(document, tags: Self.tags(for: request)),
            document: document,
            originalBytes: keepsOriginal ? container.rfc822 : nil,
            attachments: writes,
            attachmentNameByDigest: attachmentNameByDigest,
            takenAttachmentNames: takenAttachmentNames,
            isRegeneration: existing != nil,
            rowID: row.rowID,
            conversationID: row.conversationID
        )
    }

    /// ADR §D4: only `.notInStore` means «non più in Mail», and a drifted rule is not
    /// that - both are skipped here, and R-16's caption is decided by
    /// `noLongerInMail(request:reader:)` against the index instead.
    private func locate(_ row: MailMessageRow, reader: MailStoreReader) -> URL? {
        switch EMLXLocator.locate(predictedURL: reader.emlxPath(forRow: row)) {
        case let .found(url), let .foundPartial(url):
            return url
        case .notInStore, .ruleFailed:
            return nil
        }
    }

    // MARK: - «Rigenera» (ADR §D21)

    /// Everything an approved «Rigenera» needs to perform itself, acquired before any
    /// file was touched. Opaque on purpose: the only way to obtain one is
    /// `regenerationPreview`, and the only thing that can be done with one is
    /// `commitRegeneration` - so the bytes shown and the bytes written cannot diverge.
    struct RegenerationPlan: Sendable, Identifiable {
        var id: String { notePath }
        let praticaFolder: String
        let messageID: String
        let notePath: String
        let currentText: String
        let replacementText: String
        let diff: String?
        let attachmentFileNames: [String]
        let rewritesOriginalEML: Bool
        fileprivate let prepared: PreparedMessage
        fileprivate let request: SyncRequest
    }

    enum RegenerationFailure: Error, Equatable, Sendable {
        case rowNotFound
        case notInStore
        case notDecodable
        case fileMissing
    }

    /// ADR §D21.1/§D21.3: resolves the row (the index first, the ledger's own `rowID`
    /// only on `.notResolvableFromIndex`), locates and decodes its `.emlx` through the
    /// existing `prepare(_:request:reader:folder:)` with `request.regenerating` set to
    /// `messageID` (which is what narrows §D6's guard for exactly this one message),
    /// and diffs the result against the file already on disk.
    func regenerationPreview(
        _ request: SyncRequest, messageID: String, rowID: Int?
    ) async throws -> RegenerationPlan {
        let reader = try openedReader()

        let row: MailMessageRow
        if let known = request.candidates.first(where: { $0.messageID == messageID }) {
            // Already resolved by whoever built this request (typically the same
            // candidate set a sync just ran with) - reusing it, rather than re-querying
            // the index, is what makes «Rigenera» reproduce exactly what the last
            // import wrote when nothing has changed.
            row = known
        } else {
            switch reader.row(forMessageID: messageID) {
            case .found(let found):
                row = found
            case .notResolvableFromIndex:
                guard let rowID, let found = reader.row(rowID: rowID) else {
                    throw RegenerationFailure.rowNotFound
                }
                row = found
            }
        }

        // §D4: only `.notInStore` is R-16's legitimate «non più in Mail» - a drifted
        // fan-out rule is a diagnostic, not that, so it is reported as `.notDecodable`
        // rather than silently reused as `.notInStore`.
        switch EMLXLocator.locate(predictedURL: reader.emlxPath(forRow: row)) {
        case .found, .foundPartial:
            break
        case .notInStore:
            throw RegenerationFailure.notInStore
        case .ruleFailed:
            throw RegenerationFailure.notDecodable
        }

        var regenerationRequest = request
        regenerationRequest.regenerating = messageID
        let folder = try folderContext(of: request)
        guard let prepared = prepare(row, request: regenerationRequest, reader: reader, folder: folder)
        else { throw RegenerationFailure.notDecodable }

        let notePath = "\(request.praticaFolder)/email/\(prepared.fileName)"
        let noteURL = try boundary.url(for: notePath)
        guard let currentText = try? String(contentsOf: noteURL, encoding: .utf8) else {
            throw RegenerationFailure.fileMissing
        }

        return RegenerationPlan(
            praticaFolder: request.praticaFolder,
            messageID: messageID,
            notePath: notePath,
            currentText: currentText,
            replacementText: prepared.noteText,
            diff: UnifiedDiff.between(currentText, prepared.noteText, path: notePath, context: 3),
            attachmentFileNames: prepared.attachments.map(\.fileName),
            rewritesOriginalEML: prepared.originalBytes != nil,
            prepared: prepared,
            request: regenerationRequest
        )
    }

    /// ADR §D21.2: reuses the existing `commit(_:request:folder:outcome:)` verbatim -
    /// a throwaway `FolderContext` is enough, since a regeneration writes exactly one
    /// message and does not need the rest of the folder's state.
    func commitRegeneration(_ plan: RegenerationPlan) async throws -> SyncOutcome {
        var folder = FolderContext()
        var outcome = SyncOutcome.empty
        try await commit(plan.prepared, request: plan.request, folder: &folder, outcome: &outcome)
        return outcome
    }

    // MARK: - Writing

    private func commit(
        _ prepared: PreparedMessage,
        request: SyncRequest,
        folder: inout FolderContext,
        outcome: inout SyncOutcome
    ) async throws {
        // Sidecars first, note last: a note is what says "this message is imported", so
        // it must never be the thing that exists while what it points at does not. The
        // attachment bytes are written the same way regardless of write mode below
        // (ADR-0040 §D4).
        let allegatiDirectory = try directory("allegati", of: request)
        for attachment in prepared.attachments {
            try Self.writeAtomically(
                attachment.bytes,
                to: allegatiDirectory.appending(path: attachment.fileName, directoryHint: .notDirectory)
            )
        }
        folder.attachmentNameByDigest = prepared.attachmentNameByDigest
        folder.takenAttachmentNames = prepared.takenAttachmentNames

        let notePath = "\(request.praticaFolder)/email/\(prepared.fileName)"

        // ADR-0040 §D4: the write-mode fork, decided here and nowhere else - the guard
        // in `prepare` is reached from two callers (the main loop and
        // `regeneratePending`) and a mode chosen there would differ between them. Four
        // rows, evaluated in order; the first three keep today's full render, the
        // fourth is the new attachment-line-only patch.
        //
        // One addition beyond §D4's own table: a pending attachment can resolve into an
        // over-threshold `StoreReference` rather than a local link (R-07's retry). That
        // entry is never part of `pergamenum-mail-attachments` - `MessageAttachmentPatch`
        // only ever touches that one key (its own test suite confirms this) - so a
        // change to `storeReferences` cannot be expressed as a one-line patch and falls
        // back to a full render, the same tradeoff §D4 already accepts for a `pending`
        // body's arrival. This never fires for an attachment that keeps failing (the
        // no-cost retry of §D6 is untouched): it fires exactly once, the sync the
        // reference actually appears.
        let existingOnDisk = folder.messagesByID[prepared.messageID]
        let isRequestedRegeneration = request.regenerating == prepared.messageID
        let mustFullyRender = existingOnDisk == nil
            || isRequestedRegeneration
            || existingOnDisk?.document.frontmatter.body == .pending
            || existingOnDisk?.document.frontmatter.storeReferences != prepared.document.frontmatter.storeReferences

        guard mustFullyRender else {
            // Row 4: an existing, non-`pending`, non-regenerating note - only its
            // `pergamenum-mail-attachments` line may change. The `.eml` sidecar is
            // never rewritten in this mode: its bytes have not changed (§D18).
            guard let existingOnDisk,
                  let patchedText = MessageAttachmentPatch.applying(
                      entries: prepared.document.frontmatter.attachments, to: existingOnDisk.text
                  )
            else { return }
            // §D6: a patch identical to the file already on disk is never written -
            // this is what makes the unresolved retry free.
            guard patchedText != existingOnDisk.text else { return }

            try await write(patchedText, notePath)

            folder.messagesByID[prepared.messageID] = ExistingMessage(
                fileName: prepared.fileName, document: prepared.document, text: patchedText
            )
            outcome.resolvedAttachmentFiles.append(notePath)
            if let conversationID = prepared.conversationID {
                outcome.bridge.append(PraticaLedger.Entry(
                    messageID: prepared.messageID, rowID: prepared.rowID, conversationID: conversationID
                ))
            }
            return
        }

        if let originalBytes = prepared.originalBytes {
            let baseName = (prepared.fileName as NSString).deletingPathExtension
            try Self.writeAtomically(
                originalBytes,
                to: try directory("email", of: request)
                    .appending(path: "\(baseName).eml", directoryHint: .notDirectory)
            )
        }

        try await write(prepared.noteText, notePath)

        if !prepared.isRegeneration {
            folder.takenNoteNames.append((prepared.fileName, prepared.messageID))
            outcome.importedMessageIDs.append(prepared.messageID)
        } else {
            outcome.regeneratedPendingFiles.append(notePath)
        }
        folder.messagesByID[prepared.messageID] = ExistingMessage(
            fileName: prepared.fileName, document: prepared.document, text: prepared.noteText
        )
        outcome.writtenFiles.append(notePath)
        // §D23.1: outside the isRegeneration branch above — a regeneration is exactly
        // when a stale ROWID gets corrected, so its triple is recorded too.
        if let conversationID = prepared.conversationID {
            outcome.bridge.append(PraticaLedger.Entry(
                messageID: prepared.messageID, rowID: prepared.rowID, conversationID: conversationID
            ))
        }
    }

    /// SPEC "Sync algorithm": «re-check `pending` files from earlier runs». A message
    /// whose id the ledger already lists is not a work item (`PraticaSyncPlan` skips
    /// it), so the one file §D6 allows a sync to rewrite would otherwise stay pending
    /// forever - widened by ADR-0040 §D5 to also revisit a `.complete` message that
    /// still carries a pending attachment entry, for the same reason.
    private func regeneratePending(
        request: SyncRequest,
        reader: MailStoreReader,
        folder: inout FolderContext,
        outcome: inout SyncOutcome
    ) async throws {
        for row in request.candidates {
            guard let messageID = row.messageID, request.onDisk.contains(messageID) else { continue }
            let frontmatter = folder.messagesByID[messageID]?.document.frontmatter
            guard frontmatter?.body == .pending || !(frontmatter?.pendingAttachmentNames.isEmpty ?? true)
            else { continue }
            guard let prepared = prepare(row, request: request, reader: reader, folder: folder)
            else { continue }
            await Task.yield()
            if cancelled {
                outcome.cancelled = true
                return
            }
            try await commit(prepared, request: request, folder: &folder, outcome: &outcome)
        }
    }

    /// R-11's «write temp, rename»: `.atomic` is Foundation's own implementation of it
    /// - the bytes land in a temporary sibling and are renamed over the target in one
    /// operation, so an interrupted run leaves either the previous file or the new one
    /// and never half of either.
    private static func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Attachment placement (R-10)

    private static func place(
        _ bytes: Data,
        named name: String,
        date: CalendarDate,
        nameByDigest: inout [String: String],
        taken: inout Set<String>
    ) -> (fileName: String, write: PreparedAttachment?) {
        let digest = Self.digest(of: bytes)
        // Same content already in this pratica: linked, never copied a second time
        // (SPEC "Attachment file name").
        if let existing = nameByDigest[digest] { return (existing, nil) }

        let fileName = uniqueAttachmentName(
            PraticaNaming.attachmentFileName(date: date, name: name), taken: taken
        )
        nameByDigest[digest] = fileName
        taken.insert(fileName)
        return (fileName, PreparedAttachment(fileName: fileName, bytes: bytes, digest: digest))
    }

    /// Same name, different content: `-2`, `-3`, … before the extension (SPEC
    /// "Attachment file name"). Reached only after the SHA-256 check above, so a
    /// second copy of the same bytes never gets here.
    private static func uniqueAttachmentName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        let stem = (base as NSString).deletingPathExtension
        let suffix = (base as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = suffix.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(suffix)"
            if !taken.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Where an over-threshold attachment actually lives, for the chip that opens it
    /// «if still there» (SPEC "Edge cases"): Mail's own extracted copy when it exists,
    /// and otherwise the `.emlx` container that really holds those bytes. Never a path
    /// this app has not looked at.
    private static func storePath(of name: String, at emlxURL: URL, rowID: Int, part: Int) -> String {
        let extracted = EMLXReader
            .attachmentsDirectory(forMessageAt: emlxURL, rowID: rowID, part: "\(part)")
            .appending(path: name, directoryHint: .notDirectory)
        let path = extracted.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) ? path : emlxURL.path(percentEncoded: false)
    }

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Reading the message

    /// `EmailHeaderParser` stops at the first blank line, but it splits on `.newlines`,
    /// where a bare `\r\n` yields an empty component - the same normalisation
    /// `MIMEDecoder` does before calling it, and without which every CRLF message
    /// parses as having no headers at all.
    private static func headerText(of rfc822: Data) -> String {
        let end = EMLXReader.headerBodySeparator(in: rfc822) ?? rfc822.endIndex
        return String(decoding: rfc822[rfc822.startIndex..<end], as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// SPEC "Sync algorithm": «text/plain preferred, else HTML→markdown».
    private static func bodyText(of parts: [MIMEPart]) -> String {
        let plain = parts.first { $0.kind == .textPlain }?.decodedText ?? ""
        if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalised(plain)
        }
        guard let html = parts.first(where: { $0.kind == .textHTML })?.decodedText else {
            return normalised(plain)
        }
        return normalised(HTMLTextReducer.reduce(html))
    }

    /// A note in this vault has Unix line endings; a message off the wire has CRLF.
    private static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private static func addresses(of name: String, in headers: EmailHeaders) -> [EmailAddress] {
        guard let raw = headers.all.first(where: { $0.name.lowercased() == name })?.value
        else { return [] }
        return EmailHeaderParser.parseAddressList(raw)
    }

    /// `Mario Rossi <m.rossi@rossi-spa.it>`, the form the SPEC's own frontmatter
    /// example carries.
    private static func headerForm(_ address: EmailAddress) -> String {
        guard let name = address.name, !name.isEmpty else { return address.address }
        return "\(name) <\(address.address)>"
    }

    private static func time(of date: Date) -> TaskTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TaskTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// ADR §D11's tag set for a message file: `type-note` (what `missingRequired`
    /// demands of every non-daily note - two `type-*` tags is legal, only `status` is
    /// limited to one), `type-email`, `topic-pratica`, the pratica's own
    /// `client-<slug>` when the folder layout gives one, and `source-email`.
    private static func tags(for request: SyncRequest) -> [Tag] {
        [
            Tag("type-note"),
            Tag("type-email"),
            Tag("topic-pratica"),
            PraticaNaming.clientTag(
                forPraticaAt: request.praticaFolder, root: request.settings.rootFolder
            ),
            Tag("source-email"),
        ].compactMap { $0 }
    }

    // MARK: - Paths and constants

    /// `email/` or `allegati/` under the pratica's own folder, refused when
    /// `praticaFolder` escapes the vault (ADR-0041 §D2). Every read and every write this
    /// engine performs under a pratica goes through here, so the refusal lands before the
    /// directory is listed rather than after something has been read out of it.
    private func directory(_ name: String, of request: SyncRequest) throws -> URL {
        let folder = request.praticaFolder
        return try boundary.url(for: folder.isEmpty ? name : "\(folder)/\(name)")
    }

    private static func fileNames(in directory: URL) -> [String] {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        )
        // Sorted, so every decision derived from what is already on disk is a function
        // of the folder's contents rather than of the file system's listing order.
        return (names ?? []).sorted()
    }

    private static let frontmatterSchemaVersion = 1
    private static let unknownCounterpart = "Sconosciuto"
    private static let unnamedAttachment = "allegato"
    private static let pendingPlaceholder =
        "*Il corpo di questo messaggio non è ancora stato scaricato da Mail.*"

    private static func thresholdBytes(_ settings: PraticheSettings) -> Int {
        settings.attachmentThresholdMB * 1024 * 1024
    }
}
