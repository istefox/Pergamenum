import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.
//
// `PraticaSyncPlan.workItems` and every `PraticaSyncEngine` method are declared-but-
// stubbed by this batch's tester (ADR-0155 §D1) - every test below is red because the
// stub does nothing, not because a symbol is missing. The coder fills in the bodies;
// these tests, unedited, are what proves the fill-in is correct.

@Suite struct PraticaSyncWritePathTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: R-11 - atomic writes, cancel between two messages, resumable from the ledger

    @Test func cancellingBetweenTwoMessagesLeavesOnlyCompleteFilesResumableFromTheLedger() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Prima", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000),
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                ),
                .init(
                    rowID: 2, subject: "Seconda", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000),
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                        .replacingOccurrences(of: "abc123@rossi-spa.it", with: "def456@rossi-spa.it")
                ),
            ]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 2, messageID: "<def456@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000)),
                Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000)),
            ],
            onDisk: [], settings: .default
        )

        let syncTask = Task { try await engine.sync(request) }
        for await progress in await engine.progressStream() where progress.completed == 1 {
            await engine.cancel()
            break
        }
        let outcome = try await syncTask.value

        #expect(outcome.cancelled, "cancel() was called after the first message finished")
        #expect(outcome.writtenFiles.count == 1, "only the message before the cancellation boundary is written")
        #expect(Fixtures.mdFiles(under: vaultRoot).count == 1, "exactly one complete .md file, nothing partial")

        // No temp artefact from an interrupted atomic write is left anywhere in the vault.
        let everyFile = (FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: nil)?
            .allObjects as? [URL]) ?? []
        #expect(!everyFile.contains { $0.lastPathComponent.contains(".tmp") })
    }

    // MARK: R-09 - `.eml` retention, and never for a pending message (ADR §D18)

    @Test func writesEmlBesideTheNoteAndReferencesItWhenRetentionIsOn() async throws {
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

        var settings = PraticheSettings.default
        settings.keepOriginalEML = true
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let mdName = names.first { $0.hasSuffix(".md") }
        let baseName = mdName.map { ($0 as NSString).deletingPathExtension }

        #expect(names.contains { $0.hasSuffix(".eml") }, "no .eml was written")
        if let mdName, let baseName {
            let text = try? String(contentsOf: emailDir.appending(path: mdName), encoding: .utf8)
            #expect(text?.contains("pergamenum-mail-original: \"\(baseName).eml\"") == true)
            // PG-155: the sidecar .eml came out of a mail store, same as an allegati/
            // copy (PG-123) - it must carry com.apple.quarantine too.
            let emlCopy = emailDir.appending(path: "\(baseName).eml", directoryHint: .notDirectory)
            #expect(AttachmentQuarantine.isApplied(to: emlCopy), "the .eml sidecar must carry com.apple.quarantine")
        } else {
            Issue.record("no .md file was written at all")
        }
    }

    @Test func writesNoEmlWhenRetentionIsOff() async throws {
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

        var settings = PraticheSettings.default
        settings.keepOriginalEML = false
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        #expect(!names.contains { $0.hasSuffix(".eml") }, "retention is off; no .eml must exist")
    }

    @Test func neverWritesAnEmlForAPendingMessageEvenWithRetentionOn() async throws {
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

        var settings = PraticheSettings.default
        settings.keepOriginalEML = true
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        let outcome = try await engine.sync(request)

        #expect(outcome.writtenFiles.contains { $0.hasSuffix(".md") }, "the pending .md itself must still be written")
        #expect(!outcome.writtenFiles.contains { $0.hasSuffix(".eml") }, "§D18: no complete RFC 822 bytes exist yet")
    }

    // MARK: ADR-0065 §D8.2 (R-15) - the date is written in the sender's offset

    /// A `Date` carrying `+0900` writes `+09:00` on any machine, whatever its own zone; a message
    /// with no `Date` header falls back to the Envelope Index's epoch, which has no zone, so `Z`.
    @Test func aSyncedMessageCarriesTheHeaderOffset() async throws {
        let original = "Date: Wed, 10 Jun 2026 14:06:10 +0200\r\n"
        let tokyo = EmailFixtureCorpus.completeMessageRFC822
            .replacingOccurrences(of: original, with: "Date: Wed, 10 Jun 2026 14:06:10 +0900\r\n")
        let undated = EmailFixtureCorpus.completeMessageRFC822
            .replacingOccurrences(of: original, with: "")
            .replacingOccurrences(of: "abc123@rossi-spa.it", with: "def456@rossi-spa.it")
        #expect(tokyo != EmailFixtureCorpus.completeMessageRFC822, "the fixture's Date line was not found")
        #expect(!undated.contains("Date:"))

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Tokyo", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: tokyo
                ),
                .init(
                    rowID: 2, subject: "Senza data", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000), emlxBody: undated
                ),
            ]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000)),
                Fixtures.row(rowID: 2, messageID: "<def456@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        var dateLines: [String: String] = [:]
        for name in Fixtures.mdFiles(under: vaultRoot) {
            let text = try String(contentsOf: emailDir.appending(path: name), encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            let id = lines.first { $0.hasPrefix("pergamenum-mail-message-id:") } ?? ""
            dateLines[id] = lines.first { $0.hasPrefix("pergamenum-mail-date:") }
        }
        let tokyoLine = try #require(dateLines[#"pergamenum-mail-message-id: "<abc123@rossi-spa.it>""#])
        let undatedLine = try #require(dateLines[#"pergamenum-mail-message-id: "<def456@rossi-spa.it>""#])
        #expect(tokyoLine == "pergamenum-mail-date: 2026-06-10T14:06:10+09:00")
        #expect(undatedLine.hasSuffix("Z"))
    }
}
