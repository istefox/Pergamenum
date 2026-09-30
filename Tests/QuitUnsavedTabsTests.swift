import Foundation
import Testing
@testable import Pergamenum

// PG-326, #693, ADR-0073: quitting (or switching vault) with unsaved note tabs asks first, and
// "Salva tutto" writes every dirty tab. These tests pin the pieces that are not AppKit:
// `VaultController.unsavedTabs`, `UnsavedNotesPrompt`, `unsavedTabsDecision(asking:)`,
// `saveAllUnsavedTabs()` and the `catchUp(to:)` rule §D4 adds. `AppDelegate` and the alert are
// AppKit lifecycle and not unit-testable (`Tests/DiarySettleTests.swift`'s header); the wiring
// is covered by the plan's manual checklist. Requirements are the plan's R-01..R-04 and R-07
// (`docs/plans/pg-326-quit-unsaved-note-tabs.md`), not the repo-root SPEC.md.

private func body(_ name: String) -> String {
    "---\ndate: 2026-08-19\ntags:\n  - type-note\n---\n\n## \(name)\n\nTesto di \(name).\n"
}

/// Two columns: column 0 holds `C` (clean), then `A` and `B`; column 1 holds a clean copy of
/// `C` and `D`. `A`, `B` and `D` are dirty. Focus ends on column 0 with `B` in front, so `A`
/// is a dirty background tab and `D` a dirty tab in the other column.
@MainActor
private func threeDirty(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    for name in ["A", "B", "C", "D"] { try vault.write(body(name), to: "\(name).md") }
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "C.md")
    controller.splitEditor()
    controller.openNoteInNewTab(at: "D.md")
    controller.updateOpenNoteText(body("D") + "modifica D\n")
    controller.focusColumn(0)
    controller.openNoteInNewTab(at: "A.md")
    controller.updateOpenNoteText(body("A") + "modifica A\n")
    controller.openNoteInNewTab(at: "B.md")
    controller.updateOpenNoteText(body("B") + "modifica B\n")
    return controller
}

private func paths(_ tabs: [NoteTab]) -> [String] { tabs.map(\.note.relativePath) }

@MainActor
private func openNote(_ path: String, title: String? = nil, text: String, saved: String) -> NoteTab {
    NoteTab(note: VaultController.OpenNote(
        relativePath: path, title: title ?? path, text: text, savedText: saved
    ))
}

// MARK: unsavedTabs (R-01)

@MainActor
@Test func unsavedTabsIsEmptyWhileEveryTabIsClean() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    #expect(controller.unsavedTabs.isEmpty)
    controller.close()
}

@MainActor
@Test func unsavedTabsListsTheFocusedDirtyTab() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    controller.updateOpenNoteText(body("A") + "modifica\n")

    #expect(paths(controller.unsavedTabs) == ["A.md"])
    controller.close()
}

@MainActor
@Test func unsavedTabsListsADirtyBackgroundTabOfTheFocusedColumn() async throws {
    let vault = try TemporaryVault()
    for name in ["A", "B"] { try vault.write(body(name), to: "\(name).md") }
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    let a = try #require(controller.focusedTab?.id)
    controller.updateOpenNoteText(body("A") + "modifica\n")
    controller.openNoteInNewTab(at: "B.md")
    // The dirty tab is not in front: the focused tab is clean.
    #expect(controller.focusedTab?.note.relativePath == "B.md")
    #expect(controller.focusedTab?.id != a)

    #expect(paths(controller.unsavedTabs) == ["A.md"])
    controller.close()
}

@MainActor
@Test func unsavedTabsListsADirtyTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    for name in ["A", "B"] { try vault.write(body(name), to: "\(name).md") }
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    controller.splitEditor()
    controller.openNoteInNewTab(at: "B.md")
    controller.updateOpenNoteText(body("B") + "modifica\n")
    controller.focusColumn(0)
    #expect(controller.focusedColumnIndex == 0)

    #expect(paths(controller.unsavedTabs) == ["B.md"])
    controller.close()
}

// MARK: The decision (R-01, R-02, R-04)

@MainActor
@Test func theDecisionAsksNothingWhenNoTabIsDirty() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")

    var calls = 0
    let answer = controller.unsavedTabsDecision { _ in
        calls += 1
        return .discard
    }

    #expect(calls == 0)
    #expect(answer == nil)
    controller.close()
}

