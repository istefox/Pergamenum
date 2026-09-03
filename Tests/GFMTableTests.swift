import Foundation
import Testing
@testable import Pergamenum

/// ADR-0029 §D2 (plan `2026-09-02-editor-wysiwyg-unification`, Task 3): `GFMTable` is the
/// one GFM pipe-table grammar the reading view (`MarkdownBlockParser.table(header:consuming:)`,
/// unchanged) and the editor's live grid (Task 4) both parse - extracted here so the two
/// cannot silently drift the way two independent implementations of the same grammar would.
///
/// `runs(in:from:outside:)`, `parse(_:)` and `serialised()` are stubbed to return nothing at
/// all (Task 3, tester), so every positive assertion below is red until the coder fills the
/// grammar in.

@Suite struct GFMTableParsing {
    @Test func aTwoColumnFourLineTableParsesWithItsSourceRangeExcludingTheBlankLineAfter() {
        let text = "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\naltro"
        let tables = GFMTable.runs(in: text, from: text.startIndex, outside: [])

        #expect(tables.count == 1)
        guard let table = tables.first else { return }
        #expect(table.header == ["a", "b"])
        #expect(table.alignments == [.leading, .leading])
        #expect(table.rows == [["1", "2"], ["3", "4"]])
        #expect(table.lineRanges.count == 4)

        let lastLine = text.range(of: "| 3 | 4 |")
        #expect(lastLine != nil)
        if let lastLine {
            // The four table lines, and nothing past them - the blank line and "altro"
            // that follow are outside `range` (R-05).
            #expect(table.range == text.startIndex..<lastLine.upperBound)
        }
    }

    @Test func aPipeContainingParagraphWithNoDelimiterRowParsesAsNothing() {
        // R-10: the same first line without a delimiter row is prose that happens to
        // contain a pipe.
        #expect(GFMTable.parse(["| a | b |", "testo"][...]) == nil)
    }

    @Test func aDelimiterRowWhoseColumnCountDisagreesWithTheHeaderParsesAsNothing() {
        // R-10: GFM requires the delimiter to have exactly as many cells as the header.
        #expect(GFMTable.parse(["| a | b |", "|---|"][...]) == nil)
    }

    @Test func theThreeDelimiterFormsGiveLeadingCenterAndTrailingAlignment() {
        // Matching what `MarkdownBlockParser.alignments(in:)` already returns for the same
        // three forms.
        let table = GFMTable.parse(["| a | b | c |", "|:--|:-:|--:|", "| 1 | 2 | 3 |"][...])
        #expect(table?.alignments == [.leading, .center, .trailing])
    }

    @Test func aShortRowIsPaddedAndALongRowIsTruncated() {
        // GFM's rule, unchanged from `MarkdownBlockParser.fit(_:to:)`.
        let table = GFMTable.parse(["| a | b |", "|---|---|", "| 1 |", "| 1 | 2 | 3 |"][...])
        #expect(table?.rows == [["1", ""], ["1", "2"]])
    }

    @Test func anEscapedPipeSurvivesTheRoundTripAndABackslashWithNothingToEscapeKeepsItself() {
        // `cells(in:)`'s existing escape rule - easy to lose in an extraction, so asserted
        // here directly rather than only trusted to carry over.
        let escaped = GFMTable.parse(["| comando | esito |", "|---|---|", "| a \\| b | ok |"][...])
        #expect(escaped?.rows == [["a | b", "ok"]])

        let backslash = GFMTable.parse(["| percorso |", "|---|", "| C:\\dati |"][...])
        #expect(backslash?.rows == [["C:\\dati"]])
    }

    @Test func aTableWrittenInsideAFenceYieldsNothing() {
        // R-09: table recognition only applies outside fenced code, the same rule the
        // existing code-fence handling already enforces for headings and tags.
        let text = "```md\n| a | b |\n|---|---|\n| 1 | 2 |\n```"
        let fences = CodeFence.regions(in: text)
        #expect(!fences.isEmpty)
        let tables = GFMTable.runs(in: text, from: text.startIndex, outside: fences)
        #expect(tables.isEmpty)
    }

    @Test func serialisedRoundTripsForEveryFixture() {
        let fixtures: [ArraySlice<String>] = [
            ["| a | b |", "|---|---|", "| 1 | 2 |"][...],
            ["| a | b | c |", "|:--|:-:|--:|", "| 1 | 2 | 3 |"][...],
            ["| comando | esito |", "|---|---|", "| a \\| b | ok |"][...],
        ]
        for lines in fixtures {
            guard let table = GFMTable.parse(lines) else {
                Issue.record("fixture non parsata: \(Array(lines))")
                continue
            }
            let roundTripped = GFMTable.parse(table.serialised().components(separatedBy: "\n")[...])
            #expect(roundTripped == table, "round-trip fallito per \(Array(lines))")
        }
    }
}
