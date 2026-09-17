import Foundation
import Testing
@testable import Pergamenum

/// The scaffolding every `PraticaSyncEngine` suite shares: a throwaway vault-shaped
/// directory, a fixture engine that writes straight into it, the one pratica folder
/// every fixture message belongs to, and the handful of on-disk readbacks (`.md`
/// names, attachment names, parsed `MessageDocument`s) a test needs to check what the
/// engine actually wrote.
///
/// In a file of its own for the reason `EmbedEditorTestSupport` is: nine suites need
/// it - `PraticaSyncPlanTests`, `PraticaSyncWritePathTests`, `PraticaSyncAttachmentTests`,
/// `PraticaSyncIntegrityTests`, `PraticaSyncInlineImageTests`, `PraticaSyncThresholdTests`,
/// `PraticaSyncPendingTests`, `PraticaSyncRetryTests` and `PraticaSyncRepairTests` (plus
/// `PraticaRegenerationTests` for its `makeEngine`/`praticaFolder` half) - and a copy in
/// each is a copy that drifts.
internal enum PraticaSyncFixtures {
    static func sampleDossier(
        counterparts: [String] = ["m.rossi@rossi-spa.it"],
        conversations: [Int] = [112_409]
    ) -> Dossier {
        Dossier(
            schemaVersion: 1, counterparts: counterparts, conversations: conversations,
            keywords: [], included: [], excluded: [], ignored: []
        )
    }

    static func row(
        rowID: Int,
        messageID: String,
        mailboxURL: String = "ews://acct1/INBOX",
        date: Date = Date(timeIntervalSince1970: 1_749_557_170),
        deleted: Bool = false
    ) -> MailMessageRow {
        MailMessageRow(
            rowID: rowID, indexMessageIDHash: nil, globalMessageID: nil,
            subject: "Richiesta offerta", sender: "m.rossi@rossi-spa.it",
            dateSent: date, dateReceived: date,
            mailbox: MailboxRef(rowID: 1, url: mailboxURL),
            conversationID: 112_409, deleted: deleted, messageID: messageID
        )
    }

    /// A throwaway vault-shaped directory (no `VaultSession`, no note index - the
    /// engine's own attachment/`.eml` writes are plain files, and the one `.md` hop
    /// this closure stands in for is `VaultSession.write`'s job in production).
    static func makeVaultRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-pratica-sync-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `PraticaRegenerationTests`' own vault root - kept separate from `makeVaultRoot()`
    /// rather than merged: the two differ only in the temp-directory prefix, and merging
    /// them would silently rename a directory a failing test prints.
    static func makeRegenerationVaultRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-pratica-regen-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeEngine(mailStoreURL: URL, vaultRoot: URL) -> PraticaSyncEngine {
        PraticaSyncEngine(mailStoreURL: mailStoreURL, vaultRoot: vaultRoot) { text, relativePath in
            let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    static let praticaFolder = "01 Progetti/Rossi/Offerta 2026"

    static func mdFiles(under vaultRoot: URL, folder: String = praticaFolder) -> [String] {
        let emailDir = vaultRoot.appending(path: "\(folder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
    }

    static func allegatiFiles(under vaultRoot: URL, folder: String = praticaFolder) -> [String] {
        let dir = vaultRoot.appending(path: "\(folder)/allegati", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []).sorted()
    }

    /// Every message note currently on disk, parsed, in file-name order - Tasks 4/5's
    /// tests read the attachment lists back through `MessageDocument`, never by
    /// grepping the rendered text.
    static func messageDocuments(under vaultRoot: URL, folder: String = praticaFolder) throws -> [MessageDocument] {
        let emailDir = vaultRoot.appending(path: "\(folder)/email", directoryHint: .isDirectory)
        return try Self.mdFiles(under: vaultRoot, folder: folder).map { name in
            let text = try String(contentsOf: emailDir.appending(path: name), encoding: .utf8)
            return try #require(MessageDocument.parse(text), "\(name) must parse back as a message note")
        }
    }

    /// The single message note this test's sync produced - fails loudly (`#require`)
    /// rather than silently reading `nil` when a test's own setup wrote zero or more
    /// than one, which would otherwise misreport as "no attachments" everywhere below.
    static func onlyMessageDocument(under vaultRoot: URL, folder: String = praticaFolder) throws -> MessageDocument {
        let documents = try Self.messageDocuments(under: vaultRoot, folder: folder)
        return try #require(documents.first, "expected exactly one message note, found \(documents.count)")
    }

    static func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.modificationDate] as? Date)
    }

    /// The single note this suite's fixtures produce, and its raw file URL - unlike
    /// `onlyMessageDocument`, this keeps the text as written so a test can compare
    /// byte-for-byte rather than through `MessageDocument.parse`'s round trip.
    static func onlyNoteURLAndText(under vaultRoot: URL) throws -> (url: URL, text: String) {
        let emailDir = vaultRoot.appending(path: "\(praticaFolder)/email", directoryHint: .isDirectory)
        let name = try #require(Self.mdFiles(under: vaultRoot).first, "expected exactly one message note")
        let url = emailDir.appending(path: name, directoryHint: .notDirectory)
        return (url, try String(contentsOf: url, encoding: .utf8))
    }

    /// ADR-0048: writes `bytes` where Mail itself would, when it externalizes a part
    /// instead of leaving it inline - the sibling `Attachments/<rowID>/<part>/<name>`
    /// directory `EMLXReader.attachmentsDirectory(forMessageAt:rowID:part:)` computes.
    ///
    /// Locates the `.emlx` `MailStoreFixture.build` already wrote for `rowID` by a
    /// plain recursive search under `fixture.root`, rather than re-deriving
    /// `MailStoreFixture`'s own private fan-out digits a third time (`PraticaSyncEngine`
    /// already duplicates that arithmetic nowhere - `EMLXLocator`/`MailStoreReader` are
    /// the only production readers of the layout, and neither exposes it for a test to
    /// call). A rowID collision is not possible: `MailStoreFixture.build` writes exactly
    /// one `.emlx` per message, named after its own unique rowID.
    static func writeExternalizedAttachment(
        _ bytes: Data, named name: String, rowID: Int, part: String, into fixture: MailStoreFixture.Built
    ) throws {
        let targetName = "\(rowID).emlx"
        let enumerator = FileManager.default.enumerator(
            at: fixture.root, includingPropertiesForKeys: nil
        )
        let matches = enumerator?.compactMap { $0 as? URL }.filter { $0.lastPathComponent == targetName } ?? []
        let emlxURL = try #require(
            matches.first, "no .emlx file found for rowID \(rowID) under \(fixture.root.path(percentEncoded: false))"
        )

        let directory = EMLXReader.attachmentsDirectory(forMessageAt: emlxURL, rowID: rowID, part: part)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: directory.appending(path: name, directoryHint: .notDirectory))
    }
}
