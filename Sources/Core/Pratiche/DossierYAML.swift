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
        // Coder-owned.
        nil
    }

    static func renderScalarInt(key: String, value: Int) -> [String] {
        ["\(key): \(value)"]
    }

    /// `"key:"` followed by one `"  - value"` (or `"  - \"value\""`) line per item -
    /// the shape `counterparts`/`keywords`/`included`/`excluded` all use. Empty when
    /// the key is absent, matching `FrontmatterSerializer`'s own "no empty list key"
    /// rule.
    static func stringList(key: String, lines: [String]) -> [String] {
        // Coder-owned.
        []
    }

    static func renderStringList(key: String, values: [String], quoted: Bool) -> [String] {
        guard !values.isEmpty else { return [] }
        var rendered = ["\(key):"]
        rendered.append(contentsOf: values.map { quoted ? "  - \"\($0)\"" : "  - \($0)" })
        return rendered
    }

    /// `"key: [1, 2]"` → `[1, 2]` - the shape `conversations`/`ignored` use.
    static func inlineIntList(key: String, lines: [String]) -> [Int] {
        // Coder-owned.
        []
    }

    static func renderInlineIntList(key: String, values: [Int]) -> [String] {
        guard !values.isEmpty else { return [] }
        return ["\(key): [\(values.map(String.init).joined(separator: ", "))]"]
    }
}
