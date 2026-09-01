import Foundation

/// What moving a section in the Outline means as plain text: which two ranges of the note
/// change, and what replaces them (PG-019).
///
/// A move is always exactly two edits - the section removed from where it was, the same
/// section (heading level rewritten to fit) inserted where it is dropped - computed against
/// the ORIGINAL text and left for the caller to apply in descending range order, the same
/// contract `NoteTextView.Coordinator.apply(_:to:)` already keeps for find/replace-all
/// (`NoteTextView+Matches.swift`): from the bottom up, nothing an earlier range depends on
/// has moved yet.
///
/// In `Core` and without AppKit: the move is a fact about the text, not about the editor.
enum OutlineMove {
    /// The two range/text pairs that move a section, ordered by range location descending
    /// so replaying them in this order never invalidates a range not yet applied.
    ///
    /// `destination` is the outline entry index the moved section should land BEFORE, or
    /// `nil` to move it to the very end of the note. Dropping "before X" means "becomes a
    /// sibling of X": the moved section's own heading takes X's level (X's enclosing
    /// heading's level, when X is an embed), and every nested heading inside the moved
    /// section shifts by the same delta, preserving its relative depth.
    ///
    /// Returns `nil` when the move is impossible or a no-op: `entry` is not a heading,
    /// `destination` is out of range, `destination` falls inside the section's own extent
    /// (including onto itself or one of its nested subsections), or the drop would leave
    /// the section exactly where it already is, at the same level.
    static func replacements(
        in text: String,
        moving entry: Int,
        toPrecede destination: Int?
    ) -> [(range: NSRange, text: String)]? {
        let entries = NoteOutline.entries(in: text)
        guard entries.indices.contains(entry),
              case .heading(let sourceLevel) = entries[entry].kind
        else { return nil }
        guard let extent = extentIncludingNewline(in: text, headingAt: entry) else { return nil }
        guard let (insertionPoint, targetLevel) = target(
            in: text, entries: entries, destination: destination, excluding: extent
        ) else { return nil }

        // Refused: dropping onto the section itself or a nested subsection of it.
        guard !extent.contains(insertionPoint) else { return nil }
        // Refused: dropping right back where it already is, unchanged.
        guard insertionPoint != extent.upperBound || targetLevel != sourceLevel else { return nil }

        let extracted = rewriteLevels(of: String(text[extent]), delta: targetLevel - sourceLevel)
        let insertedText = insertionText(
            for: extracted, in: text, extent: extent, before: destination != nil
        )
        let deletion = (range: NSRange(extent, in: text), text: "")
        let insertion = (
            range: NSRange(location: insertionPoint.utf16Offset(in: text), length: 0),
            text: insertedText
        )
        return [deletion, insertion].sorted { $0.range.location > $1.range.location }
    }

    // MARK: -

    /// `extracted`, given exactly the line break its new position needs - never assumed
    /// from whatever `extent` happened to carry, which is a fact about the OLD position.
    ///
    /// Dropped before another line: that line's own start is always either the very start
    /// of the note or immediately after a "\n" already there (every `NoteOutline` line
    /// range starts that way), so only a trailing "\n" has to be supplied, separating the
    /// moved section from the line that now follows it.
    ///
    /// Appended at the end of the note: nothing follows it to separate it from, so instead
    /// a LEADING "\n" is supplied when needed - and "needed" depends on what will actually
    /// end up right before it once the section is gone, which is the character before the
    /// note's own end when the section was moved from elsewhere, or the character before
    /// the section's own extent when the section was the last thing in the note already
    /// (moved to "the end", i.e. a level-only change in place).
    private static func insertionText(
        for extracted: String,
        in text: String,
        extent: Range<String.Index>,
        before destinationGiven: Bool
    ) -> String {
        let body = extracted.hasSuffix("\n") ? String(extracted.dropLast()) : extracted
        guard !destinationGiven else { return body + "\n" }

        let precedingCharacter: Character?
        if extent.upperBound == text.endIndex {
            precedingCharacter = extent.lowerBound > text.startIndex
                ? text[text.index(before: extent.lowerBound)]
                : nil
        } else {
            precedingCharacter = text.isEmpty ? nil : text[text.index(before: text.endIndex)]
        }
        return (precedingCharacter == nil || precedingCharacter == "\n") ? body : "\n" + body
    }

