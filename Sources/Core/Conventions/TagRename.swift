import Foundation

/// Editing the tag lines of one note's frontmatter (ADR-0012 D7, ADR-0009 D5).
///
/// **Surgical, not a re-serialisation.** Parsing the note and writing the document back through
/// `FrontmatterSerializer` would rename the tag *and* rewrite the whole block into canonical
/// form - block lists where the note had an inline one, dropped empty keys, reordered values.
/// That is a conformance edit nobody asked for, arriving in forty notes at once and drowning
/// the one change the person approved. So this touches the tag lines and nothing else, and a
/// note whose frontmatter it cannot make sense of is left alone rather than guessed at.
///
/// The match is a whole token: `topic-gomma` does not rename the `topic-gomma-metallo` beside
/// it, which is the failure this would be found by in the vault three weeks later.
enum TagRename {
    /// The note's text with `old` renamed to `new`, or nil when nothing changed - which is how
    /// a caller skips a note without writing an identical file.
    static func apply(_ old: Tag, to new: Tag, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closing = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              })
        else { return nil }

        var result = lines
        var changed = false
        for index in tagLineIndices(in: lines, upTo: closing) {
            let rewritten = replacing(old, with: new, in: lines[index])
            guard rewritten != lines[index] else { continue }
            result[index] = rewritten
            changed = true
        }
        return changed ? result.joined(separator: "\n") : nil
    }

    /// The lines of the frontmatter block that carry tag values: the `tags:` line itself, for
    /// the inline form, and the indented items under it, for the block form.
    ///
    /// A key at column zero ends the list. This is the same shape `FrontmatterParser` reads,
    /// written again here rather than shared with it because that one answers "what are the
    /// tags" and this one answers "where are they written", which is a different question about
    /// the same lines.
    private static func tagLineIndices(in lines: [String], upTo closing: Int) -> [Int] {
        var indices: [Int] = []
        var insideTags = false
        for index in 1...closing where index < lines.count {
            let line = lines[index]
            if line.hasPrefix("tags:") {
                insideTags = true
                indices.append(index)
                continue
            }
            if insideTags {
                // An indented line continues the list; anything else ends it, including the
                // closing delimiter.
                if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    indices.append(index)
                } else {
                    insideTags = false
                }
            }
        }
        return indices
    }

    /// Replaces whole-token occurrences, leaving `topic-gomma-metallo` alone when renaming
    /// `topic-gomma`. A tag can be preceded by `#` in the inline form, so that is not a
    /// boundary character to refuse.
    private static func replacing(_ old: Tag, with new: Tag, in line: String) -> String {
        let needle = old.description
        var result = ""
        var rest = Substring(line)

        while let range = rest.range(of: needle) {
            let before = rest[rest.startIndex..<range.lowerBound]
            let afterIndex = range.upperBound
            let precedingOK = before.last.map { !isTokenCharacter($0) } ?? true
            let followingOK = rest[afterIndex...].first.map { !isTokenCharacter($0) } ?? true

            result += before
            result += precedingOK && followingOK ? new.description : needle
            rest = rest[afterIndex...]
        }
        return result + rest
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
    }

    // MARK: - What a board's drop does (ADR-0009 D5)

    /// The text a card dropped from one column into another leaves behind: one tag out, one
    /// tag in.
    ///
    /// Three cases, and §D5 decides all three. Both tags present is a rename, the ordinary
    /// drop. `old` nil is a drag **out of** *Senza stato* and adds the destination's tag.
    /// `new` nil is a drag **into** it and removes the one the card came from - which is what
    /// makes that column the only way to take a tag off a note with a gesture rather than a
    /// decoration.
    ///
    /// Surgical here too: a note whose frontmatter this cannot make sense of comes back nil
    /// and is left alone. Re-serialising it would rewrite the whole block into canonical form,
    /// which is a conformance edit nobody asked for arriving on the back of a drag.
    static func move(from old: Tag?, to new: Tag?, in text: String) -> String? {
        switch (old, new) {
        case (let old?, let new?): apply(old, to: new, in: text)
        case (nil, let new?): adding(new, in: text)
        case (let old?, nil): removing(old, in: text)
        case (nil, nil): nil
        }
    }

    /// Adds a tag to the block list, in the order F-04 puts it in.
    ///
    /// An inline `tags: [a, b]` is refused rather than appended to: the linter already reports
    /// that form (`inlineTagList`), and turning it into a block list on the way past would be
    /// the same unasked-for rewrite this file exists to avoid.
    private static func adding(_ tag: Tag, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let closing = frontmatterEnd(of: lines) else { return nil }
        let indices = tagLineIndices(in: lines, upTo: closing)

        guard let header = indices.first else {
            // No `tags:` key at all: open one after `date:`, or at the top of the block.
            let dateLine = lines[1...closing].firstIndex { $0.hasPrefix("date:") }
            var result = lines
            result.insert(contentsOf: ["tags:", "  - \(tag)"], at: (dateLine ?? 0) + 1)
            return result.joined(separator: "\n")
        }
        // Anything written on the `tags:` line itself is the inline form.
        guard lines[header].dropFirst("tags:".count).trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }

        let items = Array(indices.dropFirst())
        guard !items.contains(where: { Tag(listItemValue(lines[$0])) == tag }) else { return text }

        let successor = items.first { index in
            guard let existing = Tag(listItemValue(lines[index])) else { return false }
            return tag < existing
        }
        var result = lines
        result.insert("  - \(tag)", at: successor ?? (items.last.map { $0 + 1 } ?? header + 1))
        return result.joined(separator: "\n")
    }

    /// Takes a tag off the block list, and the `tags:` key with it when it was the last one.
    ///
    /// A `tags:` with nothing under it is not a smaller version of a note with tags: it is a
    /// key the linter reports on its own account, and leaving one behind would make the drop
    /// introduce a second problem while solving none.
    private static func removing(_ tag: Tag, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let closing = frontmatterEnd(of: lines) else { return nil }
        let indices = tagLineIndices(in: lines, upTo: closing)
        guard let header = indices.first else { return nil }

        let items = Array(indices.dropFirst())
        guard let victim = items.first(where: { Tag(listItemValue(lines[$0])) == tag }) else { return nil }

        var result = lines
        result.remove(at: victim)
        if items.count == 1 { result.remove(at: header) }
        return result.joined(separator: "\n")
    }

    private static func frontmatterEnd(of lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        return lines.dropFirst().firstIndex { $0.trimmingCharacters(in: .whitespaces) == "---" }
    }

    /// `  - client-vibrofer` without its bullet, or an empty string for a line that is not one.
    private static func listItemValue(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") else { return "" }
        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
}
