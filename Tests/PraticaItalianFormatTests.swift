import Foundation
import Testing
@testable import Pergamenum

// PG-263 (burn-down 2026-10-03): the Pratiche pane's dates followed the machine's region while
// the rest of the interface is Italian; the three row formatters and the tray strip's range
// formatter are pinned to `it_IT`.
//
// An Italian machine would pass these without the pin, so they cannot prove the pin by
// themselves: `uiLocale` is asserted directly, and the words are asserted so that a machine
// set to another region fails them the day the pin is dropped.

@Suite struct PraticaItalianFormatTests {
    /// 10 June 2026 (a Wednesday), 14:06, in the machine's own zone: the formatters read the
    /// person's time zone, so the date is built in it.
    private static func instant(day: Int = 10, month: Int = 6, hour: Int = 14, minute: Int = 6) throws -> Date {
        try #require(Calendar.current.date(
            from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        ))
    }

    @Test func theUILocaleIsItalian() {
        #expect(PraticaRowFormat.uiLocale.identifier == "it_IT")
    }

    @Test func theRowTimeIsTwentyFourHour() throws {
        #expect(PraticaRowFormat.time(try Self.instant()) == "14:06")
        #expect(PraticaRowFormat.time(try Self.instant(hour: 9, minute: 5)) == "09:05")
    }

    @Test func theDaySeparatorIsInItalian() throws {
        #expect(PraticaRowFormat.day(try Self.instant()) == "mercoledì 10 giugno 2026")
    }

    @Test func theSpokenDateIsInItalian() throws {
        // CLDR's own connective («alle ore») is not this code's to pin, so the day and the
        // time are asserted and the words between them are not.
        let spoken = PraticaRowFormat.spokenDate(try Self.instant())
        #expect(spoken.hasPrefix("10 giugno"), "\(spoken)")
        #expect(spoken.hasSuffix("14:06"), "\(spoken)")
    }

    @Test func theAnchoredEntryDayAndTimeIsInItalian() throws {
        // The row's own call, with no locale and no zone: the cached short-day formatter, which
        // the test host's own locale spelled «3 Oct» without the pin.
        let date = try Self.instant(day: 3, month: 10, hour: 20, minute: 22)
        #expect(PraticaRowFormat.dayAndTime(date) == "3 ott 20:22")
    }

    @Test func theTrayRangeIsInItalianAndCollapsesASingleDay() throws {
        let morning = try Self.instant(hour: 8, minute: 0)
        let evening = try Self.instant(hour: 18, minute: 30)
        let later = try Self.instant(day: 12)

        #expect(PraticaTrayStrip.range(morning...evening) == "10 giu", "one day reads as one date")
        #expect(PraticaTrayStrip.range(morning...later) == "10 giu – 12 giu")
    }
}
