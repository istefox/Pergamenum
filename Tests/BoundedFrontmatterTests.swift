import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D8, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406).
//
// `NoteDocument.frontmatter(in:)` reads the block at the top of a note without splitting the body, for
// the inspector's category row, which parsed the whole note per body evaluation. Its contract is the
// existing parser's: for every text, the frontmatter it answers is `NoteDocument.parse(text).frontmatter`.
// A case that holds a block must have a parse that is not empty, or equality would hold for two empty
// answers. Red until Task 5: the red-phase function answers `.empty`.

struct FrontmatterCase: Sendable, CustomTestStringConvertible {
    var name: String
    var text: String
    /// Whether the block yields something: the parse is not `.empty`.
    var hasContent: Bool

    var testDescription: String { name }
}

private let frontmatterBody = String(repeating: "una riga di corpo con alcune parole\n", count: 30_000)

private let frontmatterCases: [FrontmatterCase] = [
    FrontmatterCase(name: "no block", text: "corpo\n# Titolo\n", hasContent: false),
    FrontmatterCase(name: "an empty note", text: "", hasContent: false),
    FrontmatterCase(
        name: "a closed block",
        text: "---\ndate: 2026-10-13\ntags:\n  - topic-uno\nrelated: []\n---\ncorpo\n", hasContent: true
    ),
    FrontmatterCase(name: "an empty block", text: "---\n---\ncorpo\n", hasContent: false),
    FrontmatterCase(
        name: "CRLF lines", text: "---\r\ndate: 2026-10-13\r\ntags: [topic-uno]\r\n---\r\ncorpo\r\n", hasContent: true
    ),
    FrontmatterCase(name: "a leading U+FEFF", text: "\u{FEFF}---\ndate: 2026-10-13\n---\ncorpo\n", hasContent: true),
    FrontmatterCase(
        name: "delimiters with trailing spaces", text: "---  \ndate: 2026-10-13\n---   \ncorpo\n", hasContent: true
    ),
    FrontmatterCase(name: "an unclosed block", text: "---\ndate: 2026-10-13\ncorpo\n", hasContent: false),
    FrontmatterCase(name: "--- not on line 0", text: "intro\n---\ndate: 2026-10-13\n---\ncorpo\n", hasContent: false),
    FrontmatterCase(
        name: "pergamenum-category among foreign keys",
        text: "---\ndate: 2026-10-13\nfoo: bar\npergamenum-category: cliente\nbaz:\n  - a\n  - b\n---\ncorpo\n",
        hasContent: true
    ),
    FrontmatterCase(name: "a closing delimiter on the last line", text: "---\ndate: 2026-10-13\n---", hasContent: true),
    FrontmatterCase(name: "a second block in the body", text: "---\ndate: 2026-10-13\n---\ncorpo\n---\ntags: [x]\n---\n", hasContent: true),
    FrontmatterCase(
        name: "a 1 MB body after a closed block",
        text: "---\ndate: 2026-10-13\ntags: [topic-uno]\npergamenum-category: cliente\n---\n" + frontmatterBody,
        hasContent: true
    ),
]

struct BoundedFrontmatterTests {
    @Test(arguments: frontmatterCases)
    func theBoundedReadEqualsTheFullParse(_ c: FrontmatterCase) {
        let expected = NoteDocument.parse(c.text).frontmatter
        if c.hasContent {
            #expect(expected != .empty, "the case holds nothing for the comparison to bite on: \(c.name)")
        }
        #expect(NoteDocument.frontmatter(in: c.text) == expected)
    }

    @Test func theBodyIsOneMegabyteWhereItIsMeant() {
        let c = frontmatterCases[frontmatterCases.count - 1]
        #expect(c.text.utf8.count > 1_000_000)
    }

    @Test func theForeignKeysSurviveWhichIsWhatTheCategoryRowReads() {
        let text = "---\ndate: 2026-10-13\npergamenum-category: cliente\n---\ncorpo\n"
        let keys = NoteDocument.frontmatter(in: text).foreignKeys
        #expect(keys.map(\.name) == ["pergamenum-category"])
        #expect(keys.first?.lines == ["pergamenum-category: cliente"])
    }
}
