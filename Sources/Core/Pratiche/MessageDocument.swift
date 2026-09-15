import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-08,
// R-12.

/// One imported message's `.md` file: the closed four-key frontmatter plus the
/// `pergamenum-mail-*` keys (SPEC "Message file frontmatter"), the new text as body,
/// and the quoted history (plus a signature) in a `<details>` block.
struct MessageDocument: Equatable, Sendable {
    enum Direction: String, Equatable, Sendable {
        case received
        case sent
    }

    enum BodyState: String, Equatable, Sendable {
        case complete
        case pending
    }

    /// One over-threshold attachment's record (SPEC "Edge cases"): an attachment past
    /// `PraticheSettings.attachmentThresholdMB` is never copied into `allegati/` - this
    /// is what stands in its place, so the message file still names it, its size and
    /// where it actually lives inside Mail's own store.
    ///
    /// Written and read back as `pergamenum-mail-store-references` (see
    /// `flowMap(_:)`), so the chip that offers «apri dallo store» has a path to open
    /// and a size to explain why there is no local copy.
    struct StoreReference: Equatable, Sendable {
        var name: String
        var size: Int
        var storePath: String
    }

    struct MailFrontmatter: Equatable, Sendable {
        /// `pergamenum-mail` - the schema version of the keys below.
        var schemaVersion: Int
        /// `pergamenum-mail-message-id`, with the angle brackets (SPEC's own example
        /// keeps them, unlike `EmailHeaders.messageID`).
        var messageID: String
        var conversationID: Int?
        var direction: Direction
        /// `pergamenum-mail-date` - the header `Date`, governs ordering.
        var date: Date
        var received: Date?
        var from: String
        var to: [String]
        var cc: [String]
        /// `pergamenum-mail-subject` (SPEC "Message file frontmatter") - the header
        /// `Subject`, undecorated (no `Re:`/`Fwd:` stripping: that trimming is
        /// `PraticaNaming.messageFileName`'s job for the file name slug, this key is
        /// the subject as the message actually carried it).
        ///
        /// Added after Task 3, which shipped `MessageDocument` without it: the file
        /// name only carries a slug of the subject, capped at 40 characters and
        /// stripped of its reply prefixes, so it is not a place the real one survives.
        var subject: String
        /// Wikilinks, e.g. `"[[20260610_offerta-2024-118.pdf]]"`.
        var attachments: [String]
        /// `pergamenum-mail-store-references` (SPEC "Edge cases") - a block list of flow
        /// maps, one per over-threshold attachment, e.g.
        /// `  - { name: "big.zip", size: 157286400, storePath: "/…/Attachments/…/big.zip" }`.
        /// Defaulted empty and omitted from the rendered file when empty, the same rule
        /// `attachments`/`to`/`cc` already follow, so every existing call site of this
        /// memberwise initializer keeps compiling unchanged.
        var storeReferences: [StoreReference] = []
        /// `pergamenum-mail-inline-pending` (ADR-0042 §D3): the content ids of inline
        /// images this note is still waiting for, one per placeholder, in the order the
        /// placeholders appear in the rendered file. Defaulted empty, so every existing
        /// construction site keeps compiling and every note written before this fix
        /// reads back as "waiting for nothing".
        var pendingInlineImages: [String] = []
        var body: BodyState
        /// `pergamenum-mail-original` - absent when retention is off (R-09).
        var original: String?
    }

    var frontmatter: MailFrontmatter
    var newText: String
    var quotedHistory: String?
    var signature: String?

