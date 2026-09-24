import Foundation
import Testing
@testable import Pergamenum

/// `DiaryController`'s own races, ADR-0057 §D4/§D5/§D9: every one forced with a `Gate` held at
/// `.willWrite` and settled by counting `.didWrite` calls, never by sleeping.
///
/// Four of the five below are red against today's code, on purpose - the point of this file
/// is to reproduce, deterministically, the three defects ADR-0057 §Context names plus the
/// reordering the ticket itself is about. The fifth is a regression guard that must stay green
/// through the coder pass.

@MainActor
@Test func aNewerSaveIsNeverOverwrittenByAnOlderOne() async throws {
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

    diary.add(title: "Entrata A", startMinutes: 9 * 60, durationMinutes: 30)
    try await waitUntil { heldOnce }

    diary.add(title: "Entrata B", startMinutes: 10 * 60, durationMinutes: 30)

    gate.open()
    try await waitUntil { diary.isSettled }

    #expect(didWriteCount == 2)
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Entrata A"))
    #expect(onDisk.contains("Entrata B"))
    controller.close()
}

@MainActor
@Test func aKeystrokeTypedDuringAWriteIsWrittenToo() async throws {
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

    diary.prose += "Seconda frase.\n"

    gate.open()
    try await waitUntil { didWriteCount == 1 }
    diary.flush()

    try await waitUntil { diaryOnDisk(root)?.contains("Seconda frase.") == true }
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Prima frase."))
    #expect(onDisk.contains("Seconda frase."))
    controller.close()
}

@MainActor
@Test func aDaySwitchWaitsForItsWrite() async throws {
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

    diary.prose += "Frase del giorno.\n"
    diary.move(by: 1)

    #expect(diary.day == testDay)

    gate.open()
    try await waitUntil { didWriteCount == 1 }

    #expect(diary.day == testDay.adding(days: 1))
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase del giorno."))
    controller.close()
}

@MainActor
@Test func comingBackBeforeTheFlushLandedKeepsTheFlushedText() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nScritto in precedenza.\n",
        to: "Diario/20260811.md"
    )
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

    diary.prose += "Frase in sospeso.\n"
    diary.move(by: 1)
    diary.move(by: -1)

    #expect(diary.prose.contains("Frase in sospeso."))

    gate.open()
    try await waitUntil { didWriteCount >= 1 }

    diary.prose += "Frase successiva.\n"
    diary.flush()

    try await waitUntil {
        diaryOnDisk(root)?.contains("Frase in sospeso.") == true
            && diaryOnDisk(root)?.contains("Frase successiva.") == true
    }
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase in sospeso."))
    #expect(onDisk.contains("Frase successiva."))
    controller.close()
}

/// Regression guard for the destination rule (ADR-0057 §D5): `move(by:)` counts from the
/// destination, not from `day`, so two clicks during one flush go two days once that flush
/// lands - even though `day` itself does not move until the queued switch runs behind the
/// held write (the same in-flight shape `aDaySwitchWaitsForItsWrite` asserts).
@MainActor
@Test func twoClicksDuringAFlushGoTwoDays() async throws {
    let vault = try TemporaryVault()
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

    diary.prose += "Frase.\n"
    diary.move(by: 1)
    diary.move(by: 1)

    #expect(diary.day == testDay)

    gate.open()
    try await waitUntil { didWriteCount >= 1 }

    #expect(diary.day == testDay.adding(days: 2))
    controller.close()
}
