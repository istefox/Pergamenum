import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0086 §D3/§D4, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-06, R-08:
// the caret a day's note is born with. A day opened by the call that created it carries the
// template's `{{cursor}}` as the new tab's pending caret; reopening an existing day moves none;
// `takePendingCaret(forColumn:)` hands it over once; «Applica un template…» carries the same
// marker as `cursorBack`.
//
// The Oggi pane's embedded daily editor is not a tab and does not consume the caret (SPEC edge
// case); that is a hosted-editor fact, not a controller one, and is left to the GUI test of Task 8.

private let day = CalendarDate(iso: "2026-10-12")!

private let dailyTemplate = """
---
date: 2026-01-01
tags:
  - type-note
---

Appunti: {{cursor}}
"""

@MainActor
private func opened(
    _ vault: borrowing TemporaryVault, withTemplate: Bool = true
) async throws -> VaultController {
    try vault.write(dailyTemplate, to: "Templates/Giorno.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    if withTemplate {
        let session = try #require(controller.session)
        session.updateSettings { $0.dailyTemplate = "Templates/Giorno.md" }
    }
    return controller
}

private func written(_ path: String, in vault: borrowing TemporaryVault) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

/// Where `{{cursor}}` ends up in the day the template makes: right after «Appunti: ».
private func expectedCaret(in text: String) -> Int {
    let marker = (text as NSString).range(of: "Appunti: ")
    return marker.location + marker.length
}

// MARK: - A day born from the template

@MainActor
@Test func aDayCreatedByTheCallCarriesTheTemplatesCaretOnItsNewTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)

    let path = try await controller.openDailyNote(for: day)

    let text = try written(path, in: vault)
    #expect(text.contains("Appunti: "))
    #expect(!text.contains("{{cursor}}"), "the marker is never written") // R-07
    #expect(controller.focusedTab?.note.relativePath == path)
    #expect(controller.focusedTab?.pendingCaret == expectedCaret(in: text)) // R-08
    controller.close()
}

@MainActor
@Test func reopeningAnExistingDayMovesNoCaret() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    _ = try await controller.openDailyNote(for: day)
    _ = controller.takePendingCaret(forColumn: 0)

    _ = try await controller.openDailyNote(for: day)

    #expect(controller.focusedTab?.pendingCaret == nil) // R-08: only the call that created it places it
    #expect(controller.takePendingCaret(forColumn: 0) == nil)
    controller.close()
}

@MainActor
@Test func withoutATemplateSettingTheDayOpensWithNoPendingCaret() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault, withTemplate: false)

    _ = try await controller.openDailyNote(for: day)

    #expect(controller.focusedTab?.pendingCaret == nil) // R-06: absent means none
    controller.close()
}

// MARK: - Handing the caret over once

@MainActor
@Test func takingThePendingCaretReturnsItOnceAndClearsIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let path = try await controller.openDailyNote(for: day)
    let expected = expectedCaret(in: try written(path, in: vault))
    try #require(controller.focusedTab?.pendingCaret == expected)

    #expect(controller.takePendingCaret(forColumn: 0) == expected) // R-08
    #expect(controller.takePendingCaret(forColumn: 0) == nil, "a second take finds nothing")
    #expect(controller.focusedTab?.pendingCaret == nil)
    controller.close()
}

@MainActor
@Test func theCaretBelongsToItsOwnColumnOnly() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let path = try await controller.openDailyNote(for: day)
    let expected = expectedCaret(in: try written(path, in: vault))
    controller.splitEditor()
    controller.focusColumn(0)
    try #require(controller.columns.count == 2)
    try #require(controller.columns[0].active?.pendingCaret == expected)

    #expect(controller.takePendingCaret(forColumn: 1) == nil, "the other column's tab was not the one born") // R-08
    #expect(controller.columns[0].active?.pendingCaret == expected, "and asking there took nothing from column 0")
    #expect(controller.takePendingCaret(forColumn: 0) == expected)
    controller.close()
}

@MainActor
@Test func aColumnThatDoesNotExistHasNoCaret() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)

    #expect(controller.takePendingCaret(forColumn: 7) == nil)
    #expect(controller.takePendingCaret(forColumn: -1) == nil)
    controller.close()
}

// MARK: - «Applica un template…» (R-08)

@Test func applyingATemplateCarriesTheCursorAsHowFarBackFromTheEnd() {
    let insertion = TemplateSheet.insertion(
        templateText: dailyTemplate.replacingOccurrences(of: "Appunti: {{cursor}}", with: "Prima {{cursor}}dopo"),
        title: "Nota", date: day, time: TaskTime(hour: 9, minute: 5)
    )

    #expect(!insertion.text.contains("{{cursor}}")) // R-07
    #expect(insertion.text.contains("Prima dopo"))
    #expect(insertion.cursorBack == "dopo".utf16.count) // R-08
}

@Test func aTemplateWithoutAMarkerHasNoCursorBack() {
    let insertion = TemplateSheet.insertion(
        templateText: "---\ndate: 2026-01-01\ntags:\n  - type-note\n---\n\nSolo testo.",
        title: "Nota", date: day, time: TaskTime(hour: 9, minute: 5)
    )

    #expect(insertion.cursorBack == 0)
    #expect(insertion.text.contains("Solo testo."))
}

@Test func theTimePlaceholderResolvesInAnAppliedTemplate() {
    let insertion = TemplateSheet.insertion(
        templateText: "---\ndate: 2026-01-01\ntags:\n  - type-note\n---\n\nOre {{time}}",
        title: "Nota", date: day, time: TaskTime(hour: 9, minute: 5)
    )

    #expect(insertion.text.contains("Ore 09:05")) // R-07
}
