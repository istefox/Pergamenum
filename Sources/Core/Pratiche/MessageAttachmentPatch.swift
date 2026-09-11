import Foundation

// ADR-0040 (Pratiche attachment reliability bugs) §D4, plan
// docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md, Task 3 -
// R-04.

/// Patches only the `pergamenum-mail-attachments:` line of an already-rendered message
/// file, leaving every other byte untouched - a full `MessageDocument.render`
/// re-render would destroy any prose a person added below the quoted-history
/// `<details>` block (ADR §D6), which is the whole reason this exists instead of a
/// re-render-and-diff.
enum MessageAttachmentPatch {
    /// `nil` when `text` carries no `pergamenum-mail` frontmatter to patch: no opening
    /// `---` delimiter, no closing one, or a closed block that carries no top-level
    /// `pergamenum-mail` key.
    static func applying(entries: [String], to text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }

        let block = 1..<closing
        guard lines[block].contains(where: { isTopLevelKey($0, named: "pergamenum-mail") })
        else { return nil }

        let newLine = entries.isEmpty ? nil : MessageDocument.attachmentsLine(for: entries)

        if let existing = lines[block].firstIndex(where: {
            isTopLevelKey($0, named: MessageDocument.attachmentsKey)
        }) {
            if let newLine {
                lines[existing] = newLine
            } else {
                lines.remove(at: existing)
            }
        } else if let newLine {
            lines.insert(newLine, at: insertionIndex(lines: lines, block: block))
        }

        return lines.joined(separator: "\n")
    }

    /// Mirrors `MessageDocument.foreignKeys(of:)`'s own key order: before
    /// `pergamenum-mail-store-references` when it is present, else before
    /// `pergamenum-mail-body`. Neither present falls back to the end of the block,
    /// which does not arise for a real `pergamenum-mail` note (`body` is always
    /// written) but keeps this total rather than a forced unwrap.
    private static func insertionIndex(lines: [String], block: Range<Int>) -> Int {
        if let index = lines[block].firstIndex(where: {
            isTopLevelKey($0, named: MessageDocument.storeReferencesKey)
        }) { return index }
        if let index = lines[block].firstIndex(where: {
            isTopLevelKey($0, named: "pergamenum-mail-body")
        }) { return index }
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
