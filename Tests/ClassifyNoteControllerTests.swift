import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D3/§D4 and ADR-0067, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 -
// R-03, R-04: the controller door of «Classifica…» (`VaultController.classifyNote`), what it does
// with a dirty tab, and how open tabs follow a move; and the pure preview the sheet draws.
//
// Not driven here, and reported rather than faked: a *stale* `expecting:` on the frontmatter write.
// `NoteBirthSessionTests` documents why (the read and the write share one main-actor turn).

private typealias VaultTag = Pergamenum.Tag

private let topic = VaultTag("topic-x")!

@MainActor
private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(captureNote("Pensiero."), to: "00 Inbox/Idea.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

private func disk(_ path: String, in root: URL) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

private func exists(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

/// Types into the focused tab without saving, the way the editor does.
@MainActor
private func dirty(_ controller: VaultController, adding extra: String = "\nUna riga non salvata.") throws {
    var note = try #require(controller.openNote)
    note.text += extra
    controller.replaceOpenNote(note)
    try #require(controller.openNote?.hasUnsavedChanges == true)
}

// MARK: - A clean tab

@MainActor
@Test func aCleanNoteIsClassifiedThroughTheController() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.openNote(at: "00 Inbox/Idea.md")

    let outcome = try await controller.classifyNote(
        at: "00 Inbox/Idea.md", topics: [topic], toFolder: nil, savingFirst: false
    )

    let text = try disk("00 Inbox/Idea.md", in: vault.root)
    #expect(text.contains("topic-x")) // R-03
    #expect(!text.contains("status-inbox")) // R-03
    #expect(outcome.movedTo == nil)
    #expect(controller.openNote?.text == text, "the open tab follows the write (ADR-0067)")
    controller.close()
}

// MARK: - A dirty tab

@MainActor
@Test func aDirtyTabIsRefusedWithoutSavingFirstAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.openNote(at: "00 Inbox/Idea.md")
    try dirty(controller)
    let before = try disk("00 Inbox/Idea.md", in: vault.root)

    var refused = false
    do {
        _ = try await controller.classifyNote(
            at: "00 Inbox/Idea.md", topics: [topic], toFolder: nil, savingFirst: false
        )
    } catch {
        refused = true
    }

    #expect(refused, "classifying over unsaved edits without saving them first is refused") // R-03
    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == before) // nothing written
    #expect(controller.openNote?.hasUnsavedChanges == true, "the person's edit is untouched")
    controller.close()
}

@MainActor
@Test func savingFirstSavesTheEditThenClassifiesAndTheTabIsReReadAfterTheAwait() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.openNote(at: "00 Inbox/Idea.md")
    try dirty(controller)

    _ = try await controller.classifyNote(
        at: "00 Inbox/Idea.md", topics: [topic], toFolder: nil, savingFirst: true
    )

    let text = try disk("00 Inbox/Idea.md", in: vault.root)
    #expect(text.contains("Una riga non salvata."), "the edit was saved, not lost") // R-03
    #expect(text.contains("topic-x")) // R-03
    #expect(!text.contains("status-inbox"))
    #expect(controller.openNote?.text == text, "the tab was re-read after the await") // ADR-0043 §D7
    #expect(controller.openNote?.hasUnsavedChanges == false)
    controller.close()
}

// MARK: - Open tabs follow a move

@MainActor
@Test func withAFolderEveryTabShowingTheNoteFollowsTheMove() async throws {
    let vault = try TemporaryVault()
    try vault.write(classifiedNote("Esistente."), to: "03 Risorse/Esistente.md")
    let controller = try await opened(vault)
    controller.openNote(at: "00 Inbox/Idea.md")
    controller.splitEditor()
    controller.focusColumn(0)
    try #require(controller.columns.count == 2)
    try #require(controller.columns[1].tabs.contains { $0.note.relativePath == "00 Inbox/Idea.md" })

    let outcome = try await controller.classifyNote(
        at: "00 Inbox/Idea.md", topics: [topic], toFolder: "03 Risorse", savingFirst: false
    )

    #expect(exists("03 Risorse/Idea.md", in: vault.root)) // R-03
    #expect(!exists("00 Inbox/Idea.md", in: vault.root))
    #expect(outcome.moveProblem == nil)
    for column in controller.columns {
        #expect(!column.tabs.contains { $0.note.relativePath == "00 Inbox/Idea.md" }, "a tab still names the old path")
        #expect(column.tabs.contains { $0.note.relativePath == "03 Risorse/Idea.md" }, "every column follows the move")
    }
    controller.close()
}

// MARK: - The preview the sheet draws (R-04)

@Test func theClassifyPreviewStrikesStatusInboxAndMarksTheAddedTopics() throws {
    let current = [VaultTag("type-note")!, VaultTag("status-inbox")!]
    let result = [VaultTag("type-note")!, topic]

    let lines = ClassificaPreview.lines(current: current, result: result)

    let inbox = try #require(lines.first { $0.tag == VaultTag("status-inbox")! })
    #expect(inbox.struck) // R-04: status-inbox struck through
    #expect(!inbox.added)
    let added = try #require(lines.first { $0.tag == topic })
    #expect(added.added) // R-04
    #expect(!added.struck)
    let kept = try #require(lines.first { $0.tag == VaultTag("type-note")! })
    #expect(!kept.struck && !kept.added, "a tag that stays is drawn plain")
    #expect(lines.count == 3)
}

@Test func theCountLabelReadsNOfSevenTags() {
    #expect(ClassificaPreview.countLabel(5) == "5 di 7 tag") // R-04
    #expect(ClassificaPreview.countLabel(1) == "1 di 7 tag")
    #expect(ClassificaPreview.countLabel(7) == "7 di 7 tag")
}
