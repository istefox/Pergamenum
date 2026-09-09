import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-05.

/// Walks a (possibly multipart) RFC 822 message and decodes its parts.
///
/// **Extends `EmailHeaderParser`, does not replace it** (SPEC "Components"):
/// `EmailHeaderParser.parse` still owns header parsing, folding and RFC 2047 decoding
/// for both the top-level message and each part; this type adds only what
/// `EmailHeaderParser` never had to do, because it stops at the blank line ending the
/// headers - the multipart boundary walk, transfer-encoding decode and charset
/// handling.
enum MIMEDecoder {
    /// Walks `rfc822`'s body and returns its parts, decoded and classified
    /// (text/plain, text/html, inline `Content-ID`, attachment). A non-multipart
    /// message is returned as exactly one part.
    static func decode(_ rfc822: Data) -> [MIMEPart] {
        parts(of: rfc822, depth: 0)
    }

    /// A `multipart/*` nested deeper than this is either a loop or an attack; real mail
    /// stops at three or four (`mixed` › `related` › `alternative`).
    private static let maximumDepth = 12

    private static func parts(of message: Data, depth: Int) -> [MIMEPart] {
        guard depth <= maximumDepth else { return [] }

        let split = splitHeaders(message)
        let headers = EmailHeaderParser.parse(
            String(decoding: split.headers, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        ).all
        // RFC 2045: a part with no `Content-Type` is `text/plain; charset=us-ascii`.
        let contentType = value(of: "content-type", in: headers) ?? "text/plain"
        let base = baseType(of: contentType)

        if base.hasPrefix("multipart/"), let boundary = parameter("boundary", of: contentType) {
            return bodies(of: split.body, boundary: boundary)
                .flatMap { parts(of: $0, depth: depth + 1) }
        }
        return [leaf(headers: headers, contentType: base, body: split.body)]
    }

    // MARK: - One leaf part

    private static func leaf(
        headers: [(name: String, value: String)],
        contentType: String,
        body: Data
    ) -> MIMEPart {
        let disposition = value(of: "content-disposition", in: headers) ?? ""
        let transferEncoding = value(of: "content-transfer-encoding", in: headers)
        let filename = parameter("filename", of: disposition)
            ?? parameter("name", of: value(of: "content-type", in: headers) ?? "")
        // `EmailHeaders.messageID` strips the angle brackets a `Content-ID` is written
        // in, and a `cid:` reference in the body carries none either: the stripped form
        // is the one both sides can compare.
        let contentID = value(of: "content-id", in: headers)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "<> "))

        let isAttachment = baseType(of: disposition) == "attachment"
        let kind: MIMEPart.Kind
        if !isAttachment, contentType == "text/plain" {
            kind = .textPlain
        } else if !isAttachment, contentType == "text/html" {
            kind = .textHTML
        } else if let contentID, !contentID.isEmpty, contentType.hasPrefix("image/") {
            kind = .inlineImage(contentID: contentID)
        } else {
            kind = .attachment(filename: filename)
        }

