import Foundation
import Testing
@testable import Pergamenum

// ADR-0053, plan `docs/plans/ui-suite-replacement.md` Task 5, PR 4 (Sidebar move). No seam, no
// production change: `VaultController.moveNote` (`VaultController+Files.swift`) already does
// three things beyond the file move itself - refuses while the note has unsaved edits
// (`canOperate(on:)`), turns a thrown error or a reported refusal into `recordProblem`, and
// rescans before following an open tab to the note's new path - and none of the three was under
// test, per the census this plan's §2 re-verified.
//
// Converts `UITests/SidebarMoveUITests.swift:124`
// (`testMovingANoteRowViaTheMenuMovesTheFile_R03`): a note's «Sposta in ▸» moves the file. The GUI
// test stays in place until `--affected` has proved the collapse (SPEC R-10); deleting it is a
// later step, not part of this file.
//
// No RED note: `moveNote` already exists and already works, so every assertion below is a real
// one from the first run, the same "no seam" shape `Tests/PraticheControllerTests.swift`'s
// `selectedTray`/`dismissRegeneration` additions (PR 3) already used for this plan.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-22\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func exists(_ relativePath: String, at root: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: root.appending(path: relativePath).path(percentEncoded: false)
    )
}

// MARK: - `canOperate(on:)`: a dirty tab refuses the move (SidebarMove :124's own move, refused)

@MainActor
@Test func moveNoteRefusesWhileTheNoteHasUnsavedEditsAndMovesNothingOnDisk() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    let root = vault.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)
    controller.openNote(at: "A/x.md")
    controller.updateOpenNoteText(note("Modifica non salvata."))
    try #require(controller.openNote?.hasUnsavedChanges == true)

    let moved = await controller.moveNote(at: "A/x.md", toFolder: "Target")

    #expect(!moved)
    #expect(exists("A/x.md", at: root))
    #expect(!exists("Target/x.md", at: root))
    #expect(
        controller.problems.contains(VaultController.unsavedNoteRefusal),
        "\(controller.problems)"
    )
    controller.close()
}

// MARK: - `recordProblem`: a thrown error from the session's own move is reported, not swallowed

@MainActor
@Test func moveNoteRecordsTheCollisionAndMovesNothingWhenTheDestinationIsAlreadyTaken() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    try vault.write(note(), to: "Target/x.md")
    let root = vault.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)

    let moved = await controller.moveNote(at: "A/x.md", toFolder: "Target")

    #expect(!moved)
    #expect(exists("A/x.md", at: root), "una collisione non deve spostare nulla")
    #expect(
        controller.problems.contains { $0.contains("esiste già: Target/x.md") },
        "\(controller.problems)"
    )
    controller.close()
}

// MARK: - The success path: moves the file, rescans, and follows an open tab to the new path

@MainActor
@Test func moveNoteMovesTheFileRescansAndFollowsTheOpenTabToItsNewPath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    let root = vault.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)
    controller.openNote(at: "A/x.md")
    #expect(controller.openNote?.relativePath == "A/x.md")

    let moved = await controller.moveNote(at: "A/x.md", toFolder: "Target")

    #expect(moved)
    #expect(controller.problems.isEmpty, "\(controller.problems)")
    // `movedNote` runs after `rescan()` inside the same fire-and-forget `Task` (§D "rescan
    // behaviour"), so waiting for the tab to follow also waits for the rescan to have happened.
    try await waitUntil { controller.openNote?.relativePath == "Target/x.md" }

    #expect(exists("Target/x.md", at: root))
    #expect(!exists("A/x.md", at: root))
    #expect(controller.openNote?.relativePath == "Target/x.md")
    // The rescan itself, read off the index rather than inferred from the tab follow alone.
    #expect(controller.index.note(at: "Target/x.md") != nil)
    #expect(controller.index.note(at: "A/x.md") == nil)
    controller.close()
}

// MARK: - The success path with nothing open: no tab to follow, still moves and rescans

@MainActor
@Test func moveNoteMovesTheFileAndRescansWithNoOpenTabToFollow() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    let root = vault.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)

    let moved = await controller.moveNote(at: "A/x.md", toFolder: "Target")

    #expect(moved)
    #expect(controller.problems.isEmpty, "\(controller.problems)")
    try await waitUntil { controller.index.note(at: "Target/x.md") != nil }

    #expect(exists("Target/x.md", at: root))
    #expect(!exists("A/x.md", at: root))
    controller.close()
}
