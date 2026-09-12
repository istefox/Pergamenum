import Foundation
import Testing
@testable import Pergamenum

// ADR-0042 (Pratiche inline image placeholders) §D8.
@Suite struct MessageFrontmatterPatchTests {
    private static let sample = """
    ---
    date: 2026-09-01
    pergamenum-mail: true
    pergamenum-mail-attachments: ["[[foo.png]]"]
    pergamenum-mail-store-references:
      - { name: "big.zip", size: 100, storePath: "/tmp/big.zip" }
    pergamenum-mail-body: complete
    ---
    Corpo del messaggio.
    """

    @Test func applyingReplacesAnExistingKey() {
        let withKey = Self.sample.replacingOccurrences(
            of: "pergamenum-mail-store-references:",
            with: "pergamenum-mail-inline-pending: [\"old\"]\npergamenum-mail-store-references:"
        )
        let result = MessageFrontmatterPatch.applying(
            line: "pergamenum-mail-inline-pending: [\"cid1\"]",
            forKey: "pergamenum-mail-inline-pending",
            before: ["pergamenum-mail-store-references", "pergamenum-mail-body"],
            to: withKey
        )
        #expect(result?.contains("pergamenum-mail-inline-pending: [\"cid1\"]") == true)
        #expect(result?.contains("\"old\"") == false)
    }

    @Test func applyingInsertsBeforeFirstPresentCandidate() {
        let result = MessageFrontmatterPatch.applying(
            line: "pergamenum-mail-inline-pending: [\"cid1\"]",
            forKey: "pergamenum-mail-inline-pending",
            before: ["pergamenum-mail-store-references", "pergamenum-mail-body"],
            to: Self.sample
        )
        guard let result else { Issue.record("expected a patch"); return }
        let lines = result.components(separatedBy: "\n")
        let insertedIndex = lines.firstIndex(where: { $0.hasPrefix("pergamenum-mail-inline-pending:") })
        let storeReferencesIndex = lines.firstIndex(where: { $0.hasPrefix("pergamenum-mail-store-references:") })
        #expect(insertedIndex != nil)
        #expect(storeReferencesIndex != nil)
        #expect(insertedIndex! < storeReferencesIndex!)
    }

    @Test func applyingInsertsBeforeBodyWhenFirstCandidateAbsent() {
        let textWithoutStoreRefs = Self.sample
            .components(separatedBy: "\n")
            .filter { !$0.contains("pergamenum-mail-store-references") && !$0.contains("big.zip") }
            .joined(separator: "\n")
        let result = MessageFrontmatterPatch.applying(
            line: "pergamenum-mail-inline-pending: [\"cid1\"]",
            forKey: "pergamenum-mail-inline-pending",
            before: ["pergamenum-mail-store-references", "pergamenum-mail-body"],
            to: textWithoutStoreRefs
        )
        guard let result else { Issue.record("expected a patch"); return }
        let lines = result.components(separatedBy: "\n")
        let insertedIndex = lines.firstIndex(where: { $0.hasPrefix("pergamenum-mail-inline-pending:") })
        let bodyIndex = lines.firstIndex(of: "pergamenum-mail-body: complete")
        #expect(insertedIndex != nil)
        #expect(bodyIndex != nil)
        #expect(insertedIndex! < bodyIndex!)
    }

    @Test func applyingRemovesTheKeyWhenLineIsNil() {
        let withKey = Self.sample.replacingOccurrences(
            of: "pergamenum-mail-store-references:",
            with: "pergamenum-mail-inline-pending: [\"cid1\"]\npergamenum-mail-store-references:"
        )
        let result = MessageFrontmatterPatch.applying(
            line: nil, forKey: "pergamenum-mail-inline-pending",
            before: ["pergamenum-mail-store-references"], to: withKey
        )
        #expect(result?.contains("pergamenum-mail-inline-pending") == false)
    }

    @Test func applyingReturnsNilForNoFrontmatter() {
        let result = MessageFrontmatterPatch.applying(
            line: "x: y", forKey: "x", before: [], to: "just some text\nno frontmatter here"
        )
        #expect(result == nil)
    }

    @Test func applyingReturnsNilForUnterminatedBlock() {
        let result = MessageFrontmatterPatch.applying(
            line: "x: y", forKey: "x", before: [],
            to: "---\ndate: 2026-09-01\npergamenum-mail: true\nno closing delimiter"
        )
        #expect(result == nil)
    }

    @Test func applyingReturnsNilForNoPergamenumMailKey() {
        let result = MessageFrontmatterPatch.applying(
            line: "x: y", forKey: "x", before: [],
            to: "---\ndate: 2026-09-01\ntags: []\n---\nBody."
        )
        #expect(result == nil)
    }
}

@Suite struct MessageInlineImagePatchTests {
    private static let twoPlaceholders = """
    ---
    date: 2026-09-01
    pergamenum-mail: true
    pergamenum-mail-inline-pending: ["cid1", "cid2"]
    pergamenum-mail-body: complete
    ---
    Prima immagine: \(MessageInlineImage.placeholder)

    Seconda immagine: \(MessageInlineImage.placeholder)

    <details><summary>Cronologia</summary>testo citato</details>

    Nota aggiunta a mano sotto la cronologia.
    """

