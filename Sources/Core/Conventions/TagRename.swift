import Foundation

/// Renaming a tag inside one note's frontmatter (ADR-0012 D7).
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
}
