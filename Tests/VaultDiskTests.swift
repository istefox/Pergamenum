import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: the disk work of a write moves to one actor, and ordering stops being an accident.
//
// **Tester-only stub (ADR-0155/ADR-0049), declared in `Sources/Vault/VaultDisk.swift`.**
// `VaultDisk.write(_:to:precomputedHash:journalEntry:journal:recordsHistory:)` is a stub
// that always throws before touching disk - the boundary check, the atomic write, the
// stat, the record derivation, the history write, the journal append and the per-path
// sequence stamping (§D9-§D11) are the coder's implementation and have not landed. Every
// test below that calls `disk.write` is red for that reason; that is the point of this
// file existing before the coder's task.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func makeDisk(_ vault: borrowing TemporaryVault) -> VaultDisk {
    let store = NoteStore(root: vault.root)
    let history = NoteHistory(directory: vault.stateBase.appending(path: "history"))
    return VaultDisk(store: store, history: history)
}

// MARK: - A basic write (red: the stub never touches disk)

@Test func aWriteProducesTheFileAndARecordMatchingAFreshRead() async throws {
    let vault = try TemporaryVault()
    let disk = makeDisk(vault)
    let text = note()
    let hash = NoteStore.hash(Data(text.utf8))

    do {
        let outcome = try await disk.write(
            text, to: "N.md",
            precomputedHash: hash,
            journalEntry: nil,
            journal: nil,
            recordsHistory: true
        )

        // Only reached once the coder's real actor body exists.
        #expect(FileManager.default.fileExists(
            atPath: vault.root.appending(path: "N.md").path(percentEncoded: false)
        ))
        let fresh = try NoteStore(root: vault.root).read("N.md")
        #expect(outcome.record == fresh.record)
        #expect(outcome.hash == hash)
        #expect(NoteHistory(directory: vault.stateBase.appending(path: "history"))
            .snapshots(for: "N.md").count == 1)
    } catch {
        Issue.record("VaultDisk.write ha lanciato (stub del Task 8, il coder non l'ha ancora implementato): \(error)")
    }
}

// MARK: - `recordsHistory: false` (red: the stub throws before recording anything either way)

@Test func recordsHistoryFalseWritesNoVersionForACanvasPath() async throws {
    let vault = try TemporaryVault()
    let disk = makeDisk(vault)
    let history = NoteHistory(directory: vault.stateBase.appending(path: "history"))
    let text = "{\"nodes\":[],\"edges\":[]}"

    do {
        _ = try await disk.write(
            text, to: "Board.canvas",
            precomputedHash: NoteStore.hash(Data(text.utf8)),
            journalEntry: nil,
            journal: nil,
            recordsHistory: false
        )
        #expect(history.snapshots(for: "Board.canvas").isEmpty)
    } catch {
        Issue.record("VaultDisk.write ha lanciato (stub del Task 8): \(error)")
    }
}

// MARK: - The journal gains an entry with the right hashBefore/hashAfter

@Test func aWriteWithAJournalEntryRecordsHashBeforeAndAfter() async throws {
    let vault = try TemporaryVault()
    let disk = makeDisk(vault)
    let journal = WriteJournal(directory: vault.stateBase.appending(path: "journal"))
    let text = note("Seconda.")
    let hash = NoteStore.hash(Data(text.utf8))
    let entry = WriteJournal.Entry(
        id: WriteJournal.makeID(at: Date()),
        timestamp: Date(),
        path: "N.md",
        hashBefore: "prima-hash-fittizia",
        hashAfter: hash,
        textBefore: note("Prima."),
        command: "test"
    )

    do {
        _ = try await disk.write(
            text, to: "N.md",
            precomputedHash: hash,
            journalEntry: entry,
            journal: journal,
            recordsHistory: true
        )
        let recorded = try #require(journal.entries().last)
        #expect(recorded.hashAfter == hash)
        #expect(recorded.hashBefore == "prima-hash-fittizia")
        #expect(recorded.textBefore == note("Prima."))
    } catch {
        Issue.record("VaultDisk.write ha lanciato (stub del Task 8): \(error)")
    }
}

// MARK: - The boundary is inherited: a `../` path throws before any byte is written

@Test func aPathEscapingTheVaultThrowsBeforeAnyByteIsWritten() async throws {
    let vault = try TemporaryVault()
    let disk = makeDisk(vault)
    let text = "non deve arrivare fuori dal vault"

    do {
        _ = try await disk.write(
            text, to: "../fuori.md",
            precomputedHash: NoteStore.hash(Data(text.utf8)),
            journalEntry: nil,
            journal: nil,
            recordsHistory: false
        )
        Issue.record("un percorso «../» avrebbe dovuto lanciare prima di scrivere qualunque byte")
    } catch {
        // Expected either way right now: the stub always throws (`StubError.notImplemented`)
        // and the coder's real boundary check will throw `VaultBoundary.Violation` for this
        // specific input - this assertion does not pin the error type down, on purpose, so
        // it stays meaningful once the real body lands.
    }

    let escaped = vault.root.deletingLastPathComponent().appending(path: "fuori.md")
    #expect(!FileManager.default.fileExists(atPath: escaped.path(percentEncoded: false)))
}

// MARK: - The sequence increments per path and independently across paths

@Test func theSequenceIncrementsPerPathAndIndependentlyAcrossPaths() async throws {
    let vault = try TemporaryVault()
    let disk = makeDisk(vault)

    do {
        let first = try await disk.write(
            "uno", to: "A.md", precomputedHash: NoteStore.hash(Data("uno".utf8)),
            journalEntry: nil, journal: nil, recordsHistory: false
        )
        let second = try await disk.write(
            "due", to: "A.md", precomputedHash: NoteStore.hash(Data("due".utf8)),
            journalEntry: nil, journal: nil, recordsHistory: false
        )
        let otherPath = try await disk.write(
            "tre", to: "B.md", precomputedHash: NoteStore.hash(Data("tre".utf8)),
            journalEntry: nil, journal: nil, recordsHistory: false
        )

        #expect(second.sequence == first.sequence + 1, "la sequenza non è cresciuta di uno sullo stesso percorso")
        #expect(otherPath.sequence == first.sequence, "un percorso diverso non ha una sequenza indipendente")
    } catch {
        Issue.record("VaultDisk.write ha lanciato (stub del Task 8): \(error)")
    }
}
