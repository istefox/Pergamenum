import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - §D12.

/// The deliberately tiny YAML subset `Dossier` is written in (ADR §D12): a scalar
/// `Int`, a scalar `String`, a `- ` string-list block, and an inline `[1, 2]` int
/// list. Not a general YAML parser - exactly the four shapes the SPEC's worked
/// example uses for the seven `pergamenum-dossier-*` keys, nothing else.
enum DossierYAML {
    /// `"key: 1"` → `1`. `nil` when the line is not present or does not parse.
    static func scalarInt(key: String, lines: [String]) -> Int? {
        guard let index = index(of: key, in: lines) else { return nil }
        return Int(inlineValue(of: lines[index]))
    }

    static func renderScalarInt(key: String, value: Int) -> [String] {
        ["\(key): \(value)"]
    }

    /// `"key:"` followed by one `"  - value"` (or `"  - \"value\""`) line per item -
    /// the shape `counterparts`/`keywords`/`included`/`excluded` all use. Empty when
    /// the key is absent, matching `FrontmatterSerializer`'s own "no empty list key"
    /// rule.
    /// The inline `key: ["a", "b"]` form is accepted on the way in as well: the SPEC's
    /// own worked example writes `keywords`/`included`/`excluded` that way, so a
    /// `pratica.md` typed by hand from the SPEC must parse. Only the block form is ever
    /// written back, which is what `Tests/DossierTests.swift` pins.
    static func stringList(key: String, lines: [String]) -> [String] {
        guard let index = index(of: key, in: lines) else { return [] }
        let inline = inlineValue(of: lines[index])
        if let items = inlineItems(of: inline) {
            return items.map(unquoted).filter { !$0.isEmpty }
        }
        if !inline.isEmpty { return [unquoted(inline)] }

        var values: [String] = []
        var cursor = index + 1
        while cursor < lines.count, let item = listItem(lines[cursor]) {
            values.append(item)
            cursor += 1
        }
        return values.filter { !$0.isEmpty }
    }

    static func renderStringList(key: String, values: [String], quoted: Bool) -> [String] {
        guard !values.isEmpty else { return [] }
        var rendered = ["\(key):"]
        rendered.append(contentsOf: values.map { quoted ? "  - \"\($0)\"" : "  - \($0)" })
        return rendered
    }

    /// `"key: [1, 2]"` → `[1, 2]` - the shape `conversations`/`ignored` use.
    static func inlineIntList(key: String, lines: [String]) -> [Int] {
        guard let index = index(of: key, in: lines) else { return [] }
        let inline = inlineValue(of: lines[index])
        if let items = inlineItems(of: inline) {
            return items.compactMap { Int(unquoted($0)) }
        }
        if let single = Int(inline) { return [single] }

        // A person who wrote the conversations as a block list is not wrong, only
        // unusual: reading it costs three lines and losing it costs a re-sync.
        var values: [Int] = []
        var cursor = index + 1
        while cursor < lines.count, let item = listItem(lines[cursor]) {
            guard let value = Int(item) else { break }
            values.append(value)
            cursor += 1
        }
        return values
    }

    static func renderInlineIntList(key: String, values: [Int]) -> [String] {
        guard !values.isEmpty else { return [] }
        return ["\(key): [\(values.map(String.init).joined(separator: ", "))]"]
    }

    // MARK: - Line shapes

    /// The index of the line that opens `key`. A continuation line (indented, or a
    /// `- ` item) is never a key, or a list value carrying a colon would be read as
    /// one.
    private static func index(of key: String, in lines: [String]) -> Int? {
        lines.firstIndex { line in
            guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { return false }
            guard let colon = line.firstIndex(of: ":") else { return false }
            return String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces) == key
        }
    }

    private static func inlineValue(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// The comma-separated items of a `[a, b]` inline list, or `nil` when the value is
    /// not one. A comma inside a quoted item would split it - accepted, because the
    /// four values this codec carries (addresses, message ids, keywords, integers) are
    /// written by this app and none contains one.
    private static func inlineItems(of value: String) -> [String]? {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return nil }
        let inner = value.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return [] }
        return inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func listItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("-") else { return nil }
        return unquoted(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else { return value }
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
