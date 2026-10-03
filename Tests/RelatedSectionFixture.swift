import Foundation

/// The note scaffolding the `## Note correlate` suites share - `RelatedSectionTests` and
/// `RelatedSectionLineRolesTests` (moved out of `RelatedSectionTests.swift` when PG-378's
/// tests got a file of their own, so the two cannot drift).
enum RelatedSectionFixture {
    /// A conforming note with `related` set to `related` and `body` after the frontmatter.
    static func note(related: [String] = [], _ body: String) -> String {
        let relatedBlock = related.isEmpty ? "" : "related:\n" + related.map { "  - \"\($0)\"\n" }.joined()
        return "---\ndate: 2026-09-26\ntags:\n  - type-note\n  - topic-vibration-isolation\n"
            + "\(relatedBlock)---\n\n\(body)"
    }

    /// Every line break in `text` is CRLF, and `text` ends in one.
    static func isAllCRLF(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        return lines.last == "" && lines.dropLast().allSatisfy { $0.hasSuffix("\r") }
    }
}
