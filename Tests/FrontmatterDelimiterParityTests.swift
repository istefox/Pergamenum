import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D1.2 (how a frontmatter line is interpreted), §D3 (line endings: a written
// line takes the document's line break) and §D13.3 (the two readers that kept the
// whitespace-only delimiter test), plan docs/plans/pg-276-crlf-delimiter-parsers.md,
// Task 1 - R-01, R-02, R-03, R-04, R-06.
//
// `MessageFrontmatterPatch` and `ViewCatalogue.locations(in:)` must find a frontmatter block
// exactly where `NoteDocument.parse` does. CRLF fixtures are single-line literals with `\r\n`
// spelled out, or an LF literal passed through `crlf(_:)`: Swift normalises the line endings
// of a multi-line string literal to LF (`FormatEdgeCorpus.swift:7-9`).

private func crlf(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: "\r\n")
}

private let lfMessage = """
---
date: 2026-06-10
tags:
  - type-note
  - type-email
pergamenum-mail: 1
pergamenum-mail-message-id: "<abc@rossi-spa.it>"
pergamenum-mail-body: complete
---

Buongiorno,
"""

private let noteKey = "pergamenum-mail-note"

private func lines(_ text: String) -> [String] {
    text.components(separatedBy: "\n")
}

/// Every line but the last ends in `\r`.
private func isAllCRLF(_ text: String) -> Bool {
    lines(text).dropLast().allSatisfy { $0.hasSuffix("\r") }
}

private func patch(_ line: String?, in text: String) -> String? {
    MessageFrontmatterPatch.applying(
        line: line, forKey: noteKey, before: ["pergamenum-mail-body"], to: text
    )
}

// MARK: - R-01: MessageFrontmatterPatch on a CRLF message

@Suite struct MessageFrontmatterPatchCRLFTests {
    // R-01
    @Test func insertsIntoACRLFMessageAndKeepsEveryOtherByte() throws {
        let input = crlf(lfMessage)
        let line = MessageDocument.noteLine(for: "[[X]]")
        let result = try #require(patch(line, in: input))

        let expected = input.replacingOccurrences(
            of: "pergamenum-mail-body: complete\r\n",
            with: "\(line)\r\npergamenum-mail-body: complete\r\n"
        )
        #expect(result == expected)
        #expect(isAllCRLF(result))
        #expect(MessageDocument.parse(result)?.frontmatter.linkedNote == "[[X]]")
    }

    // R-01
    @Test func replacesAndRemovesAKeyInACRLFMessage() throws {
        let old = MessageDocument.noteLine(for: "[[Old]]")
        let new = MessageDocument.noteLine(for: "[[New]]")
        let withOld = crlf(lfMessage).replacingOccurrences(
            of: "pergamenum-mail-body: complete\r\n",
            with: "\(old)\r\npergamenum-mail-body: complete\r\n"
        )

        let replaced = try #require(patch(new, in: withOld))
        #expect(replaced == withOld.replacingOccurrences(of: "\(old)\r\n", with: "\(new)\r\n"))
        #expect(isAllCRLF(replaced))
        #expect(MessageDocument.parse(replaced)?.frontmatter.linkedNote == "[[New]]")

        let removed = try #require(patch(nil, in: withOld))
        #expect(removed == withOld.replacingOccurrences(of: "\(old)\r\n", with: ""))
        #expect(MessageDocument.parse(removed)?.frontmatter.linkedNote == nil)
    }

    // R-01, §D1.3.1: a value that is already there is left verbatim.
    @Test func anUnchangedValueLeavesTheLineVerbatim() throws {
        let line = MessageDocument.noteLine(for: "[[Same]]")

        // (a) all-CRLF
        let allCRLF = crlf(lfMessage).replacingOccurrences(
            of: "pergamenum-mail-body: complete\r\n",
            with: "\(line)\r\npergamenum-mail-body: complete\r\n"
        )
        #expect(patch(line, in: allCRLF) == allCRLF)

        // (b) mixed: LF delimiters and first line break, one CRLF note line
        let mixed = lfMessage.replacingOccurrences(
            of: "pergamenum-mail-body: complete\n",
            with: "\(line)\r\npergamenum-mail-body: complete\n"
        )
        #expect(patch(line, in: mixed) == mixed)
    }

    // R-01: the sync's door
    @Test func theSyncsAttachmentDoorReachesACRLFMessage() throws {
        let entry = MessageDocument.attachmentEntry(linking: "a.pdf")
        let result = try #require(MessageAttachmentPatch.applying(entries: [entry], to: crlf(lfMessage)))

        let attachmentsLine = try #require(
            lines(result).first { $0.hasPrefix(MessageDocument.attachmentsKey) }
        )
        #expect(attachmentsLine.hasSuffix("\r"))
        #expect(isAllCRLF(result))
    }

    // R-04: regression pin, an LF file behaves as before
    @Test func anLFMessageIsPatchedExactlyAsBefore() throws {
        let line = MessageDocument.noteLine(for: "[[X]]")
        let inserted = try #require(patch(line, in: lfMessage))
        #expect(inserted == lfMessage.replacingOccurrences(
            of: "pergamenum-mail-body: complete\n",
            with: "\(line)\npergamenum-mail-body: complete\n"
        ))

        let new = MessageDocument.noteLine(for: "[[Y]]")
        let replaced = try #require(patch(new, in: inserted))
        #expect(replaced == inserted.replacingOccurrences(of: line, with: new))

        let removed = try #require(patch(nil, in: replaced))
        #expect(removed == lfMessage)

        #expect(!inserted.contains("\r"))
        #expect(!replaced.contains("\r"))
        #expect(!removed.contains("\r"))
    }
}

