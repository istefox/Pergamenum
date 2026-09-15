import Foundation

extension PraticaSyncEngine {
    // MARK: - What is already in the folder

    /// One message file already on disk, and what it says about itself - R-08's
    /// collision rule and §D6's "never rewrite" both need the recorded `Message-ID`,
    /// not just the name.
    ///
    /// Not `private`: `FolderContext.messagesByID` below stores these, and
    /// `FolderContext` widens to `internal` for `PraticaSyncEngine+Messages.swift`
    /// (a stored property cannot be less accessible than its own type).
    struct ExistingMessage {
        var fileName: String
        var document: MessageDocument
        /// The file's raw text, as read from disk - ADR-0040 §D6: a patch is compared
        /// against this so `commit` needs no second read, and the no-op rule (a patch
        /// identical to what is already there is never written) has something to
        /// compare against.
        var text: String
    }

    /// Everything the folder already holds that a decision this run makes depends on.
    ///
    /// Not `private`: `PraticaSyncEngine.swift`'s `sync(_:)` declares a `var folder`
    /// of this type, and `PraticaSyncEngine+Messages.swift`'s `commit(_:request:
    /// folder:outcome:)`, `prepare(_:request:reader:folder:)`, `regeneratePending(
    /// request:reader:folder:outcome:)`, `regenerationPreview(_:messageID:rowID:)` and
    /// `commitRegeneration(_:)` all take or construct one - all extensions of this
    /// actor in separate files.
    struct FolderContext {
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

    /// Not `private`: `PraticaSyncEngine.swift`'s `sync(_:)` and `PraticaSyncEngine+
    /// Messages.swift`'s `regenerationPreview(_:messageID:rowID:)` are extensions of
    /// this actor in separate files, and both call this.
    func folderContext(of request: SyncRequest) throws -> FolderContext {
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
    /// Not `private`: `PraticaSyncEngine.swift`'s `sync(_:)` is an extension of this
    /// actor in a separate file, and is this member's only caller.
    func repairCorruptAttachments(
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
            try await write(patchedText, notePath, NoteStore.hash(Data(existing.text.utf8)))

            var updatedDocument = existing.document
            updatedDocument.frontmatter.attachments = entries
            folder.messagesByID[messageID] = ExistingMessage(
                fileName: existing.fileName, document: updatedDocument, text: patchedText
            )
            outcome.resolvedAttachmentFiles.append(notePath)
        }
    }
}
