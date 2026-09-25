import Foundation

// ADR-0045 §D4 (PG-143 structure refactor): this file is one file on purpose, past the
// 400-line file_length warning threshold but comfortably inside the 1000-line error
// threshold (ADR §D1). `PreparedMessage`, `PreparedAttachment` and
// `RegenerationPlan.prepared` stay `fileprivate`, unchanged: that keyword is ADR-0036
// §D21's whole implementation of "the bytes shown in the diff are the bytes written" -
// splitting this file further would either force the cluster apart (repealing §D21) or
// force it to widen to `internal` (the same repeal, one step removed). A future split
// must keep the cluster whole or supersede §D21 explicitly, not widen past it.
extension PraticaSyncEngine {
    // MARK: - One message, decoded

    /// `fileprivate` for the same reason as `PreparedMessage` below, which holds an
    /// array of these.
    fileprivate struct PreparedAttachment: Sendable {
        var fileName: String
        var bytes: Data
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
        /// What this decode judged for every inline image it resolved this sync
        /// (ADR-0042 §D8) - `commit` hands it to `MessageInlineImagePatch` when the
        /// on-disk note is still waiting on some of these ids.
        var inlineResolutions: [String: MessageInlineImagePatch.Resolution]
    }

    // MARK: - Attachment placement (R-10)

