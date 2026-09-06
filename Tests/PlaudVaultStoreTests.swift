import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 3 -
// R-10, R-11, R-12.
//
// Every store here is handed a scratch temporary directory, never
// `VaultState.applicationSupportBase()` - that call carries a `precondition` that fires
// under test (`VaultState.swift:67-71`), and ADR-0017 §Consequences already names the cost
// of getting this wrong: 860 stray directories from one afternoon.
@Suite struct PlaudVaultStoreTests {
    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-plaud-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsALedgerWithEntries() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlaudVaultStore(directory: directory)

        var ledger = PlaudVaultStore.Ledger(days: 21, notesFolder: "Trascrizioni", recordings: [:])
        ledger.recordings["2dade977e60e3428deaee7bffc75bd9b"] = PlaudVaultStore.Entry(
            status: "imported",
            notePath: "Registrazioni/20260904_Registrazione_audit-cgm.md",
            quoteFingerprints: ["bisogna mettere in cassette quel numero"],
            pendingConfirmation: [],
            lastImportedAt: "2026-09-05T07:55:24.906Z"
        )

        try store.saveLedger(ledger)

        #expect(store.loadLedger() == ledger)
    }

    @Test func missingFileYieldsDefaults() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlaudVaultStore(directory: directory)

        #expect(store.loadLedger() == .empty)
    }

    @Test func corruptFileYieldsDefaultsWithoutThrowingOrTouchingTheFile() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledgerURL = directory.appending(
            path: PlaudVaultStore.ledgerFileName, directoryHint: .notDirectory
        )
        let corrupt = Data("{ not json at all".utf8)
        try corrupt.write(to: ledgerURL)
        let store = PlaudVaultStore(directory: directory)

        let loaded = store.loadLedger()

        #expect(loaded == .empty)
        // The person may want to recover a hand-edited file: a corrupt `plaud.json` is
        // never deleted or overwritten just because it failed to decode.
        #expect(try Data(contentsOf: ledgerURL) == corrupt)
    }

    @Test func clampsDaysToTheServicesAcceptedRangeOnRead() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledgerURL = directory.appending(
            path: PlaudVaultStore.ledgerFileName, directoryHint: .notDirectory
        )
        // The service returns 400 invalid_days outside 1...3650 (measured live; SPEC Edge
        // cases) - a hand-edited plaud.json holding 99999 must not survive the read.
        try Data(#"{"days":99999,"notesFolder":"Registrazioni","recordings":{}}"#.utf8)
            .write(to: ledgerURL)
        let store = PlaudVaultStore(directory: directory)

        #expect(store.loadLedger().days == PlaudVaultStore.maximumDays)
    }

    @Test func discardsADraftWhenGeneratedAtDiffersButKeepsItWhenItMatches() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlaudVaultStore(directory: directory)
        let recordingID = "2dade977e60e3428deaee7bffc75bd9b"
        try store.saveDrafts([
            recordingID: PlaudVaultStore.Draft(
                generatedAt: "2026-09-05T07:54:16.838Z",
                decisions: ["7cec8849-f9be-4090-983e-9578e9cc6bb8": true],
                speakerRenames: ["Speaker 1": "Stefano"]
            ),
        ])

        // Same generated_at as stored: task ids are still the ones the decisions were made
        // against, so the draft survives (R-10's boundary, kept side).
        #expect(
            store.draft(for: recordingID, currentGeneratedAt: "2026-09-05T07:54:16.838Z")?.decisions
                == ["7cec8849-f9be-4090-983e-9578e9cc6bb8": true]
        )

        // A re-run produced a new generated_at: task ids are no longer the same set, so
        // carrying the old decisions forward would silently apply them to different tasks
        // (R-10's boundary, discarded side; ADR §D12).
        #expect(store.draft(for: recordingID, currentGeneratedAt: "2026-09-05T08:10:00.000Z") == nil)
    }

    @Test func twoVaultsDoNotSeeEachOthersLedger() throws {
        let directoryA = try makeScratchDirectory()
        let directoryB = try makeScratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }
        let storeA = PlaudVaultStore(directory: directoryA)
        let storeB = PlaudVaultStore(directory: directoryB)

        var ledgerA = PlaudVaultStore.Ledger.empty
        ledgerA.recordings["265473800bc50a6cdfc7a602f390d1d3"] = PlaudVaultStore.Entry(status: "ready")
        try storeA.saveLedger(ledgerA)

        #expect(storeA.loadLedger() == ledgerA)
        #expect(storeB.loadLedger() == .empty)
        #expect(storeB.loadLedger().recordings["265473800bc50a6cdfc7a602f390d1d3"] == nil)
    }
}
