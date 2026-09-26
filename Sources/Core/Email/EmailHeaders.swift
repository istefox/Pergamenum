import Foundation

/// The header fields of an `.eml` file.
///
/// SPEC §14 excludes body rendering: no maintained Swift library does it well, and a
/// double click into Mail is enough. So this reads headers only, and stops at the
/// blank line that ends them - which also means it never has to hold a large
/// attachment in memory.
struct EmailHeaders: Equatable, Sendable {
    var from: EmailAddress?
    var to: [EmailAddress]
    var subject: String?
    var date: Date?
    /// The `Message-ID`, without the angle brackets. What a `message://` link is
    /// built from.
    var messageID: String?
    /// Every field as it appeared, unfolded, for anything this app does not model.
    var all: [(name: String, value: String)]
    /// The sender's zone offset in seconds east of UTC, read from the raw `Date` field
    /// (ADR-0065 §D8.2, R-15). `nil` when the field carries none a reader can trust:
    /// `-0000`, a military letter, an unknown name, or no `Date` at all.
    var dateOffset: Int?

    static func == (lhs: EmailHeaders, rhs: EmailHeaders) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to && lhs.subject == rhs.subject
            && lhs.date == rhs.date && lhs.dateOffset == rhs.dateOffset && lhs.messageID == rhs.messageID
            && lhs.all.map(\.name) == rhs.all.map(\.name)
            && lhs.all.map(\.value) == rhs.all.map(\.value)
    }

    func value(for name: String) -> String? {
        all.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    /// The `message://` URL that opens this message in Mail (SPEC §6.5).
    ///
    /// Mail's scheme wraps the Message-ID in percent-encoded angle brackets, which is
    /// why the brackets are stripped on parse and put back by the builder.
    ///
    /// ADR-0036 §D9: the encoding lives in `MailURL.forMessageID` alone, shared with
    /// `MailLink.url(forMessageID:)`, so the two cannot drift apart again.
    var mailURL: URL? { MailURL.forMessageID(messageID) }
}

struct EmailAddress: Equatable, Sendable {
    /// The display name, decoded from RFC 2047 when it was encoded.
    var name: String?
    var address: String

    /// What a card shows: the name when there is one, the address otherwise.
    var displayText: String { name ?? address }
}

enum EmailHeaderParser {
    /// Parses the header block of an `.eml` file.
    ///
    /// Reads only up to the blank line separating headers from the body, so a message
    /// with a 20 MB attachment costs the same as an empty one.
    static func parse(_ text: String) -> EmailHeaders {
        var fields: [(String, String)] = []
        var currentName: String?
        var currentValue = ""

        func flush() {
            if let name = currentName {
                fields.append((name, currentValue.trimmingCharacters(in: .whitespaces)))
            }
            currentName = nil
            currentValue = ""
        }

        // A CRLF pair is one line break. Split on `.newlines` alone, it leaves an empty line
        // between the two halves, which reads as the blank line that ends the header block: an
        // `.eml` imported with CRLF endings kept only its first field. The sync already hands
        // this LF text (`PraticaSyncEngine.headerText`); the import doors did not.
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            // The blank line ends the header block.
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }

            // A line starting with whitespace continues the previous field (RFC 5322
            // folding). Real subjects are folded constantly, and a parser that misses
            // this truncates them mid-word.
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            flush()
            currentName = String(line[line.startIndex..<colon])
            currentValue = String(line[line.index(after: colon)...])
        }
        flush()

        let decoded = fields.map { ($0.0, EncodedWord.decode($0.1)) }
        let rawDate = fields.first { $0.0.lowercased() == "date" }?.1

        return EmailHeaders(
            from: decoded.first { $0.0.lowercased() == "from" }.flatMap { parseAddress($0.1) },
            to: decoded.first { $0.0.lowercased() == "to" }.map { parseAddressList($0.1) } ?? [],
            subject: decoded.first { $0.0.lowercased() == "subject" }?.1,
            date: decoded.first { $0.0.lowercased() == "date" }.flatMap { RFC5322Date.parse($0.1) },
            messageID: decoded.first { $0.0.lowercased() == "message-id" }
                .map { $0.1.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")) },
            all: decoded.map { (name: $0.0, value: $0.1) },
            dateOffset: rawDate.flatMap(RFC5322Date.offset(of:))
        )
    }

    /// Parses `Nome Cognome <a@b.test>`, `<a@b.test>` or a bare address.
    static func parseAddress(_ raw: String) -> EmailAddress? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let address = String(trimmed[trimmed.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            var name: String? = String(trimmed[trimmed.startIndex..<open])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if name?.isEmpty == true { name = nil }
            guard !address.isEmpty else { return nil }
            return EmailAddress(name: name, address: address)
        }
        guard trimmed.contains("@") else { return nil }
        return EmailAddress(name: nil, address: trimmed)
    }

    /// Splits a comma-separated address list, ignoring commas inside a quoted name.
    static func parseAddressList(_ raw: String) -> [EmailAddress] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false

        for character in raw {
            switch character {
            case "\"": inQuotes.toggle()
            case "<": inAngle = true
            case ">": inAngle = false
            case "," where !inQuotes && !inAngle:
                parts.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        parts.append(current)
        return parts.compactMap(parseAddress)
    }
}

