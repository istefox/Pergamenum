import Foundation
import Testing
@testable import Pergamenum

// MARK: The window itself

@Test func keepsAWindowTheRightWayRound() {
    #expect(HourWindow.clamped(first: 20, last: 6) == HourWindow(first: 20, last: 21))
    #expect(HourWindow.clamped(first: -4, last: 12) == HourWindow(first: 0, last: 12))
    #expect(HourWindow.clamped(first: 30, last: 40) == HourWindow(first: 22, last: 24))
    #expect(HourWindow.clamped(first: 8, last: 18) == HourWindow(first: 8, last: 18))
}

@Test func countsTheHoursItDraws() {
    #expect(HourWindow.dayDefault.hours == 16)
    #expect(HourWindow.diaryDefault.hours == 18)
}

/// The setting says which hours are always drawn, not which hours may exist: a block
/// outside the window widens it rather than disappearing.
@Test func widensItselfToReachWhatIsDrawnOnIt() {
    let window = HourWindow(first: 8, last: 18)

    let earlier = window.covering(startMinutes: [5 * 60 + 30], endMinutes: [6 * 60 + 30])
    #expect(earlier.first == 5)
    #expect(earlier.last == 18)

    let later = window.covering(startMinutes: [20 * 60], endMinutes: [21 * 60 + 30])
    #expect(later.first == 8)
    // The hour above, so a block ending at 21:30 has the 22:00 line to stop against.
    #expect(later.last == 22)

    let inside = window.covering(startMinutes: [9 * 60], endMinutes: [10 * 60])
    #expect(inside == window)
    #expect(window.covering(startMinutes: [], endMinutes: []) == window)
}

@Test func neverWidensPastTheEndOfTheDay() {
    let widened = HourWindow(first: 6, last: 20).covering(
        startMinutes: [23 * 60], endMinutes: [24 * 60]
    )
    #expect(widened.last == 24)
}

// MARK: In the vault's settings

@Test func settingsCarryOneWindowPerSection() throws {
    let settings = VaultSettings.default
    #expect(settings.dayHours == .dayDefault)
    #expect(settings.diaryHours == .diaryDefault)

    let json = """
    {"dailyFolder":"Calendar","dayHours":{"first":8,"last":18},
     "diaryHours":{"first":5,"last":23}}
    """
    let decoded = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))
    #expect(decoded.dayHours == HourWindow(first: 8, last: 18))
    #expect(decoded.diaryHours == HourWindow(first: 5, last: 23))
}

/// A settings file written before these keys existed keeps working, and one edited by
/// hand into nonsense is repaired rather than obeyed.
@Test func repairsAWindowWrittenByHand() throws {
    let old = try JSONDecoder().decode(
        VaultSettings.self, from: Data("{\"dailyFolder\":\"Calendar\"}".utf8)
    )
    #expect(old.dayHours == .dayDefault)
    #expect(old.diaryHours == .diaryDefault)

    let backwards = try JSONDecoder().decode(
        VaultSettings.self,
        from: Data("{\"diaryHours\":{\"first\":22,\"last\":3}}".utf8)
    )
    #expect(backwards.diaryHours.first < backwards.diaryHours.last)
    #expect(backwards.diaryHours.hours >= 1)
}

@Test func aWindowSurvivesBeingWrittenAndReadBack() throws {
    var settings = VaultSettings.default
    settings.dayHours = HourWindow(first: 7, last: 19)
    settings.diaryHours = HourWindow(first: 6, last: 24)

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(VaultSettings.self, from: data)
    #expect(decoded == settings)
}
