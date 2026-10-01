import Foundation
import Testing
@testable import Pergamenum

// PG-270, burn-down plan docs/plans/burn-down-2026-10-01-pg-270.md.
//
// Reminders were rescheduled on `taskGeneration` alone, which an editor save and an external edit
// never move, so a `@remind` typed in a note notified nothing until the next rescan. The key now
// carries the index generation too; these pin that the two ways the index changes without a scan
// move it, and that an in-app task write still does.

private func reminderNote(_ body: String) -> String {
    "---\ndate: 2026-10-01\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
@Suite(.serialized) struct ReminderRescheduleKeyTests {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(reminderNote("Niente."), to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    // Discriminates against the old key: the save leaves `taskGeneration` where it was, so a key
    // still reading only that would stay equal and fail here.
    @Test func anEditorSaveMovesTheReminderKeyButNotTheTaskGeneration() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let task0 = controller.taskGeneration
        let before = PergamenumApp.reminderKey(for: controller)

        controller.updateOpenNoteText(reminderNote("- [ ] Chiama @remind(2026-10-02 09:00)"))
        await controller.saveOpenNote()

        #expect(controller.taskGeneration == task0)
        #expect(PergamenumApp.reminderKey(for: controller) != before)
        #expect(controller.index.allTasks.contains { $0.text.contains("Chiama") })
        controller.close()
    }

    @Test func typingWithoutSavingLeavesTheReminderKeyAlone() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let before = PergamenumApp.reminderKey(for: controller)

        controller.updateOpenNoteText(reminderNote("- [ ] Chiama @remind(2026-10-02 09:00)"))

        #expect(PergamenumApp.reminderKey(for: controller) == before)
        controller.close()
    }

    @Test func anExternalEditMovesTheReminderKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = PergamenumApp.reminderKey(for: controller)

        try vault.write(reminderNote("- [ ] Chiama @remind(2026-10-02 09:00)"), to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])

        #expect(PergamenumApp.reminderKey(for: controller) != before)
        controller.close()
    }

    @Test func anInAppTaskWriteStillMovesTheReminderKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = PergamenumApp.reminderKey(for: controller)

        controller.recordTaskWrite()

        #expect(PergamenumApp.reminderKey(for: controller) != before)
        controller.close()
    }

    // The guard keeps the pre-change lifecycle: `close()` and the start of `open(_:)` move the
    // key (through `indexGeneration`) but must not wipe the pending reminders.
    @Test func closingAVaultMovesTheKeyButDoesNotReschedule() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        #expect(PergamenumApp.shouldReschedule(controller))
        let before = PergamenumApp.reminderKey(for: controller)

        controller.close()

        #expect(PergamenumApp.reminderKey(for: controller) != before)
        #expect(controller.session == nil)
        #expect(!PergamenumApp.shouldReschedule(controller))
    }

    @Test func aRunWhileTheIndexIsBeingRebuiltDoesNotReschedule() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        var seen: [Bool] = []
        let scan = Task { @MainActor in await controller.rescan() }
        // `rescan()` sets `isScanning` synchronously before its first suspension, so the first
        // yield of this task observes it mid-scan.
        await Task.yield()
        seen.append(PergamenumApp.shouldReschedule(controller))
        await scan.value

        #expect(seen == [false])
        #expect(PergamenumApp.shouldReschedule(controller))
        controller.close()
    }

    // The no-loop guarantee: `reschedule` mints a note id per task-bearing source path, which
    // writes `.pergamenum/note-ids.json`. If that write moved the key, every reschedule would
    // start the next one.
    @Test func mintingANoteIDLeavesTheReminderKeyAlone() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let session = try #require(controller.session)
        let before = PergamenumApp.reminderKey(for: controller)

        let id = session.mintNoteID(for: "Note/N.md")
        await Task.yield()

        #expect(id != nil)
        #expect(PergamenumApp.reminderKey(for: controller) == before)
        controller.close()
    }

    @Test func theKeyDiffersAcrossOpenCloseAndAnotherOpen() async throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        try vaultB.write(reminderNote("Altro."), to: "Note/B.md")
        let controller = try await opened(vaultA)
        let openA = PergamenumApp.reminderKey(for: controller)

        controller.close()
        let closed = PergamenumApp.reminderKey(for: controller)
        await controller.open(vaultB.root)
        let openB = PergamenumApp.reminderKey(for: controller)

        #expect(openA != closed)
        #expect(closed != openB)
        #expect(openA != openB)
        controller.close()
    }
}
