import Foundation
import Testing
@testable import Pergamenum

// PG-292 (#637): ADR-0068 §D7's engine half. `EMLXLocatorTests` pins the walk's own
// `.indeterminate` answers; this pins what the engine does with one - the message is
// skipped this run, recorded in the outcome's `indeterminateLookups` by `Message-ID`,
// never written, and never marked «non più in Mail».

@Suite(.serialized) struct PraticaSyncIndeterminateTests {
    private typealias Fixtures = PraticaSyncFixtures
    private static let date = Date(timeIntervalSince1970: 1_781_093_170)

    @Test func anIndeterminateLookupIsRecordedAndTheMessageIsNeitherWrittenNorMarkedGone() async throws {
        let body = EmailFixtureCorpus.completeMessageRFC822
            .replacingOccurrences(of: "abc123@rossi-spa.it", with: "msg1@rossi-spa.it")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Messaggio 1", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409, dateSent: Self.date, dateReceived: Self.date,
                emlxBody: body
            )]
        )
        // The predicted path misses, and the fallback walk meets a directory it cannot
        // read with no hit elsewhere: `.indeterminate(.unreadable)`, as the locator's own
        // test produces it.
        let emlx = try #require(Self.firstFile(named: "1.emlx", under: fixture.root))
        try FileManager.default.removeItem(at: emlx)
        let data = try #require(Self.ancestor(named: "Data", of: emlx))
        let locked = data.appending(path: "9/Messages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        }
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<msg1@rossi-spa.it>", date: Self.date)],
            onDisk: [], settings: .default
        )

        let outcome = try await engine.sync(request)

        #expect(outcome.indeterminateLookups == ["<msg1@rossi-spa.it>"])
        #expect(outcome.importedMessageIDs.isEmpty)
        #expect(outcome.noLongerInMail.isEmpty, "an indeterminate lookup is never «non più in Mail»")
        #expect(Fixtures.mdFiles(under: vaultRoot).isEmpty)
    }

    private static func firstFile(named name: String, under root: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    private static func ancestor(named name: String, of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if current.lastPathComponent == name { return current }
            current = current.deletingLastPathComponent()
        }
        return nil
    }
}
