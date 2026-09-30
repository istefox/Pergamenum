import Foundation

// ADR-0076 §D1/§D4 (PG-338): the pure text transforms behind every body write the timeline makes
// to `pratica.md` - writing, replacing and removing one anchor line, and carrying anchored entry
// blocks between two `pratica.md` files on «Sposta in…». Each one is computed from a fresh read
// by the caller and written back whole with `expecting:`; nothing here touches the disk.
//
// Every line this writes takes the target's own line break (`LineBreak.detected(in:)`, R-19),
// and every byte it does not mean to change is kept: the frontmatter, the other entries, the
// other lines of the entry it edits.
enum PraticaEntryEdit {
    /// What removing carried blocks from a source left: the new text, and the carried blocks it
    /// did not find there (edited since, or already gone), which stay wherever they are.
    struct Removal: Equatable, Sendable {
        var text: String
        var missing: [String]
    }

    /// `source` with the entry at `ordinal` anchored to `messageID` (R-11): the anchor line is
    /// inserted directly under the heading, or an existing one is replaced in place, keeping its
    /// line break. Nil when the ordinal names no entry, the id cannot be spelled, or the entry
    /// already carries that anchor - nothing to write.
    static func anchoring(entryAt ordinal: Int, to messageID: String, in source: String) -> String? {
        let entries = PraticaManualEntries.parse(source)
        guard entries.indices.contains(ordinal),
              let line = PraticaEntryAnchor.line(for: messageID)
        else { return nil }
        let entry = entries[ordinal]
        guard entry.anchor != messageID else { return nil }

        let text = source as NSString
        if let existing = entry.anchorLineRange {
            return text.replacingCharacters(in: existing, with: line)
        }
        let lineBreak = LineBreak.detected(in: source).characters
        let heading = headingLine(of: entry, in: source)
        if heading.terminatorLength == 0 {
            // The heading is the file's last line and has no line break of its own.
            return text.replacingCharacters(in: NSRange(location: heading.end, length: 0), with: lineBreak + line)
        }
        return text.replacingCharacters(in: NSRange(location: heading.end, length: 0), with: line + lineBreak)
    }

    /// `source` with the entry at `ordinal`'s anchor line removed, with its own line break and
    /// nothing else (R-12). Nil when the ordinal names no entry or the entry has no anchor.
    static func unanchoring(entryAt ordinal: Int, in source: String) -> String? {
        let entries = PraticaManualEntries.parse(source)
        guard entries.indices.contains(ordinal),
              let range = entries[ordinal].anchorLineRange
        else { return nil }
        return (source as NSString).replacingCharacters(in: lineRangeWithTerminator(range, in: source), with: "")
    }

    /// Every entry block of `source` anchored to `messageID`, in file order, LF-normalised and
    /// with its trailing blank lines dropped (R-14): the unit a carry appends and removes.
    static func blocks(anchoredTo messageID: String, in source: String) -> [String] {
        PraticaManualEntries.parse(source)
            .filter { $0.anchor == messageID }
            .map { normalisedBlock($0, in: source) }
    }

    /// `target` with `blocks` appended at its end, one blank line before each block and never
    /// two, in `target`'s own line break (R-14, R-19) - the separator rule `PraticaEntry.insert`
    /// already applies.
    static func appending(_ blocks: [String], to target: String) -> String {
        let lineBreak = LineBreak.detected(in: target)
        var text = target
        for block in blocks {
            if !text.isEmpty {
                if text.last.map(LineBreak.isTerminator) != true { text += lineBreak.characters }
                if text.dropLast().last.map(LineBreak.isTerminator) != true { text += lineBreak.characters }
            }
            text += lineBreak.normalised(block) + lineBreak.characters
        }
        return text
    }

    /// `source` with each block anchored to `messageID` whose normalised text equals a carried
    /// one removed, whole, every other byte kept (R-14). Each carried block is consumed once, so
    /// two identical carried blocks remove two identical entries; a carried block with no match
    /// lands in `missing`.
    ///
    /// A removed block that ended the file also takes the one blank line before it, the
    /// separator `appending` puts there: appending then removing the same blocks gives the
    /// target back byte for byte (R-14's undo), where keeping it would leave one blank line
    /// more at the end of the file on every round trip. A block removed from anywhere else
    /// takes only its own range.
    static func removing(_ blocks: [String], anchoredTo messageID: String, from source: String) -> Removal {
        var candidates = PraticaManualEntries.parse(source)
            .filter { $0.anchor == messageID }
            .map { (range: $0.blockRange, text: normalisedBlock($0, in: source), consumed: false) }
        var missing: [String] = []
        for block in blocks {
            if let index = candidates.firstIndex(where: { !$0.consumed && $0.text == block }) {
                candidates[index].consumed = true
            } else {
                missing.append(block)
            }
        }
        let text = NSMutableString(string: source)
        let endsFile = candidates.last { $0.consumed }.map { NSMaxRange($0.range) == text.length } ?? false
        for candidate in candidates.reversed() where candidate.consumed {
            text.replaceCharacters(in: candidate.range, with: "")
        }
        if endsFile { dropTrailingBlankLine(of: text) }
        return Removal(text: text as String, missing: missing)
    }

    /// `source` with every entry's position-one anchor line removed, with its line break: what
    /// the inspector renders (ADR-0076 §D7, R-01). An anchor line lower in an entry is body text
    /// and stays.
    static func removingAnchorLines(in source: String) -> String {
        let text = NSMutableString(string: source)
        for entry in PraticaManualEntries.parse(source).reversed() {
            guard let range = entry.anchorLineRange else { continue }
            text.replaceCharacters(in: lineRangeWithTerminator(range, in: source), with: "")
        }
        return text as String
    }

    // MARK: - Helpers

    /// The entry's heading line, addressed in the full source.
    private static func headingLine(of entry: PraticaManualEntry, in source: String) -> PraticaManualEntries.Line {
        let lines = PraticaManualEntries.bodyLines(of: source)
        return lines.first { $0.location == entry.blockRange.location } ?? PraticaManualEntries.Line(
            content: "", location: entry.blockRange.location, length: 0, terminatorLength: 0
        )
    }

    /// `range` widened over the line break that follows it, CRLF or LF, when there is one.
    private static func lineRangeWithTerminator(_ range: NSRange, in source: String) -> NSRange {
        let text = source as NSString
        let end = NSMaxRange(range)
        if end + 1 < text.length, text.character(at: end) == 0x0D, text.character(at: end + 1) == 0x0A {
            return NSRange(location: range.location, length: range.length + 2)
        }
        if end < text.length, text.character(at: end) == 0x0A {
            return NSRange(location: range.location, length: range.length + 1)
        }
        return range
    }

    /// One empty last line of `text` removed - its final line break, CRLF or LF - when the
    /// text ends with an empty line; nothing otherwise. The inverse of the blank line
    /// `appending` adds before a block.
    private static func dropTrailingBlankLine(of text: NSMutableString) {
        let length = text.length
        if length >= 4, text.substring(from: length - 4) == "\r\n\r\n" {
            text.deleteCharacters(in: NSRange(location: length - 2, length: 2))
        } else if length >= 2, text.character(at: length - 1) == 0x0A, text.character(at: length - 2) == 0x0A {
            text.deleteCharacters(in: NSRange(location: length - 1, length: 1))
        }
    }

    /// An entry's block as a carry compares and appends it: LF line breaks, trailing blank lines
    /// dropped, no final line break.
    private static func normalisedBlock(_ entry: PraticaManualEntry, in source: String) -> String {
        let raw = (source as NSString).substring(with: entry.blockRange)
        var lines = raw.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
