import Foundation

/// Turns a set of UTF-16 character offsets - each a folded heading's own start, the identity
/// `NoteTab.foldedEntries` now carries - into the ordinal `Set<Int>` `NoteFolding.layout`/
/// `hiddenParagraphs` expect, by resolving every offset against a FRESH
/// `NoteOutline.entries(in:)` call.
///
/// This is the boundary a stale ordinal index cannot cross: an offset names *where in the
/// text* a heading is, so it keeps meaning the same heading across an edit that shifts every
/// later entry's position in the array (`FoldStateOrdinalIndexStalenessTests`). An offset with
/// no current match - its heading deleted, or genuinely stale - is dropped rather than
/// resolved to whatever now sits at some leftover position.
///
/// A free function beside `NoteFolding` rather than a member of it: this is the note editor's
/// own translation from its storage convention to `NoteFolding`'s input, not a fact about
/// folding itself - `NoteFolding` and its existing ordinal-index callers (Workspace `.text`
/// cards, ADR-0028 §D8) are untouched.
func foldedOrdinals(ofOffsets offsets: Set<Int>, in text: String) -> Set<Int> {
    guard !offsets.isEmpty else { return [] }
    let entries = NoteOutline.entries(in: text)
    var ordinals: Set<Int> = []
    for offset in offsets {
        guard let index = entries.firstIndex(where: {
            text.utf16.distance(from: text.startIndex, to: $0.range.lowerBound) == offset
        }) else { continue }
        ordinals.insert(index)
    }
    return ordinals
}

/// Which lines disappear when a section is folded, and what the folded heading has to say
/// about it.
///
/// A section runs from its heading to the next heading of the **same or a higher** level,
/// which is the only rule that behaves the way a person expects and is not the obvious
/// one: folding a `##` has to take its `###` with it, and stop at the next `##` or `#`.
///
/// Works on `NoteOutline`, so it inherits its two hard-won rules for free - a `#` inside a
/// code fence is not a heading, and the frontmatter is not part of the note's structure.
///
/// In `Core` and without AppKit: what is hidden is a fact about the text, and how it is
/// hidden is the text view's problem.
enum NoteFolding {
    /// Everything the editor needs to draw a folded note, in one pass.
    struct Layout: Equatable, Sendable {
        /// The UTF-16 offset at which each hidden line begins, which is how the text view
        /// recognises the paragraphs to leave out of the layout.
        var hiddenLineOffsets: Set<Int> = []
        /// Each folded heading's own line offset, and how many lines it is hiding - the
        /// number the badge shows, and the only thing on screen that a person could not
        /// have worked out for themselves.
        var foldedHeadings: [Int: Int] = [:]
    }

    /// One folded section, resolved to line numbers.
    private struct Section {
        let headingLine: Int
        let firstHidden: Int
        let lastHidden: Int
    }

    static func layout(in text: String, foldedEntries: Set<Int>) -> Layout {
        let starts = lineStarts(in: text)
        let sections = sections(in: text, foldedEntries: foldedEntries, starts: starts)
        guard !sections.isEmpty else { return Layout() }

        var result = Layout()
        for section in sections {
            for line in section.firstHidden...section.lastHidden where starts.indices.contains(line) {
                result.hiddenLineOffsets.insert(offset(ofLine: line, in: text, starts: starts))
            }
            result.foldedHeadings[offset(ofLine: section.headingLine, in: text, starts: starts)] =
                section.lastHidden - section.firstHidden + 1
        }
        return result
    }

    /// The hidden lines as paragraph numbers. The readable form of the same answer, and
    /// what the tests are written against.
    ///
    /// The heading's own line is never hidden. A folded section that took its title with it
    /// would leave nothing to unfold.
    static func hiddenParagraphs(in text: String, foldedEntries: Set<Int>) -> Set<Int> {
        let starts = lineStarts(in: text)
        var hidden: Set<Int> = []
        for section in sections(in: text, foldedEntries: foldedEntries, starts: starts) {
            hidden.formUnion(section.firstHidden...section.lastHidden)
        }
        return hidden
    }

