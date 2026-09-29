import Foundation

// MARK: - Reading the file back

extension MessageDocument {
    /// Parses a message `.md` file back into structured form - used by R-08's
    /// collision rule (does an existing file carry this `Message-ID`?) and by the
    /// sync's "already on disk" dedup (SPEC "Membership rule", item 5) when the
    /// ledger does not have the answer.
    ///
    /// The frontmatter is scanned once into a first-occurrence field map and every key is a lookup
    /// in it, and one date formatter serves the whole file (ADR-0072 §D9, R-13).
    static func parse(_ text: String) -> MessageDocument? {
        let note = NoteDocument.parse(text)
        let lines = note.frontmatter.foreignKeys.flatMap(\.lines)
        let fields = scalars(in: lines)
        guard let schemaVersion = fields["pergamenum-mail"].flatMap(Int.init),
              let messageID = fields["pergamenum-mail-message-id"].map(unquoted)
        else { return nil }

        let formatter = ISO8601DateFormatter()
        let body = splitBody(note.body)
        return MessageDocument(
            frontmatter: MailFrontmatter(
                schemaVersion: schemaVersion,
                messageID: messageID,
                conversationID: fields["pergamenum-mail-conversation-id"].flatMap(Int.init),
                direction: fields["pergamenum-mail-direction"]
                    .flatMap { Direction(rawValue: unquoted($0)) } ?? .received,
                // A message whose date this app cannot read still has to be findable by
                // its `Message-ID`: it sorts to the beginning rather than disappearing.
                date: fields["pergamenum-mail-date"].flatMap { isoDate($0, formatter) } ?? .distantPast,
                dateOffset: fields["pergamenum-mail-date"].flatMap(isoOffset),
                received: fields["pergamenum-mail-received"].flatMap { isoDate($0, formatter) },
                from: fields["pergamenum-mail-from"].map(unquoted) ?? "",
                to: list(fields["pergamenum-mail-to"]),
                cc: list(fields["pergamenum-mail-cc"]),
                // A message file written before this key existed reads back with an
                // empty subject rather than failing to parse: the file is still a
                // message, and its `Message-ID` is what every caller matches on.
                subject: fields["pergamenum-mail-subject"].map(unquoted) ?? "",
                attachments: list(fields[attachmentsKey]),
                storeReferences: storeReferences(in: lines),
                pendingInlineImages: list(fields[inlinePendingKey]),
                linkedNote: fields[noteKey].map(unquoted),
                body: fields["pergamenum-mail-body"]
                    .flatMap { BodyState(rawValue: unquoted($0)) } ?? .complete,
                original: fields["pergamenum-mail-original"].map(unquoted)
            ),
            newText: body.newText,
            quotedHistory: body.quotedHistory,
            signature: body.signature
        )
    }

    /// `formatter` is the caller's, shared across the file's dates: its options are set at the
    /// start of every call, so the fractional fallback of one date never leaks into the next.
    private static func isoDate(_ text: String, _ formatter: ISO8601DateFormatter) -> Date? {
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// The offset a stored date was written in (ADR-0065 §D8.2): `±hh:mm` as seconds east of
    /// UTC, and `Z` - or a zero offset, which renders as `Z` - as `nil`, so render → parse →
    /// render stays identical.
    private static func isoOffset(_ text: String) -> Int? {
        let zone = text.suffix(6)
        guard zone.count == 6, let sign = zone.first, sign == "+" || sign == "-",
              zone[zone.index(zone.startIndex, offsetBy: 3)] == ":",
              let hours = Int(zone.dropFirst().prefix(2)), let minutes = Int(zone.suffix(2))
        else { return nil }
        let seconds = (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
        return seconds == 0 ? nil : seconds
    }

    /// Every non-indented line holding a colon, as key → value, both trimmed of spaces and tabs.
    /// The first occurrence of a key wins, as the per-key scan this replaced answered it.
    private static func scalars(in lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines where !line.hasPrefix(" ") && !line.hasPrefix("\t") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard fields[key] == nil else { continue }
            fields[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    private static func list(_ raw: String?) -> [String] {
        guard let raw, raw.hasPrefix("["), raw.hasSuffix("]") else { return [] }
        let inner = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return [] }
        return splitOutsideQuotes(String(inner), on: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
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

    /// The exact inverse of `quoted()` (ADR-0065 §D8.1, R-14): one left-to-right scan that
    /// decodes `\\`, `\"`, `\n` and `\r` (PG-314) as pairs and leaves any other backslash as
    /// it is. Chained replacements are not an inverse in either order: `C:\nuovo` is written
    /// `C:\\nuovo`, and once `\\` is back to `\`, the `\n` that follows reads as a line break.
    ///
    /// Walks unicode scalars, as `quoted()` does, so a decoded `\r` followed by a decoded `\n`
    /// comes back as the CRLF pair it was written from.
    private static func unquoted(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.count >= 2, scalars.first == "\"", scalars.last == "\"" else { return value }
        var result = String.UnicodeScalarView()
        var pendingBackslash = false
        for scalar in scalars.dropFirst().dropLast() {
            if pendingBackslash {
                pendingBackslash = false
                switch scalar {
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "r": result.append("\r")
                default:
                    result.append("\\")
                    result.append(scalar)
                }
            } else if scalar == "\\" {
                pendingBackslash = true
            } else {
                result.append(scalar)
            }
        }
        if pendingBackslash { result.append("\\") }
        return String(result)
    }

    /// The three parts `splitBody` reads a body back into - a named type rather than a
    /// 3-member tuple (`large_tuple`).
    private struct SplitBody {
        var newText: String
        var quotedHistory: String?
        var signature: String?
    }

    /// The body up to the first `<details>`, then each block by its own summary. A
    /// person who added prose of their own after the quoted block keeps it inside that
    /// block rather than losing it: this parser reads, it never rewrites (ADR §D6).
    private static func splitBody(_ body: String) -> SplitBody {
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
        return SplitBody(newText: newText, quotedHistory: quoted, signature: signature)
    }

    private static func summaryText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<summary>"), trimmed.hasSuffix("</summary>") else { return nil }
        return String(trimmed.dropFirst("<summary>".count).dropLast("</summary>".count))
    }
}
