import Foundation

// ADR-0065 (Every on-disk format round-trips faithfully or is refused), plan
// docs/plans/format-edge-hardening.md, Tasks 1-5 and 8 - R-01 to R-15, R-23.
//
// The chain's in-code corpus (SPEC Decision 10), in `EmailFixtureCorpus`'s shape: one enum of
// static values, no fixture directory. Every byte is spelled out (plan Rule 4). Swift normalises
// the line endings of a multi-line literal to LF, so every CRLF case is a single-line literal with
// `\r\n` written out, and U+FEFF is written `\u{FEFF}`.

enum FormatEdgeCorpus {
    struct NoteCase: Sendable, CustomStringConvertible {
        let name: String
        let text: String
        var description: String { name }
    }

    // MARK: - Notes (Task 1)

    static let lfConformant = NoteCase(
        name: "lfConformant",
        text: "---\ndate: 2026-09-26\ntags:\n  - type-note\n---\n# Titolo\n\nCorpo.\n"
    )
    static let crlfWithFrontmatter = NoteCase(
        name: "crlfWithFrontmatter",
        text: "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\n---\r\n# Titolo\r\n\r\nCorpo.\r\n"
    )
    static let crlfWithoutFrontmatter = NoteCase(
        name: "crlfWithoutFrontmatter",
        text: "# Titolo\r\n\r\nCorpo.\r\n"
    )
    static let lfWithoutFrontmatter = NoteCase(
        name: "lfWithoutFrontmatter",
        text: "# Titolo\n\ntesto"
    )
    static let mixedLineEndings = NoteCase(
        name: "mixedLineEndings",
        text: "---\r\ndate: 2026-09-26\ntags:\r\n  - type-note\n---\r\n# Titolo\r\n\r\nCorpo.\r\n"
    )
    static let textBorneBOM = NoteCase(
        name: "textBorneBOM",
        text: "\u{FEFF}---\ndate: 2026-09-26\ntags: [type-note]\n---\nCorpo.\n"
    )
    static let yamlComment = NoteCase(
        name: "yamlComment",
        text: "---\n# importato da Plaud\ndate: 2026-09-26\ntags:\n  - type-note\n---\nCorpo.\n"
    )
    static let colonlessAndBlankLines = NoteCase(
        name: "colonlessAndBlankLines",
        text: "---\ndate: 2026-09-26\n\nsolo testo\ntags:\n  - type-note\n---\nCorpo.\n"
    )
    static let orphanContinuation = NoteCase(
        name: "orphanContinuation",
        text: "---\n  - vagante\ndate: 2026-09-26\ntags:\n  - type-note\n---\nCorpo.\n"
    )
    static let duplicateTags = NoteCase(
        name: "duplicateTags",
        text: "---\ndate: 2026-09-26\ntags:\n  - type-note\ntags:\n  - topic-gomma\n---\nCorpo.\n"
    )
    static let duplicateRelated = NoteCase(
        name: "duplicateRelated",
        text: "---\ndate: 2026-09-26\ntags:\n  - type-note\nrelated:\n  - \"[[Alfa]]\"\nrelated:\n  - \"[[Beta]]\"\n---\nCorpo.\n"
    )
    static let duplicateForeign = NoteCase(
        name: "duplicateForeign",
        text: "---\ncssclass: wide\ndate: 2026-09-26\ncssclass: narrow\ntags:\n  - type-note\n---\nCorpo.\n"
    )
    static let duplicateCategory = NoteCase(
        name: "duplicateCategory",
        text: "---\ndate: 2026-09-26\ntags:\n  - type-note\npergamenum-category: officina\npergamenum-category: magazzino\n---\nCorpo.\n"
    )
    static let unparsableTag = NoteCase(
        name: "unparsableTag",
        text: "---\ndate: 2026-09-26\ntags:\n  - cliente-acme\n  - type-note\n---\nCorpo.\n"
    )
    static let unsortedInlineTags = NoteCase(
        name: "unsortedInlineTags",
        text: "---\ndate: 2026-09-26\ntags: [topic-zeta, type-note]\n---\nCorpo.\n"
    )
    static let closingWithoutLineBreak = NoteCase(
        name: "closingWithoutLineBreak",
        text: "---\ndate: 2026-09-26\ntags:\n  - type-note\n---"
    )
    static let unterminatedBlock = NoteCase(
        name: "unterminatedBlock",
        text: "---\ndate: 2026-09-26\ntesto che continua"
    )
    /// The prepend defect's trace: an empty block, then the original CRLF one (read by Task 7).
    static let damagedDoubleBlock = NoteCase(
        name: "damagedDoubleBlock",
        text: "---\n---\n---\r\ndate: 2026-01-01\r\ntags: [type-note]\r\n---\r\nCorpo.\r\n"
    )