    /// The text of one section, its heading line included.
    ///
    /// The same rule the folds use, exposed rather than copied: a transclusion of
    /// `![[nota#sezione]]` shows exactly what folding that section would hide, plus the
    /// heading itself (ADR-0010 §D5). A second implementation of "up to the next heading of
    /// the same or a higher level" would drift, and this is the kind of rule nobody notices
    /// has drifted until a `###` goes missing.
    ///
    /// The trailing newline is not part of it: the caller is showing the section, not
    /// splicing it back into a file.
    static func sectionRange(in text: String, headingAt entry: Int) -> Range<String.Index>? {
        let entries = NoteOutline.entries(in: text)
        guard entries.indices.contains(entry),
              case .heading(let level) = entries[entry].kind
        else { return nil }

        let starts = lineStarts(in: text)
        let headingLine = line(of: entries[entry].range.lowerBound, in: starts)
        let lastLine = sectionEnd(after: entry, level: level, entries: entries, starts: starts)
        guard starts.indices.contains(headingLine) else { return nil }

        let lower = starts[headingLine]
        let upper = endOfLine(max(headingLine, lastLine), in: text, starts: starts)
        return lower <= upper ? lower..<upper : nil
    }

    // MARK: -

    /// Where a line's text ends, before its newline. The last line ends at the note's end.
    private static func endOfLine(_ line: Int, in text: String, starts: [String.Index]) -> String.Index {
        guard starts.indices.contains(line + 1) else { return text.endIndex }
        return text.index(before: starts[line + 1])
    }

    private static func sections(
        in text: String,
        foldedEntries: Set<Int>,
        starts: [String.Index]
    ) -> [Section] {
        guard !foldedEntries.isEmpty else { return [] }
        let entries = NoteOutline.entries(in: text)
        guard !entries.isEmpty else { return [] }

        var sections: [Section] = []
        for index in foldedEntries.sorted() {
            guard entries.indices.contains(index),
                  case .heading(let level) = entries[index].kind
            else { continue }

            let headingLine = line(of: entries[index].range.lowerBound, in: starts)
            let last = sectionEnd(after: index, level: level, entries: entries, starts: starts)
            guard headingLine + 1 <= last else { continue }
            sections.append(Section(headingLine: headingLine, firstHidden: headingLine + 1, lastHidden: last))
        }
        return sections
    }

    /// The last line of the section opened by `entries[index]`.
    ///
    /// The line before the next heading of the same or a higher level; the last line of the
    /// note when there is none. An embed is not a heading and never ends a section: a note
    /// embedded inside a section belongs to it.
    private static func sectionEnd(
        after index: Int,
        level: Int,
        entries: [NoteOutline.Entry],
        starts: [String.Index]
    ) -> Int {
        for next in entries.indices where next > index {
            guard case .heading(let nextLevel) = entries[next].kind, nextLevel <= level else { continue }
            return line(of: entries[next].range.lowerBound, in: starts) - 1
        }
        return starts.count - 1
    }

    private static func line(of index: String.Index, in starts: [String.Index]) -> Int {
        // The last line that begins at or before `index`. Linear, and deliberately so: a
        // note has hundreds of lines, not millions, and a binary search over
        // `String.Index` reads worse than it performs.
        var result = 0
        for (number, start) in starts.enumerated() where start <= index { result = number }
        return result
    }

    private static func offset(ofLine line: Int, in text: String, starts: [String.Index]) -> Int {
        text.utf16.distance(from: text.startIndex, to: starts[line])
    }

    /// The start of every line, empty ones included - the paragraph numbering the text
    /// view uses, which counts a blank line like any other.
    private static func lineStarts(in text: String) -> [String.Index] {
        var starts: [String.Index] = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" { starts.append(text.index(after: index)) }
            index = text.index(after: index)
        }
        return starts
    }
}
