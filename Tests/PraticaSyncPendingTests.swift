import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncPendingTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: R-15 - pending body, and the one file a later sync rewrites unasked

    /// This test's second `sync(request)` reuses the first request unchanged -
    /// `onDisk: []` on both calls - so the regeneration below comes from the MAIN
    /// LOOP's `prepare()`, not from `regeneratePending`.
    /// `aPendingBodyRegeneratesOnAnOrdinarySyncOnceTheMessageIsOnDisk` (Regression
    /// section, below) is what exercises `regeneratePending` with the shape
    /// `MembershipRule` actually produces once this message is on disk.
    @Test func aHeadersOnlyMessageIsWrittenPendingAndRegeneratedOnceTheBodyArrives() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1, "the pending message is still written once, as a placeholder")

        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        let firstNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let firstDoc = firstNames.first { $0.hasSuffix(".md") }
            .flatMap { try? String(contentsOf: emailDir.appending(path: $0), encoding: .utf8) }
            .flatMap(MessageDocument.parse)
        #expect(firstDoc?.frontmatter.body == .pending)
        #expect(firstDoc?.newText.isEmpty == false, "a placeholder body, never an empty one")

        // The body has since arrived: the same ROWID's `.emlx` is rewritten in place.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "pending123@rossi-spa.it")
            )],
            in: fixture.root
        )

        let secondOutcome = try await engine.sync(request)
        #expect(secondOutcome.regeneratedPendingFiles.count == 1, "the pending file is rewritten unasked")

        let secondNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let secondDoc = secondNames.first { $0.hasSuffix(".md") }
            .flatMap { try? String(contentsOf: emailDir.appending(path: $0), encoding: .utf8) }
            .flatMap(MessageDocument.parse)
        #expect(secondDoc?.frontmatter.body == .complete, "the body arrived; the file is no longer pending")
    }

    // MARK: R-16 - a vanished row keeps its file, loses its link, is never deleted

    @Test func aMessageWhoseRowDisappearsKeepsItsFilesLosesItsLinkAndIsNeverDeleted() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(firstRequest)

        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        let firstNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let mdName = try #require(firstNames.first { $0.hasSuffix(".md") })
        let mdURL = emailDir.appending(path: mdName)

        // Second sync: the message no longer surfaces among this run's candidates -
        // its row is gone from Mail - but the ledger still remembers importing it. A
        // fresh, separate fixture with no rows at all (rather than rebuilding the same
        // one) is what actually makes `reader.row(forMessageID:)` answer
        // `.notResolvableFromIndex` here: `PraticaSyncEngine.openedReader()` caches its
        // `MailStoreReader` for the actor's lifetime, so a rebuild "in place" at the
        // first fixture's own path would be invisible to this already-open engine.
        let goneFixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let secondEngine = Fixtures.makeEngine(mailStoreURL: goneFixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: ["<abc123@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        #expect(secondOutcome.noLongerInMail == ["<abc123@rossi-spa.it>"])
        #expect(FileManager.default.fileExists(atPath: mdURL.path(percentEncoded: false)), "the file is kept, never deleted")
    }

    // MARK: §D23.1 - the bridge triple is recorded at the write boundary

    // ADR §D23, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 1
    // - `SyncOutcome.bridge`, filled from the `PreparedMessage.rowID`/`.conversationID`
    // fields by the `commit`-time append (§D23.1's own two numbered steps).
    @Test func recordsOneBridgeEntryPerImportedMessageAndNoneForAMessageWithNoConversationID() async throws {
        let messageWithConversation = EmailFixtureCorpus.completeMessageRFC822
        let messageWithoutConversation = EmailFixtureCorpus.completeMessageRFC822
            .replacingOccurrences(of: "abc123@rossi-spa.it", with: "noconv@rossi-spa.it")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Con conversazione", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: messageWithConversation
                ),
                .init(
                    rowID: 2, subject: "Senza conversazione", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000), emlxBody: messageWithoutConversation
                ),
            ]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var withConversation = Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000))
        withConversation.conversationID = 112_409
        var withoutConversation = Fixtures.row(rowID: 2, messageID: "<noconv@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000))
        withoutConversation.conversationID = nil

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [withoutConversation, withConversation],
            onDisk: [], settings: .default
        )
        let outcome = try await engine.sync(request)

        #expect(outcome.writtenFiles.count == 2, "both messages are imported regardless of the bridge")
        #expect(outcome.bridge.count == 1, "only the message with a conversation_id gets a bridge entry")
        let entry = try #require(outcome.bridge.first)
        #expect(entry.messageID == "<abc123@rossi-spa.it>")
        #expect(entry.rowID == 1)
        #expect(entry.conversationID == 112_409)
    }

    /// Its own concern is narrow and deliberate: does the bridge triple get replaced
    /// (not merely appended to) when a regeneration corrects a stale ROWID. Its second
    /// `SyncRequest` puts the same Message-ID in both `candidates` and `onDisk` - the
    /// one combination `MembershipRule.candidates` never actually produces - purely so
    /// `regeneratePending` (now scanning `folder.messagesByID`, so `candidates` plays
    /// no part in reaching it) still finds the message pending and re-decodes it. The
    /// general "does the automatic retry even run" question belongs to the Regression
    /// tests above, not here.
    @Test func aRegenerationOfAPendingMessageRecordsItsBridgeTripleToo() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.bridge.count == 1, "the pending placeholder still gets a bridge triple - §D23.1 is 'outside the isRegeneration branch'")

        // The body has since arrived under a NEW ROWID (Mail's own reindex): the
        // regeneration must replace the triple, not merely add to it.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 99, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "pending123@rossi-spa.it")
            )],
            in: fixture.root
        )
        // `regeneratePending` now resolves the row itself via `reader.row(forMessageID:)`
        // rather than through `candidates` - and `PraticaSyncEngine.openedReader()`
        // caches its `MailStoreReader` for the actor's lifetime, so the rebuild above
        // (same index path) is invisible to `engine`'s already-open reader. A fresh
        // engine on the same (now rebuilt) path is what
        // `aMessageWhoseRowDisappearsKeepsItsFilesLosesItsLinkAndIsNeverDeleted` already
        // does for the same reason.
        let secondEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: ["<pending123@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        #expect(secondOutcome.regeneratedPendingFiles.count == 1)
        #expect(secondOutcome.bridge.count == 1, "the regeneration's own run records exactly its own triple")
        #expect(secondOutcome.bridge.first?.rowID == 99, "the stale ROWID 1 is what this regeneration corrects")
    }
}
