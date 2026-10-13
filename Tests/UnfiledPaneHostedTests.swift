import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D1/§D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-01: the
// «Da classificare» pane built for real in a window that is never shown
// (`Tests/HostedViewSupport.swift`).
//
// **Why the rows are counted on the `NSTableView`.** Identifiers are unreachable in-process
// (`ContenitoreHostedViewTests` measured it: every view and accessibility element reports an
// empty one), so the test counts the rows of the table AppKit puts under a SwiftUI `List`. The
// pane is flat rows (ADR-0024), so one list is one table. Nothing here makes a window key or
// sends an event.

private func seedFourRows(in vault: borrowing TemporaryVault) throws {
    try vault.write(captureNote("Uno.", date: "2026-10-03"), to: "00 Inbox/Uno.md")
    try vault.write(captureNote("Due.", date: "2026-10-02"), to: "00 Inbox/Due.md")
    try vault.write(captureNote("Tre.", date: "2026-10-01"), to: "00 Inbox/Tre.md")
    try ContenitoreFixture.seed(stem: "20261001 Fattura", in: "Contenitore/2026", date: "2026-10-01", vault: vault)
    try vault.write(classifiedNote(), to: "03 Risorse/Classificata.md")
}

@MainActor
@Test func threeCapturesAndACaptureSchedaGiveFourRows() async throws {
    let vault = try TemporaryVault()
    try seedFourRows(in: vault)
    let app = try await NoteBirthApp.make(vault)
    app.navigation.pane = .unfiled

    let host = app.hosted(UnfiledPane(), size: CGSize(width: 1100, height: 700))
    defer { host.tearDown() }
    await host.settle()

    let rows = tables(under: host.hosting).map(\.table.numberOfRows)
    #expect(rows.contains(4), "one table lists the four captures; found tables with \(rows) rows") // R-01
    #expect(!rows.contains(5), "the classified note is not a row")

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func anEmptyVaultGivesTheEmptyStateAndNoRows() async throws {
    let vault = try TemporaryVault()
    try vault.write(classifiedNote(), to: "03 Risorse/Classificata.md")
    let app = try await NoteBirthApp.make(vault)
    app.navigation.pane = .unfiled

    let host = app.hosted(UnfiledPane(), size: CGSize(width: 1100, height: 700))
    defer { host.tearDown() }
    await host.settle()

    let rows = tables(under: host.hosting).map(\.table.numberOfRows)
    #expect(rows.allSatisfy { $0 == 0 }, "nothing to classify, nothing listed; found \(rows)") // R-01
    // The empty state is text the pane draws, which cannot be read in-process; that it drew
    // *something* beyond a flat fill can.
    #expect(host.snapshot().map { $0.distinctColors > 1 } == true, "the empty state is drawn") // R-01

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func classifyingARowTakesItOutOfThePane() async throws {
    let vault = try TemporaryVault()
    try seedFourRows(in: vault)
    let app = try await NoteBirthApp.make(vault)
    app.navigation.pane = .unfiled

    let host = app.hosted(UnfiledPane(), size: CGSize(width: 1100, height: 700))
    defer { host.tearDown() }
    await host.settle()
    try #require(tables(under: host.hosting).map(\.table.numberOfRows).contains(4))

    let session = try #require(app.vault.session)
    let candidate = Pergamenum.Tag("topic-x")
    let topic = try #require(candidate)
    _ = try await session.classifyNote(at: "00 Inbox/Due.md", topics: [topic], toFolder: nil)
    await host.settle()

    let rows = tables(under: host.hosting).map(\.table.numberOfRows)
    #expect(rows.contains(3), "after the classification three captures remain; found \(rows)") // R-01
    #expect(!rows.contains(4))

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func theListHoldsTheKeyboardOnceThePaneIsOnScreen() async throws {
    let vault = try TemporaryVault()
    try seedFourRows(in: vault)
    let app = try await NoteBirthApp.make(vault)
    app.navigation.pane = .unfiled

    let host = app.hosted(UnfiledPane(), size: CGSize(width: 1100, height: 700))
    defer { host.tearDown() }
    await host.settle()

    // ADR-0070 / R-01: Ctrl+Cmd+I then Down moves in the list, so the table is first responder
    // without a click on a row.
    let table = try #require(tables(under: host.hosting).first { $0.table.numberOfRows == 4 }?.table)
    let responder = host.window.firstResponder
    #expect(responder === table, "first responder is \(String(describing: responder)), not the list's table") // R-01

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}