/// RFC 2047 encoded words, the `=?UTF-8?B?…?=` form.
///
/// Not optional in practice: any Italian correspondent's subject line with an accent
/// arrives encoded, and showing the raw form on a card is worse than showing nothing.
enum EncodedWord {
    /// RFC 2047 §6.2 (ADR-0065 §D7.3): linear whitespace between two encoded-words is dropped
    /// when both decode - a folded subject's unfold puts exactly that whitespace between the two
    /// halves of a word. Whitespace next to plain text stays, and so does whitespace next to a
    /// word that fails and is shown raw.
    static func decode(_ text: String) -> String {
        guard text.contains("=?") else { return text }

        var result = ""
        var remainder = Substring(text)
        var previousDecoded = false

        while let start = remainder.range(of: "=?") {
            let between = remainder[remainder.startIndex..<start.lowerBound]
            let afterStart = remainder[start.upperBound...]

            guard let end = tokenEnd(in: afterStart) else {
                result += remainder
                return result
            }
            let token = afterStart[afterStart.startIndex..<end.lowerBound]
            if let decoded = decodeToken(String(token)) {
                let onlyWhitespace = between.allSatisfy { $0 == " " || $0 == "\t" || $0.isNewline }
                if !(previousDecoded && onlyWhitespace) { result += between }
                result += decoded
                previousDecoded = true
            } else {
                result += between + "=?\(token)?="
                previousDecoded = false
            }
            remainder = afterStart[end.upperBound...]
        }
        result += remainder
        return result
    }

    /// The `?=` that closes a word, searched for only after `charset?encoding?`, so a Q payload
    /// that starts with an escape (`=?UTF-8?Q?=C3=A8?=`) is not cut at its own `?=C3`.
    private static func tokenEnd(in afterStart: Substring) -> Range<Substring.Index>? {
        guard let charsetEnd = afterStart.firstIndex(of: "?"),
              let encodingEnd = afterStart[afterStart.index(after: charsetEnd)...].firstIndex(of: "?")
        else { return afterStart.range(of: "?=") }
        return afterStart[afterStart.index(after: encodingEnd)...].range(of: "?=")
    }

    /// `charset?encoding?text`
    private static func decodeToken(_ token: String) -> String? {
        let parts = token.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        let encoding = String(parts[1]).uppercased()
        let payload = String(parts[2])
        let charset = String(parts[0]).uppercased()

        let data: Data?
        switch encoding {
        case "B":
            // ADR-0065 §D7.3: padding is normalised before decoding - every `=` removed, the
            // payload re-padded to a multiple of four - so a sender that drops or misplaces it
            // still decodes.
            let unpadded = payload.replacingOccurrences(of: "=", with: "")
            let padded = unpadded + String(repeating: "=", count: (4 - unpadded.count % 4) % 4)
            data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters)
        case "Q":
            data = quotedPrintable(payload)
        default:
            return nil
        }
        guard let data else { return nil }
        return String(data: data, encoding: MailCharset.encoding(for: charset))
    }

    /// Quoted-printable as used inside an encoded word, where `_` means a space.
    private static func quotedPrintable(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "=" {
                let hexStart = text.index(after: index)
                guard let hexEnd = text.index(hexStart, offsetBy: 2, limitedBy: text.endIndex),
                      let byte = UInt8(text[hexStart..<hexEnd], radix: 16)
                else { return nil }
                bytes.append(byte)
                index = hexEnd
                continue
            }
            bytes.append(character == "_" ? 0x20 : UInt8(character.asciiValue ?? 0x3F))
            index = text.index(after: index)
        }
        return Data(bytes)
    }
}

/// The `Date:` header format of RFC 5322.
enum RFC5322Date {
    /// Parses `Tue, 4 Aug 2026 09:15:00 +0200`, with or without the day name and with
    /// an obsolete zone name in place of an offset.
    static func parse(_ raw: String) -> Date? {
        // The locale is fixed to POSIX: month and day names in the header are always
        // English, and parsing them under the user's locale fails on an Italian Mac.
        //
        // Formatter and cleaned text are built once for the whole call rather than once
        // per candidate format - six identical allocations for every message read. The
        // formatter stays local to the call, never a `static`, so there is no shared
        // instance whose `dateFormat` two threads could be reassigning at once.
        let text = cleaned(raw)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let formats = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss zzz",
    ]

    /// The zone of a `Date` field in seconds east of UTC (ADR-0065 §D8.2, R-15): `±hhmm` as
    /// written, `UT`/`GMT`/`Z` as 0, the eight US names of RFC 5322 §4.3 by their value. `-0000`
    /// means "zone unknown" (RFC 5322 §3.3), and a military letter or any other name is not one
    /// a reader can trust, so all of those are `nil`.
    static func offset(of raw: String) -> Int? {
        guard let zone = cleaned(raw).split(separator: " ").last.map(String.init) else { return nil }
        if let sign = zone.first, sign == "+" || sign == "-" {
            let digits = zone.dropFirst()
            guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits),
                  zone != "-0000"
            else { return nil }
            let minutes = value / 100 * 60 + value % 100
            return (sign == "-" ? -1 : 1) * minutes * 60
        }
        let hours: Int? = switch zone.uppercased() {
        case "UT", "GMT", "Z": 0
        case "EDT": -4
        case "EST", "CDT": -5
        case "CST", "MDT": -6
        case "MST", "PDT": -7
        case "PST": -8
        default: nil
        }
        return hours.map { $0 * 3600 }
    }

    /// Strips the trailing `(CEST)` comment some senders append after the offset.
    private static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if let comment = text.range(of: " (") {
            text = String(text[text.startIndex..<comment.lowerBound])
        }
        return text
    }
}
