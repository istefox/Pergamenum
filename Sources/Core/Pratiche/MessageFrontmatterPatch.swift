import Foundation

// ADR-0042 (Pratiche inline image placeholders) §D8: the line surgery
// `MessageAttachmentPatch` already performed for exactly one key, generalized so a
// second key (`pergamenum-mail-inline-pending`) cannot drift from the first's rules.

/// Patches a single top-level `pergamenum-mail-*` line of an already-rendered message
/// file, leaving every other byte untouched - the same reason `MessageAttachmentPatch`
/// exists instead of a re-render-and-diff (ADR-0040 §D6).
enum MessageFrontmatterPatch {
    /// `nil` when `text` carries no `pergamenum-mail` frontmatter to patch: no opening
    /// `---` delimiter, no closing one, or a closed block that carries no top-level
    /// `pergamenum-mail` key.
    ///
    /// - Parameters:
    ///   - line: the full replacement line (e.g. `"pergamenum-mail-inline-pending: […]"`),
    ///     or `nil` to remove the key entirely.
    ///   - key: the top-level key name to find, replace or insert.
    ///   - before: candidate key names to insert in front of, tried in order - the
    ///     first one present in the block wins. Falls back to the end of the block
    ///     when none is present.
    static func applying(line: String?, forKey key: String, before: [String], to text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }

        let block = 1..<closing
        guard lines[block].contains(where: { isTopLevelKey($0, named: "pergamenum-mail") })
        else { return nil }

        if let existing = lines[block].firstIndex(where: { isTopLevelKey($0, named: key) }) {
            if let line {
                lines[existing] = line
            } else {
                lines.remove(at: existing)
            }
        } else if let line {
            lines.insert(line, at: insertionIndex(lines: lines, block: block, before: before))
        }

        return lines.joined(separator: "\n")
    }

    /// The first of `before` that is present in the block, else the block's end.
    private static func insertionIndex(lines: [String], block: Range<Int>, before: [String]) -> Int {
        for candidate in before {
            if let index = lines[block].firstIndex(where: { isTopLevelKey($0, named: candidate) }) {
                return index
            }
        }
        return block.upperBound
    }

    /// A top-level line is one that is not a continuation - the same
    /// `!hasPrefix(" ") && !hasPrefix("\t")` rule `MessageDocument.scalar` already
    /// applies - whose text before the first `:` trims to exactly `key`.
    private static func isTopLevelKey(_ line: String, named key: String) -> Bool {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { return false }
        guard let colon = line.firstIndex(of: ":") else { return false }
        return String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces) == key
    }
}
