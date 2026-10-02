import Foundation
import Testing
@testable import Pergamenum

// PG-367: a manual entry's heading is written in the writer's zone with that zone's offset
// (`## 2026-06-10 16:06 +02:00 Telefonata · Mario Rossi`) and read back to the same instant; a
// heading with no offset keeps meaning UTC (`PraticaManualEntriesTests` pins that legacy read).

@Suite struct PraticaEntryHeadingZoneTests {
    private static let rome = TimeZone(identifier: "Europe/Rome")!
    private static let newYork = TimeZone(identifier: "America/New_York")!

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private static func heading(_ line: String) throws -> PraticaManualEntries.Heading {
        try #require(PraticaManualEntries.heading(line))
    }

    private static func stamp(_ iso: String, in zone: TimeZone) -> String {
        PraticaEntry.headingTimestamp(date(iso), in: zone)
    }

    // MARK: - The writer

    @Test func aSummerHeadingInRomeSaysPlusTwo() {
        #expect(Self.stamp("2026-06-10T14:06:00Z", in: Self.rome) == "2026-06-10 16:06 +02:00")
    }

    @Test func aWinterHeadingInRomeSaysPlusOne() {
        #expect(Self.stamp("2026-01-15T09:00:00Z", in: Self.rome) == "2026-01-15 10:00 +01:00")
    }

    @Test func theOffsetIsTheOneInForceAtTheInstantAcrossTheSpringChange() {
        // Rome moves from +01:00 to +02:00 at 2026-03-29 01:00 UTC.
        #expect(Self.stamp("2026-03-29T00:30:00Z", in: Self.rome) == "2026-03-29 01:30 +01:00")
        #expect(Self.stamp("2026-03-29T01:30:00Z", in: Self.rome) == "2026-03-29 03:30 +02:00")
    }

    @Test func theRepeatedHourOfTheAutumnChangeKeepsItsTwoInstantsApart() throws {
        // Rome moves from +02:00 to +01:00 at 2026-10-25 01:00 UTC, so 02:30 happens twice. The
        // offset is what tells the two apart: without it both would read back as one instant.
        let first = Self.stamp("2026-10-25T00:30:00Z", in: Self.rome)
        let second = Self.stamp("2026-10-25T01:30:00Z", in: Self.rome)
        #expect(first == "2026-10-25 02:30 +02:00")
        #expect(second == "2026-10-25 02:30 +01:00")
        #expect(first != second)

        let earlier = try Self.heading("## \(first) Telefonata · Mario Rossi")
        let later = try Self.heading("## \(second) Telefonata · Mario Rossi")
        #expect(earlier.date == Self.date("2026-10-25T00:30:00Z"))
        #expect(later.date == Self.date("2026-10-25T01:30:00Z"))
        #expect(earlier.date != later.date)
    }

    @Test func aZoneWestOfGreenwichWritesANegativeOffset() {
        #expect(Self.stamp("2026-06-10T14:06:00Z", in: Self.newYork) == "2026-06-10 10:06 -04:00")
    }

    @Test func insertWritesTheOffsetFormBetweenTheTimeAndTheKind() {
        let insertion = PraticaEntry.insert(
            kind: .call, at: Self.date("2026-06-10T14:06:00Z"), counterpart: "Mario Rossi",
            timeZone: Self.rome, in: "corpo\n"
        )
        #expect(insertion.text == "corpo\n\n## 2026-06-10 16:06 +02:00 Telefonata · Mario Rossi\n\n")
    }

    // MARK: - The round trip

    @Test(arguments: ["2026-06-10T14:06:00Z", "2026-01-15T09:00:00Z", "2026-03-29T01:30:00Z"])
    func anEntryWrittenInRomeReadsBackAtTheInstantItWasWritten(iso: String) throws {
        let instant = Self.date(iso)
        let insertion = PraticaEntry.insert(
            kind: .call, at: instant, counterpart: "Mario Rossi", anchor: "<a@rossi.it>",
            timeZone: Self.rome, in: "---\ndate: 2026-06-10\n---\n\ncorpo\n"
        )
        let entry = try #require(PraticaManualEntries.parse(insertion.text).last)
        #expect(entry.date == instant)
        #expect(entry.kind == .call)
        #expect(entry.subject == "Telefonata · Mario Rossi")
        #expect(entry.counterpart == "Mario Rossi")
        #expect(entry.anchor == "<a@rossi.it>")
    }