    /// ADR-0045 §D4 (PG-143 structure refactor): kept beside `PreparedAttachment`
    /// rather than in `PraticaSyncEngine+Attachments.swift` with its three siblings
    /// (`uniqueAttachmentName`, `storePath`, `digest`) - this one returns a
    /// `PreparedAttachment`, and that type is `fileprivate` on ADR-0036 §D21's own
    /// instruction (this file's header comment). A `fileprivate` type cannot be
    /// named from a function declared in a different file, widening it or not: the
    /// plan's literal file split and §D4's own "stays `fileprivate`" cannot both
    /// hold for this one function, and §D4 is the invariant that governs.
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
        return (fileName, PreparedAttachment(fileName: fileName, bytes: bytes))
    }

    // MARK: - Externalized attachments (ADR-0048)

    /// What trying the sibling `Attachments/<rowID>/<part>/<name>` file (ADR-0048)
    /// answered - tried only when the inline MIME payload's own
    /// `AttachmentIntegrity` verdict is `.empty`. Never worse than today: a missing,
    /// unreadable or itself-corrupt sibling file is `.unavailable`, which every
    /// caller folds straight into its existing `pendingAttachmentNames` retry.
    private enum ExternalizedResolution {
        case unavailable
        /// Read in full and re-verified in memory - ready for the same
        /// threshold-check-then-`place` pipeline an inline attachment already uses.
        case bytes(Data)
        /// Verified on disk without a full read (`AttachmentIntegrity.verdict(ofFileAt:)`,
        /// the same head/tail-window check an inline over-threshold `StoreReference`
        /// already relies on) - never loaded whole just to record where it lives.
        case overThreshold(size: Int, storePath: String)
    }

    /// Tries Mail's sibling `Attachments/<rowID>/<part>/` directory for a part whose
    /// inline MIME payload decoded to zero bytes - Exchange's own storage
    /// optimization for some attachments, permanent rather than "not yet downloaded"
    /// (ADR-0048). `partNumber` is `MIMEPart.partNumber`, Mail's own IMAP-style
    /// numbering - never a flat decode-order index, which diverges from it as soon as
    /// the message nests a `multipart/alternative` or similar ahead of the part.
    private static func resolveExternalized(
        name: String,
        contentType: String,
        context: PrepareContext,
        rowID: Int,
        partNumber: String,
        settings: PraticheSettings
    ) -> ExternalizedResolution {
        let url = EMLXReader
            .attachmentsDirectory(forMessageAt: context.emlxURL, rowID: rowID, part: partNumber)
            .appending(path: name, directoryHint: .notDirectory)
        // `try?`, matching the "no permission prompt, no crash on a missing file"
        // idiom `storePath` already uses: a sibling file that simply is not there is
        // the common, expected case, not a diagnostic.
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0
        else { return .unavailable }

        if size > Self.thresholdBytes(settings) {
            guard AttachmentIntegrity.verdict(ofFileAt: url, named: name) == .usable
            else { return .unavailable }
            return .overThreshold(
                size: size,
                storePath: Self.storePath(of: name, at: context.emlxURL, rowID: rowID, part: partNumber)
            )
        }

        guard let bytes = try? Data(contentsOf: url),
              AttachmentIntegrity.verdict(of: bytes, named: name, contentType: contentType) == .usable
        else { return .unavailable }
        return .bytes(bytes)
    }

    // MARK: - Per-part resolution (ADR-0045 shape: pulled out of `decodeBody`'s loop
    // body so the loop itself stays under SwiftLint's complexity/length error
    // thresholds - ADR-0048 added a second lookup, `resolveExternalized`, inline into
    // both switch cases and that alone crossed both. No behavior changes: each helper
    // is the exact code that used to sit in its `case`, unchanged statement for
    // statement, only the effects (`writes`/`links`/`storeReferences`/
    // `pendingAttachmentNames` for attachments; `body`/`inlineResolutions`/
    // `inlineContentIDByOrdinal` for inline images) are now returned instead of
    // mutated in place, since those accumulators are shared across every part in the
    // loop and don't belong on either helper.

    /// The three per-message values `resolveAttachment` and `resolveInlineImage` both
    /// need and neither ever changes across a single `decodeBody` call - bundled so
    /// each helper stays at 5-7 parameters instead of crossing SwiftLint's
    /// `function_parameter_count` error threshold of 8 (`resolveInlineImage` alone
    /// would otherwise need `context`, `request` and `row` on top of its own four).
    private struct DecodedPartContext {
        var context: PrepareContext
        var request: SyncRequest
        var row: MailMessageRow
    }

    /// What `decodeBody` does with one `.attachment` part, once resolved.
    private enum AttachmentResolution {
        case placed(write: PreparedAttachment?, link: String)
        case storeReference(MessageDocument.StoreReference)
        case pending(name: String)
    }

    /// The `.attachment` case's full resolution: inline bytes first, the sibling
    /// `Attachments/` directory second (ADR-0048) when the inline payload is
    /// `.empty`, threshold check, then `place` - identical order and identical
    /// verdict handling to before this was pulled out of `decodeBody`.
    private static func resolveAttachment(
        filename: String?,
        part: MIMEPart,
        decoding: DecodedPartContext,
        attachmentNameByDigest: inout [String: String],
        takenAttachmentNames: inout Set<String>
    ) -> AttachmentResolution {
        let name = filename ?? Self.unnamedAttachment
        let inlineBytes = part.decodedData ?? Data()
        // ADR-0040 §D2/§D3, R-01/R-02/R-12: the verdict is taken once, before the
        // threshold comparison, and governs both the copy branch and the
        // store-reference branch (R-07, Task 5) - never place, never digest, never a
        // `StoreReference`, for anything but `.usable`.
        let verdict = AttachmentIntegrity.verdict(
            of: inlineBytes, named: name, contentType: part.contentType
        )
        var resolvedBytes: Data?
        switch verdict {
        case .usable:
            resolvedBytes = inlineBytes
        case .empty:
            // ADR-0048: an inline payload that decodes to zero bytes is not
            // necessarily "not yet downloaded" - Exchange routinely externalizes the
            // part to the sibling `Attachments/` directory instead, permanently, with
            // nothing left inline. Tried once, before conceding the name to the
            // pending list below.
            switch Self.resolveExternalized(
                name: name, contentType: part.contentType, context: decoding.context,
                rowID: decoding.row.rowID, partNumber: part.partNumber, settings: decoding.request.settings
            ) {
            case .unavailable:
                break
            case .bytes(let bytes):
                resolvedBytes = bytes
            case .overThreshold(let size, let storePath):
                return .storeReference(
                    MessageDocument.StoreReference(name: name, size: size, storePath: storePath)
                )
            }
        case .signatureMismatch, .truncated:
            break
        }
        guard let bytes = resolvedBytes else {
            return .pending(
                name: PraticaNaming.attachmentFileName(date: decoding.context.calendarDate, name: name)
            )
        }
        if bytes.count > Self.thresholdBytes(decoding.request.settings) {
            // R-10: recorded where it really lives, never copied.
            return .storeReference(MessageDocument.StoreReference(
                name: name,
                size: bytes.count,
                storePath: Self.storePath(
                    of: name, at: decoding.context.emlxURL, rowID: decoding.row.rowID, part: part.partNumber
                )
            ))
        }
        let placed = Self.place(
            bytes, named: name, date: decoding.context.calendarDate,
            nameByDigest: &attachmentNameByDigest, taken: &takenAttachmentNames
        )
        return .placed(write: placed.write, link: placed.fileName)
    }

    /// What `decodeBody` does with one `.inlineImage` part, once resolved. Unlike
    /// `AttachmentResolution`, applying this one also rewrites `body` - the caller
    /// keeps that mutation, since `body` is shared across every part in the loop.
    private enum InlineImageResolution {
        /// ADR-0042 §D5 (R-03): the body never mentions this id at all - no
        /// placeholder, no pending entry, no retry state.
        case notReferenced
        case deferred(token: String)
        case droppedAsDecorative
        case embedded(write: PreparedAttachment?, fileName: String)
    }

    /// The `.inlineImage` case's full resolution, `body` read but not mutated here
    /// (see `InlineImageResolution`'s doc comment) - same verdict handling, same
    /// narrower ADR-0048 scope (no over-threshold path) as before this was pulled out.
    private static func resolveInlineImage(
        contentID: String,
        part: MIMEPart,
        ordinal: Int,
        body: String,
        decoding: DecodedPartContext,
        attachmentNameByDigest: inout [String: String],
        takenAttachmentNames: inout Set<String>
    ) -> InlineImageResolution {
        let inlineBytes = part.decodedData ?? Data()
        let name = part.filename ?? "\(contentID).png"
        // ADR-0040 §D9: integrity first, `isDecorative` second - a corrupt image's
        // dimensions are unreadable, so `isDecorative` would already answer `false`
        // (its own "never drop on a guess" rule) and place it.
        let verdict = AttachmentIntegrity.verdict(
            of: inlineBytes, named: name, contentType: part.contentType
        )
        var resolvedBytes: Data?
        switch verdict {
        case .usable:
            resolvedBytes = inlineBytes
        case .empty:
            // ADR-0048, smaller scope than the attachment case above: no
            // over-threshold path exists for an inline image, so an externalized one
            // that happens to be oversized is treated the same as unavailable rather
            // than growing a new store-reference shape this feature has never needed
            // for inline pictures.
            if case .bytes(let bytes) = Self.resolveExternalized(
                name: name, contentType: part.contentType, context: decoding.context,
                rowID: decoding.row.rowID, partNumber: part.partNumber, settings: decoding.request.settings
            ) {
                resolvedBytes = bytes
            }
        case .signatureMismatch, .truncated:
            break
        }
        guard let bytes = resolvedBytes else {
            guard MessageInlineImage.referencesContentID(contentID, in: body) else { return .notReferenced }
            return .deferred(token: MessageInlineImage.deferralToken(forPart: ordinal))
        }
        guard !InlineImageClassifier.isDecorative(bytes) else { return .droppedAsDecorative }
        let placed = Self.place(
            bytes, named: name, date: decoding.context.calendarDate,
            nameByDigest: &attachmentNameByDigest, taken: &takenAttachmentNames
        )
        return .embedded(write: placed.write, fileName: placed.fileName)
    }

    /// Everything `resolveContext` reads or computes once from `row`/`reader`, so
    /// `decodeBody` and `prepare` itself don't each recompute it (ADR-0045 Task 4:
    /// `prepare`'s own body, split along its existing comment blocks to clear the
    /// function_body_length error, never changes what any of these values are).
    private struct PrepareContext {
        var emlxURL: URL
        var container: EMLXDocument
        var headers: EmailHeaders
        var messageID: String
        var isPending: Bool
        var existing: ExistingMessage?
        var date: Date
        var calendarDate: CalendarDate
        var subject: String
        var direction: MessageDocument.Direction
        var carbonCopies: [EmailAddress]
        var counterpart: EmailAddress?
    }

    /// `prepare`'s "locate + read `.emlx`" and "resolve `Message-ID` and the
    /// exclusion recheck" blocks, unchanged - still answers `nil` for every reason
    /// this run must leave the message alone: no `.emlx` to read, no `Message-ID`
    /// to key it by, or a file already on disk that §D6 forbids rewriting.
    private func resolveContext(
        _ row: MailMessageRow, request: SyncRequest, reader: MailStoreReader, folder: FolderContext
    ) -> PrepareContext? {
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
            let hasPendingInlineImages = !existing.document.frontmatter.pendingInlineImages.isEmpty
            guard isRequestedRegeneration
                || (existing.document.frontmatter.body == .pending && !isPending)
                || hasPendingAttachments
                || hasPendingInlineImages
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

        return PrepareContext(
            emlxURL: emlxURL, container: container, headers: headers, messageID: messageID,
            isPending: isPending, existing: existing, date: date, calendarDate: calendarDate,
            subject: subject, direction: direction, carbonCopies: carbonCopies, counterpart: counterpart
        )
    }

    /// `decodeBody`'s answer: everything `prepare` folds into a `MailFrontmatter`
    /// and a `PreparedMessage` once the MIME walk and body reduction are done.
    private struct DecodedBody {
        var newText: String
        var quotedHistory: String?
        var signature: String?
        var links: [String]
        var pendingAttachmentNames: [String]
        var pendingInlineImages: [String]
        var storeReferences: [MessageDocument.StoreReference]
        var writes: [PreparedAttachment]
        var inlineResolutions: [String: MessageInlineImagePatch.Resolution]
    }

    /// `prepare`'s "MIME walk and body reduction" plus "attachment and inline-image
    /// resolution" blocks, unchanged - mutates the two dedup maps that carry across
    /// an entire sync (ADR-0040 §D2/§D3, R-10).
    private func decodeBody(
        _ context: PrepareContext, request: SyncRequest, row: MailMessageRow,
        attachmentNameByDigest: inout [String: String], takenAttachmentNames: inout Set<String>
    ) -> DecodedBody {
        var writes: [PreparedAttachment] = []
        var links: [String] = []
        // ADR-0040 §D3: placed names for parts `AttachmentIntegrity` rejected -
        // never hashed, never written, never handed to `place`.
        var pendingAttachmentNames: [String] = []
        var pendingInlineImages: [String] = []
        var storeReferences: [MessageDocument.StoreReference] = []
        var newText: String
        var quotedHistory: String?
        var signature: String?
        // ADR-0042 §D1/§D6: an inline image never becomes a pending *attachment* -
        // `contentIDByOrdinal` records what a deferral token (planted in the body below)
        // resolves back to, once render order is known after `QuoteSplitter.split`.
        var inlineContentIDByOrdinal: [Int: String] = [:]
        var inlineResolutions: [String: MessageInlineImagePatch.Resolution] = [:]

        if context.isPending {
            // R-15: a placeholder, never an empty body - a file with nothing in it
            // reads as a message that said nothing.
            newText = Self.pendingPlaceholder
        } else {
            let parts = MIMEDecoder.decode(context.container.rfc822)
            var body = Self.bodyText(of: parts)
            let decoding = DecodedPartContext(context: context, request: request, row: row)
            for (ordinal, part) in parts.enumerated() {
                switch part.kind {
                case .attachment(let filename):
                    switch Self.resolveAttachment(
                        filename: filename, part: part, decoding: decoding,
                        attachmentNameByDigest: &attachmentNameByDigest, takenAttachmentNames: &takenAttachmentNames
                    ) {
                    case .placed(let write, let link):
                        if let write { writes.append(write) }
                        links.append(link)
                    case .storeReference(let reference):
                        storeReferences.append(reference)
                    case .pending(let name):
                        pendingAttachmentNames.append(name)
                    }

                case .inlineImage(let contentID):
                    switch Self.resolveInlineImage(
                        contentID: contentID, part: part, ordinal: ordinal, body: body, decoding: decoding,
                        attachmentNameByDigest: &attachmentNameByDigest,
                        takenAttachmentNames: &takenAttachmentNames
                    ) {
                    case .notReferenced:
                        continue
                    case .deferred(let token):
                        body = MessageInlineImage.replacingReferences(to: contentID, in: body, with: token)
                        inlineContentIDByOrdinal[ordinal] = contentID
                    case .droppedAsDecorative:
                        // R-10: a signature logo is not an attachment. The reference
                        // goes with it, or the body keeps a `cid:` pointing nowhere.
                        body = MessageInlineImage.replacingReferences(to: contentID, in: body, with: "")
                        inlineResolutions[contentID] = .dropped
                    case .embedded(let write, let fileName):
                        if let write { writes.append(write) }
                        // Embedded rather than listed: an inline image belongs where
                        // the sender put it (SPEC "Edge cases").
                        body = MessageInlineImage.replacingReferences(
                            to: contentID, in: body, with: "![[\(fileName)]]"
                        )
                        inlineResolutions[contentID] = .embedded(fileName: fileName)
                    }

                case .textPlain, .textHTML:
                    continue
                }
            }
            let split = QuoteSplitter.split(body)
            // ADR-0042 §D6: `QuoteSplitter.split` reorders the body relative to MIME
            // decode order, so deferral tokens are resolved AFTER the split, over the
            // texts in their real render order - new text, then quoted history, then
            // signature - never over the decode loop's own ordinal order.
            let resolved = MessageInlineImage.resolvingDeferralTokens(
                in: [split.newText, split.quotedHistory ?? "", split.signature ?? ""],
                contentIDByOrdinal: inlineContentIDByOrdinal
            )
            newText = resolved.texts[0]
            quotedHistory = resolved.texts[1].isEmpty ? nil : resolved.texts[1]
            signature = resolved.texts[2].isEmpty ? nil : resolved.texts[2]
            pendingInlineImages = resolved.pending
        }

        return DecodedBody(
            newText: newText, quotedHistory: quotedHistory, signature: signature, links: links,
            pendingAttachmentNames: pendingAttachmentNames, pendingInlineImages: pendingInlineImages,
            storeReferences: storeReferences, writes: writes, inlineResolutions: inlineResolutions
        )
    }

    /// Reads and decodes one message. Writes nothing, and answers `nil` for every
    /// reason this run must leave the message alone: no `.emlx` to read, no
    /// `Message-ID` to key it by, or a file already on disk that §D6 forbids
    /// rewriting. `resolveContext` and `decodeBody` above carry the body this
    /// function used to hold in full - ADR-0045 Task 4 split along the existing
    /// comment blocks, never changing what is computed or written.
    ///
    /// Stays `private`, not merely un-widened: its result is `PreparedMessage`,
    /// `fileprivate` on ADR §D4's own instruction, and the compiler caps a
    /// function's access at the access of the types in its signature - `internal`
    /// is not legal here regardless of who would need to call it. `decodeAndCommit`
    /// below is the cross-file entry point `sync(_:)` in `PraticaSyncEngine.swift`
    /// calls instead, since its own signature never names `PreparedMessage`.
    private func prepare(
        _ row: MailMessageRow,
        request: SyncRequest,
        reader: MailStoreReader,
        folder: FolderContext
    ) -> PreparedMessage? {
        guard let context = resolveContext(row, request: request, reader: reader, folder: folder)
        else { return nil }

        var attachmentNameByDigest = folder.attachmentNameByDigest
        var takenAttachmentNames = folder.takenAttachmentNames
        let decoded = decodeBody(
            context, request: request, row: row,
            attachmentNameByDigest: &attachmentNameByDigest, takenAttachmentNames: &takenAttachmentNames
        )

        // "Assemble `PreparedMessage`" - unchanged from before the split above.
        let fileName: String
        if let existing = context.existing {
            // R-15's regeneration is in place: the same file, so a link to it from
            // anywhere else in the vault survives the body's arrival.
            fileName = existing.fileName
        } else {
            fileName = PraticaNaming.uniqueMessageFileName(
                date: context.calendarDate,
                time: Self.time(of: context.date),
                counterpart: context.counterpart?.displayText ?? Self.unknownCounterpart,
                subject: context.subject,
                messageID: context.messageID,
                existing: folder.takenNoteNames
            )
        }
        let baseName = (fileName as NSString).deletingPathExtension
        // §D18: a pending message has no complete RFC 822 bytes to keep, so it gets no
        // `.eml` and no `pergamenum-mail-original`, whatever retention says.
        let keepsOriginal = request.settings.keepOriginalEML && !context.isPending

        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: Self.frontmatterSchemaVersion,
                messageID: context.messageID,
                conversationID: row.conversationID,
                direction: context.direction,
                date: context.date,
                received: row.dateReceived,
                from: context.headers.from.map(Self.headerForm) ?? row.sender ?? "",
                to: context.headers.to.map(Self.headerForm),
                cc: context.carbonCopies.map(Self.headerForm),
                subject: context.subject,
                // ADR-0040 §D3: linked entries in their existing order, then pending
                // ones - `body` stays `isPending ? .pending : .complete` unchanged, so a
                // message with some usable and some not-yet-usable parts is `.complete`
                // (R-04).
                attachments: decoded.links.map(MessageDocument.attachmentEntry(linking:))
                    + decoded.pendingAttachmentNames.map(MessageDocument.attachmentEntry(pending:)),
                storeReferences: decoded.storeReferences,
                pendingInlineImages: decoded.pendingInlineImages,
                body: context.isPending ? .pending : .complete,
                original: keepsOriginal ? "\(baseName).eml" : nil
            ),
            newText: decoded.newText,
            quotedHistory: decoded.quotedHistory,
            signature: decoded.signature
        )

        return PreparedMessage(
            messageID: context.messageID,
            fileName: fileName,
            noteText: MessageDocument.render(document, tags: Self.tags(for: request)),
            document: document,
            originalBytes: keepsOriginal ? context.container.rfc822 : nil,
            attachments: decoded.writes,
            attachmentNameByDigest: attachmentNameByDigest,
            takenAttachmentNames: takenAttachmentNames,
            isRegeneration: context.existing != nil,
            rowID: row.rowID,
            conversationID: row.conversationID,
            inlineResolutions: decoded.inlineResolutions
        )
    }

    /// The main loop's one candidate, decoded and (unless the run was cancelled at
    /// the write boundary the two yields below establish) committed. `sync(_:)` in
    /// `PraticaSyncEngine.swift` calls this rather than `prepare`/`commit`
    /// themselves: both take or return `PreparedMessage`, `fileprivate` in this
    /// file on ADR §D4's own instruction, and a `fileprivate` type cannot be named
    /// at a call site in a different file, widening the referencing function or
    /// not (the same constraint `place(...)`'s header comment above names for
    /// `PreparedAttachment`). This wrapper's own signature never names
    /// `PreparedMessage`, so it is the one member of the cluster that can cross the
    /// file boundary without widening what §D4 says must not widen.
    ///
    /// Returns `false` exactly when `sync(_:)`'s loop must `break` - cancellation
    /// observed at this message's write boundary (R-11, ADR §D14), never
    /// mid-message.
    ///
    /// Not `private`: `PraticaSyncEngine.swift`'s `sync(_:)` is an extension of
    /// this actor in a separate file, and is this member's only caller.
    func decodeAndCommit(
        _ row: MailMessageRow, request: SyncRequest, reader: MailStoreReader,
        folder: inout FolderContext, outcome: inout SyncOutcome
    ) async throws -> Bool {
        // Decoding happens first and writes nothing: it is the window during which
        // a `cancel()` sent from outside gets queued on this actor.
        let prepared = prepare(row, request: request, reader: reader, folder: folder)
        // ADR §D14: cancellation is observed at the write boundary, never
        // mid-message. The yields are what let a queued `cancel()` actually run -
        // an actor only services another job while the job it is running is
        // suspended, and everything above this line is synchronous.
        await Task.yield()
        await Task.yield()
        if cancelled {
            outcome.cancelled = true
            return false
        }
        if let prepared {
            try await commit(prepared, request: request, folder: &folder, outcome: &outcome)
        }
        return true
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

    /// ADR-0049 §D7: a linked note survives «Rigenera» - carried into
    /// `prepared.noteText` **before** the diff `regenerationPreview` computes just after
    /// calling this, so the plan's `replacementText`, its diff and the bytes
    /// `commitRegeneration` writes (`prepared`, not `replacementText`) are one and the
    /// same. Patching `replacementText` alone would look right in the sheet and
    /// silently destroy the link.
    private static func carryingOverLinkedNote(
        from currentText: String, into prepared: PreparedMessage
    ) -> PreparedMessage {
        guard let linkedNote = MessageDocument.parse(currentText)?.frontmatter.linkedNote,
              let patched = MessageFrontmatterPatch.applying(
                  line: MessageDocument.noteLine(for: linkedNote), forKey: MessageDocument.noteKey,
                  before: [MessageDocument.storeReferencesKey, "pergamenum-mail-body"], to: prepared.noteText
              )
        else { return prepared }
        var prepared = prepared
        prepared.noteText = patched
        return prepared
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
        guard var prepared = prepare(row, request: regenerationRequest, reader: reader, folder: folder)
        else { throw RegenerationFailure.notDecodable }

        let notePath = "\(request.praticaFolder)/email/\(prepared.fileName)"
        let noteURL = try boundary.url(for: notePath)
        guard let currentText = try? String(contentsOf: noteURL, encoding: .utf8) else {
            throw RegenerationFailure.fileMissing
        }

        prepared = Self.carryingOverLinkedNote(from: currentText, into: prepared)

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

    /// Stays `private`, not merely un-widened: its `prepared` parameter is
    /// `PreparedMessage`, `fileprivate` on ADR §D4's own instruction, and the
    /// compiler caps a function's access at the access of the types in its
    /// signature - `internal` is not legal here regardless of who would need to
    /// call it. `decodeAndCommit` above is the cross-file entry point `sync(_:)` in
    /// `PraticaSyncEngine.swift` calls instead, since its own signature never names
    /// `PreparedMessage`.
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
        //
        // PG-168: the pratica is verified once, HERE, before a single byte moves - a folder a
        // relocation or a trash has already vacated costs nothing, instead of "attachments
        // written, note refused". Whatever this call creates (`email/`, then `allegati/` only
        // when there is something to put in it) is a leaf under a pratica that still has its
        // `pratica.md`; `writeAtomically` below no longer creates anything itself.
        let emailDirectory = try makeDirectory("email", of: request)
        if !prepared.attachments.isEmpty {
            let allegatiDirectory = try makeDirectory("allegati", of: request)
            for attachment in prepared.attachments {
                let target = allegatiDirectory.appending(path: attachment.fileName, directoryHint: .notDirectory)
                try Self.writeAtomically(attachment.bytes, to: target)
                // PG-123: the bytes came out of a mail store, so the copy is a download as far
                // as Gatekeeper is concerned - stamped after the rename, or the xattr would
                // land on the temporary sibling `.atomic` throws away.
                try AttachmentQuarantine.apply(to: target)
            }
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
            // `pergamenum-mail-attachments` line, its inline-image placeholders and its
            // `pergamenum-mail-inline-pending` line may change (ADR-0042 §D8). The `.eml`
            // sidecar is never rewritten in this mode: its bytes have not changed (§D18).
            guard let existingOnDisk else { return }

            let pendingIDs = existingOnDisk.document.frontmatter.pendingInlineImages
            guard let inlineOutcome = MessageInlineImagePatch.applying(
                resolved: prepared.inlineResolutions, pending: pendingIDs, to: existingOnDisk.text
            ) else { return }

            // A resolved image the placeholder count could not place (a count mismatch -
            // somebody edited the prose) is not lost: it is linked as an ordinary
            // attachment instead, appended after every already-linked entry.
            let attachmentEntries = prepared.document.frontmatter.attachments
                + inlineOutcome.unplaceable.map(MessageDocument.attachmentEntry(linking:))
            guard let patchedText = MessageAttachmentPatch.applying(
                entries: attachmentEntries, to: inlineOutcome.text
            ) else { return }

            // §D6: a patch identical to the file already on disk is never written -
            // this is what makes the unresolved retry free.
            guard patchedText != existingOnDisk.text else { return }

            try await write(patchedText, notePath, NoteStore.hash(Data(existingOnDisk.text.utf8)))

            var patchedFrontmatter = prepared.document.frontmatter
            patchedFrontmatter.attachments = attachmentEntries
            patchedFrontmatter.pendingInlineImages = inlineOutcome.remaining
            var patchedDocument = prepared.document
            patchedDocument.frontmatter = patchedFrontmatter
            folder.messagesByID[prepared.messageID] = ExistingMessage(
                fileName: prepared.fileName, document: patchedDocument, text: patchedText
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
            let emlTarget = emailDirectory.appending(path: "\(baseName).eml", directoryHint: .notDirectory)
            try Self.writeAtomically(originalBytes, to: emlTarget)
            // PG-155: same rationale as PG-123 above - the bytes came out of a mail
            // store, so the sidecar `.eml` is a download as far as Gatekeeper is
            // concerned, and the xattr must be stamped after the rename.
            try AttachmentQuarantine.apply(to: emlTarget)
        }

        // §D8 excludes this by name: `prepared.noteText` is composed from Mail, not from
        // the file on disk - there is no "before" to expect, whether this note is being
        // created for the first time or fully re-rendered.
        try await write(prepared.noteText, notePath, nil)

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
    ///
    /// Scans the pratica's own files on disk, not `request.candidates`:
    /// `MembershipRule.candidates(dossier:store:onDisk:)` subtracts `onDisk` from its
    /// result by design (rule 5), so a message already on disk can never appear in
    /// `candidates` - looking for pending work there, as this used to, made the scan
    /// structurally empty on every sync after the message's first import.
    /// Not `private`: `PraticaSyncEngine.swift`'s `sync(_:)` is an extension of this
    /// actor in a separate file, and is this member's only caller.
    func regeneratePending(
        request: SyncRequest,
        reader: MailStoreReader,
        folder: inout FolderContext,
        outcome: inout SyncOutcome
    ) async throws {
        let rowIDByMessageID = Dictionary(
            request.ledgerEntries.map { ($0.messageID, $0.rowID) }, uniquingKeysWith: { first, _ in first }
        )
        for messageID in folder.messagesByID.keys.sorted() {
            let frontmatter = folder.messagesByID[messageID]?.document.frontmatter
            let isPending = frontmatter?.body == .pending
                || !(frontmatter?.pendingAttachmentNames.isEmpty ?? true)
                || !(frontmatter?.pendingInlineImages.isEmpty ?? true)
            guard isPending else { continue }

            let row: MailMessageRow
            switch reader.row(forMessageID: messageID) {
            case .found(let found):
                row = found
            case .notResolvableFromIndex:
                // The same fallback `regenerationPreview` uses: the ledger's own
                // bridge, for the ~3% of messages the index cannot resolve by
                // `Message-ID` alone. Neither answering means this message simply
                // waits for a later sync - no write, so the retry stays free.
                guard let rowID = rowIDByMessageID[messageID], let found = reader.row(rowID: rowID) else {
                    continue
                }
                row = found
            }

            guard let prepared = prepare(row, request: request, reader: reader, folder: folder) else {
                continue
            }
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
    ///
    /// PG-168: the directory is the caller's business and is made by `makeDirectory`, under
    /// a pratica that still has its `pratica.md`. It used to be created here, with its whole
    /// parent chain, which is how an attachment or `.eml` landing after a folder relocation
    /// brought the vacated folder back. These bytes never go through `VaultSession`, so
    /// `expecting:` never protected them: a move landing after `makeDirectory` now makes this
    /// write fail with ENOENT instead.
    private static func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
