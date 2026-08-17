import Foundation
import Testing
@testable import Pergamenum

private func route(_ string: String) -> PergamenumRoute? {
    URL(string: string).flatMap(PergamenumRoute.init)
}

@Test func parsesEveryRouteOfTheSpec() {
    #expect(route("pergamenum://note?file=01%20Progetti/Nota.md") == .note(path: "01 Progetti/Nota.md"))
    #expect(route("pergamenum://note?id=abc-123") == .noteID("abc-123"))
    #expect(route("pergamenum://canvas?file=Area/Area.canvas") == .canvas(path: "Area/Area.canvas", nodeID: nil))
    #expect(route("pergamenum://canvas?file=Area/Area.canvas&node=7a1f") == .canvas(path: "Area/Area.canvas", nodeID: "7a1f"))
    #expect(route("pergamenum://day/20260811") == .day(CalendarDate(iso: "2026-08-11")!))
    #expect(route("pergamenum://today") == .today)
    #expect(route("pergamenum://search?q=trasmissibilit%C3%A0") == .search("trasmissibilità"))
    #expect(route("pergamenum://capture?text=appunto")
        == .capture(text: "appunto", destination: nil, scheduled: nil, due: nil))
    #expect(route("pergamenum://task?add=Richiamare%20Rossi") == .addTask("Richiamare Rossi"))
}

/// The capture route grew three parameters (ADR-0008 §D5) and the form SPEC §9 published
/// had to keep working: a link already sitting in a Shortcut cannot start doing something
/// else because the panel needed more.
@Test func theCaptureRouteGainsDestinationsWithoutLosingTheOldForm() {
    // `?note=` was the only destination there was, and it still means that note.
    #expect(route("pergamenum://capture?text=x&note=Calendar/20260811.md")
        == .capture(text: "x", destination: "note:Calendar/20260811.md", scheduled: nil, due: nil))

    // The new spelling, and the dates that only a task can carry.
    #expect(route("pergamenum://capture?text=x&dest=task&schedule=2026-08-20&deadline=2026-08-25")
        == .capture(text: "x", destination: "task", scheduled: "2026-08-20", due: "2026-08-25"))
    #expect(route("pergamenum://capture?text=x&dest=oggi")
        == .capture(text: "x", destination: "oggi", scheduled: nil, due: nil))

    // Both given: the explicit one wins rather than the two being merged.
    #expect(route("pergamenum://capture?text=x&dest=task&note=A.md")
        == .capture(text: "x", destination: "task", scheduled: nil, due: nil))

    // An unreadable destination is not the route's business: it is carried as written
    // and refused by the connector, which is the only place that knows the four names.
    #expect(route("pergamenum://capture?text=x&dest=inventata")
        == .capture(text: "x", destination: "inventata", scheduled: nil, due: nil))
}

@Test(arguments: [
    "pergamenum://note",                    // neither file nor id
    "pergamenum://note?file=",              // empty value
    "pergamenum://canvas",                  // no file
    "pergamenum://day/2026-08-11",          // hyphenated, not the compact form
    "pergamenum://day/nonunadata",
    "pergamenum://search?q=",
    "pergamenum://sconosciuto",
    "obsidian://open?vault=Labs",           // another app's scheme
    "https://example.test",
])
func refusesRoutesItDoesNotAnswer(_ string: String) {
    // A link that opens the wrong note is worse than one that reports it does not
    // work, so an unrecognised route is nil rather than a nearest guess.
    #expect(route(string) == nil)
}

@Test func onlyCaptureLeavesTheAppInTheBackground() {
    // SPEC §9: capture appends without interrupting what the user is doing elsewhere.
    #expect(route("pergamenum://capture?text=x")?.raisesApp == false)
    #expect(route("pergamenum://today")?.raisesApp == true)
    #expect(route("pergamenum://note?file=a.md")?.raisesApp == true)
}

@Test func acceptsTheDayRouteOnlyInTheCompactForm() {
    // naming.md 4.6 fixes the daily-note name as YYYYMMDD, and the route matches it.
    #expect(route("pergamenum://day/20260811") != nil)
    #expect(route("pergamenum://day/20261301") == nil)   // month 13
    #expect(route("pergamenum://day/20260230") == nil)   // 30 February
}

