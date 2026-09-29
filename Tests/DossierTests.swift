import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// R-37, §D11, §D12 (C4).
//
// No test here touches `~/Library/Mail`.

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

// PG-275 (#614), ADR-0065 §D13.2: a quoted `DossierYAML` scalar escapes `\`, `"`, `\n` and
// `\r`, and reads them back through the exact inverse (§D8.1's rule, applied here).

@Suite struct DossierQuotingTests {
    /// The whole `pratica.md` text a set of foreign keys produces, as the wizard writes it.
    private static func text(of foreignKeys: [Frontmatter.ForeignKey]) -> String {
        var frontmatter = Frontmatter.empty
        frontmatter.foreignKeys = foreignKeys
        return NoteDocument(frontmatter: frontmatter, body: "\n", hasFrontmatterBlock: true).serialized()
    }

    private static func dossier(carrying value: String) -> Dossier {
        Dossier(
            schemaVersion: 1, counterparts: [], conversations: [], keywords: [value],
            included: [value], excluded: [value], ignored: []
        )
    }

    @Test(arguments: [
        "a\"b", #"x\y"#, #"x\\y"#, "riga\nriga", "riga\r\nriga", "a\rb", #"a\nb"#, #"a\rb"#,
        #"fine\"#, #"\t"#, "\t", "\"", "\"\u{301}inizio", "\\\"\n\r",
    ])
    func aQuotedValueRoundTripsThroughAPraticaMd(_ value: String) throws {
        let text = Self.text(of: Dossier.render(Self.dossier(carrying: value)))
        let foreignKeys = NoteDocument.parse(text).frontmatter.foreignKeys
        let parsed = try #require(Dossier.parse(foreignKeys))
        #expect(parsed.keywords.map { Array($0.unicodeScalars) } == [Array(value.unicodeScalars)])
        #expect(parsed.included == [value])
        #expect(parsed.excluded == [value])
        #expect(Self.text(of: Dossier.render(parsed)) == text)
    }

    @Test func aQuoteOrALineBreakStaysInsideItsOwnListItem() {
        let lines = Dossier.render(Self.dossier(carrying: "OF \"118\"\nseconda\rterza"))
            .first { $0.name == Dossier.keywordsKey }?.lines
        #expect(lines == [
            "pergamenum-dossier-keywords:",
            #"  - "OF \"118\"\nseconda\rterza""#,
        ])
    }

    @Test func aHandTypedBackslashThatEscapesNothingReadsAsWritten() throws {
        let foreignKeys: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
            .init(name: "pergamenum-dossier-keywords", lines: [
                "pergamenum-dossier-keywords:",
                #"  - "C:\temp""#,
            ]),
        ]
        #expect(try #require(Dossier.parse(foreignKeys)).keywords == [#"C:\temp"#])
    }

    @Test func aLinkTargetCarryingAQuoteOrABackslashRoundTrips() {
        var links = PraticaLinks()
        links.notes = [#"Offerta "Rossi" \ 2026"#]
        links.tasks = [PraticaLinks.TaskReference(noteTitle: #"Nota "A""#, localID: 3)]
        links.boards = [#"C:\nuovo.canvas"#]
        let text = Self.text(of: PraticaLinks.render(links))
        #expect(PraticaLinks.parse(NoteDocument.parse(text).frontmatter.foreignKeys) == links)
    }

    @Test func aCRLFPraticaMdStillParsesItsEscapedKeywords() throws {
        let value = "OF \"118\"\nseconda\\"
        let lf = Self.text(of: Dossier.render(Self.dossier(carrying: value)))
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(crlf.contains("\r\n"))
        let foreignKeys = NoteDocument.parse(crlf).frontmatter.foreignKeys
        let parsed = try #require(Dossier.parse(foreignKeys))
        #expect(parsed.keywords == [value])
        #expect(parsed.included == [value])
        #expect(parsed.excluded == [value])
    }

    @Test func theInlineListFormReadsAnEscapedQuoteAndABackslash() {
        let lines = [#"pergamenum-dossier-keywords: ["OF \"118\"", "C:\\dir", "plain"]"#]
        #expect(DossierYAML.stringList(key: "pergamenum-dossier-keywords", lines: lines)
            == ["OF \"118\"", #"C:\dir"#, "plain"])
    }

    @Test func aSingleQuotedValueIsOnlyStrippedNeverUnescaped() {
        let block = ["k:", #"  - 'a\nb "q" \\'"#]
        #expect(DossierYAML.stringList(key: "k", lines: block) == [#"a\nb "q" \\"#])
        let inline = [#"k: ['x\ny', 'z']"#]
        #expect(DossierYAML.stringList(key: "k", lines: inline) == [#"x\ny"#, "z"])
    }
}