// MARK: - R-02, R-06: ViewCatalogue on a CRLF note

private let viewFence = "```pergamenum-view\nrender: list\n```\n"

@Suite struct ViewCatalogueCRLFTests {
    // R-02
    @Test func aCommentInACRLFFrontmatterIsNotAViewHeading() {
        let text = "---\r\ndate: 2026-01-01\r\n# commento\r\n---\r\n" + viewFence
        let found = ViewCatalogue.locations(in: text)
        #expect(found.count == 1)
        #expect(found.first?.heading == nil)
    }

    private static let viewNoteLF = """
    ---
    date: 2026-01-01
    # commento
    ---

    ## Vista valida

    ```pergamenum-view
    render: list
    ```

    ## Vista rotta

    ```pergamenum-view
    render: list
    ```
    """

    // R-06
    @Test func aCRLFNotesViewsAreLocatedWithTheirHeadings() {
        let text = crlf(Self.viewNoteLF)
        let found = ViewCatalogue.locations(in: text)
        #expect(found.count == 2)
        #expect(found.map(\.heading) == ["Vista valida", "Vista rotta"])
        let split = lines(text)
        for location in found where location.lineIndex < split.count {
            #expect(split[location.lineIndex] == "```pergamenum-view\r")
        }
        #expect(found.count == ViewBlock.blocks(in: NoteDocument.parse(text).body).count)
    }

    // R-04: regression pin
    @Test func anLFNoteIsLocatedExactlyAsBefore() {
        let text = Self.viewNoteLF
        let found = ViewCatalogue.locations(in: text)
        #expect(found.count == 2)
        #expect(found.map(\.heading) == ["Vista valida", "Vista rotta"])
        let split = lines(text)
        for location in found where location.lineIndex < split.count {
            #expect(split[location.lineIndex] == "```pergamenum-view")
        }
        #expect(found.map(\.lineIndex) == [7, 13])
        #expect(found.count == ViewBlock.blocks(in: NoteDocument.parse(text).body).count)
    }
}

// MARK: - R-03: every reader agrees with the note parser

struct DelimiterCase: CustomTestStringConvertible, Sendable {
    let opening: String
    let closing: String
    let expected: Bool
    var testDescription: String { "\(opening.debugDescription) ... \(closing.debugDescription)" }
}

private let delimiterCases: [DelimiterCase] = [
    DelimiterCase(opening: "---", closing: "---", expected: true),
    DelimiterCase(opening: "--- ", closing: "--- ", expected: true),
    DelimiterCase(opening: "\t---", closing: "\t---", expected: true),
    DelimiterCase(opening: "  ---  ", closing: "  ---  ", expected: true),
    DelimiterCase(opening: "\u{00A0}---", closing: "\u{00A0}---", expected: true),
    DelimiterCase(opening: "---\r", closing: "---\r", expected: true),
    DelimiterCase(opening: "--- \r", closing: "--- \r", expected: true),
    DelimiterCase(opening: "\t---\r", closing: "\t---\r", expected: true),
    // a BOM is a delimiter on line 0 only
    DelimiterCase(opening: "\u{FEFF}---", closing: "---", expected: true),
    DelimiterCase(opening: "\u{FEFF}---\r", closing: "---\r", expected: true),
    DelimiterCase(opening: "---", closing: "\u{FEFF}---", expected: false),
    DelimiterCase(opening: "---", closing: "\u{FEFF}---\r", expected: false),
    // two carriage returns, and near misses
    DelimiterCase(opening: "---\r\r", closing: "---", expected: false),
    DelimiterCase(opening: "---", closing: "---\r\r", expected: false),
    DelimiterCase(opening: "----", closing: "---", expected: false),
    DelimiterCase(opening: "--- x", closing: "---", expected: false),
    DelimiterCase(opening: "-- -", closing: "---", expected: false),
    DelimiterCase(opening: "---", closing: "----", expected: false),
    DelimiterCase(opening: "---", closing: "--- x", expected: false),
    DelimiterCase(opening: "---", closing: "-- -", expected: false),
    // an opening with no closing: the whole text is body
    DelimiterCase(opening: "---", closing: "solo testo", expected: false)
]

@Suite struct DelimiterParityTests {
    // R-03: one case per line of the plan's rule table.
    @Test(arguments: delimiterCases)
    func everyReaderAgreesWithTheNoteParser(_ c: DelimiterCase) {
        let message = c.opening + "\npergamenum-mail: 1\npergamenum-mail-body: complete\n"
            + c.closing + "\n\nCorpo.\n"
        // The rule itself, pinned on the note parser.
        #expect(NoteDocument.parse(message).hasFrontmatterBlock == c.expected)

        let patched = MessageFrontmatterPatch.applying(
            line: MessageDocument.noteLine(for: "[[X]]"), forKey: noteKey,
            before: ["pergamenum-mail-body"], to: message
        )
        #expect((patched != nil) == c.expected)

        // The body stays LF on purpose: this half does not depend on R-06.
        let view = c.opening + "\n# commento\n" + c.closing + "\n" + viewFence
        let found = ViewCatalogue.locations(in: view)
        #expect(found.count == ViewBlock.blocks(in: NoteDocument.parse(view).body).count)
        #expect((found.first?.heading == nil) == c.expected)
    }
}
