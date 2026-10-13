import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D1/§D6/§D8, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-01,
// R-04, R-13: the two verbs the note's birth adds to the command catalogue, in `CommandActions`.
// «Classifica…» acts on the row selected in «Da classificare», on the Contenitore's selection when
// that pane is in front (ADR-0071 §D12's redirect), and otherwise on the open note.
// «Estrai in una nota» follows the focused tab's selection.

private let capturePath = "00 Inbox/Idea.md"

@MainActor
private func makeApp(
    _ vault: borrowing TemporaryVault
) async throws -> (app: NoteBirthApp, scheda: String) {
    try vault.write(captureNote("Pensiero."), to: capturePath)
    try vault.write(captureNote("Altro."), to: "00 Inbox/Altro.md")
    let scheda = try ContenitoreFixture.seed(stem: "20261001 Fattura", in: "Contenitore/2026", date: "2026-10-01", vault: vault)
    return (try await NoteBirthApp.make(vault), scheda)
}

// MARK: - «Classifica…» availability (R-04)

@MainActor
@Test func classifyCannotRunWithNothingOpenAndNoRowSelected() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)

    #expect(!app.actions.canRun(.classifyNote)) // R-04
}

@MainActor
@Test func classifyCanRunWithANoteOpen() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.vault.openNote(at: capturePath)
    try #require(app.vault.openNote != nil)

    #expect(app.actions.canRun(.classifyNote)) // R-04
}

@MainActor
@Test func classifyCanRunWithARowSelectedInTheUnfiledPane() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.navigation.pane = .unfiled
    app.navigation.unfiledSelection = capturePath

    #expect(app.actions.canRun(.classifyNote)) // R-01, R-04
}

@MainActor
@Test func classifyIsOnTheNoteRowMenu() {
    // The row menu and the menu bar read one set (ADR-0023 §D1), so the verb cannot be offered
    // by one and refused by the other.
    #expect(CommandActions.rowCommands.contains(.classifyNote)) // R-04
}

// MARK: - «Classifica…» subject (R-01, R-04)

@MainActor
@Test func fromTheUnfiledPaneClassifyOpensTheSheetOnTheSelectedRow() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.navigation.pane = .unfiled
    app.navigation.unfiledSelection = capturePath

    app.actions.run(.classifyNote)

    #expect(app.navigation.classifying == .note(capturePath)) // R-04
}

@MainActor
@Test func fromTheUnfiledPaneASchedaRowOpensTheSchedaForm() async throws {
    let vault = try TemporaryVault()
    let (app, scheda) = try await makeApp(vault)
    app.navigation.pane = .unfiled
    app.navigation.unfiledSelection = scheda

    app.actions.run(.classifyNote)

    #expect(app.navigation.classifying == .scheda(scheda)) // SPEC edge case: no folder field
}

@MainActor
@Test func withTheContenitoreInFrontClassifyRedirectsToItsOwnSheet() async throws {
    let vault = try TemporaryVault()
    let (app, scheda) = try await makeApp(vault)
    app.navigation.pane = .contenitore
    app.contenitore.selection = scheda

    app.actions.run(.classifyNote)

    #expect(app.contenitore.classifying == scheda) // ADR-0071 §D12
    #expect(app.navigation.classifying == nil, "the Contenitore's selection is not also a note sheet")
}

@MainActor
@Test func elsewhereClassifyOpensTheSheetOnTheOpenNote() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.navigation.pane = .notes
    app.vault.openNote(at: capturePath)

    app.actions.run(.classifyNote)

    #expect(app.navigation.classifying == .note(capturePath)) // R-04
}

// MARK: - Going to the pane (R-01)

@MainActor
@Test func goToUnfiledShowsThePane() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.navigation.pane = .notes
    try #require(app.actions.canRun(.paneUnfiled))

    app.actions.run(.paneUnfiled)

    #expect(app.navigation.pane == .unfiled) // R-01
}

// MARK: - «Estrai in una nota» (R-13)

@MainActor
@Test func extractCannotRunWithNothingSelected() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.vault.openNote(at: capturePath)

    #expect(!app.actions.canRun(.extractToNote)) // R-13: enabled by a non-empty selection
}

@MainActor
@Test func extractFollowsTheFocusedTabsSelection() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)
    app.vault.openNote(at: capturePath)

    app.vault.recordSelection(NSRange(location: 0, length: 4), inColumn: 0)
    #expect(app.actions.canRun(.extractToNote), "a non-empty selection enables it") // R-13
    #expect(app.vault.focusedTab?.selection == NSRange(location: 0, length: 4))

    app.vault.recordSelection(nil, inColumn: 0)
    #expect(!app.actions.canRun(.extractToNote), "a collapsed selection disables it again") // R-13
    #expect(app.vault.focusedTab?.selection == nil)
}

@MainActor
@Test func extractCannotRunWithNoNoteOpenEvenIfASelectionWasRecorded() async throws {
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)

    app.vault.recordSelection(NSRange(location: 0, length: 4), inColumn: 0)

    #expect(!app.actions.canRun(.extractToNote))
}

@MainActor
@Test func theTwoVerbsNeverTrapTheDebugHostWhenRunWithNothingOpen() async throws {
    // The plan's guard (Task 4): a new command must not fall into an `assertionFailure`
    // default, which traps the Debug test host. Reaching here is the assertion.
    let vault = try TemporaryVault()
    let (app, _) = try await makeApp(vault)

    app.actions.run(.classifyNote)
    app.actions.run(.extractToNote)

    #expect(app.navigation.pane == .notes)
}
