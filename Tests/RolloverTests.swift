import Foundation
import Testing
@testable import Pergamenum

// The rollover of ADR-0013 §D1, which amends SPEC §7.3. The amendment is narrow and its
// narrowings are the thing worth testing: the window has a bound, what the day already shows
// is not shown twice, and - the one that matters - nothing is written.

/// One note holding the given task lines, indexed. The tasks come from the real parser, so a
/// line that would not parse in a vault does not silently pass here either.
private func index(_ body: String) -> IndexSnapshot {
    let path = "01 Progetti/Prove.md"
    let tasks = body.components(separatedBy: "\n").enumerated().compactMap { index, line in
        TaskParser.parse(line: line, sourcePath: path, lineIndex: index)
    }
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-20")
    frontmatter.tags = [Tag("type-note")!]
    let record = NoteRecord(
        relativePath: path, title: "Prove", frontmatter: frontmatter, linkTargets: [],
        tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
    var snapshot = IndexSnapshot()
    snapshot.update(record, at: path)
    return snapshot
}

private let thursday = CalendarDate(iso: "2026-08-20")!

@Test func aTaskLeftOnAnEarlierDayIsSurfacedWithTheDayItBelongsTo() {
    let snapshot = index("""
    - [ ] Sopralluogo >2026-08-17
    - [ ] Oggi >2026-08-20
    """)

    let rolled = snapshot.rolledOverTasks(on: thursday, daysBack: 7)

    #expect(rolled.map(\.text) == ["Sopralluogo"])
    // The marker says Monday because the file still says Monday. That is the whole amendment.
    #expect(rolled[0].scheduled == CalendarDate(iso: "2026-08-17"))
    #expect(RolloverMarker.text(for: rolled[0].scheduled!) == "lunedì 17/08")
}

@Test func theWindowHasABoundAndTheBoundIsRespected() {
    let snapshot = index("""
    - [ ] Ieri >2026-08-19
    - [ ] Sei giorni fa >2026-08-14
    - [ ] Un mese fa >2026-07-20
    """)

    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 7).map(\.text)
        == ["Ieri", "Sei giorni fa"])
    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 1).map(\.text) == ["Ieri"])
    // A window of zero is the setting off, and it surfaces nothing rather than everything.
    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 0).isEmpty)
}

@Test func theMostRecentComesFirst() {
    let snapshot = index("""
    - [ ] Tre giorni fa >2026-08-17
    - [ ] Ieri >2026-08-19
    - [ ] Due giorni fa >2026-08-18
    """)

    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 7).map(\.text)
        == ["Ieri", "Due giorni fa", "Tre giorni fa"])
}

@Test func whatTheDayAlreadyShowsIsNotShownTwice() {
    // Scheduled on Monday and due on Tuesday: `tasks(for: .today)` already draws it, because a
    // passed `!` date is what it calls overdue. Drawing it again under «Rimandati» would make
    // one late task read as two.
    let snapshot = index("- [ ] In ritardo davvero >2026-08-17 !2026-08-18")

    #expect(snapshot.tasks(for: .today, on: thursday).map(\.text) == ["In ritardo davvero"])
    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 7).isEmpty)
}

@Test func aFinishedTaskDoesNotRollOverAndNeitherDoesOneWithNoDate() {
    let snapshot = index("""
    - [x] Fatto lunedì >2026-08-17
    - [-] Annullato >2026-08-17
    - [ ] Senza data
    - [ ] Solo scadenza !2026-09-01
    """)

    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 7).isEmpty)
}

@Test func aTaskRescheduledButUnfinishedStillRollsOver() {
    // `- [>]` is open by SPEC §7.1 - it wants doing - so it belongs in the list.
    let snapshot = index("- [>] Rimandato a mano >2026-08-18")

    #expect(snapshot.rolledOverTasks(on: thursday, daysBack: 7).map(\.text) == ["Rimandato a mano"])
}

@Test func theRolloverSettingIsOffByDefaultAndCarriesItsBound() {
    #expect(VaultSettings.default.rollover == false)
    #expect(VaultSettings.default.rolloverDays == 7)
}

@Test func aHandEditedRolloverWindowIsClampedRatherThanTrusted() throws {
    // `settings.json` is meant to be edited by hand, and a 0 in there would make the setting
    // look on and show nothing at all.
    let json = #"{"dailyFolder":"Calendar","rollover":true,"rolloverDays":0}"#
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))

    #expect(settings.rollover)
    #expect(settings.rolloverDays == 1)

    let wide = #"{"dailyFolder":"Calendar","rolloverDays":9999}"#
    #expect(try JSONDecoder().decode(VaultSettings.self, from: Data(wide.utf8)).rolloverDays == 60)
}

@Test func settingsWrittenBeforeRolloverExistedKeepEverythingElse() throws {
    // The key-by-key decoder is what makes this safe: a vault configured by an earlier build
    // must not lose its daily folder to a key that did not exist then.
    let json = #"{"dailyFolder":"Giorni","blockMinutes":45}"#
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))

    #expect(settings.dailyFolder == "Giorni")
    #expect(settings.blockMinutes == 45)
    #expect(settings.rollover == false)
    #expect(settings.rolloverDays == 7)
}

@Test func theBadgeCountsWhatTheListDraws() {
    // Nothing scheduled for today and two tasks left behind: without the window the badge would
    // read blank next to a pane showing two rows.
    let snapshot = index("""
    - [ ] Ieri >2026-08-19
    - [ ] Lunedì >2026-08-17
    """)

    #expect(snapshot.taskCounts(on: thursday)[.today] == 0)
    #expect(snapshot.taskCounts(on: thursday, rolloverDays: 7)[.today] == 2)
    // The other four views are untouched by the setting.
    #expect(snapshot.taskCounts(on: thursday, rolloverDays: 7)[.all]
        == snapshot.taskCounts(on: thursday)[.all])
}
