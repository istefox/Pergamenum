import Foundation

/// Reads the linked-note key `pergamenum-category: <slug>` (SPEC "Note ↔ category",
/// ADR-0047 §D5): one scalar, one line, the same `scalar(_:_:)` shape
/// `MessageDocument+Reading.swift:13` already uses over `Frontmatter.foreignKeys` -
/// never a second YAML parser.
enum CategoryFrontmatter {
    static let key = "pergamenum-category"

    /// The slug a note's frontmatter names as its category, or nil when the note
    /// carries no `pergamenum-category` key.
    static func slug(in foreignKeys: [Frontmatter.ForeignKey]) -> String? {
        let lines = foreignKeys.flatMap(\.lines)
        guard let raw = scalar(lines) else { return nil }
        return unquoted(raw)
    }

    private static func scalar(_ lines: [String]) -> String? {
        for line in lines where !line.hasPrefix(" ") && !line.hasPrefix("\t") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            guard String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces) == key
            else { continue }
            return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
