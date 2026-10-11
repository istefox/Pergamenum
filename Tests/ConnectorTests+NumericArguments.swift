import Foundation
import Testing
@testable import Pergamenum

// The connector layer's numeric arguments (ADR-0063 §D1, ADR-0075 §D4): a `limit`, a block's
// duration or a view ordinal that cannot be honoured is one usage sentence, never clamped and
// never ignored. Moved out of `ConnectorTests.swift` unchanged, for its length.

// MARK: - ADR-0063 §D1: a malformed `limit` is one usage sentence, and `0` answers empty

/// The sentence a refused `limit` produces, read off the rule itself so every test
/// below compares against the same words.
private func limitSentence(_ attempt: () throws -> Any?) -> ConnectorError? {
    do {
        _ = try attempt()
        return nil
    } catch let error as ConnectorError {
        return error
    } catch {
        return nil
    }
}

@Test func aNegativeLimitIsOneUsageSentence() throws {
    let error = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description.contains("limit"))
    #expect(error.description.contains("-1"))
    // Absent and zero are both legal.
    #expect(try VaultAPI.checkedLimit(nil) == nil)
    #expect(try VaultAPI.checkedLimit(0) == 0)
}

@Test func unreadableLimitTextIsTheSameSentence() throws {
    let unreadable = try #require(limitSentence { try VaultAPI.limit(parsing: "abc") })
    #expect(unreadable.isUsage)
    #expect(unreadable.description.contains("abc"))
    // An empty value is not «no limit given»: the caller typed the option and left it blank.
    let empty = try #require(limitSentence { try VaultAPI.limit(parsing: "") })
    #expect(empty.isUsage)

    // The same sentence as a negative number, apart from the raw value it quotes.
    let negative = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(unreadable.description.replacingOccurrences(of: "abc", with: "-1") == negative.description)

    // `-1` is a number: the text rule reads it and leaves the refusal to `checkedLimit`.
    #expect(try VaultAPI.limit(parsing: "-1") == -1)
    #expect(try VaultAPI.limit(parsing: nil) == nil)
}

@MainActor
@Test func journalLogRefusesANegativeLimitBeforeAnyDiskWork() throws {
    // A vault this process never opened: the state lookup would say «vault mai aperto».
    // The usage error must win, because it is the caller's mistake whatever the vault.
    let vault = try TemporaryVault()
    let error = try #require(limitSentence {
        try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: -1)
    })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

@MainActor
@Test func searchRefusesANegativeLimit() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    let error = try #require(limitSentence { try VaultAPI.search(session, "Corpo", limit: -1) })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

@MainActor
@Test func searchWithLimitZeroAnswersEmpty() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    // The query matches: the positive control proves `0` is what empties the answer.
    #expect(try VaultAPI.search(session, "Corpo", limit: nil).count == 1)
    #expect(try VaultAPI.search(session, "Corpo", limit: 0).isEmpty)
}

@MainActor
@Test func journalLogWithLimitZeroAnswersEmpty() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")
    #expect(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).count == 1)
    #expect(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: 0).isEmpty)
}

@MainActor
@Test func journalLogRefusesANegativeLimitOnAnOpenedVault() async throws {
    // Before ADR-0063 this reached `suffix(-1)` and trapped the process: written only
    // together with the guard, so it can never take the test host down with it.
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")

    let error = try #require(limitSentence {
        try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: -1)
    })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

// MARK: - A block's duration (ADR-0075 §D4)

/// The refusal an `addTimeBlock` call threw, or nil when it did not throw one.
@MainActor
private func blockRefusal(
    _ session: VaultSession, minutes: Int, on day: String = "2026-08-20"
) async -> ConnectorError? {
    do {
        _ = try await VaultAPI.addTimeBlock(session, title: "Blocco", at: "09:00", minutes: minutes, on: day)
        return nil
    } catch let error as ConnectorError {
        return error
    } catch {
        return nil
    }
}

/// Refused, never clamped, and before anything is written: the daily note is not even
/// created (R-08).
@MainActor
@Test(arguments: [0, 4, 481, -5])
func aDurationOutsideTheRangeIsOneUsageSentence(_ minutes: Int) async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "add_time_block", dryRun: false)

    let error = try #require(await blockRefusal(session, minutes: minutes))

    #expect(error.isUsage)
    #expect(error.description.contains("minutes"))
    #expect(error.description.contains("«\(minutes)»"))
    let note = vault.root.appending(path: "Calendar/20260820.md")
    #expect(!FileManager.default.fileExists(atPath: note.path(percentEncoded: false)))
}

@MainActor
@Test func aRehearsalRefusesAnOutOfRangeDurationToo() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "add_time_block", dryRun: true)

    let error = try #require(await blockRefusal(session, minutes: 481))
    #expect(error.isUsage)
}

@MainActor
@Test(arguments: [5, 480])
func theRangeBoundsAreAccepted(_ minutes: Int) async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "add_time_block", dryRun: false)

    #expect(await blockRefusal(session, minutes: minutes) == nil)
    #expect(try VaultAPI.day(session, on: "2026-08-20").blocks.count == 1)
}

/// A block cut short at the next one is written shorter than asked, and the payload says
/// so rather than leaving it to be found on the timeline later.
@MainActor
@Test func aShortenedBlockSaysSo() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    VaultAPI.arm(session, command: "add_time_block", dryRun: false)

    _ = try await VaultAPI.addTimeBlock(session, title: "Riunione", at: "10:00", minutes: 60, on: "2026-08-20")
    let summary = try await VaultAPI.addTimeBlock(
        session, title: "Preparare", at: "09:45", minutes: 60, on: "2026-08-20"
    )

    #expect(summary.note?.contains("accorciato a 15 minuti") == true)
    let block = try #require(try VaultAPI.day(session, on: "2026-08-20").blocks.first { $0.title == "Preparare" })
    #expect(block.start == "09:45")
    #expect(block.end == "10:00")
}

@Test func unreadableDurationTextIsTheSameSentence() throws {
    let unreadable = try #require(limitSentence { try VaultAPI.blockMinutes(parsing: "abc") })
    #expect(unreadable.isUsage)
    #expect(unreadable.description.contains("minutes"))
    #expect(unreadable.description.contains("«abc»"))
    let empty = try #require(limitSentence { try VaultAPI.blockMinutes(parsing: "") })
    #expect(empty.isUsage)
    #expect(unreadable.description.replacingOccurrences(of: "abc", with: "481")
        == VaultAPI.durationRefusal(raw: "481").description)

    #expect(try VaultAPI.blockMinutes(parsing: nil) == nil)
    #expect(try VaultAPI.blockMinutes(parsing: "45") == 45)
}

@Test func unreadableOrdinalTextIsRefusedNotIgnored() throws {
    // PG-272: `--ordinal abc` read as «no ordinal», which on a note with one view ran that
    // view as if the person had asked for it.
    let unreadable = try #require(limitSentence { try VaultAPI.viewOrdinal(parsing: "abc") })
    #expect(unreadable.isUsage)
    #expect(unreadable.description.contains("ordinal"))
    #expect(unreadable.description.contains("«abc»"))
    #expect(try #require(limitSentence { try VaultAPI.viewOrdinal(parsing: "") }).isUsage)

    #expect(try VaultAPI.viewOrdinal(parsing: nil) == nil)
    #expect(try VaultAPI.viewOrdinal(parsing: "2") == 2)
    // The range is `runView`'s question, asked once it knows how many views there are.
    #expect(try VaultAPI.viewOrdinal(parsing: "-1") == -1)
}
