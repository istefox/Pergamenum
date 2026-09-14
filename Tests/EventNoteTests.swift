import Foundation
import Testing
@testable import Pergamenum

// The event note of ADR-0013 §D2 and §D3. Two things are worth holding: that the name it
// invents is a name the rules already in force accept, and that the note is born in the shape
// that keeps the linter off a stub nobody has tagged yet.

private let thursday = CalendarDate(iso: "2026-08-20")!

@Test func theNameIsTheDayAndASlugOfTheTitle() {
    #expect(EventNote.title(for: "Riunione tecnica", on: thursday) == "20260820-riunione-tecnica")
    // Accents folded and punctuation dropped, by the same function that names an imported
    // email - one rule for both, rather than two that drift.
    #expect(EventNote.title(for: "Sopralluogo: Vibrofer (2° turno)", on: thursday)
        == "20260820-sopralluogo-vibrofer-2-turno")
    // An event with nothing usable in its title still gets a conformant name.
    #expect(EventNote.title(for: "···", on: thursday) == "20260820")
}

@Test func theNameIsJudgedAnOrdinaryNoteAndPassesTheRules() {
    let title = EventNote.title(for: "Riunione tecnica", on: thursday)

    // The check §D2 says was made rather than assumed: `category` calls a note daily only when
    // its whole stem parses as a compact date, so this one is ordinary and goes through
    // `validate` - which it has to pass, or the gesture would create a note the linter refuses.
    #expect(NoteName.category(
        forFileName: NoteName.fileName(for: title), dailyFolder: "Calendar",
        path: "Calendar/\(title).md"
    ) == .note)
    #expect(NoteName.validate(title).isEmpty)
}

@Test func theBodyCarriesTheHourTheAttendeesAndTheWayBack() {
    let body = EventNote.body(
        eventTitle: "Riunione tecnica",
        start: TaskTime(hour: 15, minute: 30),
        end: TaskTime(hour: 16, minute: 30),
        attendees: ["Stefano Ferri", "Anna Rossi"],
        day: thursday
    )

    #expect(body.contains("15:30–16:30 · Riunione tecnica"))
    #expect(body.contains("Con: Stefano Ferri, Anna Rossi"))
    // An ordinary wikilink, so the backlink panel answers "which day was this meeting on"
    // without anything new being indexed.
    #expect(body.contains("Da [[20260820]]"))
}

@Test func anAllDayEventSaysSoRatherThanWritingMidnight() {
    let body = EventNote.body(
        eventTitle: "Ferragosto", start: nil, end: nil, attendees: [], day: thursday
    )

    #expect(body.contains("Tutto il giorno · Ferragosto"))
    #expect(!body.contains("00:00"))
    // No attendees means no line at all, not an empty one.
    #expect(!body.contains("Con:"))
}

@Test func theDailyNoteGainsASectionAndThenOnlyLines() {
    let note = """
    ---
    date: 2026-08-20
    tags:
      - type-note
    ---

    Qualcosa scritto a mano.
    """

    let once = EventNoteSection.adding("20260820-riunione-tecnica", to: note)
    #expect(once.contains("## Note"))
    #expect(once.contains("- [[20260820-riunione-tecnica]]"))
    #expect(once.contains("Qualcosa scritto a mano."))

    let twice = EventNoteSection.adding("20260820-sopralluogo", to: once)
    #expect(twice.components(separatedBy: "## Note").count == 2)
    #expect(twice.contains("- [[20260820-riunione-tecnica]]"))
    #expect(twice.contains("- [[20260820-sopralluogo]]"))
}

@Test func addingTheSameEventLinkTwiceChangesNothing() {
    // The second click is offered as «apri», but a vault edited by hand can always ask twice.
    let note = "corpo\n\n## Note\n\n- [[20260820-riunione-tecnica]]\n"

    #expect(EventNoteSection.adding("20260820-riunione-tecnica", to: note) == note)
}

@Test func theLinkLandsInsideItsSectionAndNotInTheNextOne() {
    let note = """
    corpo

    ## Note

    - [[20260820-riunione-tecnica]]

    ## Timeline

    - 09:00-10:00 Qualcosa
    """

    let updated = EventNoteSection.adding("20260820-sopralluogo", to: note)
    let noteSection = updated.range(of: "- [[20260820-sopralluogo]]")!
    let timeline = updated.range(of: "## Timeline")!

    #expect(noteSection.lowerBound < timeline.lowerBound)
    // And the timeline is still whole.
    #expect(updated.contains("- 09:00-10:00 Qualcosa"))
}

@MainActor
@Test func theNoteIsBornInTheCaptureShapeAndTheDayLinksToIt() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let created = await session.eventNote(
        for: "Riunione tecnica",
        on: thursday,
        start: TaskTime(hour: 15, minute: 30),
        end: TaskTime(hour: 16, minute: 30),
        attendees: ["Anna Rossi"]
    )

    let path = try #require(created?.path)
    #expect(path == "Calendar/20260820-riunione-tecnica.md")

    let text = try session.read(path).text
    // §D3: the capture shape. `status-inbox` is the one `status-*` a note may carry, and it is
    // what stops the linter asking a stub for a `topic-*` before anybody has said what it is.
    #expect(text.contains("- type-note"))
    #expect(text.contains("- status-inbox"))
    #expect(text.contains("15:30–16:30 · Riunione tecnica"))
    #expect(text.contains("Con: Anna Rossi"))

    // The day's note is a sibling, and it points at it.
    let daily = try session.read("Calendar/20260820.md").text
    #expect(daily.contains("- [[20260820-riunione-tecnica]]"))
}

@MainActor
@Test func askingTwiceReturnsTheSameNoteRatherThanASecondOne() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let first = await session.eventNote(for: "Riunione tecnica", on: thursday)
    let second = await session.eventNote(for: "Riunione tecnica", on: thursday)

    #expect(first?.path == second?.path)
    // The second call wrote nothing at all, which is what the nil says.
    #expect(second?.dailyNote == nil)
    let daily = try session.read("Calendar/20260820.md").text
    #expect(daily.components(separatedBy: "- [[20260820-riunione-tecnica]]").count == 2)
}
