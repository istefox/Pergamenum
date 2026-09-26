import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-28, R-29; ADR §D5.

@Suite struct PraticaEntryTests {
    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    // MARK: - R-28: the heading

    @Test func insertAppendsAHeadingWithTheKindsLabelAndCounterpartAtTheEnd() {
        let source = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n\nGià presente.\n"
        let timestamp = Self.date("2026-06-10T14:06:00Z")

        let insertion = PraticaEntry.insert(
            kind: .call, at: timestamp, counterpart: "Mario Rossi", in: source
        )

        #expect(insertion.text.hasSuffix("## 2026-06-10 14:06 Telefonata · Mario Rossi\n\n"))
        #expect(insertion.text.hasPrefix(source))
    }

    @Test func insertUsesTheNotaLabelForTheNoteKind() {
        let insertion = PraticaEntry.insert(
            kind: .note, at: Self.date("2026-06-11T09:00:00Z"), counterpart: "Studio Bianchi",
            in: ""
        )
        #expect(insertion.text.contains("## 2026-06-11 09:00 Nota · Studio Bianchi"))
    }

    /// R-28: the cursor lands in the body, not on the heading line itself - the empty
    /// line the coder's `Navigation.jumpToLine` places the caret on.
    @Test func theCursorRangeSitsAfterTheHeadingLine() {
        let source = "corpo esistente\n"
        let insertion = PraticaEntry.insert(
            kind: .note, at: Self.date("2026-06-10T14:06:00Z"), counterpart: "Mario Rossi", in: source
        )
        let headingLine = "## 2026-06-10 14:06 Nota · Mario Rossi"
        guard let headingRange = insertion.text.range(of: headingLine) else {
            Issue.record("the inserted text must contain the heading line")
            return
        }
        let headingEndOffset = insertion.text.utf16.distance(
            from: insertion.text.startIndex, to: headingRange.upperBound
        )
        #expect(insertion.cursorRange.location >= headingEndOffset)
        #expect(insertion.cursorRange.length == 0)
    }

    // MARK: - R-28: "Inserisci qui" uses the midpoint timestamp

    @Test func midpointIsExactlyHalfwayBetweenTwoNeighbours() {
        let first = Self.date("2026-06-10T10:00:00Z")
        let second = Self.date("2026-06-10T12:00:00Z")
        #expect(PraticaEntry.midpoint(between: first, and: second) == Self.date("2026-06-10T11:00:00Z"))
    }

    @Test func midpointIsSymmetric() {
        let first = Self.date("2026-06-10T10:00:00Z")
        let second = Self.date("2026-06-10T12:30:00Z")
        #expect(
            PraticaEntry.midpoint(between: first, and: second)
                == PraticaEntry.midpoint(between: second, and: first)
        )
    }

    // MARK: - The heading format round-trips with `PraticheController.parseEntryHeading`

    @Test func theHeadingFormatterMatchesPraticheControllersOwnPattern() {
        // `PraticheController.entryHeadingFormatter` (`Sources/Features/Pratiche/
        // PraticheController.swift`) already reads a heading back with this exact
        // pattern and locale - the two formatters must agree, or a heading this
        // inserts would fail to parse back into a timeline row.
        #expect(PraticaEntry.headingFormatter.dateFormat == "yyyy-MM-dd HH:mm")
        #expect(PraticaEntry.headingFormatter.locale?.identifier == "en_US_POSIX")
    }
}

@Suite struct DailyNoteMirrorTests {
    // MARK: - R-29: the line format

    @Test func lineFormatMatchesTheSpecExactly() {
        let entry = DailyNoteMirror.Entry(
            praticaTitle: "Offerta 2026", kind: .call, counterpart: "Mario Rossi"
        )
        #expect(DailyNoteMirror.line(for: entry) == "- [[Offerta 2026]] — Telefonata · Mario Rossi")
    }

    @Test func lineFormatUsesNotaForTheNoteKind() {
        let entry = DailyNoteMirror.Entry(
            praticaTitle: "Offerta 2026", kind: .note, counterpart: "Studio Bianchi"
        )
        #expect(DailyNoteMirror.line(for: entry) == "- [[Offerta 2026]] — Nota · Studio Bianchi")
    }

    // MARK: - R-29: exactly one line appended, gated by the setting

    @Test func appendingAddsExactlyOneLineWhenEnabled() {
        let entry = DailyNoteMirror.Entry(
            praticaTitle: "Offerta 2026", kind: .call, counterpart: "Mario Rossi"
        )
        let existing = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n\n"
        let result = DailyNoteMirror.appending(entry, to: existing, isEnabled: true)
        #expect(result == existing + "- [[Offerta 2026]] — Telefonata · Mario Rossi\n")
    }

    @Test func appendingWritesNothingWhenTheSettingIsOff() {
        let entry = DailyNoteMirror.Entry(
            praticaTitle: "Offerta 2026", kind: .call, counterpart: "Mario Rossi"
        )
        let existing = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n\n"
        #expect(DailyNoteMirror.appending(entry, to: existing, isEnabled: false) == nil)
    }
}
