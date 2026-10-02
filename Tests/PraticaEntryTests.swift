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

    /// PG-367: the heading is written in the writer's zone with its offset, so every heading
    /// test names its zone instead of depending on the Mac's. UTC here, so the digits are the
    /// instant's; `PraticaEntryHeadingZoneTests` covers the other zones.
    private static let utc = TimeZone(secondsFromGMT: 0)!

    // MARK: - R-28: the heading

    @Test func insertAppendsAHeadingWithTheKindsLabelAndCounterpartAtTheEnd() {
        let source = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n\nGià presente.\n"
        let timestamp = Self.date("2026-06-10T14:06:00Z")

        let insertion = PraticaEntry.insert(
            kind: .call, at: timestamp, counterpart: "Mario Rossi", timeZone: Self.utc, in: source
        )

        #expect(insertion.text.hasSuffix("## 2026-06-10 14:06 +00:00 Telefonata · Mario Rossi\n\n"))
        #expect(insertion.text.hasPrefix(source))
    }

    @Test func insertUsesTheNotaLabelForTheNoteKind() {
        let insertion = PraticaEntry.insert(
            kind: .note, at: Self.date("2026-06-11T09:00:00Z"), counterpart: "Studio Bianchi",
            timeZone: Self.utc, in: ""
        )
        #expect(insertion.text.contains("## 2026-06-11 09:00 +00:00 Nota · Studio Bianchi"))
    }

    /// R-28: the cursor lands in the body, not on the heading line itself - the empty
    /// line the coder's `Navigation.jumpToLine` places the caret on.
    @Test func theCursorRangeSitsAfterTheHeadingLine() {
        let source = "corpo esistente\n"
        let insertion = PraticaEntry.insert(
            kind: .note, at: Self.date("2026-06-10T14:06:00Z"), counterpart: "Mario Rossi",
            timeZone: Self.utc, in: source
        )
        let headingLine = "## 2026-06-10 14:06 +00:00 Nota · Mario Rossi"
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

    // MARK: - The heading format round-trips with `PraticaManualEntries.parse`

    @Test func theHeadingFormatterMatchesPraticheControllersOwnPattern() {
        // Since ADR-0076 §D1 this one formatter also reads the heading back
        // (`PraticaManualEntries.heading(_:)`); the pattern and locale are pinned so a
        // heading this inserts always parses back into a timeline row.
        #expect(PraticaEntry.headingFormatter.dateFormat == "yyyy-MM-dd HH:mm")
        #expect(PraticaEntry.headingFormatter.locale?.identifier == "en_US_POSIX")
        // GMT: the writer shifts the instant by the offset before formatting, and the reader
        // shifts the digits back (PG-367), so the formatter's own zone must not add a second one.
        #expect(PraticaEntry.headingFormatter.timeZone.secondsFromGMT() == 0)
    }

    // MARK: - ADR-0076 §D1, R-03: an entry anchored to a message

    @Test(arguments: [LineBreak.lf, .crlf])
    func anAnchoredInsertWritesTheHeadingTheAnchorLineAndAnEmptyBodyLine(_ lineBreak: LineBreak) {
        let source = lineBreak.normalised("---\ndate: 2026-06-10\n---\n\ncorpo esistente\n")
        let appended = "## 2026-06-10 14:06 +00:00 Nota · Mario Rossi" + lineBreak.characters
            + "<!-- pergamenum-message: <a@rossi.it> -->" + lineBreak.characters + lineBreak.characters

        let insertion = PraticaEntry.insert(
            kind: .note, at: Self.date("2026-06-10T14:06:00Z"), counterpart: "Mario Rossi",
            anchor: "<a@rossi.it>", timeZone: Self.utc, in: source
        )

        #expect(insertion.text == source + lineBreak.characters + appended)
        // The empty body line is the last line, after the anchor line's own line break.
        #expect(insertion.cursorRange == NSRange(
            location: insertion.text.utf16.count - lineBreak.characters.utf16.count, length: 0
        ))
        #expect(PraticaManualEntries.parse(insertion.text).last?.anchor == "<a@rossi.it>")
    }

    @Test func anInsertWithoutAnAnchorIsByteIdenticalToTodays() {
        let timestamp = Self.date("2026-06-10T14:06:00Z")
        let expected = PraticaEntry.Insertion(
            text: "corpo esistente\n\n## 2026-06-10 14:06 +00:00 Nota · Mario Rossi\n\n",
            cursorRange: NSRange(location: 63, length: 0)
        )

        #expect(PraticaEntry.insert(
            kind: .note, at: timestamp, counterpart: "Mario Rossi", timeZone: Self.utc, in: "corpo esistente\n"
        ) == expected)
        #expect(PraticaEntry.insert(
            kind: .note, at: timestamp, counterpart: "Mario Rossi", anchor: nil, timeZone: Self.utc,
            in: "corpo esistente\n"
        ) == expected)
        // An id the anchor line cannot spell writes a free entry rather than a broken line.
        #expect(PraticaEntry.insert(
            kind: .note, at: timestamp, counterpart: "Mario Rossi", anchor: "", timeZone: Self.utc,
            in: "corpo esistente\n"
        ) == expected)
    }

    // MARK: - ADR-0076 §D1, R-03: the message's counterpart

    private static let own: Set<String> = ["stefano@stefer.it"]

    private static func message(
        direction: MessageDocument.Direction, from: String, to: [String] = [], cc: [String] = []
    ) -> MessageDocument.MailFrontmatter {
        MessageDocument.MailFrontmatter(
            schemaVersion: 1, messageID: "<a@rossi.it>", conversationID: 1, direction: direction,
            date: date("2026-06-10T14:06:00Z"), received: nil,
            from: from, to: to, cc: cc, subject: "Offerta",
            attachments: [], body: .complete, original: nil
        )
    }

    @Test func aReceivedMessagesCounterpartIsItsSender() {
        let frontmatter = Self.message(
            direction: .received, from: "Mario Rossi <m.rossi@rossi.it>", to: ["Stefano <stefano@stefer.it>"]
        )
        #expect(PraticaEntry.counterpart(ofMessage: frontmatter, ownAddresses: Self.own) == "Mario Rossi")
    }

    @Test func aSentMessagesCounterpartIsTheFirstRecipientThatIsNotOwn() {
        let frontmatter = Self.message(
            direction: .sent, from: "Stefano <stefano@stefer.it>",
            to: ["Stefano <STEFANO@stefer.it>", "Anna Verdi <a.verdi@verdi.it>"], cc: ["c@bianchi.it"]
        )
        #expect(PraticaEntry.counterpart(ofMessage: frontmatter, ownAddresses: Self.own) == "Anna Verdi")
    }

    @Test func aSentMessageAddressedOnlyToMyselfFallsBackToTheFirstCc() {
        let frontmatter = Self.message(
            direction: .sent, from: "stefano@stefer.it", to: ["stefano@stefer.it"], cc: ["c@bianchi.it"]
        )
        #expect(PraticaEntry.counterpart(ofMessage: frontmatter, ownAddresses: Self.own) == "c@bianchi.it")
    }

    @Test func aMessageNamingNobodyHasNoCounterpart() {
        #expect(PraticaEntry.counterpart(
            ofMessage: Self.message(direction: .sent, from: "stefano@stefer.it"), ownAddresses: Self.own
        ) == nil)
        #expect(PraticaEntry.counterpart(
            ofMessage: Self.message(direction: .received, from: ""), ownAddresses: Self.own
        ) == nil)
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
