import Foundation
import Testing
@testable import Pergamenum

// PG-326, #693, ADR-0073 §D6, R-08: a vault switch asks the same single question quit does,
// and `open(_:)` stops carrying the outgoing vault's tabs across. The presenter is injected, so
// no alert is shown. Requirements are the plan's (`docs/plans/pg-326-quit-unsaved-note-tabs.md`).

private func body(_ name: String) -> String {
    "---\ndate: 2026-08-19\ntags:\n  - type-note\n---\n\n## \(name)\n\nTesto di \(name).\n"
}

/// Records what the presenter was asked and answers with `choice`.
@MainActor
private final class Recorder {
    var choice: UnsavedNotesChoice
    var asked: [UnsavedNotesPrompt] = []
    var reported: [UnsavedNotesPrompt?] = []

    init(_ choice: UnsavedNotesChoice) { self.choice = choice }

    var presenter: UnsavedNotesPresenter {
        UnsavedNotesPresenter(
            ask: { [self] prompt in
                asked.append(prompt)
                return choice
            },
            reportUnsaved: { [self] prompt in reported.append(prompt) }
        )
    }
}

@MainActor
private func allTabs(_ controller: VaultController) -> [NoteTab] {
    controller.columns.flatMap(\.tabs)
}

@MainActor
private func openA(_ a: borrowing TemporaryVault, store: OpenTabsStore) async throws -> VaultController {
    try a.write(body("A"), to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: store)
    await controller.open(a.root)
    controller.openNoteInNewTab(at: "A.md")
    return controller
}

@MainActor
@Test func aCleanSwitchAsksNothingAndOpensTheOtherVault() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let controller = try await openA(a, store: .volatile())
    let recorder = Recorder(.cancel)

    let switched = await controller.switchVault(to: b.root, presenter: recorder.presenter)

    #expect(switched)
    #expect(recorder.asked.isEmpty)
    #expect(controller.root?.path(percentEncoded: false) == b.root.path(percentEncoded: false))
    controller.close()
}

@MainActor
@Test func aSwitchShowsTheIncomingVaultsOwnTabsNotTheOutgoingOnes() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try b.write(body("B"), to: "B.md")
    let store = OpenTabsStore.volatile()
    // B's remembered arrangement, seeded through the same store by a second controller.
    let seeder = VaultController(recents: .volatile(), openTabs: store)
    await seeder.open(b.root)
    seeder.openNoteInNewTab(at: "B.md")
    seeder.close()

    let controller = try await openA(a, store: store)
    let switched = await controller.switchVault(to: b.root, presenter: Recorder(.cancel).presenter)

    #expect(switched)
    #expect(allTabs(controller).map(\.note.relativePath) == ["B.md"])
    controller.close()
}

@MainActor
@Test func switchingBackRestoresTheOutgoingVaultsTabs() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try b.write(body("B"), to: "B.md")
    let controller = try await openA(a, store: .volatile())
    let presenter = Recorder(.cancel).presenter

    _ = await controller.switchVault(to: b.root, presenter: presenter)
    controller.openNoteInNewTab(at: "B.md")
    _ = await controller.switchVault(to: a.root, presenter: presenter)

    #expect(allTabs(controller).map(\.note.relativePath) == ["A.md"])
    controller.close()
}

@MainActor
@Test func cancellingTheSwitchKeepsTheVaultAndEveryBuffer() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let controller = try await openA(a, store: .volatile())
    let typed = body("A") + "modifica\n"
    controller.updateOpenNoteText(typed)
    let before = try Data(contentsOf: a.root.appending(path: "A.md"))
    let columnsBefore = controller.columns
    let recorder = Recorder(.cancel)

    let switched = await controller.switchVault(to: b.root, presenter: recorder.presenter)

    #expect(!switched)
    #expect(recorder.asked.count == 1)
    #expect(controller.root?.path(percentEncoded: false) == a.root.path(percentEncoded: false))
    #expect(controller.openNote?.text == typed)
    #expect(controller.columns == columnsBefore)
    #expect(try Data(contentsOf: a.root.appending(path: "A.md")) == before)
    controller.close()
}

@MainActor
@Test func saveAllWritesEveryDirtyTabBeforeTheSwitch() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try a.write(body("D"), to: "D.md")
    let controller = try await openA(a, store: .volatile())
    controller.splitEditor()
    controller.openNoteInNewTab(at: "D.md")
    let typedD = body("D") + "modifica D\n"
    controller.updateOpenNoteText(typedD)
    controller.focusColumn(0)
    let typedA = body("A") + "modifica A\n"
    controller.updateOpenNoteText(typedA)
    let recorder = Recorder(.saveAll)

    let switched = await controller.switchVault(to: b.root, presenter: recorder.presenter)

    #expect(switched)
    #expect(controller.root?.path(percentEncoded: false) == b.root.path(percentEncoded: false))
    let fresh = VaultSession(root: a.root, stateBase: a.stateBase)
    await fresh.rescan()
    #expect(try fresh.read("A.md").text == typedA)
    #expect(try fresh.read("D.md").text == typedD)
    controller.close()
}

@MainActor
@Test func aFailedSaveAbortsTheSwitchAndReportsWhatIsStillUnsaved() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try a.write(body("N"), to: "Sub/N.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(a.root)
    controller.openNoteInNewTab(at: "Sub/N.md")
    let typed = body("N") + "modifica\n"
    controller.updateOpenNoteText(typed)
    let title = try #require(controller.openNote?.title)
    let sub = a.root.appending(path: "Sub", directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sub)
    defer {
        // Restored before `TemporaryVault.deinit` tries to remove the tree.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub)
    }
    let recorder = Recorder(.saveAll)

    let switched = await controller.switchVault(to: b.root, presenter: recorder.presenter)

    #expect(!switched)
    #expect(controller.root?.path(percentEncoded: false) == a.root.path(percentEncoded: false))
    #expect(controller.openNote?.text == typed)
    #expect(recorder.reported.count == 1)
    #expect(recorder.reported.first??.titles.contains(title) == true)
    controller.close()
}

@MainActor
@Test func discardSwitchesAndLeavesTheOutgoingFileUnchanged() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let controller = try await openA(a, store: .volatile())
    let typed = body("A") + "modifica da scartare\n"
    controller.updateOpenNoteText(typed)
    let before = try Data(contentsOf: a.root.appending(path: "A.md"))

    let switched = await controller.switchVault(to: b.root, presenter: Recorder(.discard).presenter)

    #expect(switched)
    #expect(try Data(contentsOf: a.root.appending(path: "A.md")) == before)
    #expect(controller.root?.path(percentEncoded: false) == b.root.path(percentEncoded: false))
    #expect(!allTabs(controller).contains { $0.note.text == typed })
    controller.close()
}

@MainActor
@Test func openingAVaultOnAFreshControllerRestoresItsTabs() async throws {
    let a = try TemporaryVault()
    let store = OpenTabsStore.volatile()
    let first = try await openA(a, store: store)
    first.close()

    // `open(_:)` takes no presenter: launch never asks anything.
    let second = VaultController(recents: .volatile(), openTabs: store)
    await second.open(a.root)

    #expect(allTabs(second).map(\.note.relativePath) == ["A.md"])
    second.close()
}