@MainActor
@Test(arguments: [UnsavedNotesChoice.saveAll, .discard, .cancel])
func theDecisionAsksOnceAndReturnsTheAnswer(choice: UnsavedNotesChoice) async throws {
    let vault = try TemporaryVault()
    let controller = try await threeDirty(vault)
    let columnsBefore = controller.columns

    var prompts: [UnsavedNotesPrompt] = []
    let answer = controller.unsavedTabsDecision { prompt in
        prompts.append(prompt)
        return choice
    }

    #expect(answer == choice)
    #expect(prompts.count == 1)
    let titles = try #require(prompts.first).titles
    #expect(titles.count == 3, "one title per dirty note: A, B, D")
    // Column 0 (C, A, B) before column 1 (C, D), tab order within each; the clean C is absent.
    #expect(titles == ["A", "B", "D"])
    // The question changes nothing: every buffer is exactly as it was.
    #expect(controller.columns == columnsBefore)
    controller.close()
}

@MainActor
@Test func choosingDiscardWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    controller.updateOpenNoteText(body("A") + "modifica\n")
    let before = try Data(contentsOf: vault.root.appending(path: "A.md"))

    // What the decision returns is `theDecisionAsksOnceAndReturnsTheAnswer`'s business; this
    // one pins only that asking never writes, so it holds against the stub and the real body.
    _ = controller.unsavedTabsDecision { _ in .discard }

    #expect(try Data(contentsOf: vault.root.appending(path: "A.md")) == before)
    controller.close()
}

// MARK: The prompt (ADR-0073 §D2)

@MainActor
@Test func aPromptForNoTabsIsNil() {
    #expect(UnsavedNotesPrompt(tabs: []) == nil)
}

@MainActor
@Test func aPromptCountsNotesNotTabs() throws {
    let one = openNote("Uno.md", title: "Uno", text: "x", saved: "")
    let again = openNote("Uno.md", title: "Uno", text: "x", saved: "")

    let prompt = try #require(UnsavedNotesPrompt(tabs: [one, again]))

    #expect(prompt.titles == ["Uno"])
    #expect(prompt.message == "C'è una nota con modifiche non salvate")
}

@MainActor
@Test func aPromptForTwoNotesUsesThePluralAndKeepsTheirOrder() throws {
    let second = openNote("Beta.md", title: "Beta", text: "x", saved: "")
    let first = openNote("Alfa.md", title: "Alfa", text: "x", saved: "")

    let prompt = try #require(UnsavedNotesPrompt(tabs: [second, first]))

    #expect(prompt.message == "Ci sono 2 note con modifiche non salvate")
    #expect(prompt.titles == ["Beta", "Alfa"])
}

@MainActor
@Test func aPromptListsAtMostEightTitlesThenHowManyMore() throws {
    let tabs = (0..<10).map { openNote("N\($0).md", title: "Nota \($0)", text: "x", saved: "") }

    let prompt = try #require(UnsavedNotesPrompt(tabs: tabs))

    #expect(UnsavedNotesPrompt.listedTitleLimit == 8)
    #expect(prompt.message == "Ci sono 10 note con modifiche non salvate")
    #expect(prompt.informativeText.contains("Nota 7"))
    #expect(!prompt.informativeText.contains("Nota 8"))
    #expect(prompt.informativeText.contains("e altre 2"))
}

@MainActor
@Test func aPromptWithOneNoteOverTheLimitSaysOneMoreInTheSingular() throws {
    let tabs = (0..<9).map { openNote("N\($0).md", title: "Nota \($0)", text: "x", saved: "") }

    let prompt = try #require(UnsavedNotesPrompt(tabs: tabs))

    #expect(prompt.message == "Ci sono 9 note con modifiche non salvate")
    #expect(prompt.listedTitles == ((0..<8).map { "«Nota \($0)»" } + ["e un'altra"]).joined(separator: "\n"))
    #expect(!prompt.informativeText.contains("Nota 8"))
    #expect(!prompt.informativeText.contains("e altre 1"))
}

// MARK: catchUp (ADR-0073 §D4)

@Test func catchUpOnADirtyBufferThatAlreadyEqualsTheIncomingTextAdoptsIt() {
    var note = VaultController.OpenNote(
        relativePath: "A.md", title: "A", text: "uguale", savedText: "vecchio",
        externalChangePending: .text("altro")
    )

    let answer = note.catchUp(to: .text("uguale"))

    #expect(answer == .adopted)
    #expect(note.savedText == "uguale")
    #expect(note.text == "uguale")
    #expect(note.externalChangePending == nil)
}

