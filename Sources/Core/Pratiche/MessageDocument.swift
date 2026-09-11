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
            add("pergamenum-mail-attachments", inlineList(mail.attachments))
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

    private static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// Parses a message `.md` file back into structured form - used by R-08's
    /// collision rule (does an existing file carry this `Message-ID`?) and by the
    /// sync's "already on disk" dedup (SPEC "Membership rule", item 5) when the
    /// ledger does not have the answer.
    static func parse(_ text: String) -> MessageDocument? {
        let note = NoteDocument.parse(text)
        let lines = note.frontmatter.foreignKeys.flatMap(\.lines)
        guard let schemaVersion = scalar("pergamenum-mail", lines).flatMap(Int.init),
              let messageID = scalar("pergamenum-mail-message-id", lines).map(unquoted)
        else { return nil }

        let body = splitBody(note.body)
        return MessageDocument(
            frontmatter: MailFrontmatter(
                schemaVersion: schemaVersion,
                messageID: messageID,
                conversationID: scalar("pergamenum-mail-conversation-id", lines).flatMap(Int.init),
                direction: scalar("pergamenum-mail-direction", lines)
                    .flatMap { Direction(rawValue: unquoted($0)) } ?? .received,
                // A message whose date this app cannot read still has to be findable by
                // its `Message-ID`: it sorts to the beginning rather than disappearing.
                date: scalar("pergamenum-mail-date", lines).flatMap(isoDate) ?? .distantPast,
                received: scalar("pergamenum-mail-received", lines).flatMap(isoDate),
                from: scalar("pergamenum-mail-from", lines).map(unquoted) ?? "",
                to: list("pergamenum-mail-to", lines),
                cc: list("pergamenum-mail-cc", lines),
                // A message file written before this key existed reads back with an
                // empty subject rather than failing to parse: the file is still a
                // message, and its `Message-ID` is what every caller matches on.
                subject: scalar("pergamenum-mail-subject", lines).map(unquoted) ?? "",
                attachments: list("pergamenum-mail-attachments", lines),
                storeReferences: storeReferences(in: lines),
                body: scalar("pergamenum-mail-body", lines)
                    .flatMap { BodyState(rawValue: unquoted($0)) } ?? .complete,
                original: scalar("pergamenum-mail-original", lines).map(unquoted)
            ),
            newText: body.newText,
            quotedHistory: body.quotedHistory,
            signature: body.signature
        )
    }

    // MARK: - Reading the file back

    private static func scalar(_ key: String, _ lines: [String]) -> String? {
        for line in lines where !line.hasPrefix(" ") && !line.hasPrefix("\t") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            guard String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces) == key
            else { continue }
            return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func list(_ key: String, _ lines: [String]) -> [String] {
        guard let raw = scalar(key, lines), raw.hasPrefix("["), raw.hasSuffix("]") else { return [] }
        let inner = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return [] }
        return splitTopLevel(String(inner))
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Splits on commas outside double-quoted spans, so a quoted value containing its own
    /// comma (e.g. `"Rossi, Mario"`) survives as one element. Mirrors `quoted(_:)`'s escaping:
    /// a backslash always escapes the following character inside quotes.
    private static func splitTopLevel(_ value: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for char in value {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\", inQuotes {
                current.append(char)
                escaped = true
                continue
            }
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
                continue
            }
            if char == "," && !inQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(char)
        }
        fields.append(current)
        return fields
    }

    /// Reads the `pergamenum-mail-store-references` block back: the key line, then one
    /// `- { … }` flow map per line until the block ends. A malformed entry is skipped
    /// rather than guessed at - an attachment this app cannot describe is better absent
    /// from the list than present with an invented size.
    private static func storeReferences(in lines: [String]) -> [StoreReference] {
        guard let start = lines.firstIndex(where: {
            !$0.hasPrefix(" ") && !$0.hasPrefix("\t")
                && $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(storeReferencesKey):")
        }) else { return [] }

        var references: [StoreReference] = []
        for line in lines[lines.index(after: start)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { break }
            guard let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"),
                  open < close
            else { continue }

            var fields: [String: String] = [:]
            for field in splitOutsideQuotes(String(trimmed[trimmed.index(after: open)..<close]), on: ",") {
                guard let colon = field.firstIndex(of: ":") else { continue }
                let name = String(field[field.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                fields[name] = unquoted(
                    String(field[field.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                )
            }
            guard let name = fields["name"], let storePath = fields["storePath"],
                  let size = fields["size"].flatMap(Int.init)
            else { continue }
            references.append(StoreReference(name: name, size: size, storePath: storePath))
        }
        return references
    }

    /// A store path is somebody's file name and may hold the separator: splitting a flow
    /// map on every comma would cut `"/Volumi/A, B/x.zip"` in half.
    private static func splitOutsideQuotes(_ text: String, on separator: Character) -> [String] {
        var pieces: [String] = []
        var current = ""
        var insideQuotes = false
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where insideQuotes:
                current.append(character)
                escaped = true
            case "\"":
                insideQuotes.toggle()
                current.append(character)
            case separator where !insideQuotes:
                pieces.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// The body up to the first `<details>`, then each block by its own summary. A
    /// person who added prose of their own after the quoted block keeps it inside that
    /// block rather than losing it: this parser reads, it never rewrites (ADR §D6).
    private static func splitBody(_ body: String) -> (newText: String, quotedHistory: String?, signature: String?) {
        let lines = body.components(separatedBy: "\n")
        let firstDetails = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "<details>" }
        let newText = lines[0..<(firstDetails ?? lines.count)]
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)

        var quoted: String?
        var signature: String?
        var cursor = firstDetails ?? lines.count
        while cursor < lines.count {
            guard lines[cursor].trimmingCharacters(in: .whitespaces) == "<details>" else {
                cursor += 1
                continue
            }
            let summary = cursor + 1 < lines.count ? summaryText(lines[cursor + 1]) : nil
            guard let end = lines[cursor...].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "</details>"
            }) else { break }
            // Clamped: `<details>` immediately followed by `</details>` is something a
            // person can type, and an unclamped range would crash on it.
            let content = lines[Swift.min(cursor + 2, end)..<end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            switch summary {
            case quotedSummary: quoted = content.isEmpty ? nil : content
            case signatureSummary: signature = content.isEmpty ? nil : content
            default: break
            }
            cursor = end + 1
        }
        return (newText, quoted, signature)
    }

    private static func summaryText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<summary>"), trimmed.hasSuffix("</summary>") else { return nil }
        return String(trimmed.dropFirst("<summary>".count).dropLast("</summary>".count))
    }

    /// R-12: `sent` iff `from` is one of `ownAddresses` (case-insensitive) - **never**
    /// derived from the mailbox, so an archived sent message still counts as sent.
    static func direction(from: EmailAddress?, ownAddresses: Set<String>) -> Direction {
        guard let from, isOwn(from, ownAddresses) else { return .received }
        return .sent
    }

    /// Addresses are compared case-insensitively: the domain is case-insensitive by
    /// RFC and no real mail server treats the local part otherwise, so a `Stefano@…`
    /// in a `To:` must not read as somebody else.
    private static func isOwn(_ address: EmailAddress, _ ownAddresses: Set<String>) -> Bool {
        let mine = Set(ownAddresses.map { $0.lowercased() })
        return mine.contains(address.address.lowercased())
    }

    /// R-12: the sender of a received message; for a sent one, the first `to`
    /// recipient not in `ownAddresses`, else the first `cc`.
    static func counterpart(
        direction: Direction,
        from: EmailAddress?,
        to: [EmailAddress],
        cc: [EmailAddress],
        ownAddresses: Set<String>
    ) -> EmailAddress? {
        switch direction {
        case .received:
            return from
        case .sent:
            // The first recipient who is not me. A message addressed only to myself
            // with the other side in copy still has a counterpart, which is why `cc`
            // is a fallback and not an afterthought.
            return to.first { !isOwn($0, ownAddresses) }
                ?? cc.first { !isOwn($0, ownAddresses) }
                ?? cc.first
        }
    }
}