        let isText = kind == .textPlain || kind == .textHTML
        return MIMEPart(
            kind: kind,
            contentType: contentType,
            headers: headers,
            decodedText: isText
                ? decodeText(
                    body,
                    transferEncoding: transferEncoding,
                    charset: parameter("charset", of: value(of: "content-type", in: headers) ?? "")
                )
                : nil,
            // A TNEF `winmail.dat` is carried through exactly as it arrived: this app
            // does not decode TNEF, and half-decoding it would lose the file.
            decodedData: isText ? nil : decodeBytes(body, transferEncoding: transferEncoding),
            filename: filename
        )
    }

    // MARK: - Header/body split and the boundary walk

    private static func splitHeaders(_ message: Data) -> (headers: Data, body: Data) {
        guard let bodyStart = EMLXReader.headerBodySeparator(in: message) else {
            return (Data(message), Data())
        }
        return (Data(message[message.startIndex..<bodyStart]), Data(message[bodyStart...]))
    }

    /// Splits a multipart body on its boundary delimiter lines.
    ///
    /// The match is exact (`--boundary` plus optional trailing whitespace, or
    /// `--boundary--` to close), never a prefix test: a nested boundary is routinely
    /// the outer one with a suffix — `----=_X` and `----=_X-alt` — and a prefix test
    /// would cut the outer walk on every line of the inner part.
    private static func bodies(of body: Data, boundary: String) -> [Data] {
        let bytes = Array(body)
        let open = Array("--\(boundary)".utf8)
        var parts: [Data] = []
        var current: Int?
        var offset = 0

        while offset <= bytes.count {
            let lineEnd = bytes[offset...].firstIndex(of: 0x0A) ?? bytes.count
            let line = Array(bytes[offset..<lineEnd])
            switch delimiter(line, open: open) {
            case .none:
                break
            case .some(let isClosing):
                if let start = current {
                    // The CRLF in front of a delimiter line belongs to the delimiter
                    // (RFC 2046), so it is not part of the payload.
                    var end = offset
                    if end > start, bytes[end - 1] == 0x0A { end -= 1 }
                    if end > start, bytes[end - 1] == 0x0D { end -= 1 }
                    parts.append(Data(bytes[start..<end]))
                }
                current = isClosing ? nil : lineEnd + 1
                if isClosing { return parts }
            }
            if lineEnd >= bytes.count { break }
            offset = lineEnd + 1
        }
        // A multipart that ends without its closing `--boundary--` (truncated download,
        // a client that forgot): the last part is kept, but an empty tail is not, or a
        // phantom `text/plain` part appears with nothing in it.
        if let start = current, start < bytes.count {
            parts.append(Data(bytes[start..<bytes.count]))
        }
        return parts
    }

    /// `nil` when the line is not a delimiter for this boundary; `true` when it is the
    /// closing one.
    private static func delimiter(_ line: [UInt8], open: [UInt8]) -> Bool? {
        guard line.count >= open.count, Array(line.prefix(open.count)) == open else { return nil }
        var rest = Array(line.dropFirst(open.count))
        while let last = rest.last, last == 0x0D || last == 0x20 || last == 0x09 { rest.removeLast() }
        if rest.isEmpty { return false }
        if rest == [0x2D, 0x2D] { return true }
        return nil
    }

    // MARK: - Header field access

    private static func value(of name: String, in headers: [(name: String, value: String)]) -> String? {
        headers.first { $0.name.lowercased() == name }?.value
    }

    /// The media type without its parameters, lowercased: `text/html`, never
    /// `text/html; charset=utf-8`.
    private static func baseType(of raw: String) -> String {
        String(raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// One `; name=value` parameter, quoted or bare. Case-insensitive on the name,
    /// value returned verbatim so a file name keeps its capitals.
    private static func parameter(_ name: String, of raw: String) -> String? {
        for piece in raw.split(separator: ";").dropFirst() {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<equals])
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard key == name else { continue }
            return String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /// Decodes one part's raw body bytes given its `Content-Transfer-Encoding`
    /// (`7bit`/`8bit`/`quoted-printable`/`base64`, case-insensitive, `nil` treated as
    /// `7bit`) and charset (`utf-8`/`iso-8859-1`/`windows-1252`, `nil` treated as
    /// `utf-8`). A byte sequence the charset cannot decode becomes U+FFFD, never a
    /// thrown error or a dropped part (R-05).
    static func decodeText(_ data: Data, transferEncoding: String?, charset: String?) -> String {
        let bytes = decodeBytes(data, transferEncoding: transferEncoding)
        let encoding = stringEncoding(for: charset)
        if encoding == .utf8 {
            // `String(data:encoding:.utf8)` answers `nil` on a single bad byte and
            // would lose the whole part; `String(decoding:as:)` substitutes U+FFFD for
            // it and keeps the rest (R-05).
            return String(decoding: bytes, as: UTF8.self)
        }
        // Latin-1 and CP1252 map almost every byte, but CP1252 leaves five undefined:
        // a `nil` there falls back to the lossy UTF-8 read rather than dropping the part.
        return String(data: bytes, encoding: encoding) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// The transfer-encoding half of `decodeText`, on its own: what an attachment or an
    /// inline image needs, since those are never charset-interpreted.
    static func decodeBytes(_ data: Data, transferEncoding: String?) -> Data {
        switch (transferEncoding ?? "7bit").trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64":
            return Data(base64Encoded: data, options: .ignoreUnknownCharacters) ?? data
        case "quoted-printable":
            return quotedPrintable(data)
        default:
            // `7bit`, `8bit`, `binary`, and anything unknown: the bytes as they are.
            // Guessing at an unknown encoding corrupts a part that was probably fine.
            return data
        }
    }

    /// RFC 2045 §6.7. Unlike `EncodedWord`'s own quoted-printable, `_` is an ordinary
    /// underscore here — the space substitution belongs to encoded words alone — and a
    /// trailing `=` before a line break is a soft break that disappears.
    private static func quotedPrintable(_ data: Data) -> Data {
        let bytes = Array(data)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            guard bytes[index] == 0x3D else {
                decoded.append(bytes[index])
                index += 1
                continue
            }
            if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
                index += 3
                continue
            }
            if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                index += 2
                continue
            }
            if index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                decoded.append(high << 4 | low)
                index += 3
                continue
            }
            // A lone `=` that is not an escape: kept, because a sender who wrote one is
            // better served by a stray character than by a silent deletion.
            decoded.append(bytes[index])
            index += 1
        }
        return Data(decoded)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    /// The charsets Italian and English business mail actually arrives in. Anything
    /// else is read as UTF-8, which degrades to U+FFFD rather than to nothing.
    private static func stringEncoding(for charset: String?) -> String.Encoding {
        switch (charset ?? "utf-8").trimmingCharacters(in: .whitespaces).uppercased() {
        case "ISO-8859-1", "ISO8859-1", "LATIN1", "ISO_8859-1": .isoLatin1
        case "ISO-8859-15", "LATIN9": .isoLatin2
        case "WINDOWS-1252", "CP1252", "CP-1252": .windowsCP1252
        case "US-ASCII", "ASCII": .ascii
        default: .utf8
        }
    }
}
