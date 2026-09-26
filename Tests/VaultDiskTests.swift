import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: the disk work of a write moves to one actor, and ordering stops being an accident.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func makeDisk(_ vault: borrowing TemporaryVault) -> VaultDisk {
    let store = NoteStore(root: vault.root)
    let history = NoteHistory(directory: vault.stateBase.appending(path: "history"))
    return VaultDisk(store: store, history: history)
}

// MARK: - A basic write

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

// MARK: - `recordsHistory: false`

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
        // The boundary check throws `VaultBoundary.Violation` for this specific input; this
        // assertion does not pin the error type down, on purpose.
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
