import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 9 - R-35,
// R-36.
//
// `VaultAPI.pratiche(_:)`/`.pratica(_:_:)` and their two payload shapes
// (`PraticaSummary`/`PraticaTimelinePayload`, `Sources/Connector/VaultPayloads.swift`,
// `Sources/Connector/VaultPratiche.swift`) are tester-declared boundaries (ADR-0155
// §D1): the coder fills the bodies. `pratiche(_:)` always answers `[]` and
// `pratica(_:_:)` always throws today - wrong-but-compiling, never a `fatalError`, so
// every positive assertion below is genuinely red rather than a crash.
//
// The fixture pratica folder is built entirely from already-real Task 3/6 machinery
// (`Dossier`, `MessageDocument`, `PraticaLedger`) - only the connector functions
// themselves are stubs. No test here touches `~/Library/Mail` or
// `MailStoreReader`/`MailStoreConnection`/`SQLite3` in any form (R-36's own
// structural half, already checked by `SharedSourcesPurityTests`).

private let praticaFolder = "01 Progetti/Rossi/Offerta"

private let praticaNoteWithTagsAndConversation = """
---
date: 2026-09-01
tags:
  - type-note
  - topic-pratica
  - client-rossi
  - status-active
  - source-email
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-conversations: [112409]
---

Appunti pratica.
"""

@MainActor
private func openVaultWithOnePratica(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(praticaNoteWithTagsAndConversation, to: "\(praticaFolder)/pratica.md")

    let message = MessageDocument(
        frontmatter: .init(
            schemaVersion: 1,
            messageID: "<abc@rossi-spa.it>",
            conversationID: 112_409,
            direction: .received,
            date: Date(timeIntervalSince1970: 1_749_557_170),
            received: Date(timeIntervalSince1970: 1_749_557_191),
            from: "Mario Rossi <m.rossi@rossi-spa.it>",
            to: ["Stefano Ferri <stefano@stefer.it>"],
            cc: [],
            subject: "Richiesta offerta staffe antivibranti",
            attachments: [],
            body: .complete,
            original: nil
        ),
        newText: "Buongiorno Stefano,\npotrebbe farci un'offerta?",
        quotedHistory: nil,
        signature: nil
    )
    let messageText = MessageDocument.render(
        message,
        tags: [Tag("type-note")!, Tag("type-email")!, Tag("topic-pratica")!, Tag("client-rossi")!, Tag("source-email")!]
    )
    try vault.write(messageText, to: "\(praticaFolder)/email/20260610_richiesta-offerta.md")

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    // R-35's own `trayCount` gap: seeded straight into the ledger's on-disk file
    // (`Sources/Core/Pratiche/PraticaLedger.swift`'s Task 9 widening), bypassing any
    // in-app sync - exactly what a re-launched `perg`/`pergamenum-mcp` would find.
    var ledger = PraticaLedger.empty
    ledger.byPraticaPath[praticaFolder] = .empty
    ledger.byPraticaPath[praticaFolder]?.trayCount = 3
    let ledgerURL = PraticheController.stateDirectory(for: session).appending(
        path: "ledger.json", directoryHint: .notDirectory
    )
    try ledger.save(to: ledgerURL)

    return session
}

@MainActor
@Suite(.serialized) struct VaultAPIPraticheTests {
    // MARK: - R-35, R-36: `pratiche(_:)` - every field of `PraticaSummary`

    @Test func praticheListsEveryDossierFolderWithAllEightFields() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        let summaries = VaultAPI.pratiche(session)

        // RED until the coder fills `VaultAPI.pratiche(_:)`'s body: the stub answers
        // `[]` unconditionally.
        let summary = try #require(summaries.first)
        #expect(summaries.count == 1)
        #expect(summary.path == praticaFolder)
        #expect(summary.title == "Offerta")
        #expect(summary.client == "Rossi")
        #expect(summary.status == "active")
        #expect(summary.counterparts == ["m.rossi@rossi-spa.it"])
        #expect(summary.messageCount == 1)
        #expect(summary.trayCount == 3)
        // R-36: "no connector opens the Mail store or triggers a sync… what they
        // read is what is on disk" - `lastActivity` is a non-empty ISO-ish string
        // read off the folder's own files, never a value that required opening Mail.
        #expect(!summary.lastActivity.isEmpty)
    }

    @Test func praticheReportsNoPraticheOnAVaultThatHasNone() async throws {
        let vault = try TemporaryVault()
        try vault.write("---\ndate: 2026-09-01\ntags:\n  - type-note\n---\n\nUna nota qualunque.\n", to: "Nota.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        await session.rescan()

        #expect(VaultAPI.pratiche(session).isEmpty)
    }

    // MARK: - R-35: `pratica(_:_:)` - resolution by title and by path, ordered timeline

    @Test func praticaIsFoundByItsTitle() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        // RED until the coder fills `VaultAPI.pratica(_:_:)`'s body: the stub always
        // throws.
        let payload = try VaultAPI.pratica(session, "Offerta")
        #expect(payload.path == praticaFolder)
        #expect(payload.title == "Offerta")
        #expect(payload.entries.count == 1)
        let entry = try #require(payload.entries.first)
        #expect(entry.kind == "message")
        #expect(entry.direction == "received")
        #expect(entry.from == "Mario Rossi <m.rossi@rossi-spa.it>")
        #expect(entry.subject == "Richiesta offerta staffe antivibranti")
        #expect(entry.body.contains("potrebbe farci un'offerta"))
    }

    @Test func praticaIsFoundByItsExactPath() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        let payload = try VaultAPI.pratica(session, praticaFolder)
        #expect(payload.title == "Offerta")
    }

    @Test func praticaRefusesAnUnknownReferenceRatherThanGuessing() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        #expect(throws: ConnectorError.self) { try VaultAPI.pratica(session, "Non esiste") }
    }

    // MARK: - R-36: the connector never needs the Mail store to answer at all

    @Test func praticaAndPraticheAnswerWithNoMailStoreFixtureConfiguredInThisProcess() async throws {
        // Deliberately sets no `-mailStoreRoot` override and builds no
        // `MailStoreFixture` - if either read above required Mail data to resolve, it
        // would have nothing to read and could only fail loudly, never silently
        // substitute a real `~/Library/Mail` read. Reaching a real answer here is
        // itself R-36's structural guarantee, on top of `SharedSourcesPurityTests`'
        // static check.
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        _ = VaultAPI.pratiche(session)
        _ = try VaultAPI.pratica(session, praticaFolder)
    }
}