// MARK: - Building links

@Test func buildsLinksThatParseBackToTheSameRoute() {
    let path = "01 Progetti/Nota con & e ? nel nome.md"
    let url = PergamenumLink.note(path: path)
    #expect(url != nil)
    // The round-trip is the point: a title with a query character must survive being
    // pasted into Obsidian and clicked.
    #expect(url.flatMap(PergamenumRoute.init) == .note(path: path))
}

@Test func buildsCanvasAndDayAndSearchLinks() {
    #expect(PergamenumLink.canvas(path: "Area/Area.canvas", nodeID: "7a1f")
        .flatMap(PergamenumRoute.init) == .canvas(path: "Area/Area.canvas", nodeID: "7a1f"))
    #expect(PergamenumLink.day(CalendarDate(iso: "2026-08-11")!)
        .flatMap(PergamenumRoute.init) == .day(CalendarDate(iso: "2026-08-11")!))
    #expect(PergamenumLink.search("curva di trasmissibilità")
        .flatMap(PergamenumRoute.init) == .search("curva di trasmissibilità"))
}

@Test func linksCarryTheAppsOwnScheme() {
    #expect(PergamenumLink.note(path: "a.md")?.scheme == AppInfo.urlScheme)
    #expect(PergamenumLink.note(path: "a.md")?.absoluteString.hasPrefix("pergamenum://") == true)
}

// MARK: - Handling routes against a vault

private struct RouteVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-routes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}

private let routableNote = """
---
date: 2026-08-11
tags:
  - type-note
  - topic-x
---

Corpo.
"""

@MainActor
@Test func opensTheNoteANoteRouteNames() async throws {
    let vault = try RouteVault()
    try vault.write(routableNote, to: "01 Progetti/Nota.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.note(path: "01 Progetti/Nota.md")))
    #expect(controller.openNote?.relativePath == "01 Progetti/Nota.md")
    controller.close()
}

@MainActor
@Test func reportsALinkToANoteThatIsNotThere() async throws {
    let vault = try RouteVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    // A link from DEVONthink that quietly does nothing is worse than one that says
    // the note has moved.
    #expect(!controller.handle(.note(path: "Sparita.md")))
    #expect(controller.problems.contains { $0.contains("Sparita.md") })
    controller.close()
}

@MainActor
@Test func theDayRouteOpensOrCreatesTheDailyNote() async throws {
    let vault = try RouteVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.day(CalendarDate(iso: "2026-08-11")!)))
    #expect(controller.openNote?.relativePath == "Calendar/20260811.md")
    controller.close()
}

@MainActor
@Test func theCaptureRouteAppendsWithoutOpeningTheNote() async throws {
    let vault = try RouteVault()
    try vault.write(routableNote, to: "Destinazione.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.capture(
        text: "appunto veloce", destination: "note:Destinazione.md", scheduled: nil, due: nil
    )))
    let onDisk = try String(contentsOf: vault.root.appending(path: "Destinazione.md"), encoding: .utf8)
    #expect(onDisk.hasSuffix("appunto veloce\n"))
    #expect(onDisk.hasPrefix(routableNote))
    // A blank line before it, not merely a newline. The first version checked only
    // that the text was last, which it was - fused onto whatever came before.
    #expect(onDisk.hasSuffix("\n\nappunto veloce\n"))
    // SPEC §9: capture does not bring the app forward, and it does not open the note.
    #expect(controller.openNote == nil)
    controller.close()
}

@MainActor
@Test func theTaskRouteLandsInTheInbox() async throws {
    let vault = try RouteVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.addTask("Richiamare Rossi")))
    let onDisk = try String(contentsOf: vault.root.appending(path: "00 Inbox/Capture.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Richiamare Rossi"))
    controller.close()
}

@MainActor
@Test func theSearchRouteOpensTheQuickSwitcherWithItsQuery() async throws {
    let vault = try RouteVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.search("trasmissibilità")))
    #expect(controller.isShowingQuickSwitcher)
    #expect(controller.consumePendingSearch() == "trasmissibilità")
    // Consumed once: reopening the switcher later must not re-apply an old query.
    #expect(controller.consumePendingSearch() == nil)
    controller.close()
}

