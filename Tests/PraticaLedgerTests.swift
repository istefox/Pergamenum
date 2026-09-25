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

// PG-172, ADR-0052 §D3 (`docs/plans/pg-172-pratiche-ledger-marker.md`, Task 1) - R-03, R-04,
// R-05. `PraticaLedger.read(from:)` tells «not there yet» from «there and unreadable», the one
// distinction a writer needs before it saves: the first is a creation, the second a destruction.
// The whole decision is the classification, so each of the three answers is pinned and so is
// the direction of each mistake: a missing file called unreadable would refuse every first
// write (R-03), an unreadable one called missing would be saved over (R-04).
@Suite struct PraticaLedgerReadTests {
    /// A ledger path inside a fresh temporary directory, which the caller removes.
    private static func scratch() throws -> (directory: URL, ledger: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pratica-ledger-read-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appending(path: PraticaLedger.fileName, directoryHint: .notDirectory))
    }

    @Test func aMissingLedgerFileReadsAsMissing() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(PraticaLedger.read(from: url) == .missing)
    }

    @Test func aLedgerWithNoParentDirectoryYetReadsAsMissing() {
        // The state directory does not exist on a vault's first run: `Data(contentsOf:)` throws a
        // different `CocoaError` there than for a missing file inside an existing directory, and
        // both are «not there yet».
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pratica-ledger-none-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "pratiche/ledger.json", directoryHint: .notDirectory)

        #expect(PraticaLedger.read(from: url) == .missing)
    }

    @Test func aLedgerWrittenByThisBuildReadsAsLoaded() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = PraticaLedger.PraticaState.empty
        state.importedMessageIDs = ["<a@rossi-spa.it>"]
        state.trayCount = 3
        // Whole seconds only: the file stores ISO 8601 and drops the fraction.
        state.lastOpenedAt = Date(timeIntervalSince1970: 1_749_557_170)
        var ledger = PraticaLedger.empty
        ledger.byPraticaPath["01 Progetti/Rossi/Offerta"] = state
        try ledger.save(to: url)

        #expect(PraticaLedger.read(from: url) == .loaded(ledger))
    }

    @Test func anEmptyLedgerWrittenByThisBuildReadsAsLoadedNotMissing() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try PraticaLedger.empty.save(to: url)

        #expect(PraticaLedger.read(from: url) == .loaded(.empty), "a file that decodes to nothing is still a file")
    }

    @Test func corruptJSONReadsAsUnreadable() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not json".utf8).write(to: url)

        #expect(PraticaLedger.read(from: url) == .unreadable)
    }

    @Test func anEmptyFileReadsAsUnreadable() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: url)

        // `.empty` is not what zero bytes mean: it is a file somebody, or a crash, left behind.
        #expect(PraticaLedger.read(from: url) == .unreadable)
    }

    @Test func validJSONOfAnotherShapeReadsAsUnreadable() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A schema this build does not know: well-formed JSON that is not a ledger.
        try Data(#"["a", "b"]"#.utf8).write(to: url)

        #expect(PraticaLedger.read(from: url) == .unreadable)
    }

    @Test func aDirectoryAtTheLedgersPathReadsAsUnreadable() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // There is something there and it is not a ledger: saving over it is not a creation.
        #expect(PraticaLedger.read(from: url) == .unreadable)
    }

    /// The other side of R-05: only a genuinely undecodable file is refused. `PraticaState`'s
    /// lenient decoder is what lets a FORMAT addition survive, and a ledger written before
    /// `notInStore` and `trayCount` existed must keep reading as loaded, or the refusal would
    /// turn every upgrade into a ledger nobody may write.
    @Test func aLegacyLedgerWithNoNotInStoreKeyStillReadsAsLoaded() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "byPraticaPath": {
            "01 Progetti/Rossi/Offerta": {
              "lastSyncAt": null,
              "lastOpenedAt": null,
              "importedMessageIDs": ["<a@rossi-spa.it>"],
              "pending": [],
              "entries": []
            }
          }
        }
        """
        try Data(json.utf8).write(to: url)

        guard case .loaded(let ledger) = PraticaLedger.read(from: url) else {
            Issue.record("a ledger from before `notInStore` existed must still read as loaded")
            return
        }
        let state = ledger.byPraticaPath["01 Progetti/Rossi/Offerta"]
        #expect(state?.importedMessageIDs == ["<a@rossi-spa.it>"])
        #expect(state?.notInStore == [])
        #expect(state?.trayCount == 0)
    }

    /// The connector-facing signature (`VaultAPI.pratiche(_:)`) keeps its exact answer: a reader
    /// wants `.empty` for both, and only a writer asks `read(from:)`.
    @Test func loadStillAnswersEmptyForMissingAndForUnreadable() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(PraticaLedger.load(from: url) == .empty, "missing")

        try Data("{ not json".utf8).write(to: url)
        #expect(PraticaLedger.load(from: url) == .empty, "unreadable")
    }

    @Test func loadStillAnswersTheLedgerForALoadedFile() throws {
        let (directory, url) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        var ledger = PraticaLedger.empty
        ledger.byPraticaPath["01 Progetti/Rossi/Offerta"] = .empty
        try ledger.save(to: url)

        #expect(PraticaLedger.load(from: url) == ledger)
    }
}

// PG-134/#234: `MailStorePreparation.resolveFollowedConversations` used to hand-copy
// `memberMessageIDs`'s own filter over `state.entries` instead of calling it, because
// its call site only has flat `[PraticaLedger.Entry]` (already scoped to one pratica),
// never a whole `PraticaLedger` plus a path. `memberMessageIDs(in:forConversation:)` is
// the entries-only overload that closes that gap; the instance method now calls it too.
@Suite struct PraticaLedgerMemberMessageIDsTests {
    private static func entry(_ messageID: String, conversation: Int) -> PraticaLedger.Entry {
        PraticaLedger.Entry(messageID: messageID, rowID: 1, conversationID: conversation)
    }

    @Test func returnsOnlyTheEntriesOfTheRequestedConversation() {
        let entries = [
            Self.entry("<a@rossi-spa.it>", conversation: 1),
            Self.entry("<b@rossi-spa.it>", conversation: 2),
            Self.entry("<c@rossi-spa.it>", conversation: 1),
        ]
        #expect(
            Set(PraticaLedger.memberMessageIDs(in: entries, forConversation: 1))
                == Set(["<a@rossi-spa.it>", "<c@rossi-spa.it>"])
        )
    }

    @Test func theInstanceMethodAgreesWithTheEntriesOnlyOverload() {
        var ledger = PraticaLedger.empty
        var state = PraticaLedger.PraticaState.empty
        state.entries = [
            Self.entry("<a@rossi-spa.it>", conversation: 1),
            Self.entry("<b@rossi-spa.it>", conversation: 2),
        ]
        ledger.byPraticaPath["01 Progetti/Rossi/Offerta"] = state

        #expect(
            ledger.memberMessageIDs(forConversation: 1, praticaPath: "01 Progetti/Rossi/Offerta")
                == PraticaLedger.memberMessageIDs(in: state.entries, forConversation: 1)
        )
    }
}