// MARK: saveAllUnsavedTabs (R-03, R-07)

@MainActor
@Test func saveAllWritesEveryDirtyTabInEveryColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await threeDirty(vault)
    let expected = Dictionary(uniqueKeysWithValues: controller.unsavedTabs.map {
        ($0.note.relativePath, $0.note.text)
    })
    #expect(expected.count == 3)

    let saved = await controller.saveAllUnsavedTabs()

    #expect(saved)
    let fresh = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await fresh.rescan()
    for (path, text) in expected {
        #expect(try fresh.read(path).text == text, "\(path) must be on disk")
    }
    #expect(controller.unsavedTabs.isEmpty)
    controller.close()
}

@MainActor
@Test func saveAllWritesTwoIdenticalDirtyCopiesOnceAndLeavesBothClean() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    controller.splitEditor()
    let typed = body("A") + "stessa modifica\n"
    controller.updateOpenNoteText(typed)
    controller.focusColumn(0)
    controller.updateOpenNoteText(typed)
    #expect(controller.unsavedTabs.count == 2)

    let saved = await controller.saveAllUnsavedTabs()

    #expect(saved)
    #expect(controller.unsavedTabs.isEmpty)
    for column in controller.columns {
        for tab in column.tabs { #expect(tab.note.externalChangePending == nil) }
    }
    #expect(try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8) == typed)
    controller.close()
}

@MainActor
@Test func saveAllRefusesDivergentCopiesOfOnePathAndStillWritesTheOthers() async throws {
    let vault = try TemporaryVault()
    for name in ["A", "B"] { try vault.write(body(name), to: "\(name).md") }
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    controller.splitEditor()
    controller.updateOpenNoteText(body("A") + "versione destra\n")
    controller.focusColumn(0)
    controller.updateOpenNoteText(body("A") + "versione sinistra\n")
    controller.openNoteInNewTab(at: "B.md")
    let typedB = body("B") + "modifica B\n"
    controller.updateOpenNoteText(typedB)
    let aBefore = try Data(contentsOf: vault.root.appending(path: "A.md"))
    let columnsBefore = controller.columns.map { $0.tabs.filter { $0.note.relativePath == "A.md" } }

    let saved = await controller.saveAllUnsavedTabs()

    #expect(!saved)
    #expect(try Data(contentsOf: vault.root.appending(path: "A.md")) == aBefore)
    #expect(controller.columns.map { $0.tabs.filter { $0.note.relativePath == "A.md" } } == columnsBefore)
    #expect(controller.problems.contains { $0.contains("A.md") })
    #expect(try String(contentsOf: vault.root.appending(path: "B.md"), encoding: .utf8) == typedB)
    controller.close()
}

@MainActor
@Test func saveAllReturnsFalseAndKeepsTheBufferWhenAWriteFails() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("N"), to: "Sub/N.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "Sub/N.md")
    let typed = body("N") + "modifica\n"
    controller.updateOpenNoteText(typed)

    let sub = vault.root.appending(path: "Sub", directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sub)
    defer {
        // Restored before `TemporaryVault.deinit` tries to remove the tree.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub)
    }

    let saved = await controller.saveAllUnsavedTabs()

    #expect(!saved)
    #expect(controller.problems.contains { $0.contains("Sub/N.md") })
    #expect(controller.openNote?.text == typed)
    #expect(controller.openNote?.hasUnsavedChanges == true)
    controller.close()
}

@MainActor
@Test func saveAllWritesADirtyTabOverAPendingExternalChangeAsCmdSDoes() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    let typed = body("A") + "la mia modifica\n"
    controller.updateOpenNoteText(typed)
    let other = body("A") + "modifica esterna\n"
    try vault.write(other, to: "A.md")
    controller.updateFocusedTab { $0.note.externalChangePending = .text(other) }

    let saved = await controller.saveAllUnsavedTabs()

    #expect(saved)
    #expect(try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8) == typed)
    controller.close()
}

@MainActor
@Test func saveAllWithNothingDirtyWritesNothingAndReturnsTrue() async throws {
    let vault = try TemporaryVault()
    try vault.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNoteInNewTab(at: "A.md")
    let before = try Data(contentsOf: vault.root.appending(path: "A.md"))

    let saved = await controller.saveAllUnsavedTabs()

    #expect(saved)
    #expect(try Data(contentsOf: vault.root.appending(path: "A.md")) == before)
    controller.close()
}
