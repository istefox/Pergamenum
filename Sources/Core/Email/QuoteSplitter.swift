import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-07.

/// The result of splitting a message body into new text, quoted history and a
/// trailing signature.
struct QuoteSplit: Equatable, Sendable {
    /// The text before the first recognised separator - the whole body when nothing
    /// matched.
    var newText: String
    /// Everything from the first recognised separator onward, `nil` when no
    /// separator matched (SPEC "Quoted-text rules": "When no separator matches, the
    /// body stays whole").
    var quotedHistory: String?
    /// Text after the signature marker (`^-- $`, or the sender's display name
    /// followed by ≤6 short lines), moved out of `newText`/`quotedHistory` into its
    /// own `Firma` block. `nil` when no signature was found.
    var signature: String?
}

/// Splits a body on the **first** recognised separator (SPEC "Quoted-text rules"):
/// `Il giorno … ha scritto:`/`On … wrote:`, `--- Messaggio originale/Original
/// Message ---`, a `Da:/Inviato:/A:/Oggetto:` header block, an all-`>` tail, or an
/// Outlook `_{10,}` divider. A pure function with a fixture corpus of at least five
/// styles (`Tests/EmailFixtureCorpus.swift`).
enum QuoteSplitter {
    static func split(_ body: String) -> QuoteSplit {
        let lines = body.components(separatedBy: "\n")
        guard let cut = separatorLine(in: lines) else {
            // Nothing recognised: the body is returned byte for byte, never trimmed.
            // A message this app could not read is a message it must not rewrite.
            return withSignature(newText: body, quotedHistory: nil)
        }
        return withSignature(
            newText: lines[0..<cut].joined(separator: "\n"),
            quotedHistory: lines[cut...].joined(separator: "\n")
        )
    }

    /// The **first** line any rule recognises: the styles are checked against every
    /// line rather than one style at a time, because a body can carry two (Outlook
    /// writes an underscore divider *and* a `Da:` block) and the earlier one is the
    /// real edge of what the sender wrote.
    private static func separatorLine(in lines: [String]) -> Int? {
        var earliest: Int?
        func consider(_ index: Int?) {
            guard let index else { return }
            earliest = earliest.map { Swift.min($0, index) } ?? index
        }
        consider(attributionLine(in: lines))
        consider(originalMessageLine(in: lines))
        consider(underscoreDividerLine(in: lines))
        consider(headerBlockLine(in: lines))
        consider(angleBracketTail(in: lines))
        return earliest
    }

    /// Italian Mail «Il giorno … ha scritto:» and English «On … wrote:», plus the
    /// German/Outlook «… schrieb:». Anchored on the closing colon at end of line, which
    /// is what makes it an attribution rather than a sentence mentioning the verb.
    private static func attributionLine(in lines: [String]) -> Int? {
        let endings = ["ha scritto:", "wrote:", "schrieb:", "a écrit :", "escribió:"]
        return lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 12 else { return false }
            // Lowercased once per line, not once per ending: the closure below ran it
            // up to five times for every line of every body.
            let lowered = trimmed.lowercased()
            return endings.contains { lowered.hasSuffix($0) }
        }
    }

    /// The dashes and spaces `originalMessageLine` strips off its divider, held once
    /// rather than rebuilt for every line it looks at.
    private static let dashesAndSpaces = CharacterSet(charactersIn: "- ")

    /// `----- Messaggio originale -----` / `----- Original Message -----`, with any
    /// number of dashes on either side.
    private static func originalMessageLine(in lines: [String]) -> Int? {
        lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { return false }
            let inner = trimmed.trimmingCharacters(in: dashesAndSpaces).lowercased()
            return inner == "messaggio originale" || inner == "original message"
                || inner == "messaggio inoltrato" || inner == "forwarded message"
        }
    }

    /// Outlook's divider: a line of ten or more underscores and nothing else.
    private static func underscoreDividerLine(in lines: [String]) -> Int? {
        lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 10 && trimmed.allSatisfy { $0 == "_" }
        }
    }

    /// The Italian/English Outlook header block: a `Da:`/`From:` line with a
    /// `Inviato:`/`Sent:`/`A:`/`To:`/`Oggetto:`/`Subject:` line close behind it. The
    /// second line is required, or every message quoting an address book entry as
    /// «Da: …» in its own prose would be cut.
    private static func headerBlockLine(in lines: [String]) -> Int? {
        let openers = ["da:", "from:", "von:"]
        let followers = ["inviato:", "sent:", "a:", "to:", "oggetto:", "subject:", "cc:", "gesendet:"]
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard openers.contains(where: { trimmed.hasPrefix($0) }) else { continue }
            let window = lines[(index + 1)..<Swift.min(index + 4, lines.count)]
            let hasFollower = window.contains { candidate in
                let candidate = candidate.trimmingCharacters(in: .whitespaces).lowercased()
                return followers.contains { candidate.hasPrefix($0) }
            }
            if hasFollower { return index }
        }
        return nil
    }

    /// Bare `>` quoting with no attribution line at all: the first line of the maximal
    /// run at the end of the body in which every non-empty line is quoted.
    private static func angleBracketTail(in lines: [String]) -> Int? {
        var candidate: Int?
        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix(">") else { break }
            candidate = index
        }
        guard let candidate else { return nil }
        // Walk back over the blank lines that separate the tail from the new text, so
        // the cut is the whole quoted block rather than its first quoted character.
        var start = candidate
        while start > 0, lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            start -= 1
        }
        return start
    }

    /// RFC 3676 §4.3's signature marker: a line that is exactly `-- ` (the trailing
    /// space is the marker, and every mail client writes it). Applied to the new text
    /// only - a signature inside the quoted history belongs to whoever wrote that
    /// message, not to this one.
    private static func withSignature(newText: String, quotedHistory: String?) -> QuoteSplit {
        let lines = newText.components(separatedBy: "\n")
        guard let marker = lines.firstIndex(where: { $0 == "-- " || $0 == "--" || $0 == "-- \r" })
        else {
            return QuoteSplit(newText: newText, quotedHistory: quotedHistory, signature: nil)
        }
        let signature = lines[(marker + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return QuoteSplit(
            newText: lines[0..<marker].joined(separator: "\n"),
            quotedHistory: quotedHistory,
            signature: signature.isEmpty ? nil : signature
        )
    }
}
