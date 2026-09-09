import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7/8 -
// "R-16/R-26 gap left by batch 4" (ADR follow-up "Task 5/6 implementation notes").
//
// `PraticaLedger.PraticaState` gained `notInStore` this batch so a sync can eventually
// record R-16's outcome and `PraticheController.readTimeline` can read it back into
// R-26's «non più in Mail» caption. The field itself is real (a JSON shape addition,
// not business logic), so its own round trip is green; `readTimeline`'s use of it is
// the tester-declared RED stub (ADR-0155 §D1) - it now takes a `notInStore` parameter
// but still hardcodes `isInMail: true`, ignoring it.

@Suite struct PraticaLedgerNotInStoreTests {
    // MARK: - The field itself round-trips (real code, not a stub)

    @Test func aStateCarryingNotInStoreRoundTripsThroughJSON() throws {
        var state = PraticaLedger.PraticaState.empty
        state.notInStore = ["<gone@rossi-spa.it>"]
        var ledger = PraticaLedger.empty
        ledger.byPraticaPath["01 Progetti/Rossi/Offerta"] = state

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ledger)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PraticaLedger.self, from: data)

        #expect(decoded == ledger)
        #expect(decoded.byPraticaPath["01 Progetti/Rossi/Offerta"]?.notInStore == ["<gone@rossi-spa.it>"])
    }

    /// A ledger written before this field existed (no `notInStore` key at all) must
    /// still decode to `[]`, not reset the whole ledger to `.empty` - the very
    /// regression `PraticaLedger.load(from:)`'s `try?`-to-`.empty` fallback would
    /// otherwise hide as "everything is fine, just empty".
    @Test func aLegacyStateWithNoNotInStoreKeyDecodesToAnEmptyList() throws {
        let json = """
        {
          "lastSyncAt": null,
          "lastOpenedAt": null,
          "importedMessageIDs": ["<a@rossi-spa.it>"],
          "pending": [],
          "entries": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PraticaLedger.PraticaState.self, from: Data(json.utf8))
        #expect(state.notInStore == [])
        #expect(state.importedMessageIDs == ["<a@rossi-spa.it>"])
    }

    // MARK: - `PraticheController.readTimeline` reading it back (RED: R-16/R-26)

    @Test func readTimelineStillReportsInMailForAMessageTheLedgerHasMarkedNotInStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pratica-ledger-\(UUID().uuidString)", directoryHint: .isDirectory)
        let praticaPath = "Rossi/Offerta"
        let messagesFolder = root.appending(path: "\(praticaPath)/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messagesFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let messageID = "<gone@rossi-spa.it>"
        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: messageID, conversationID: 1, direction: .received,
                date: Date(timeIntervalSince1970: 1_749_557_170), received: nil,
                from: "m.rossi@rossi-spa.it", to: [], cc: [], subject: "Offerta",
                attachments: [], body: .complete, original: nil
            ),
            newText: "Testo del messaggio.", quotedHistory: nil, signature: nil
        )
        let text = MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
        try text.write(
            to: messagesFolder.appending(path: "20260610_1406_Rossi_offerta.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let read = PraticheController.readTimeline(
            praticaPath: praticaPath, vaultRoot: root, notInStore: [messageID]
        )

        #expect(read.entries.count == 1)
        // RED: the ledger says this message is gone from Mail, but `readMessages`
        // still hardcodes `isInMail: true` - this must become `false` once the coder
        // reads `notInStore` for real (R-16/R-26).
        #expect(
            read.entries.first?.isInMail == false,
            "readTimeline must mark a message in `notInStore` as no longer in Mail"
        )
    }
}
