import Foundation
import Testing
@testable import Pergamenum

/// #497: `DiaryController.settle()`, the seam `AppDelegate.applicationShouldTerminate`
/// awaits instead of relying on `willTerminateNotification` (too late to delay anything,
/// per `DiaryController.swift`'s own doc comment on `settle()`). The `AppDelegate` method
/// itself is AppKit lifecycle and not unit-testable; `settle()` is the seam that is.

@MainActor
@Test func settleWaitsForAPendingWriteAndLeavesItOnDisk() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Frase da salvare prima di uscire.\n"
    #expect(!diary.isSettled, "un edit appena fatto deve lasciare qualcosa da scrivere")

    await diary.settle()

    #expect(diary.isSettled)
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase da salvare prima di uscire."))
    // A fresh session reading the same file agrees - the write really reached disk, not
    // only `diary`'s own in-memory `origin`.
    let freshSession = VaultSession(root: root, stateBase: vault.stateBase)
    await freshSession.rescan()
    #expect(try freshSession.read("Diario/20260811.md").text.contains("Frase da salvare prima di uscire."))
    controller.close()
}

@MainActor
@Test func settleWithNothingPendingReturnsPromptlyAndChangesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    #expect(diary.isSettled)
    let before = diaryOnDisk(root)

    await diary.settle()

    #expect(diary.isSettled)
    #expect(diaryOnDisk(root) == before)
    controller.close()
}

/// A save scheduled after the debounce (typing) is still caught: `settle()` calls `flush()`
/// first, which cancels the pending timer and writes immediately, rather than waiting out
/// the 600ms debounce.
@MainActor
@Test func settleFlushesAScheduledSaveRatherThanWaitingOutTheDebounce() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Digitato appena prima di uscire.\n"

    let clock = ContinuousClock()
    let start = clock.now
    await diary.settle()
    let elapsed = start.duration(to: clock.now)

    #expect(diary.isSettled)
    #expect(elapsed < .milliseconds(600), "settle() deve scrivere subito, non aspettare il debounce")
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Digitato appena prima di uscire."))
    controller.close()
}

/// Loops rather than awaiting once (the doc comment's own claim): an operation queued after
/// the runner it was watching finished starts a new runner, and `settle()` must wait for
/// that one too, not return the moment the first `runner` reference goes nil.
@MainActor
@Test func settleWaitsThroughAWriteQueuedWhileTheFirstOneWasHeld() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let gate = Gate()
    var heldOnce = false
    var didWriteCount = 0
    diary.testOnlyWriteHook = { phase in
        switch phase {
        case .willWrite:
            if !heldOnce {
                heldOnce = true
                await gate.wait()
            }
        case .didWrite:
            didWriteCount += 1
        }
    }

    diary.prose += "Prima frase.\n"
    diary.flush()
    try await waitUntil { heldOnce }

    // A second edit arrives while the first write is held - scheduled behind it, not yet run.
    diary.prose += "Seconda frase.\n"

    // `settle()` itself calls `flush()`, which converts the still-scheduled second write into
    // a queued one behind the held first write, then awaits the runner in a loop until both
    // have run.
    let settleTask = Task { await diary.settle() }
    gate.open()
    await settleTask.value
    #expect(didWriteCount == 2)

    #expect(diary.isSettled)
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Prima frase."))
    #expect(onDisk.contains("Seconda frase."))
    controller.close()
}
