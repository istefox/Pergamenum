import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §Context, plan docs/plans/format-edge-hardening.md, Tasks 1-5 and 8 - R-23.
//
// Every case of every format either round-trips or is refused with a named error or a recorded
// problem; none is dropped. "Round-trips" is read per format (plan, Departures 3): a note is
// byte-identical through parse and serialize, a canvas re-encodes to its canonical form or is
// refused with `notAList`, mail input decodes to the value the sender meant, and a message file
// renders byte-identical after a parse.

@Test(arguments: FormatEdgeCorpus.allCases)
func everyCorpusCaseRoundTripsOrIsRefused(_ corpusCase: FormatEdgeCorpus.Case) throws {
    switch corpusCase {
    case .note(let note):
        #expect(NoteDocument.parse(note.text).serialized() == note.text)
    case .bom(_, let bytes):
        // The BOM belongs to the file (ADR-0065 §D4): read strips it, write puts it back.
        let vault = try TemporaryVault()
        try bytes.write(to: vault.root.appending(path: "Nota.md"))
        let store = NoteStore(root: vault.root)
        let text = try store.read("Nota.md").text
        #expect(text.unicodeScalars.first != "\u{FEFF}")
        _ = try store.write(NoteDocument.parse(text).serialized(), to: "Nota.md")
        #expect(try Data(contentsOf: vault.root.appending(path: "Nota.md")) == bytes)
    case .canvas(let canvas):
        if let key = canvas.refusedKey {
            #expect {
                try CanvasDocument(data: Data(canvas.json.utf8))
            } throws: { error in
                guard case CanvasDocument.DecodingError.notAList(let refused) = error else { return false }
                return refused == key
            }
        } else {
            let reencoded = try CanvasDocument(data: Data(canvas.json.utf8)).encoded()
            #expect(reencoded == (try FormatEdgeCorpus.canonicalCanvas(canvas.json)))
        }
    case .mail(let mail):
        let decoded: String? = switch mail.input {
        case .encodedWord(let value): EncodedWord.decode(value)
        case .subjectOf(let block): EmailHeaderParser.parse(block).subject
        case .parameter(let name, let raw): MIMEParameter.value(name, in: raw)
        case .part(let bytes, let charset):
            MIMEDecoder.decodeText(Data(bytes), transferEncoding: nil, charset: charset)
        case .html(let html): HTMLTextReducer.reduce(html)
        }
        #expect(decoded == mail.expected)
    case .message(let message):
        let document = MessageDocument(
            frontmatter: .init(
                schemaVersion: 1, messageID: "<corpus@rossi-spa.it>", conversationID: nil, direction: .received,
                date: Date(timeIntervalSince1970: 1_790_384_400), dateOffset: message.dateOffset,
                received: Date(timeIntervalSince1970: 1_790_384_460), from: "m.rossi@rossi-spa.it",
                to: [], cc: [], subject: message.subject, attachments: [], body: .complete, original: nil
            ),
            newText: "Corpo.", quotedHistory: nil, signature: nil
        )
        let tags = [try #require(Tag("type-note"))]
        let text = MessageDocument.render(document, tags: tags)
        let parsed = try #require(MessageDocument.parse(text))
        #expect(parsed.frontmatter.subject == message.subject)
        #expect(parsed.frontmatter.dateOffset == message.dateOffset)
        #expect(MessageDocument.render(parsed, tags: tags) == text)
    }
}