    @Test func applyingWithNoPendingIsExactNoOp() {
        let outcome = MessageInlineImagePatch.applying(resolved: [:], pending: [], to: "qualsiasi testo")
        #expect(outcome?.text == "qualsiasi testo")
        #expect(outcome?.remaining.isEmpty == true)
        #expect(outcome?.unplaceable.isEmpty == true)
    }

    @Test func applyingWithMatchingCountsPartiallyResolves() {
        let outcome = MessageInlineImagePatch.applying(
            resolved: ["cid1": .embedded(fileName: "20260901_foto.png")],
            pending: ["cid1", "cid2"],
            to: Self.twoPlaceholders
        )
        guard let outcome else { Issue.record("expected an outcome"); return }
        #expect(outcome.text.contains("Prima immagine: ![[20260901_foto.png]]"))
        #expect(outcome.text.contains("Seconda immagine: \(MessageInlineImage.placeholder)"))
        #expect(outcome.remaining == ["cid2"])
        #expect(outcome.unplaceable.isEmpty)
        #expect(outcome.text.contains("pergamenum-mail-inline-pending: [\"cid2\"]"))
        #expect(outcome.text.contains("Nota aggiunta a mano sotto la cronologia."))
    }

    @Test func applyingWithDroppedResolutionRemovesPlaceholderWithNoReplacement() {
        let outcome = MessageInlineImagePatch.applying(
            resolved: ["cid1": .dropped],
            pending: ["cid1", "cid2"],
            to: Self.twoPlaceholders
        )
        guard let outcome else { Issue.record("expected an outcome"); return }
        #expect(outcome.text.contains("Prima immagine: \n"))
        #expect(!outcome.text.contains("Prima immagine: \(MessageInlineImage.placeholder)"))
        #expect(outcome.text.contains("Seconda immagine: \(MessageInlineImage.placeholder)"))
        #expect(outcome.remaining == ["cid2"])
    }

    @Test func applyingWithBothResolvedRemovesKeyEntirely() {
        let outcome = MessageInlineImagePatch.applying(
            resolved: [
                "cid1": .embedded(fileName: "a.png"),
                "cid2": .embedded(fileName: "b.png"),
            ],
            pending: ["cid1", "cid2"],
            to: Self.twoPlaceholders
        )
        guard let outcome else { Issue.record("expected an outcome"); return }
        #expect(outcome.text.contains("![[a.png]]"))
        #expect(outcome.text.contains("![[b.png]]"))
        #expect(outcome.remaining.isEmpty)
        #expect(!outcome.text.contains("pergamenum-mail-inline-pending"))
    }

    @Test func applyingWithNothingResolvedIsNoOp() {
        let outcome = MessageInlineImagePatch.applying(
            resolved: [:], pending: ["cid1", "cid2"], to: Self.twoPlaceholders
        )
        #expect(outcome?.text == Self.twoPlaceholders)
        #expect(outcome?.remaining == ["cid1", "cid2"])
        #expect(outcome?.unplaceable.isEmpty == true)
    }

    @Test func applyingWithCountMismatchTouchesNoPlaceholderAndReportsUnplaceable() {
        let onePlaceholderOnly = Self.twoPlaceholders.replacingOccurrences(
            of: "Seconda immagine: \(MessageInlineImage.placeholder)", with: "Seconda immagine: (rimossa a mano)"
        )
        let outcome = MessageInlineImagePatch.applying(
            resolved: ["cid1": .embedded(fileName: "a.png")],
            pending: ["cid1", "cid2"],
            to: onePlaceholderOnly
        )
        guard let outcome else { Issue.record("expected an outcome"); return }
        #expect(outcome.text.contains(MessageInlineImage.placeholder))
        #expect(!outcome.text.contains("![[a.png]]"))
        #expect(outcome.unplaceable == ["a.png"])
        #expect(outcome.remaining == ["cid2"])
    }

    @Test func applyingResolvesPlaceholderInsideDetailsBlockNormally() {
        let text = """
        ---
        date: 2026-09-01
        pergamenum-mail: true
        pergamenum-mail-inline-pending: ["cid1"]
        pergamenum-mail-body: complete
        ---
        <details><summary>Cronologia</summary>

        Vecchio messaggio: \(MessageInlineImage.placeholder)

        </details>
        """
        let outcome = MessageInlineImagePatch.applying(
            resolved: ["cid1": .embedded(fileName: "old.png")], pending: ["cid1"], to: text
        )
        #expect(outcome?.text.contains("Vecchio messaggio: ![[old.png]]") == true)
        #expect(outcome?.remaining.isEmpty == true)
    }

    @Test func applyingReturnsNilForNoFrontmatter() {
        let outcome = MessageInlineImagePatch.applying(
            resolved: ["cid1": .embedded(fileName: "a.png")],
            pending: ["cid1"],
            to: "testo senza frontmatter con \(MessageInlineImage.placeholder)"
        )
        #expect(outcome == nil)
    }
}
