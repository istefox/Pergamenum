import Foundation
import Testing
@testable import Pergamenum

// ADR-0040 (Pratiche attachment reliability bugs) §D4, plan
// docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md, Task 3 -
// R-04.
@Suite struct MessageAttachmentPatchTests {
    // MARK: - Fixtures

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

    /// Every line of `text` except the top-level `pergamenum-mail-attachments:` line -
    /// what "every other byte of the file" reduces to for a line-oriented comparison.
    private static func linesWithoutAttachmentsKey(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.hasPrefix("pergamenum-mail-attachments:") }
    }

    private static func lineIndex(of prefix: String, in text: String) -> Int? {
        text.components(separatedBy: "\n").firstIndex { $0.hasPrefix(prefix) }
    }

    // MARK: - Replaces the line, leaves every other byte identical

    /// A realistic note: a `<details>` block (the quoted history) followed by prose a
    /// person added below it by hand - exactly the case a full re-render would destroy
    /// (ADR-0040 §D4's whole reason for patching instead).
    @Test func applyingReplacesTheAttachmentsLineAndLeavesEveryOtherByteIdentical() throws {
        let document = Self.sampleDocument()
        var text = MessageDocument.render(document, tags: [Tag("type-note")!, Tag("type-email")!])
        text += "\nP.S. Ho aggiunto questa riga sotto il blocco citato, a mano.\n"

        let newEntries = document.frontmatter.attachments + [
            MessageDocument.attachmentEntry(pending: "20260610_disegno.dwg")
        ]
        let patched = try #require(MessageAttachmentPatch.applying(entries: newEntries, to: text))

        #expect(patched.contains(
            "pergamenum-mail-attachments: [\"[[20260610_offerta-2024-118.pdf]]\", \"20260610_disegno.dwg\"]"
        ))
        #expect(Self.linesWithoutAttachmentsKey(patched) == Self.linesWithoutAttachmentsKey(text))
        // The prose added below the quoted-history `<details>` block survives untouched.
        #expect(patched.contains("P.S. Ho aggiunto questa riga sotto il blocco citato, a mano."))
        #expect(patched.contains("<details>"))
    }

    // MARK: - Inserts the key in the right place when absent

    @Test func applyingInsertsTheKeyBeforeStoreReferencesWhenPresent() throws {
        var document = Self.sampleDocument()
        document.frontmatter.attachments = []
        document.frontmatter.storeReferences = [
            MessageDocument.StoreReference(
                name: "big.zip", size: 157_286_400,
                storePath: "/Users/stefano/Labs/Attachments/2026/big.zip"
            )
        ]
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        // Sanity: the fixture really has no attachments key before patching.
        #expect(!text.contains("pergamenum-mail-attachments"))

        let patched = try #require(MessageAttachmentPatch.applying(
            entries: [MessageDocument.attachmentEntry(linking: "20260610_a.pdf")], to: text
        ))

        let subjectIndex = try #require(Self.lineIndex(of: "pergamenum-mail-subject:", in: patched))
        let attachmentsIndex = try #require(Self.lineIndex(of: "pergamenum-mail-attachments:", in: patched))
        let storeReferencesIndex = try #require(Self.lineIndex(of: MessageDocument.storeReferencesKey + ":", in: patched))
        #expect(subjectIndex < attachmentsIndex)
        #expect(attachmentsIndex < storeReferencesIndex)
    }

    @Test func applyingInsertsTheKeyBeforeBodyWhenStoreReferencesIsAbsent() throws {
        var document = Self.sampleDocument()
        document.frontmatter.attachments = []
        document.frontmatter.storeReferences = []
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        #expect(!text.contains("pergamenum-mail-attachments"))
        #expect(!text.contains(MessageDocument.storeReferencesKey))

        let patched = try #require(MessageAttachmentPatch.applying(
            entries: [MessageDocument.attachmentEntry(linking: "20260610_a.pdf")], to: text
        ))

        let subjectIndex = try #require(Self.lineIndex(of: "pergamenum-mail-subject:", in: patched))
        let attachmentsIndex = try #require(Self.lineIndex(of: "pergamenum-mail-attachments:", in: patched))
        let bodyIndex = try #require(Self.lineIndex(of: "pergamenum-mail-body:", in: patched))
        #expect(subjectIndex < attachmentsIndex)
        #expect(attachmentsIndex < bodyIndex)
    }

    // MARK: - Removes the key when `entries` is empty

    @Test func applyingRemovesTheKeyWhenEntriesIsEmpty() throws {
        let document = Self.sampleDocument()
        let text = MessageDocument.render(document, tags: [Tag("type-note")!])
        #expect(text.contains("pergamenum-mail-attachments"))

        let patched = try #require(MessageAttachmentPatch.applying(entries: [], to: text))

        #expect(!patched.contains("pergamenum-mail-attachments"))
        #expect(Self.linesWithoutAttachmentsKey(patched) == Self.linesWithoutAttachmentsKey(text))
    }

    // MARK: - `nil` when there is no `pergamenum-mail` frontmatter to patch

    @Test func applyingReturnsNilForANoteWithNoPergamenumMailFrontmatter() {
        let text = """
        ---
        date: 2026-06-10
        tags:
          - type-note
        ---

        Some ordinary note, not a pratica message at all.
        """
        #expect(MessageAttachmentPatch.applying(
            entries: [MessageDocument.attachmentEntry(linking: "x.pdf")], to: text
        ) == nil)
    }

    @Test func applyingReturnsNilForTextThatIsNotYAMLAtAll() {
        let text = "Just some plain text with no frontmatter delimiters at all.\nSecond line here.\n"
        #expect(MessageAttachmentPatch.applying(
            entries: [MessageDocument.attachmentEntry(linking: "x.pdf")], to: text
        ) == nil)
    }
}
