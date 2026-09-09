import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// R-37, §D11, §D12 (C4).
//
// `Dossier.parse`/`.render`/`.merging` are tester-declared stubs (ADR-0155): the coder
// fills the bodies. No test here touches `~/Library/Mail`.

@Suite struct DossierTests {
    // MARK: - R-01: recognition

    @Test func aPergamenumDossierOneForeignKeyIsRecognisedAsAPratica() {
        let foreignKeys: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
        ]
        #expect(Dossier.parse(foreignKeys) != nil)
    }

    @Test func aFolderWithNoDossierKeyIsNotAPratica() {
        let foreignKeys: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-plaud-id", lines: ["pergamenum-plaud-id: xyz"]),
        ]
        #expect(Dossier.parse(foreignKeys) == nil)
    }

    @Test func parsesAllSevenKeys() throws {
        let foreignKeys: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
            .init(name: "pergamenum-dossier-counterparts", lines: [
                "pergamenum-dossier-counterparts:",
                "  - m.rossi@rossi-spa.it",
                "  - ufficio.acquisti@rossi-spa.it",
            ]),
            .init(name: "pergamenum-dossier-conversations", lines: [
                "pergamenum-dossier-conversations: [112409, 92415]",
            ]),
            .init(name: "pergamenum-dossier-keywords", lines: [
                "pergamenum-dossier-keywords:",
                "  - \"OF-2026-118\"",
                "  - \"staffa antivibrante\"",
            ]),
            .init(name: "pergamenum-dossier-included", lines: [
                "pergamenum-dossier-included:",
                "  - \"<abc@rossi-spa.it>\"",
            ]),
            .init(name: "pergamenum-dossier-excluded", lines: [
                "pergamenum-dossier-excluded:",
                "  - \"<def@rossi-spa.it>\"",
            ]),
            .init(name: "pergamenum-dossier-ignored", lines: ["pergamenum-dossier-ignored: [3416]"]),
        ]
        let dossier = try #require(Dossier.parse(foreignKeys))
        #expect(dossier.schemaVersion == 1)
        #expect(dossier.counterparts == ["m.rossi@rossi-spa.it", "ufficio.acquisti@rossi-spa.it"])
        #expect(dossier.conversations == [112409, 92415])
        #expect(dossier.keywords == ["OF-2026-118", "staffa antivibrante"])
        #expect(dossier.included == ["<abc@rossi-spa.it>"])
        #expect(dossier.excluded == ["<def@rossi-spa.it>"])
        #expect(dossier.ignored == [3416])
    }

    // MARK: - Rendering, in the SPEC's own order

    @Test func rendersTheSevenKeysInSpecOrder() {
        let dossier = Dossier(
            schemaVersion: 1,
            counterparts: ["m.rossi@rossi-spa.it", "ufficio.acquisti@rossi-spa.it"],
            conversations: [112409, 92415],
            keywords: ["OF-2026-118", "staffa antivibrante"],
            included: ["<abc@rossi-spa.it>"],
            excluded: ["<def@rossi-spa.it>"],
            ignored: [3416]
        )
        let lines = Dossier.render(dossier).flatMap(\.lines)
        #expect(lines == [
            "pergamenum-dossier: 1",
            "pergamenum-dossier-counterparts:",
            "  - m.rossi@rossi-spa.it",
            "  - ufficio.acquisti@rossi-spa.it",
            "pergamenum-dossier-conversations: [112409, 92415]",
            "pergamenum-dossier-keywords:",
            "  - \"OF-2026-118\"",
            "  - \"staffa antivibrante\"",
            "pergamenum-dossier-included:",
            "  - \"<abc@rossi-spa.it>\"",
            "pergamenum-dossier-excluded:",
            "  - \"<def@rossi-spa.it>\"",
            "pergamenum-dossier-ignored: [3416]",
        ])
    }

    @Test func omitsAnEmptyOptionalKeyRatherThanWritingItEmpty() {
        let dossier = Dossier(
            schemaVersion: 1, counterparts: [], conversations: [], keywords: [],
            included: [], excluded: [], ignored: []
        )
        let lines = Dossier.render(dossier).flatMap(\.lines)
        #expect(lines == ["pergamenum-dossier: 1"])
    }

    // MARK: - C4: byte-for-byte round trip, never reordering a key it does not own

    @Test func roundTripsByteForByteIncludingAForeignKeyThisAppDidNotWrite() throws {
        let original: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
            .init(name: "pergamenum-dossier-counterparts", lines: [
                "pergamenum-dossier-counterparts:",
                "  - m.rossi@rossi-spa.it",
            ]),
            .init(name: "obsidian-icon", lines: ["obsidian-icon: 📁"]),
            .init(name: "pergamenum-dossier-conversations", lines: [
                "pergamenum-dossier-conversations: [112409]",
            ]),
        ]
        let dossier = try #require(Dossier.parse(original))
        let rebuilt = Dossier.merging(dossier, into: original)
        #expect(rebuilt == original)
    }

    // MARK: - R-37 / §D11: the tag sets that actually pass the real linter

    private static let praticaVocabulary = Vocabulary(
        type: ["note", "email"], status: ["active", "waiting", "archived", "final"],
        area: [], source: ["email"], deliverableKind: []
    )

    @Test func praticaMdTagsPassTheRealLinter() {
        // ADR §D11: type-note, topic-pratica, client-<slug>, status-active, source-email.
        let tags = [
            Tag("type-note")!, Tag("topic-pratica")!, Tag("client-rossi")!,
            Tag("status-active")!, Tag("source-email")!,
        ]
        let violations = TagRules.validate(tags, category: .note, vocabulary: Self.praticaVocabulary)
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test func messageMdTagsPassTheRealLinter() {
        // ADR §D11: type-note, type-email, topic-pratica, client-<slug>, source-email -
        // two type-* tags is legal, only status is capped at one.
        let tags = [
            Tag("type-note")!, Tag("type-email")!, Tag("topic-pratica")!,
            Tag("client-rossi")!, Tag("source-email")!,
        ]
        let violations = TagRules.validate(tags, category: .note, vocabulary: Self.praticaVocabulary)
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test func statusFinalIsNotAllowedOnAPraticaOrMessageNote() {
        // §D11: `status-final` is reserved for a Deliverable (`Tag.swift`'s own
        // `NoteCategory.allowsStatus`); a pratica or message file is an ordinary
        // `.note`, so the real linter already refuses it - which is exactly what
        // keeps the app's own generation logic from ever emitting it.
        let tags = [Tag("type-note")!, Tag("topic-pratica")!, Tag("status-final")!]
        let violations = TagRules.validate(tags, category: .note, vocabulary: Self.praticaVocabulary)
        #expect(violations.contains(.statusNotAllowedOnNote(Tag("status-final")!)))
    }
}
