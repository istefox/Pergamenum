import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D9, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-14.
//
// The connector's pratica timeline dates for a message and a manual entry, pinned before Task 5
// builds one formatter per call instead of one per row. The reference formatter is built here with
// the production recipe (`[.withInternetDateTime]`, `.current`), which keeps the pin independent
// of the zone the machine running it is in.

private let pinFolder = "01 Progetti/Rossi/Offerta"

private let pinPraticaNote = """
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

## 2026-06-11 09:30 Telefonata · Mario Rossi

Chiamato per la consegna.

## 2026-06-12 16:45 Nota · Mario Rossi

Seconda voce.
"""

private func referenceString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = .current
    return formatter.string(from: date)
}

private func pinMessage(_ messageID: String, sent: Date, offset: Int?) -> MessageDocument {
    MessageDocument(
        frontmatter: .init(
            schemaVersion: 1, messageID: messageID, conversationID: 112_409, direction: .received,
            date: sent, dateOffset: offset, received: sent.addingTimeInterval(21),
            from: "Mario Rossi <m.rossi@rossi-spa.it>", to: ["stefano@stefer.it"], cc: [],
            subject: "Richiesta offerta", attachments: [], body: .complete, original: nil
        ),
        newText: "Buongiorno.", quotedHistory: nil, signature: nil
    )
}

@MainActor
@Suite(.serialized) struct PraticheConnectorTimelineDatePinTests {
    @Test func messageAndManualEntryDatesMatchTheProductionRecipe() async throws {
        let vault = try TemporaryVault()
        try vault.write(pinPraticaNote, to: "\(pinFolder)/pratica.md")
        let tags = [try #require(Tag("type-note")), try #require(Tag("source-email"))]
        let first = Date(timeIntervalSince1970: 1_749_557_170)
        let second = Date(timeIntervalSince1970: 1_781_093_170)
        try vault.write(
            MessageDocument.render(pinMessage("<uno@rossi-spa.it>", sent: first, offset: 7200), tags: tags),
            to: "\(pinFolder)/email/20250610_uno.md"
        )
        try vault.write(
            MessageDocument.render(pinMessage("<due@rossi-spa.it>", sent: second, offset: nil), tags: tags),
            to: "\(pinFolder)/email/20260610_due.md"
        )
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        await session.rescan()

        let payload = try VaultAPI.pratica(session, pinFolder)

        let call = try #require(PraticaEntry.headingFormatter.date(from: "2026-06-11 09:30"))
        let note = try #require(PraticaEntry.headingFormatter.date(from: "2026-06-12 16:45"))
        #expect(payload.entries.map(\.kind) == ["message", "message", "call", "note"])
        #expect(payload.entries.map(\.date) == [
            referenceString(first), referenceString(second), referenceString(call), referenceString(note),
        ])
    }
}