@MainActor
@Test func theCanvasRouteIsHandedToTheWorkspace() async throws {
    let vault = try RouteVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.canvas(path: "Area/Area.canvas", nodeID: "7a1f")))
    let pending = controller.consumePendingCanvasRoute()
    #expect(pending?.path == "Area/Area.canvas")
    #expect(pending?.nodeID == "7a1f")
    #expect(controller.consumePendingCanvasRoute() == nil)
    controller.close()
}

// MARK: - Vault-wide conformance

@MainActor
@Test func theLinterReportsANonConformantNoteAndPassesAConformantOne() async throws {
    let vault = try RouteVault()
    try vault.write(routableNote, to: "Conforme.md")
    try vault.write("""
    ---
    date: 2026-08-01
    tags:
      - type-note
    status: bozza
    ---

    Senza topic, con chiave fuori schema.
    """, to: "Non conforme v2.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let clean = controller.violations(forRecordAt: "Conforme.md")
    #expect(clean?.isEmpty == true, "\(String(describing: clean))")

    let dirty = try #require(controller.violations(forRecordAt: "Non conforme v2.md"))
    #expect(dirty.frontmatter.contains(.foreignKey("status")))
    #expect(dirty.tags.contains(.missingRequiredTag("topic-*")))
    #expect(dirty.name.contains { if case .hasVersionSuffix = $0 { true } else { false } })
    controller.close()
}

@MainActor
@Test func aDailyNoteIsJudgedByItsOwnNamingRule() async throws {
    let vault = try RouteVault()
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    Giornata.
    """, to: "Calendar/20260811.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    // `20260811` would fail the ordinary title check; a daily note is correct exactly
    // when it matches the compact form, and needs no topic.
    let violations = try #require(controller.violations(forRecordAt: "Calendar/20260811.md"))
    #expect(violations.name.isEmpty)
    #expect(!violations.tags.contains(.missingRequiredTag("topic-*")))
    controller.close()
}

@MainActor
@Test func theLinterReadsDiskRatherThanTheIndex() async throws {
    let vault = try RouteVault()
    try vault.write(routableNote, to: "Nota.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    #expect(controller.violations(forRecordAt: "Nota.md")?.isEmpty == true)

    // Edited behind the app's back, as Obsidian would. A linter that trusted the
    // index would report this note as still clean.
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    title: vietato
    ---

    Corpo.
    """, to: "Nota.md")

    #expect(controller.violations(forRecordAt: "Nota.md")?.frontmatter.contains(.foreignKey("title")) == true)
    controller.close()
}

@MainActor
@Test func aCaptureUnderAListDoesNotBecomePartOfTheLastBullet() async throws {
    // The shape a daily note is always in by the afternoon: a Timeline section whose
    // last line is a time block. Appended with a single newline the captured text is a
    // lazy continuation of that bullet in CommonMark, so the note reads as though the
    // block were titled "Riunione Riga catturata" - and the text sits inside a section
    // the app rewrites on the next block change.
    let vault = try RouteVault()
    try vault.write("""
    ---
    date: 2026-08-12
    tags:
      - type-note
    ---

    ## Timeline

    - 09:00-09:30 Riunione
    """, to: "Giorno.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    #expect(controller.handle(.capture(
        text: "Riga catturata", destination: "note:Giorno.md", scheduled: nil, due: nil
    )))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Giorno.md"), encoding: .utf8)
    #expect(onDisk.contains("- 09:00-09:30 Riunione\n\nRiga catturata\n"))
    controller.close()
}

@MainActor
@Test func twoCapturesInARowStayTwoSeparateLines() async throws {
    let vault = try RouteVault()
    try vault.write(routableNote, to: "Destinazione.md")
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.handle(.capture(
        text: "primo", destination: "note:Destinazione.md", scheduled: nil, due: nil
    )))
    #expect(controller.handle(.capture(
        text: "secondo", destination: "note:Destinazione.md", scheduled: nil, due: nil
    )))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Destinazione.md"), encoding: .utf8)
    // Not fused into one paragraph: two captures are two notes to self, not one.
    #expect(onDisk.hasSuffix("primo\n\nsecondo\n"))
    controller.close()
}