    /// Renders the full `.md` file text (R-08): closed frontmatter (`date`, `tags`,
    /// `related`, `aliases`) plus the `pergamenum-mail-*` keys, then `newText`, then a
    /// `<details>` block holding `quotedHistory` and, under its own `Firma` summary,
    /// `signature`.
    static func render(_ document: MessageDocument, tags: [Tag]) -> String {
        var frontmatter = Frontmatter.empty
        // The closed `date:` is the message's own local calendar day, the same rule
        // ADR-0032 §D8 fixed for a transcript: never today's, never the UTC one.
        frontmatter.date = CalendarDate(document.frontmatter.date)
        frontmatter.tags = tags
        frontmatter.foreignKeys = foreignKeys(of: document.frontmatter)

        var body = "\n\(document.newText)\n"
        // A `<details>` block rather than a blockquote: the quoted history is context,
        // not content, and Obsidian folds this natively without a plugin.
        if let quoted = document.quotedHistory, !quoted.isEmpty {
            body += "\n\(detailsBlock(summary: quotedSummary, content: quoted))"
        }
        if let signature = document.signature, !signature.isEmpty {
            body += "\n\(detailsBlock(summary: signatureSummary, content: signature))"
        }
        return FrontmatterSerializer.render(frontmatter) + body
    }

    static let quotedSummary = "Testo citato"
    static let signatureSummary = "Firma"

    private static func detailsBlock(summary: String, content: String) -> String {
        "<details>\n<summary>\(summary)</summary>\n\n\(content)\n</details>\n"
    }

    /// The `pergamenum-mail-*` keys of the SPEC's own worked example, in its order.
    ///
    /// An empty list and a `nil` are omitted rather than written `[]`, the rule
    /// `FrontmatterSerializer` already applies to `related`/`aliases`: a key present
    /// with no value is a key the next reader has to decide the meaning of.
    private static func foreignKeys(of mail: MailFrontmatter) -> [Frontmatter.ForeignKey] {
        var keys: [Frontmatter.ForeignKey] = []
        // Built as `ForeignKey`s rather than as `(name, value)` pairs because one key -
        // `pergamenum-mail-store-references` - is a block list and carries several
        // lines; every other key is a scalar and goes through `add`.
        func add(_ name: String, _ value: String) {
            keys.append(Frontmatter.ForeignKey(name: name, lines: ["\(name): \(value)"]))
        }

        add("pergamenum-mail", "\(mail.schemaVersion)")
        add("pergamenum-mail-message-id", quoted(mail.messageID))
        if let conversationID = mail.conversationID {
            add("pergamenum-mail-conversation-id", "\(conversationID)")
        }
        add("pergamenum-mail-direction", mail.direction.rawValue)
        add("pergamenum-mail-date", isoString(mail.date))
        if let received = mail.received {
            add("pergamenum-mail-received", isoString(received))
        }
        add("pergamenum-mail-from", quoted(mail.from))
        if !mail.to.isEmpty { add("pergamenum-mail-to", inlineList(mail.to)) }
        if !mail.cc.isEmpty { add("pergamenum-mail-cc", inlineList(mail.cc)) }
        // Written even when empty, unlike the lists above: the SPEC's own example
        // always carries it, and a message really sent with no subject is a fact about
        // that message rather than a key with nothing to say.
        add("pergamenum-mail-subject", quoted(mail.subject))
        if !mail.attachments.isEmpty {
            add(attachmentsKey, inlineList(mail.attachments))
        }
        if !mail.pendingInlineImages.isEmpty {
            add(inlinePendingKey, inlineList(mail.pendingInlineImages))
        }
        if !mail.storeReferences.isEmpty {
            keys.append(Frontmatter.ForeignKey(
                name: storeReferencesKey,
                lines: ["\(storeReferencesKey):"] + mail.storeReferences.map(flowMap)
            ))
        }
        add("pergamenum-mail-body", mail.body.rawValue)
        if let original = mail.original {
            add("pergamenum-mail-original", quoted(original))
        }
        return keys
    }

    static let storeReferencesKey = "pergamenum-mail-store-references"
    static let attachmentsKey = "pergamenum-mail-attachments"
    /// `pergamenum-mail-inline-pending` (ADR-0042 §D3), positioned after
    /// `attachmentsKey` and before `storeReferencesKey` in both `foreignKeys(of:)` and
    /// `MessageFrontmatterPatch`'s insertion order.
    static let inlinePendingKey = "pergamenum-mail-inline-pending"

