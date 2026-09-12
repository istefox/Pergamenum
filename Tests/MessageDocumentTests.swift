import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-08,
// R-12.

@Suite struct MessageDocumentTests {
    // MARK: - R-08: render/parse round trip

    private static func sampleDocument() -> MessageDocument {
        MessageDocument(
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
                attachments: ["[[20260610_offerta-2024-118.pdf]]"],
                body: .complete,
                original: "20260610_1406_Rossi_richiesta-offerta.eml"
            ),
            newText: "Buongiorno Stefano,\n…nuovo testo…",
            quotedHistory: "> Il giorno 9 giu 2026, alle ore 18:02, Stefano Ferri ha scritto:\n> …",
            signature: nil
        )
    }

    @Test func rendersTheFourClosedKeysPlusThePergamenumMailKeys() {
        let text = MessageDocument.render(
            Self.sampleDocument(),
            tags: [Tag("type-note")!, Tag("type-email")!, Tag("topic-pratica")!, Tag("client-rossi")!, Tag("source-email")!]
        )
        #expect(text.contains("pergamenum-mail: 1"))
        #expect(text.contains("pergamenum-mail-message-id: \"<abc@rossi-spa.it>\""))
        #expect(text.contains("pergamenum-mail-direction: received"))
        #expect(text.contains("pergamenum-mail-body: complete"))
        #expect(text.contains("Buongiorno Stefano,"))
    }

    @Test func putsTheQuotedHistoryInADetailsBlock() {
        let text = MessageDocument.render(Self.sampleDocument(), tags: [Tag("type-note")!])
        #expect(text.contains("<details>"))
        #expect(text.contains("Testo citato"))
        #expect(text.contains("Il giorno 9 giu 2026"))
    }

    @Test func roundTripsParseAfterRender() throws {
        let original = Self.sampleDocument()
        let text = MessageDocument.render(original, tags: [Tag("type-note")!, Tag("type-email")!])
        let parsed = try #require(MessageDocument.parse(text))
        #expect(parsed.frontmatter.messageID == original.frontmatter.messageID)
        #expect(parsed.frontmatter.direction == original.frontmatter.direction)
        #expect(parsed.newText == original.newText)
    }

    // MARK: - Task 4 amendment: `pergamenum-mail-subject` (plan "Batch 2 results")

    @Test func rendersThePergamenumMailSubjectKey() {
        let text = MessageDocument.render(Self.sampleDocument(), tags: [Tag("type-note")!])
        #expect(text.contains("pergamenum-mail-subject: \"Richiesta offerta staffe antivibranti\""))
    }

    @Test func roundTripsTheSubjectThroughParse() throws {
        let original = Self.sampleDocument()
        let text = MessageDocument.render(original, tags: [Tag("type-note")!])
        let parsed = try #require(MessageDocument.parse(text))
        #expect(parsed.frontmatter.subject == original.frontmatter.subject)
    }

    // MARK: - Coordinator follow-up: `pergamenum-mail-store-references` (over-threshold attachments)

    @Test func rendersThePergamenumMailStoreReferencesKey() {
        var document = Self.sampleDocument()
        document.frontmatter.storeReferences = [
            MessageDocument.StoreReference(
                name: "big.zip", size: 157_286_400,
                storePath: "/Users/stefano/Labs/Attachments/2026/big.zip"
            )
        ]
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        #expect(text.contains("pergamenum-mail-store-references:"))
        #expect(text.contains(
            "  - { name: \"big.zip\", size: 157286400, storePath: \"/Users/stefano/Labs/Attachments/2026/big.zip\" }"
        ))
    }

    @Test func roundTripsStoreReferencesThroughParse() throws {
        var original = Self.sampleDocument()
        original.frontmatter.storeReferences = [
            MessageDocument.StoreReference(
                name: "big.zip", size: 157_286_400,
                storePath: "/Users/stefano/Labs/Attachments/2026/big.zip"
            ),
            MessageDocument.StoreReference(
                name: "huge.mov", size: 998_877_665,
                storePath: "/Users/stefano/Labs/Attachments/2026/huge.mov"
            )
        ]
        let text = MessageDocument.render(original, tags: [Tag("type-note")!])
        let parsed = try #require(MessageDocument.parse(text))
        #expect(parsed.frontmatter.storeReferences == original.frontmatter.storeReferences)
    }

    // MARK: - R-12: direction and counterpart

    private static let ownAddresses: Set<String> = ["stefano@stefer.it"]
    private static let rossi = EmailAddress(name: "Mario Rossi", address: "m.rossi@rossi-spa.it")
    private static let stefano = EmailAddress(name: "Stefano Ferri", address: "stefano@stefer.it")
    private static let collega = EmailAddress(name: "Collega", address: "collega@rossi-spa.it")

    @Test func directionIsReceivedWhenFromIsNotAnOwnAddress() {
        #expect(MessageDocument.direction(from: Self.rossi, ownAddresses: Self.ownAddresses) == .received)
    }

    @Test func directionIsSentIffFromIsAnOwnAddress() {
        #expect(MessageDocument.direction(from: Self.stefano, ownAddresses: Self.ownAddresses) == .sent)
    }

    @Test func counterpartOfAReceivedMessageIsTheSender() {
        let counterpart = MessageDocument.counterpart(
            direction: .received, from: Self.rossi, to: [Self.stefano], cc: [], ownAddresses: Self.ownAddresses
        )
        #expect(counterpart?.address == "m.rossi@rossi-spa.it")
    }

    @Test func counterpartOfASentMessageIsTheFirstNonOwnRecipient() {
        let counterpart = MessageDocument.counterpart(
            direction: .sent, from: Self.stefano, to: [Self.rossi, Self.collega], cc: [],
            ownAddresses: Self.ownAddresses
        )
        #expect(counterpart?.address == "m.rossi@rossi-spa.it")
    }

    @Test func counterpartOfASentMessageFallsBackToCcWhenEveryToIsOwn() {
        let counterpart = MessageDocument.counterpart(
            direction: .sent, from: Self.stefano, to: [Self.stefano], cc: [Self.rossi],
            ownAddresses: Self.ownAddresses
        )
        #expect(counterpart?.address == "m.rossi@rossi-spa.it")
    }

    // MARK: - R-04 (ADR-0040 §D3): the pending-attachment codec
    //
    // `attachmentEntry(linking:)`/`attachmentEntry(pending:)`/`isPendingAttachmentEntry`
    // and `MailFrontmatter.linkedAttachmentNames`/`pendingAttachmentNames` are the
    // tester-declared boundary (ADR-0155 §D1); the coder's bodies do not exist yet, so
    // every assertion below is expected to fail to compile/run until Task 3 lands.

    @Test func attachmentEntryLinkingWrapsTheNameInDoubleBrackets() {
        #expect(MessageDocument.attachmentEntry(linking: "20260610_a.pdf") == "[[20260610_a.pdf]]")
    }

    @Test func attachmentEntryPendingIsTheBareName() {
        #expect(MessageDocument.attachmentEntry(pending: "20260610_a.pdf") == "20260610_a.pdf")
    }

    @Test func isPendingAttachmentEntryDistinguishesTheTwoForms() {
        #expect(MessageDocument.isPendingAttachmentEntry("20260610_a.pdf") == true)
        #expect(MessageDocument.isPendingAttachmentEntry("[[20260610_a.pdf]]") == false)
    }

    @Test func attachmentsRoundTripIntoExactlyOneLinkedAndOnePendingName() throws {
        var document = Self.sampleDocument()
        document.frontmatter.attachments = [
            MessageDocument.attachmentEntry(linking: "20260610_a.pdf"),
            MessageDocument.attachmentEntry(pending: "20260610_b.dwg")
        ]
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        let parsed = try #require(MessageDocument.parse(text))

        #expect(parsed.frontmatter.attachments == document.frontmatter.attachments)
        #expect(parsed.frontmatter.linkedAttachmentNames == ["20260610_a.pdf"])
        #expect(parsed.frontmatter.pendingAttachmentNames == ["20260610_b.dwg"])
    }

    /// The backward-compatibility guarantee the whole retry rule (ADR-0040 §D5) rests
    /// on: a note written before this fix carries only `[[…]]` entries, so
    /// `pendingAttachmentNames` must read back empty, not merely "not obviously wrong".
    @Test func pendingAttachmentNamesIsEmptyForANoteWrittenBeforeThisFix() throws {
        // `sampleDocument()` carries only a `[[…]]` entry, as every note written before
        // ADR-0040 does.
        let text = MessageDocument.render(Self.sampleDocument(), tags: [Tag("type-note")!])
        let parsed = try #require(MessageDocument.parse(text))

        #expect(parsed.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(parsed.frontmatter.linkedAttachmentNames == ["20260610_offerta-2024-118.pdf"])
    }

    /// `splitTopLevel` already survives a comma or a quote inside a quoted list element
    /// (see the `pergamenum-mail-to`/`cc` round trip); this pins that the same holds for
    /// the pending-attachment codec riding on top of it.
    @Test func fileNamesWithACommaOrAQuoteSurviveTheRoundTrip() throws {
        let nameWithComma = "20260610, copia.pdf"
        let nameWithQuote = "20260610_\"finale\".dwg"
        var document = Self.sampleDocument()
        document.frontmatter.attachments = [
            MessageDocument.attachmentEntry(linking: nameWithComma),
            MessageDocument.attachmentEntry(pending: nameWithQuote)
        ]
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        let parsed = try #require(MessageDocument.parse(text))

        #expect(parsed.frontmatter.linkedAttachmentNames == [nameWithComma])
        #expect(parsed.frontmatter.pendingAttachmentNames == [nameWithQuote])
    }
}
