import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D10 (PG-338), plan Task 4 - R-01, R-08, R-21, R-22.
//
// The connector's `pratica` payload reads manual entries through the shared parser
// (`PraticaManualEntries.parse`) and orders the timeline through the shared rule
// (`PraticaTimelineOrder.arrange`), so an entry anchored to a message follows it, an anchor
// naming no message of the pratica is orphaned at its own heading time, and the app and the
// connector put every row in one order. Fixture shape: `Tests/PraticheConnectorTests.swift`.

private let anchorPraticaFolder = "01 Progetti/Rossi/Offerta"

private let firstMessageID = "<abc@rossi-spa.it>"
private let secondMessageID = "<def@rossi-spa.it>"
private let missingMessageID = "<sparito@rossi-spa.it>"

/// A heading minute as `PraticaEntry.headingFormatter` reads it (GMT), so a message dated
/// with it sits at exactly the instant an entry heading names.
private func headingDate(_ text: String) throws -> Date {
    try #require(PraticaEntry.headingFormatter.date(from: text))
}

private func praticaNote(entries: String) -> String {
    """
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

    \(entries)
    """
}

private func messageText(messageID: String, date: Date, subject: String) -> String {
    let message = MessageDocument(
        frontmatter: .init(
            schemaVersion: 1,
            messageID: messageID,
            conversationID: 112_409,
            direction: .received,
            date: date,
            received: date,
            from: "Mario Rossi <m.rossi@rossi-spa.it>",
            to: ["Stefano Ferri <stefano@stefer.it>"],
            cc: [],
            subject: subject,
            attachments: [],
            body: .complete,
            original: nil
        ),
        newText: "Buongiorno Stefano,\ncome d'accordo.",
        quotedHistory: nil,
        signature: nil
    )
    return MessageDocument.render(
        message,
        tags: [Tag("type-note")!, Tag("type-email")!, Tag("topic-pratica")!, Tag("client-rossi")!, Tag("source-email")!]
    )
}

/// Two messages (10 June 12:06, 12 June 10:00) and four entries in file order: a free call at
/// 14:06 on the 10th, a note anchored to the first message written on the 11th, a note
/// anchored to a Message-ID no message carries at 13:00 on the 10th, and a free note at the
/// first message's exact instant.
@MainActor
private func openVaultWithAnchoredEntries(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(praticaNote(entries: """
    ## 2026-06-10 14:06 Telefonata · Mario Rossi

    Richiamare lunedì.

    ## 2026-06-11 09:00 Nota · Mario Rossi
    <!-- pergamenum-message: \(firstMessageID) -->

    Offerta da preparare.

    ## 2026-06-10 13:00 Nota · Mario Rossi
    <!-- pergamenum-message: \(missingMessageID) -->

    Il suo messaggio è stato escluso.

    ## 2026-06-10 12:06 Nota · Stessa ora

    Scritta al minuto del messaggio.
    """), to: "\(anchorPraticaFolder)/pratica.md")

    try vault.write(
        messageText(messageID: firstMessageID, date: headingDate("2026-06-10 12:06"), subject: "Richiesta offerta"),
        to: "\(anchorPraticaFolder)/email/20260610_richiesta-offerta.md"
    )
    try vault.write(
        messageText(messageID: secondMessageID, date: headingDate("2026-06-12 10:00"), subject: "Conferma ordine"),
        to: "\(anchorPraticaFolder)/email/20260612_conferma-ordine.md"
    )

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

private func isoDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}

@MainActor
@Suite(.serialized) struct PraticheConnectorAnchorTests {
    // MARK: - R-22: the anchor, anchored or orphaned, and nothing on a free entry

    @Test func anAnchoredEntryFollowsItsMessageAndAnOrphanedOneSitsAtItsHeadingTime() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithAnchoredEntries(vault)

        let entries = try VaultAPI.pratica(session, anchorPraticaFolder).entries