    static let notes: [NoteCase] = [
        lfConformant, crlfWithFrontmatter, crlfWithoutFrontmatter, lfWithoutFrontmatter,
        mixedLineEndings, textBorneBOM, yamlComment, colonlessAndBlankLines, orphanContinuation,
        duplicateTags, duplicateRelated, duplicateForeign, duplicateCategory, unparsableTag,
        unsortedInlineTags, closingWithoutLineBreak, unterminatedBlock, damagedDoubleBlock,
    ]

    // MARK: - JSON Canvas (Task 3)

    /// A `.canvas` fixture. `refusedKey` names the key whose `notAList` refusal is the expected
    /// outcome; nil means the fixture must re-encode to its own canonical form (ADR-0065 §Context).
    struct CanvasCase: Sendable, CustomStringConvertible {
        let name: String
        let json: String
        var refusedKey: String?
        var description: String { name }
    }

    static let nodeA = #"{"id":"a","type":"text","text":"A","x":0,"y":0,"width":100,"height":50}"#
    static let nodeB = #"{"id":"b","type":"text","text":"B","x":200,"y":0,"width":100,"height":50}"#
    static let edgeAB = #"{"id":"e1","fromNode":"a","toNode":"b"}"#

    static let canvases: [CanvasCase] = [
        CanvasCase(
            name: "unknownTypeNode",
            json: #"{"nodes":[{"id":"e","type":"embed","url":"https://x","label":"L","text":"T","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
        ),
        CanvasCase(
            name: "knownKindWithAnotherKindsKey",
            json: #"{"nodes":[{"id":"t","type":"text","text":"T","url":"https://x","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
        ),
        CanvasCase(
            name: "unrecognisedColours",
            json: #"{"nodes":[{"id":"n","type":"text","text":"N","color":"red","x":0,"y":0,"width":100,"height":50}],"# +
                ##""edges":[{"id":"e","fromNode":"n","toNode":"n","color":"#GGG"}]}"##
        ),
        CanvasCase(
            name: "nonStringColourAndLabel",
            json: #"{"nodes":[{"id":"n","type":"text","text":"N","color":3,"x":0,"y":0,"width":100,"height":50}],"# +
                #""edges":[{"id":"e","fromNode":"n","toNode":"n","label":7}]}"#
        ),
        CanvasCase(
            name: "unrecognisedSideAndEnd",
            json: #"{"nodes":[],"edges":[{"id":"e","fromNode":"a","toNode":"b","fromSide":"centre","toEnd":"diamond"}]}"#
        ),
        CanvasCase(
            name: "elementsMissingIdOrType",
            json: #"{"nodes":[\#(nodeA),{"type":"text","text":"x"},{"id":"z"},\#(nodeB)],"edges":[\#(edgeAB),{"id":"e2"}]}"#
        ),
        CanvasCase(
            name: "nonObjectElement",
            json: #"{"nodes":[\#(nodeA),42,\#(nodeB)],"edges":[]}"#
        ),
        CanvasCase(
            name: "duplicateIds",
            json: #"{"nodes":[\#(nodeA),{"id":"a","type":"text","text":"A2","x":10,"y":10,"width":100,"height":50}],"edges":[]}"#
        ),
        CanvasCase(name: "nodesNotAList", json: #"{"nodes":{}}"#, refusedKey: "nodes"),
        CanvasCase(name: "edgesNotAList", json: #"{"edges":"x"}"#, refusedKey: "edges"),
    ]

    /// A fixture canonicalised once through `JSONSerialization` with the codec's own options
    /// (`JSONCanvas.swift`, `encoded()`): what "round-trips" means for `.canvas` (ADR-0065
    /// §Context). A fixture without `edges` gains the `"edges": []` the codec always writes.
    static func canonicalCanvas(_ json: String) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return Data()
        }
        if object["nodes"] == nil { object["nodes"] = [Any]() }
        if object["edges"] == nil { object["edges"] = [Any]() }
        return try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    // MARK: - Mail (Task 4)

    /// Mail is an input format: nothing writes it back, so a case passes when it decodes to the
    /// value it was meant to carry (ADR-0065 §Context).
    struct MailCase: Sendable, CustomStringConvertible {
        enum Input: Sendable {
            /// One header value through `EncodedWord.decode`.
            case encodedWord(String)
            /// A header block through `EmailHeaderParser.parse`; `expected` is its subject.
            case subjectOf(String)
            /// One MIME parameter through `MIMEParameter.value`.
            case parameter(name: String, raw: String)
            /// A text part's raw bytes through `MIMEDecoder.decodeText`.
            case part(bytes: [UInt8], charset: String)
            /// An HTML body through `HTMLTextReducer.reduce`.
            case html(String)
        }

        let name: String
        let input: Input
        let expected: String
        var description: String { name }
    }

    static let mail: [MailCase] = [
        MailCase(
            name: "unclosedAnchor",
            input: .html(#"<p>Vedi <a href="https://x">Preventivo 2026 allegato"#),
            expected: "Vedi [Preventivo 2026 allegato](https://x)"
        ),
        MailCase(
            name: "unclosedCells",
            input: .html("<table><tr><td>Totale<td>1.250,00"),
            expected: "| Totale | 1.250,00 |\n| --- | --- |"
        ),
        MailCase(name: "nestedUnclosed", input: .html(#"<td>A <a href="x">B"#), expected: "A B"),
        MailCase(name: "latin9Part", input: .part(bytes: [0x31, 0x20, 0xA4], charset: "ISO-8859-15"), expected: "1 €"),
        MailCase(name: "latin9Word", input: .encodedWord("=?ISO-8859-15?Q?1.250,00_=A4?="), expected: "1.250,00 €"),
        MailCase(name: "adjacentWords", input: .encodedWord("=?UTF-8?Q?artic?= =?UTF-8?Q?oli?="), expected: "articoli"),
        MailCase(
            name: "foldedSubject",
            input: .subjectOf(
                "Subject: =?UTF-8?Q?Preventivo_fornitura_artic?=\r\n =?UTF-8?Q?oli_tecnici?=\r\nFrom: a@b.test\r\n\r\n"
            ),
            expected: "Preventivo fornitura articoli tecnici"
        ),
        MailCase(name: "unpaddedBWord", input: .encodedWord("=?UTF-8?B?Y2lhbw?="), expected: "ciao"),
        MailCase(
            name: "rfc2231Filename",
            input: .parameter(name: "filename", raw: "attachment; filename*=UTF-8''Preventivo%20%E2%82%AC.pdf"),
            expected: "Preventivo €.pdf"
        ),
        MailCase(
            name: "rfc2231Continuations",
            input: .parameter(name: "filename", raw: "attachment; filename*0*=UTF-8''Relazione%20; filename*1*=finale.pdf"),
            expected: "Relazione finale.pdf"
        ),
        MailCase(
            name: "quotedSemicolon",
            input: .parameter(name: "filename", raw: #"attachment; filename="Report; finale.pdf""#),
            expected: "Report; finale.pdf"
        ),
    ]

    // MARK: - Message documents (Task 5)

    /// A message file is written by this app, so it round-trips: render → parse gives the same
    /// subject and offset back, and rendering again is byte-identical (ADR-0065 §D8).
    struct MessageCase: Sendable, CustomStringConvertible {
        let name: String
        let subject: String
        /// The sender's offset in seconds east of UTC, `nil` for UTC.
        let dateOffset: Int?
        var description: String { name }
    }

    static let messages: [MessageCase] = [
        MessageCase(name: "plainSubject", subject: "Richiesta offerta", dateOffset: 7200),
        MessageCase(name: "backslashN", subject: #"C:\nuovo"#, dateOffset: nil),
        MessageCase(name: "quoteAndBackslash", subject: #"Rif. "A\B""#, dateOffset: -18000),
        MessageCase(name: "trailingBackslash", subject: #"fine\"#, dateOffset: 32400),
        MessageCase(name: "lineBreak", subject: "riga\nriga", dateOffset: 19800),
    ]

    // MARK: - Byte-level BOM notes (Task 2)

    /// The BOM belongs to the file, not to the text (ADR-0065 §D4): these go through
    /// `NoteStore.write`/`read` on disk, since no `String` carries the bytes `EF BB BF` once decoded.
    static let bomNotes: [(name: String, bytes: Data)] = [
        ("bomCRLFWithFrontmatter", Data([0xEF, 0xBB, 0xBF]) + Data(crlfWithFrontmatter.text.utf8)),
        ("bomLFConformant", Data([0xEF, 0xBB, 0xBF]) + Data(lfConformant.text.utf8)),
    ]

    // MARK: - Every format, for `everyCorpusCaseRoundTripsOrIsRefused` (R-23)

    enum Case: Sendable, CustomStringConvertible {
        case note(NoteCase)
        case bom(name: String, bytes: Data)
        case canvas(CanvasCase)
        case mail(MailCase)
        case message(MessageCase)

        var description: String {
            switch self {
            case .note(let note): "note/\(note.name)"
            case .bom(let name, _): "bom/\(name)"
            case .canvas(let canvas): "canvas/\(canvas.name)"
            case .mail(let mail): "mail/\(mail.name)"
            case .message(let message): "message/\(message.name)"
            }
        }
    }

    static var allCases: [Case] {
        notes.map(Case.note) + bomNotes.map { Case.bom(name: $0.name, bytes: $0.bytes) }
            + canvases.map(Case.canvas) + mail.map(Case.mail) + messages.map(Case.message)
    }
}
