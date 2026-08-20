import Foundation
import Testing
@testable import Pergamenum

// The red days of the Italian calendar, computed rather than fetched. Checked here
// because the whole argument for computing them is that they come out right for any
// year without anybody maintaining a table.

@Test func easterIsComputedForAnyYear() {
    // Years verifiable against any published table, including the two extremes of the
    // range Easter can fall in: 22 March at the earliest, 25 April at the latest.
    #expect(ItalianHolidays.easter(inYear: 2024) == CalendarDate(iso: "2024-03-31"))
    #expect(ItalianHolidays.easter(inYear: 2025) == CalendarDate(iso: "2025-04-20"))
    #expect(ItalianHolidays.easter(inYear: 2026) == CalendarDate(iso: "2026-04-05"))
    #expect(ItalianHolidays.easter(inYear: 2027) == CalendarDate(iso: "2027-03-28"))
    #expect(ItalianHolidays.easter(inYear: 2038) == CalendarDate(iso: "2038-04-25"))
    #expect(ItalianHolidays.easter(inYear: 2285) == CalendarDate(iso: "2285-03-22"))
}

@Test func theTwelveNationalHolidaysAreThere() {
    let holidays = ItalianHolidays.holidays(inYear: 2026)

    #expect(holidays.count == 12)
    #expect(holidays.map(\.day.description) == [
        "2026-01-01", "2026-01-06", "2026-04-05", "2026-04-06", "2026-04-25",
        "2026-05-01", "2026-06-02", "2026-08-15", "2026-11-01", "2026-12-08",
        "2026-12-25", "2026-12-26",
    ])
    // Pasquetta is the day after Easter, whatever Easter turned out to be.
    #expect(holidays[3].name == "Lunedì dell'Angelo")
    #expect(holidays[3].day == ItalianHolidays.easter(inYear: 2026).adding(days: 1))
    #expect(ItalianHolidays.name(of: CalendarDate(iso: "2026-08-15")!) == "Ferragosto")
}

@Test func pasquettaCrossesTheMonthWhenEasterIsLate() {
    // Easter 2038 falls on 25 April, which is already a holiday, and Pasquetta lands in
    // May. Both dates have to survive that.
    let holidays = ItalianHolidays.holidays(inYear: 2038)
    #expect(holidays.contains { $0.day == CalendarDate(iso: "2038-04-26")! && $0.name == "Lunedì dell'Angelo" })
    #expect(holidays.filter { $0.day == CalendarDate(iso: "2038-04-25")! }.count == 2)
}

@Test func aDayIsOrdinaryPrefestiveFestiveOrAHoliday() {
    // 2026-08-19 is a Wednesday, the 22nd a Saturday, the 23rd a Sunday.
    #expect(ItalianHolidays.kind(of: CalendarDate(iso: "2026-08-19")!) == .ordinary)
    #expect(ItalianHolidays.kind(of: CalendarDate(iso: "2026-08-22")!) == .prefestive)
    #expect(ItalianHolidays.kind(of: CalendarDate(iso: "2026-08-23")!) == .festive)
    #expect(ItalianHolidays.kind(of: CalendarDate(iso: "2026-04-25")!) == .holiday)
}

@Test func aHolidayOnASundayIsStillTheHoliday() {
    // 1 November 2026 falls on a Sunday. Calling it "domenica" would drop the only
    // thing the third colour was added to say.
    let ognissanti = CalendarDate(iso: "2026-11-01")!
    #expect(DateEntry.weekday(of: ognissanti) == 1)
    #expect(ItalianHolidays.kind(of: ognissanti) == .holiday)
    #expect(ItalianHolidays.name(of: ognissanti) == "Ognissanti")
}

@Test func ferragostoOnASaturdayIsAHolidayAndNotAPrefestive() {
    // 15 August 2026 is a Saturday: the holiday wins over the weekday, which is the
    // case the three tones exist for.
    #expect(ItalianHolidays.kind(of: CalendarDate(iso: "2026-08-15")!) == .holiday)
}

@Test func thePatronIsOnlyThereWhenItIsSet() {
    // 31 January 2026 is a Saturday, which makes it the case worth checking: without a
    // patron it is a prefestive, with one it is a holiday - the same precedence
    // Ferragosto has over the weekday it lands on.
    let day = CalendarDate(iso: "2026-01-31")!
    #expect(ItalianHolidays.kind(of: day) == .prefestive)

    let patron = PatronSaint(month: 1, day: 31, name: "San Geminiano")
    #expect(ItalianHolidays.kind(of: day, patron: patron) == .holiday)
    #expect(ItalianHolidays.name(of: day, patron: patron) == "San Geminiano")
    // And it comes back every year, because it is a month and a day and not a date.
    #expect(ItalianHolidays.name(of: CalendarDate(iso: "2031-01-31")!, patron: patron) == "San Geminiano")
    // Not on any other day of that year.
    #expect(ItalianHolidays.name(of: CalendarDate(iso: "2026-01-30")!, patron: patron) == nil)
}

@Test func aPatronOnADayThatDoesNotExistIsDropped() throws {
    // 30 February, hand-written into settings.json. Clamping it to the 28th would put a
    // red day on a date nobody chose; the setting is discarded instead.
    let json = #"{"dailyFolder":"Calendar","patronSaint":{"month":2,"day":30,"name":"San Nessuno"}}"#
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))

    #expect(settings.patronSaint == nil)
    #expect(settings.dailyFolder == "Calendar")
}

@Test func aValidPatronSurvivesTheSettingsFile() throws {
    let json = #"{"patronSaint":{"month":6,"day":24,"name":"San Giovanni"}}"#
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))

    #expect(settings.patronSaint == PatronSaint(month: 6, day: 24, name: "San Giovanni"))

    // And round-trips, so a vault carries its own patron.
    let encoded = try JSONEncoder().encode(settings)
    let again = try JSONDecoder().decode(VaultSettings.self, from: encoded)
    #expect(again.patronSaint == settings.patronSaint)
}
