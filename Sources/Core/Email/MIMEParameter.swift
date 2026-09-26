import Foundation

// ADR-0065 (Every on-disk format round-trips faithfully or is refused), plan
// docs/plans/format-edge-hardening.md, Task 4 - R-13; ADR §D7.4.

/// One `; name=value` parameter of a MIME header value (`Content-Type`, `Content-Disposition`).
///
/// It replaces a split on every `;`, which cut `filename="Report; finale.pdf"` in two and read
/// neither RFC 2231's extended form (`filename*=UTF-8''Preventivo%20%E2%82%AC.pdf`, how Exchange
/// and every modern client write a non-ASCII attachment name) nor its continuations
/// (`filename*0*=…; filename*1*=…`, how a long one is folded).
enum MIMEParameter {
    /// The parameter's value, or nil when absent. The name matches case-insensitively; the value
    /// comes back verbatim, so a file name keeps its capitals. When both forms are present the
    /// extended one wins: `name*`, then the joined `name*0`, `name*1`, … continuations, then the
    /// plain `name`.
    /// One `name*N` or `name*N*` continuation (RFC 2231 §3).
    private struct Segment {
        var number: Int
        var value: String
        var encoded: Bool
    }

    static func value(_ name: String, in raw: String) -> String? {
        let wanted = name.lowercased()
        var plain: String?
        var extended: String?
        var segments: [Segment] = []

        for piece in pieces(of: raw).dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let key = piece[piece.startIndex..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquoted(piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespaces))

            if key == wanted {
                if plain == nil { plain = value }
            } else if key == wanted + "*" {
                if extended == nil { extended = decodedExtended(value) }
            } else if key.hasPrefix(wanted + "*") {
                var suffix = key.dropFirst(wanted.count + 1)
                let encoded = suffix.hasSuffix("*")
                if encoded { suffix = suffix.dropLast() }
                guard let number = Int(suffix), number >= 0 else { continue }
                segments.append(Segment(number: number, value: value, encoded: encoded))
            }
        }
        return extended ?? joined(segments) ?? plain
    }

    /// Splits on `;` outside double quotes; a backslash inside quotes escapes the next character.
    private static func pieces(of raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for character in raw {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where inQuotes:
                escaped = true
            case "\"":
                inQuotes.toggle()
            case ";" where !inQuotes:
                result.append(current)
                current = ""
                continue
            default:
                break
            }
            current.append(character)
        }
        result.append(current)
        return result
    }

    /// A quoted string loses its quotes and its backslash escapes; a bare token is kept as it is.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        var result = ""
        var escaped = false
        for character in value.dropFirst().dropLast() {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// `charset'language'percent-encoded` (RFC 2231 §4).
    private static func decodedExtended(_ value: String) -> String {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return decoded(percentDecoded(value), charset: "utf-8") }
        return decoded(percentDecoded(String(parts[2])), charset: String(parts[0]))
    }

    /// RFC 2231 §3: the continuations in numeric order, the charset taken from the first segment.
    private static func joined(_ segments: [Segment]) -> String? {
        guard !segments.isEmpty else { return nil }
        var charset = "utf-8"
        var bytes = Data()
        for segment in segments.sorted(by: { $0.number < $1.number }) {
            guard segment.encoded else {
                bytes.append(Data(segment.value.utf8))
                continue
            }
            var payload = segment.value
            if segment.number == 0 {
                let parts = payload.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3 {
                    charset = parts[0].isEmpty ? charset : String(parts[0])
                    payload = String(parts[2])
                }
            }
            bytes.append(percentDecoded(payload))
        }
        return decoded(bytes, charset: charset)
    }

    private static func percentDecoded(_ text: String) -> Data {
        let source = Array(text.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            if source[index] == 0x25, index + 2 < source.count,
               let hex = String(bytes: source[(index + 1)...(index + 2)], encoding: .ascii),
               let byte = UInt8(hex, radix: 16) {
                bytes.append(byte)
                index += 3
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return Data(bytes)
    }

    private static func decoded(_ bytes: Data, charset: String) -> String {
        String(data: bytes, encoding: MailCharset.encoding(for: charset)) ?? String(decoding: bytes, as: UTF8.self)
    }
}