    @Test func theSameInstantWrittenInTwoZonesReadsBackEqual() throws {
        let instant = Self.date("2026-06-10T14:06:00Z")
        let inRome = PraticaEntry.insert(kind: .note, at: instant, counterpart: "X", timeZone: Self.rome, in: "")
        let inNewYork = PraticaEntry.insert(kind: .note, at: instant, counterpart: "X", timeZone: Self.newYork, in: "")
        #expect(inRome.text != inNewYork.text, "the digits are each writer's own")
        #expect(PraticaManualEntries.parse(inRome.text).map(\.date) == [instant])
        #expect(PraticaManualEntries.parse(inNewYork.text).map(\.date) == [instant])
    }

    // MARK: - The reader

    @Test func theOffsetNeverReachesTheKindOrTheSubject() throws {
        let call = try Self.heading("## 2026-06-10 16:06 +02:00 Telefonata · Mario Rossi")
        #expect(call.kind == .call, "with the offset left in the tail the kind would read as a note")
        #expect(call.subject == "Telefonata · Mario Rossi")
        #expect(call.counterpart == "Mario Rossi")
        #expect(call.date == Self.date("2026-06-10T14:06:00Z"))

        let note = try Self.heading("## 2026-01-15 10:00 +01:00 Nota · Studio · Bianchi")
        #expect(note.kind == .note)
        #expect(note.subject == "Nota · Studio · Bianchi")
        #expect(note.counterpart == "Studio · Bianchi")
        #expect(note.date == Self.date("2026-01-15T09:00:00Z"))
    }

    @Test func aNegativeOffsetLandsOnTheRightInstant() throws {
        let entry = try Self.heading("## 2026-06-10 10:06 -04:00 Nota · Mario Rossi")
        #expect(entry.date == Self.date("2026-06-10T14:06:00Z"))
        #expect(entry.subject == "Nota · Mario Rossi")

        let pastMidnight = try Self.heading("## 2026-06-09 22:30 -04:00 Telefonata · Mario Rossi")
        #expect(pastMidnight.date == Self.date("2026-06-10T02:30:00Z"), "the day rolls over with the offset")
    }

    @Test func aHeadingWithoutAnOffsetStillReadsAsUTC() throws {
        let legacy = try Self.heading("## 2026-06-10 14:06 Telefonata · Mario Rossi")
        #expect(legacy.date == Self.date("2026-06-10T14:06:00Z"))
        #expect(legacy.kind == .call)
        #expect(legacy.subject == "Telefonata · Mario Rossi")
    }

    @Test func aTokenThatIsNotAnOffsetStaysInTheSubject() throws {
        let entry = try Self.heading("## 2026-06-10 14:06 +2:00 Nota · Mario Rossi")
        #expect(entry.subject == "+2:00 Nota · Mario Rossi")
        #expect(entry.date == Self.date("2026-06-10T14:06:00Z"))
    }

    @Test func anOffsetNoZoneCanHaveStaysInTheSubject() throws {
        let entry = try Self.heading("## 2026-06-10 14:06 +99:00 Nota · Mario Rossi")
        #expect(entry.subject == "+99:00 Nota · Mario Rossi")
        #expect(entry.date == Self.date("2026-06-10T14:06:00Z"), "read as UTC, as with no offset")
    }

    @Test func anOffsetWithNothingAfterItIsNotAnEntry() {
        #expect(PraticaManualEntries.heading("## 2026-06-10 16:06 +02:00") == nil)
        #expect(PraticaManualEntries.heading("## 2026-06-10 16:06 +02:00   ") == nil)
    }

    // MARK: - The shared codec

    @Test func theOffsetCodecReadsOnlyTheExactForm() {
        #expect(UTCOffset.seconds("+02:00") == 7200)
        #expect(UTCOffset.seconds("-04:30") == -16200)
        #expect(UTCOffset.seconds("+00:00") == 0)
        #expect(UTCOffset.seconds("+18:00") == 64800, "the widest offset `TimeZone(secondsFromGMT:)` accepts")
        #expect(UTCOffset.seconds("-18:00") == -64800)
        let malformedTokens = [
            "+2:00", "02:00", "+02:60", "+0a:00", "+02-00", "+02:000", "", "Z", "+99:00", "+18:01", "-19:00",
        ]
        for malformed in malformedTokens {
            #expect(UTCOffset.seconds(malformed) == nil, "\(malformed) read as an offset")
        }
    }

    @Test func theOffsetCodecWritesSignHoursAndMinutes() {
        #expect(UTCOffset.text(7200) == "+02:00")
        #expect(UTCOffset.text(-16200) == "-04:30")
        #expect(UTCOffset.text(0) == "+00:00")
        #expect(UTCOffset.text(20700) == "+05:45")
    }
}
