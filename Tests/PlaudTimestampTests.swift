import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 1 -
// R-03, R-07, R-13; ADR §D8.
//
// The zone-less-is-UTC assertion is the two-hour trap ADR §D8 itself was measured against:
// recording `18682e82795a2eddecf9ec94f2a48ab0`'s `name` ("2026-09-04 13:44:51", local,
// Europe/Rome, +2 DST) and its own `recorded_at` ("2026-09-04T11:44:51", zone-less) are the
// same instant. Reading the zone-less form as local instead of UTC is a two-hour error,
// a whole-day error for anything recorded before 02:00 local.
@Suite struct PlaudTimestampTests {
    private static func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    @Test func parsesTheFractionalSecondZFormMeasuredOnGeneratedAt() {
        // Measured live, 2026-09-05: a proposal's own `generated_at`.
        let raw = "2026-09-05T07:55:24.906Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = formatter.date(from: raw)!

        #expect(PlaudTimestamp.parse(raw) == expected)
    }

    @Test func parsesThePlainZFormTheContractDocuments() {
        // The shape `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md` still documents
        // for `recorded_at` (ADR §D8, M2), even though no measured row carries it today -
        // every measured `recorded_at` is the zone-less form below instead.
        let raw = "2026-09-04T11:44:51Z"
        let expected = ISO8601DateFormatter().date(from: raw)!

        #expect(PlaudTimestamp.parse(raw) == expected)
    }

    @Test func parsesTheZoneLessFormMeasuredOnRecordedAtAsUTC() {
        // Measured live, 2026-09-05: `18682e82795a2eddecf9ec94f2a48ab0`'s own `recorded_at`.
        let raw = "2026-09-04T11:44:51"
        let expected = Self.utcDate(year: 2026, month: 9, day: 4, hour: 11, minute: 44, second: 51)

        #expect(PlaudTimestamp.parse(raw) == expected)
    }

    @Test func theZoneLessFormAgreesWithTheSameRecordingsLocalNameReadAsRomeDST() {
        // The cross-check ADR §D8 itself rests on: `name` "2026-09-04 13:44:51" (local,
        // Europe/Rome, +2 DST) and `recorded_at` "2026-09-04T11:44:51" (zone-less) name the
        // same instant. Getting the zone-less form wrong as "local" would silently shift
        // every timestamp two hours.
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = TimeZone(identifier: "Europe/Rome")!
        let localNameAsRome = rome.date(from: DateComponents(
            year: 2026, month: 9, day: 4, hour: 13, minute: 44, second: 51
        ))!

        #expect(PlaudTimestamp.parse("2026-09-04T11:44:51") == localNameAsRome)
    }

    @Test func returnsNilForGarbage() {
        #expect(PlaudTimestamp.parse("not-a-timestamp-at-all") == nil)
    }
}