    /// The section's own text extent, its trailing newline included when there is one - so
    /// removing it leaves no blank line behind and inserting it elsewhere carries its own
    /// line break with it. `NoteFolding.sectionRange` deliberately stops short of the
    /// newline (it is showing a section, not splicing one), so this is the one place that
    /// extends it for a caller that does.
    private static func extentIncludingNewline(in text: String, headingAt entry: Int) -> Range<String.Index>? {
        guard let range = NoteFolding.sectionRange(in: text, headingAt: entry) else { return nil }
        guard range.upperBound < text.endIndex, text[range.upperBound] == "\n" else { return range }
        return range.lowerBound..<text.index(after: range.upperBound)
    }

    /// Where the moved section lands, and what level it takes there.
    private static func target(
        in text: String,
        entries: [NoteOutline.Entry],
        destination: Int?,
        excluding extent: Range<String.Index>
    ) -> (point: String.Index, level: Int)? {
        guard let destination else {
            // End of the note: sibling of the last heading not inside the moved section's
            // own extent (skipping it and its nested headings when it is itself the last
            // section already). No heading anywhere else in the note: level 1.
            for candidate in entries.reversed() {
                guard case .heading(let level) = candidate.kind, !extent.contains(candidate.range.lowerBound)
                else { continue }
                return (text.endIndex, level)
            }
            return (text.endIndex, 1)
        }
        guard entries.indices.contains(destination) else { return nil }
        return (entries[destination].range.lowerBound, targetLevel(at: destination, in: entries))
    }

    /// A heading row's own level; an embed row carries none of its own
    /// (`NoteOutline.Entry.level` is one step past its heading's, for indentation only), so
    /// an embed's target is the level of the heading that encloses it.
    private static func targetLevel(at destination: Int, in entries: [NoteOutline.Entry]) -> Int {
        switch entries[destination].kind {
        case .heading(let level):
            return level
        case .embed:
            for candidate in entries[..<destination].reversed() {
                if case .heading(let level) = candidate.kind { return level }
            }
            return 1
        }
    }

    /// Rewrites every ATX heading line in `extracted` by `delta` levels, clamped to 1...6,
    /// leaving everything else - leading whitespace, the space after the hashes, the title
    /// itself - untouched. The moved heading and every nested one inside it shift by the
    /// same amount, which is what keeps their relative depth (SPEC PG-019).
    private static func rewriteLevels(of extracted: String, delta: Int) -> String {
        guard delta != 0 else { return extracted }
        var result = ""
        var index = extracted.startIndex
        while index < extracted.endIndex {
            let lineEnd = extracted[index...].firstIndex(of: "\n") ?? extracted.endIndex
            result += rewrittenLine(extracted[index..<lineEnd], delta: delta)
            guard lineEnd < extracted.endIndex else { break }
            result += "\n"
            index = extracted.index(after: lineEnd)
        }
        return result
    }

    private static func rewrittenLine(_ line: Substring, delta: Int) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let level = NoteOutline.headingLevel(of: trimmed) else { return String(line) }
        let newLevel = min(max(level + delta, 1), 6)
        guard newLevel != level,
              let hashStart = line.firstIndex(where: { $0 != " " && $0 != "\t" })
        else { return String(line) }
        let hashEnd = line.index(hashStart, offsetBy: level)
        return String(line[line.startIndex..<hashStart])
            + String(repeating: "#", count: newLevel)
            + String(line[hashEnd...])
    }
}
