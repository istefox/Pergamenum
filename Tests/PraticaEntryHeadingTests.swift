import Foundation
import Testing
@testable import Pergamenum

// ADR-0079 §D7 (PG-369), plan docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md, Task 7 -
// R-11, R-12. An anchored entry's heading no longer draws `arrow.turn.down.right` (the rail carries
// the link; VoiceOver still hears «collegata al messaggio»), and it shows the day beside the time
// when it was written on another day than its message.

@Suite struct PraticaEntryHeadingTests {
    private static func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return try #require(try calendar("UTC").date(from: components))
    }

    private static func message(at date: Date, messageID: String = "<m>") -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: "M", kind: .message, date: date, direction: .received, senderDisplayName: "Mario Rossi",
            subject: "Oggetto", bodyPreview: "", hasAttachments: false, messageID: messageID, isInMail: true
        )
    }

    private static func entry(
        _ id: String, at date: Date, kind: PraticaTimelineEntry.Kind = .note, ordinal: Int = 0, anchor: String? = nil
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: kind, date: date, direction: nil, senderDisplayName: "Mario Rossi",
            subject: kind == .call ? "Telefonata · Mario Rossi" : "Nota · Mario Rossi", bodyPreview: "voce",
            hasAttachments: false, messageID: nil, isInMail: true, anchor: anchor, fileOrdinal: ordinal
        )
    }

    /// One row of each placement, placed by the shared rule: `anchored`, `free`, `orphaned`, `excluded`.
    private static func placedRows(
        kind: PraticaTimelineEntry.Kind, messageDate: Date, entryDate: Date
    ) -> [String: PraticaTimelineEntry] {
        let rows = PraticaTimelineModel.ordered([
            message(at: messageDate),
            entry("anchored", at: entryDate, kind: kind, ordinal: 0, anchor: "<m>"),
            entry("free", at: entryDate, kind: kind, ordinal: 1),
            entry("orphaned", at: entryDate, kind: kind, ordinal: 2, anchor: "<gone>"),
            entry("excluded", at: entryDate, kind: kind, ordinal: 3, anchor: "<out>"),
        ], excluded: ["<out>"])
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    /// `headingShowsDay` of `row` in a UTC calendar; nil when the fixture has no such row.
    private static func showsDay(_ row: PraticaTimelineEntry?) -> Bool? {
        guard let row, let calendar = try? calendar("UTC") else { return nil }
        return PraticaTimelineModel.headingShowsDay(row, calendar: calendar)
    }

    // MARK: - R-11: the glyph

    @Test(arguments: [PraticaTimelineEntry.Kind.note, .call])
    func noEntryHeadingDrawsTheLinkGlyphWhateverItsPlacement(kind: PraticaTimelineEntry.Kind) throws {
        let date = try Self.utc(2026, 10, 3, 18, 22)
        let rows = Self.placedRows(kind: kind, messageDate: date, entryDate: date)
        #expect(rows["anchored"]?.placement == .anchored(messageID: "<m>"), "precondition")
        for id in ["anchored", "free", "orphaned", "excluded"] {
            let symbols = PraticaTimelineModel.entryHeadingSymbols(for: try #require(rows[id]))
            #expect(!symbols.contains("arrow.turn.down.right"), "\(id)")
            #expect(symbols == [kind == .call ? "phone" : "square.and.pencil"], "\(id): its kind's symbol alone")
        }
    }

    @Test func anAnchoredEntryStillSaysItIsLinkedToItsMessageToVoiceOver() throws {
        let date = try Self.utc(2026, 10, 3, 18, 22)
        let rows = Self.placedRows(kind: .note, messageDate: date, entryDate: date)

        let anchored = PraticaEntryRow.accessibilityText(for: try #require(rows["anchored"]), isExpanded: false)
        #expect(anchored.contains("collegata al messaggio"), Comment(rawValue: anchored))

        let orphaned = PraticaEntryRow.accessibilityText(for: try #require(rows["orphaned"]), isExpanded: false)
        #expect(orphaned.contains(PraticaTimelineModel.orphanCaptionText), Comment(rawValue: orphaned))
        #expect(!orphaned.contains("collegata al messaggio"))

        let free = PraticaEntryRow.accessibilityText(for: try #require(rows["free"]), isExpanded: false)
        #expect(!free.contains("collegata al messaggio"), Comment(rawValue: free))
        #expect(!free.contains(PraticaTimelineModel.orphanCaptionText), Comment(rawValue: free))
    }

    @Test func theAccessibilityTextKeepsItsLaneLabelSubjectAndExpansionState() throws {
        let date = try Self.utc(2026, 10, 3, 18, 22)
        let rows = Self.placedRows(kind: .note, messageDate: date, entryDate: date)
        let anchored = try #require(rows["anchored"])

        let collapsed = PraticaEntryRow.accessibilityText(for: anchored, isExpanded: false)
        let expanded = PraticaEntryRow.accessibilityText(for: anchored, isExpanded: true)
        #expect(collapsed.hasPrefix(PraticaTimelineModel.laneLabel(.entry)))
        #expect(collapsed.contains(anchored.subject) && collapsed.hasSuffix("compressa"))
        #expect(expanded.hasSuffix("espansa") && !expanded.contains("compressa"))
    }

    // MARK: - R-12: the day when it differs

    @Test func anAnchoredEntryOnItsMessagesDayShowsTheTimeAlone() throws {
        let rows = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 3, 8, 0), entryDate: try Self.utc(2026, 10, 3, 18, 22)
        )
        #expect(Self.showsDay(rows["anchored"]) == false)
    }

    @Test func anAnchoredEntryOnAnotherDayThanItsMessageShowsTheDay() throws {
        let rows = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 1, 8, 0), entryDate: try Self.utc(2026, 10, 3, 18, 22)
        )
        #expect(Self.showsDay(rows["anchored"]) == true)
    }

    @Test func aFreeAnOrphanedAndAnExcludedEntryNeverShowTheDayHoweverFarFromAnyMessage() throws {
        let rows = Self.placedRows(
            kind: .call, messageDate: try Self.utc(2026, 10, 1, 8, 0), entryDate: try Self.utc(2026, 10, 3, 18, 22)
        )
        for id in ["free", "orphaned", "excluded"] {
            #expect(Self.showsDay(rows[id]) == false, Comment(rawValue: id))
        }
    }

    @Test func midnightIsTheDayBoundary() throws {
        let utc = try Self.calendar("UTC")
        let justAfter = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 2, 23, 59), entryDate: try Self.utc(2026, 10, 3, 0, 0)
        )
        #expect(PraticaTimelineModel.headingShowsDay(try #require(justAfter["anchored"]), calendar: utc) == true,
                "00:00 the next day against a message at 23:59")
        let justBefore = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 3, 0, 0), entryDate: try Self.utc(2026, 10, 3, 23, 59)
        )
        #expect(PraticaTimelineModel.headingShowsDay(try #require(justBefore["anchored"]), calendar: utc) == false,
                "00:00 and 23:59 are one day")
    }

    @Test func theReadersCalendarDecidesWhatIsTheSameDay() throws {
        // 22:30Z and 21:00Z are one UTC day; in Rome (UTC+2 in October) they are 00:30 on the 4th
        // and 23:00 on the 3rd.
        let rows = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 3, 21, 0), entryDate: try Self.utc(2026, 10, 3, 22, 30)
        )
        let anchored = try #require(rows["anchored"])
        #expect(PraticaTimelineModel.headingShowsDay(anchored, calendar: try Self.calendar("Europe/Rome")) == true)
        #expect(PraticaTimelineModel.headingShowsDay(anchored, calendar: try Self.calendar("UTC")) == false)
    }

    @Test func anAnchoredEntryIsComparedWithItsMessagesInstantNotWithTheMessageRowsOwnDay() throws {
        // The entry sorts under the message, but the message is dated the 1st: `placedAt` is the
        // message's instant, whatever the entry's own date.
        let rows = Self.placedRows(
            kind: .note, messageDate: try Self.utc(2026, 10, 1, 8, 0), entryDate: try Self.utc(2026, 10, 1, 9, 0)
        )
        let anchored = try #require(rows["anchored"])
        #expect(anchored.placedAt == (try Self.utc(2026, 10, 1, 8, 0)))
        #expect(PraticaTimelineModel.headingShowsDay(anchored, calendar: try Self.calendar("UTC")) == false)
    }

    // MARK: - dayAndTime

    private static let italian = Locale(identifier: "it_IT")

    @Test func dayAndTimeReadsDayMonthThenTimeInItalian() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        // 18:22Z on 3 October is 20:22 in Rome (CEST).
        let text = PraticaRowFormat.dayAndTime(try Self.utc(2026, 10, 3, 18, 22), locale: Self.italian, timeZone: rome)
        #expect(text == "3 ott 20:22")
    }

    @Test func dayAndTimeTakesTheZonesDayNotUTCs() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        // 23:30Z on 2 October is 01:30 on the 3rd in Rome.
        let text = PraticaRowFormat.dayAndTime(try Self.utc(2026, 10, 2, 23, 30), locale: Self.italian, timeZone: rome)
        #expect(text == "3 ott 01:30")
    }

    @Test func dayAndTimeNamesNoYearAndNoComma() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let text = PraticaRowFormat.dayAndTime(try Self.utc(2025, 12, 31, 9, 5), locale: Self.italian, timeZone: utc)
        #expect(text == "31 dic 09:05")
        #expect(!text.contains("2025") && !text.contains(","))
    }

    /// The default branch is the only one production calls (a row's body, through the cached
    /// formatters); the explicit-pair tests above never reach it. No locale is pinned: the
    /// branches must agree on whatever the machine's own is.
    @Test func theCachedDefaultBranchAgreesWithAFreshFormatterOnTheCurrentLocaleAndZone() throws {
        let date = try Self.utc(2026, 10, 3, 18, 22)
        let cached = PraticaRowFormat.dayAndTime(date)
        #expect(cached == PraticaRowFormat.dayAndTime(date, locale: .current, timeZone: .current))
        #expect(cached.hasSuffix(PraticaRowFormat.time(date)))
        #expect(!cached.contains(","))
        #expect(!cached.contains("2026"))
    }
}