    /// The full `pergamenum-mail-attachments:` line for a list of entries, in the same
    /// quoting `foreignKeys(of:)` already uses for this key (ADR-0040 §D4) -
    /// `MessageAttachmentPatch.applying`'s only source for the line's text, so the
    /// codec is written in exactly one place.
    static func attachmentsLine(for entries: [String]) -> String {
        "\(attachmentsKey): \(inlineList(entries))"
    }

    /// The full `pergamenum-mail-inline-pending:` line for a list of content ids
    /// (ADR-0042 §D3) - `MessageFrontmatterPatch`'s only source for this key's text.
    static func inlinePendingLine(for contentIDs: [String]) -> String {
        "\(inlinePendingKey): \(inlineList(contentIDs))"
    }

    /// `  - { name: "big.zip", size: 157286400, storePath: "/…/big.zip" }` - a YAML flow
    /// map per over-threshold attachment (SPEC "Edge cases"). One line each, so
    /// `FrontmatterParser`'s continuation rule (an indented or dashed line belongs to
    /// the key above it) carries the whole block back as one `ForeignKey`.
    private static func flowMap(_ reference: StoreReference) -> String {
        "  - { name: \(quoted(reference.name)), size: \(reference.size), "
            + "storePath: \(quoted(reference.storePath)) }"
    }

    /// A header value is somebody else's text: a `"` or a line break in it would close
    /// the scalar early and let the rest be read as new frontmatter keys (the same
    /// escaping `TranscriptNote` pays for the Plaud service's strings).
    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func inlineList(_ values: [String]) -> String {
        "[\(values.map(quoted).joined(separator: ", "))]"
    }

    /// ISO 8601 with the offset, as the SPEC writes it - the instant plus the zone the
    /// message was sent in, which is what «14:06» means to the person who received it.
    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

}

// MARK: - R-04 (ADR-0040 §D3): the pending-attachment codec
//
// An attachment already placed in `allegati/` is a wikilink, `"[[name]]"`; one still
// waiting for its bytes is the bare name. `hasPrefix("[[") && hasSuffix("]]")` is the
// discriminator - a pending entry is everything that is not that shape.

extension MessageDocument {
    static func attachmentEntry(linking fileName: String) -> String {
        "[[\(fileName)]]"
    }

    static func attachmentEntry(pending fileName: String) -> String {
        fileName
    }

    static func isPendingAttachmentEntry(_ entry: String) -> Bool {
        !(entry.hasPrefix("[[") && entry.hasSuffix("]]"))
    }

    /// `[[20260610_offerta.pdf]]` → `20260610_offerta.pdf`, alias form included -
    /// mirrors `PraticheController.attachmentFileName(fromWikilink:)` exactly (Core
    /// cannot depend on Features, so the rule is duplicated rather than shared; the two
    /// must agree, and the one in `PraticheController` is about to stop being used for
    /// classification).
    fileprivate static func unwrapWikilink(_ entry: String) -> String {
        var name = entry.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[[") { name.removeFirst(2) }
        if name.hasSuffix("]]") { name.removeLast(2) }
        return name.components(separatedBy: "|").first ?? name
    }
}

extension MessageDocument.MailFrontmatter {
    /// Attachments already placed in `allegati/` (ADR-0040 §D3): the wikilink form,
    /// unwrapped and with its alias half (after `|`) dropped.
    var linkedAttachmentNames: [String] {
        attachments
            .filter { !MessageDocument.isPendingAttachmentEntry($0) }
            .map(MessageDocument.unwrapWikilink)
    }

    /// Attachments still waiting for their bytes (ADR-0040 §D3): the bare name, as
    /// written - empty for every note written before this fix, since such a note
    /// carries only `[[…]]` entries (the retry rule of ADR-0040 §D5 rests on this).
    var pendingAttachmentNames: [String] {
        attachments.filter(MessageDocument.isPendingAttachmentEntry)
    }
}