        // Nothing sits between a message and its anchored entries: the free note at the
        // message's own instant comes after the group (ADR-0076 §D2).
        #expect(entries.map(\.subject) == [
            "Richiesta offerta",
            "Nota · Mario Rossi",
            "Nota · Stessa ora",
            "Nota · Mario Rossi",
            "Telefonata · Mario Rossi",
            "Conferma ordine",
        ])
        #expect(entries.map(\.kind) == ["message", "note", "note", "note", "call", "message"])
        let anchoredHeading = try headingDate("2026-06-11 09:00")
        let orphanedHeading = try headingDate("2026-06-10 13:00")

        // Written the next day, placed right after its message: the order is the message's,
        // the `date` stays the heading's own time.
        let anchored = entries[1]
        #expect(anchored.anchorMessageID == firstMessageID)
        #expect(anchored.anchorState == "anchored")
        #expect(anchored.body == "Offerta da preparare.")
        #expect(isoDate(anchored.date) == anchoredHeading)

        let orphaned = entries[3]
        #expect(orphaned.anchorMessageID == missingMessageID)
        #expect(orphaned.anchorState == "orphaned")
        #expect(isoDate(orphaned.date) == orphanedHeading)

        for free in [entries[0], entries[2], entries[4], entries[5]] {
            #expect(free.anchorMessageID == nil)
            #expect(free.anchorState == nil)
        }
    }

    @Test func aFreeEntryAndAMessageEncodeNeitherAnchorKey() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithAnchoredEntries(vault)

        let payload = try VaultAPI.pratica(session, anchorPraticaFolder)
        let data = try JSONEncoder().encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(object["entries"] as? [[String: Any]])
        #expect(rows.count == 6)

        for index in [0, 2, 4, 5] {
            #expect(rows[index]["anchorMessageID"] == nil, "row \(index) carries no anchor key")
            #expect(rows[index]["anchorState"] == nil, "row \(index) carries no anchor state key")
        }
        #expect(rows[1]["anchorMessageID"] as? String == firstMessageID)
        #expect(rows[1]["anchorState"] as? String == "anchored")
        #expect(rows[3]["anchorMessageID"] as? String == missingMessageID)
        #expect(rows[3]["anchorState"] as? String == "orphaned")
    }

    // MARK: - R-01: the anchor line is never part of the connector's body

    @Test func anEntrysBodyExcludesTheAnchorLine() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithAnchoredEntries(vault)

        let entries = try VaultAPI.pratica(session, anchorPraticaFolder).entries

        for entry in entries where entry.kind != "message" {
            #expect(!entry.body.contains("pergamenum-message"), "\(entry.subject): \(entry.body)")
            #expect(!entry.body.contains("<!--"))
        }
        #expect(entries[3].body == "Il suo messaggio è stato escluso.")
    }

    // MARK: - R-08: at one instant the message comes first

    @Test func atOneInstantTheMessageSortsBeforeAFreeEntry() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithAnchoredEntries(vault)

        let entries = try VaultAPI.pratica(session, anchorPraticaFolder).entries

        let message = try #require(entries.firstIndex { $0.subject == "Richiesta offerta" })
        let freeNote = try #require(entries.firstIndex { $0.subject == "Nota · Stessa ora" })
        #expect(entries[message].date == entries[freeNote].date)
        #expect(message < freeNote)
    }

    // MARK: - R-21: one parser, one rule - the app and the connector agree row for row

    @Test func theAppAndTheConnectorPutEveryRowInOneOrder() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithAnchoredEntries(vault)

        let read = PraticheController.readTimeline(praticaPath: anchorPraticaFolder, vaultRoot: vault.root)
        let app = PraticaTimelineModel.ordered(read.entries).map { entry -> String in
            let kind = switch entry.kind {
            case .message: "message"
            case .note: "note"
            case .call: "call"
            }
            return "\(kind) \(entry.date.timeIntervalSince1970) \(entry.subject)"
        }
        let connector = try VaultAPI.pratica(session, anchorPraticaFolder).entries.map { entry -> String in
            let date = isoDate(entry.date)?.timeIntervalSince1970 ?? -1
            return "\(entry.kind) \(date) \(entry.subject)"
        }

        #expect(app.count == 6)
        #expect(app == connector)

        // The placement agrees too, not only the order.
        let appAnchors = PraticaTimelineModel.ordered(read.entries).map { entry -> String? in
            switch entry.placement {
            case let .anchored(messageID): "anchored \(messageID)"
            case let .orphaned(messageID): "orphaned \(messageID)"
            case .message, .free: nil
            }
        }
        let connectorAnchors = try VaultAPI.pratica(session, anchorPraticaFolder).entries.map { entry in
            entry.anchorState.map { "\($0) \(entry.anchorMessageID ?? "")" }
        }
        #expect(appAnchors == connectorAnchors)
    }
}
