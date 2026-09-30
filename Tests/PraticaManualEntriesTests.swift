import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D1 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 2 -
// R-01, R-19, R-23: the one parser of `pratica.md`'s manual entries and the anchor codec.

@Suite struct PraticaManualEntriesTests {
    private static let frontmatter = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n"

    private static let anchorLine = "<!-- pergamenum-message: <a@rossi.it> -->"

    /// A call anchored to a message, an ordinary `## ` heading, and two notes in one minute, the
    /// first with a counterpart that itself contains ` · `.
    private static let body = "\nIntroduzione.\n\n"
        + "## 2026-06-10 14:06 Telefonata · Mario Rossi\n"
        + anchorLine + "\n"
        + "Ha confermato.\n\n"
        + "## Appunti\n"
        + "testo libero\n\n"
        + "## 2026-06-11 09:00 Nota · Studio · Bianchi\n"
        + "Primo.\n"
        + "## 2026-06-11 09:00 Nota · Studio Bianchi\n"
        + "Secondo.\n"

    private static let source = frontmatter + body

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private static func text(_ source: String, at range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    // MARK: - Grammar

    @Test func parsesACallAndTwoNotesWithTheirHeadings() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(entries.map(\.kind) == [.call, .note, .note])
        #expect(entries.map(\.date) == [
            Self.date("2026-06-10T14:06:00Z"), Self.date("2026-06-11T09:00:00Z"), Self.date("2026-06-11T09:00:00Z"),
        ])
        #expect(entries.map(\.subject) == [
            "Telefonata · Mario Rossi", "Nota · Studio · Bianchi", "Nota · Studio Bianchi",
        ])
        #expect(entries.map(\.counterpart) == ["Mario Rossi", "Studio · Bianchi", "Studio Bianchi"])
        #expect(entries.map(\.body) == ["Ha confermato.", "Primo.", "Secondo."])
    }

    @Test func aHeadingThatIsNotAnEntryEndsTheOpenOneAndOpensNothing() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(entries.count == 3)
        #expect(!entries.contains { $0.body.contains("testo libero") || $0.body.contains("Appunti") })
        #expect(Self.text(Self.source, at: entries[0].blockRange).hasSuffix("Ha confermato.\n\n"))
    }

    @Test func frontmatterBeforeTheBodyShiftsEveryRange() {
        let bare = PraticaManualEntries.parse(Self.body)
        let full = PraticaManualEntries.parse(Self.source)
        let shift = Self.frontmatter.utf16.count

        #expect(bare.count == full.count)
        for (plain, shifted) in zip(bare, full) {
            #expect(shifted.blockRange
                == NSRange(location: plain.blockRange.location + shift, length: plain.blockRange.length))
            #expect(shifted.anchorLineRange.map(\.location) == plain.anchorLineRange.map { $0.location + shift })
            #expect(shifted.body == plain.body)
            #expect(shifted.anchor == plain.anchor)
        }
    }

    @Test func aFileWithoutFrontmatterStartsItsFirstBlockAtZero() {
        let source = "## 2026-06-10 14:06 Nota · Mario Rossi\ncorpo\n"
        let entries = PraticaManualEntries.parse(source)

        #expect(entries.count == 1)
        #expect(entries.first?.blockRange == NSRange(location: 0, length: source.utf16.count))
        #expect(entries.first?.body == "corpo")
    }

    @Test func ordinalFollowsFileOrderAndOccurrenceCountsARepeatedMinute() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(entries.map(\.ordinal) == [0, 1, 2])
        #expect(entries.map(\.occurrence) == [0, 0, 1])
    }

    // MARK: - Ranges

    @Test func blockRangeRunsFromTheHeadingToTheNextHeadingOrTheEndOfTheFile() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(Self.text(Self.source, at: entries[0].blockRange)
            == "## 2026-06-10 14:06 Telefonata · Mario Rossi\n\(Self.anchorLine)\nHa confermato.\n\n")
        #expect(Self.text(Self.source, at: entries[1].blockRange)
            == "## 2026-06-11 09:00 Nota · Studio · Bianchi\nPrimo.\n")
        #expect(Self.text(Self.source, at: entries[2].blockRange)
            == "## 2026-06-11 09:00 Nota · Studio Bianchi\nSecondo.\n")
        #expect(NSMaxRange(entries[2].blockRange) == Self.source.utf16.count)
    }

    @Test func theTextAtAnchorLineRangeIsTheAnchorLine() throws {
        let entries = PraticaManualEntries.parse(Self.source)

        let range = try #require(entries[0].anchorLineRange)
        #expect(Self.text(Self.source, at: range) == Self.anchorLine)
        #expect(entries[1].anchorLineRange == nil)
        #expect(entries[2].anchorLineRange == nil)
    }

    // MARK: - R-01: the anchor

    @Test func anAnchorDirectlyUnderTheHeadingAnchorsTheEntry() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(entries.map(\.anchor) == ["<a@rossi.it>", nil, nil])
    }

    @Test func anAnchorLineWithSurroundingWhitespaceStillAnchors() throws {
        let line = "  \(Self.anchorLine)\t "
        let source = "## 2026-06-10 14:06 Nota · Mario Rossi\n\(line)\ncorpo\n"
        let entry = try #require(PraticaManualEntries.parse(source).first)

        #expect(entry.anchor == "<a@rossi.it>")
        #expect(Self.text(source, at: try #require(entry.anchorLineRange)) == line)
        #expect(entry.body == "corpo")
    }

    @Test func anAnchorLineAfterABlankLineIsBodyText() throws {
        let source = "## 2026-06-10 14:06 Nota · Mario Rossi\n\n\(Self.anchorLine)\ncorpo\n"
        let entry = try #require(PraticaManualEntries.parse(source).first)

        #expect(entry.anchor == nil)
        #expect(entry.anchorLineRange == nil)
        #expect(entry.body == "\(Self.anchorLine)\ncorpo")
    }

    @Test func anAnchorLineLowerInTheEntryIsBodyText() throws {
        let source = "## 2026-06-10 14:06 Nota · Mario Rossi\ncorpo\n\(Self.anchorLine)\n"
        let entry = try #require(PraticaManualEntries.parse(source).first)

        #expect(entry.anchor == nil)
        #expect(entry.body == "corpo\n\(Self.anchorLine)")
    }

    @Test func theAnchorLineIsNeverPartOfTheBody() {
        let entries = PraticaManualEntries.parse(Self.source)

        #expect(!entries.contains { $0.body.contains("pergamenum-message") })
    }

    // MARK: - R-19: CRLF

    @Test func aCRLFFileParsesToTheSameValuesWithRangesInTheCRLFSource() throws {
        let crlf = LineBreak.crlf.normalised(Self.source)
        let lf = PraticaManualEntries.parse(Self.source)
        let entries = PraticaManualEntries.parse(crlf)

        #expect(entries.map(\.kind) == lf.map(\.kind))
        #expect(entries.map(\.date) == lf.map(\.date))
        #expect(entries.map(\.subject) == lf.map(\.subject))
        #expect(entries.map(\.counterpart) == lf.map(\.counterpart))
        #expect(entries.map(\.anchor) == lf.map(\.anchor))
        #expect(entries.map(\.body) == lf.map(\.body))
        #expect(entries.map(\.ordinal) == lf.map(\.ordinal))
        #expect(entries.map(\.occurrence) == lf.map(\.occurrence))

        for entry in entries {
            #expect(!entry.subject.contains("\r"))
            #expect(!entry.counterpart.contains("\r"))
            #expect(!entry.body.contains("\r"))
            #expect(entry.anchor?.contains("\r") != true)
        }
        #expect(Self.text(crlf, at: try #require(entries[0].anchorLineRange)) == Self.anchorLine)
        for (index, entry) in entries.enumerated() {
            #expect(Self.text(crlf, at: entry.blockRange)
                == LineBreak.crlf.normalised(Self.text(Self.source, at: lf[index].blockRange)))
        }
    }

    // MARK: - The codec

    @Test func anAnchorLineRoundTripsThroughItsMessageID() throws {
        let line = try #require(PraticaEntryAnchor.line(for: "<a@rossi.it>"))

        #expect(line == Self.anchorLine)
        #expect(PraticaEntryAnchor.messageID(inLine: line) == "<a@rossi.it>")
    }

    @Test func anIDThatCannotSurviveTheRoundTripHasNoLine() {
        #expect(PraticaEntryAnchor.line(for: "") == nil)
        #expect(PraticaEntryAnchor.line(for: "<a-->b@rossi.it>") == nil)
        #expect(PraticaEntryAnchor.line(for: "<a\rb@rossi.it>") == nil)
        #expect(PraticaEntryAnchor.line(for: "<a\nb@rossi.it>") == nil)
    }

    @Test func messageIDRefusesAMissingSpaceAndAnEmptyID() {
        #expect(PraticaEntryAnchor.messageID(inLine: "<!-- pergamenum-message:<a@rossi.it> -->") == nil)
        #expect(PraticaEntryAnchor.messageID(inLine: "<!-- pergamenum-message: <a@rossi.it>-->") == nil)
        #expect(PraticaEntryAnchor.messageID(inLine: "<!-- pergamenum-message:  -->") == nil)
        #expect(PraticaEntryAnchor.messageID(inLine: "<!-- pergamenum-message: -->") == nil)
        #expect(PraticaEntryAnchor.messageID(inLine: "<!-- altro: <a@rossi.it> -->") == nil)
    }
}
