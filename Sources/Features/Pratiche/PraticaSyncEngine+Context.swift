import Foundation

// ADR-0045 §D4's convention, applied once more (PG-257): `prepare`'s context block moved
// out of `PraticaSyncEngine+Messages.swift` when ADR-0067 took that file past the
// 1000-line file_length error threshold. Nothing here names `PreparedMessage`,
// `PreparedAttachment` or `RegenerationPlan.prepared`, so the ADR-0036 §D21 cluster stays
// whole and `fileprivate` in that file. Bodies unchanged.
extension PraticaSyncEngine {
    /// Everything `resolveContext` reads or computes once from `row`/`reader`, so
    /// `decodeBody` and `prepare` itself don't each recompute it (ADR-0045 Task 4:
    /// `prepare`'s own body, split along its existing comment blocks to clear the
    /// function_body_length error, never changes what any of these values are).
    ///
    /// Not `private`: `PraticaSyncEngine+Messages.swift` (`resolveExternalized`,
    /// the per-part resolution, `decodeBody`, `prepare`) reads it.
    struct PrepareContext {
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
    ///
    /// Not `private`: `PraticaSyncEngine+Messages.swift`'s `prepare` is its only caller.
    func resolveContext(
        _ row: MailMessageRow, request: SyncRequest, reader: MailStoreReader, folder: FolderContext,
        indeterminateLookups: inout [String]
    ) -> PrepareContext? {
        guard let emlxURL = locate(row, reader: reader, indeterminateLookups: &indeterminateLookups),
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

    /// ADR §D4: only `.notInStore` means «non più in Mail», and a drifted rule is not
    /// that - both are skipped here, and R-16's caption is decided by
    /// `noLongerInMail(request:reader:)` against the index instead.
    ///
    /// ADR-0067 §D7: `.indeterminate` is skipped too - never imported this run, so it
    /// stays a candidate and is looked for again next sync - but it is recorded in
    /// `indeterminateLookups`, so the pane can say so. No marker is ever set from it.
    private func locate(
        _ row: MailMessageRow, reader: MailStoreReader, indeterminateLookups: inout [String]
    ) -> URL? {
        switch EMLXLocator.locate(predictedURL: reader.emlxPath(forRow: row)) {
        case let .found(url), let .foundPartial(url):
            return url
        case .indeterminate:
            indeterminateLookups.append(row.messageID ?? "#\(row.rowID)")
            return nil
        case .notInStore, .ruleFailed:
            return nil
        }
    }
}
