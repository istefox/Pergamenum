import CryptoKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0072, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-09, R-10.
//
// The byte-identity run the SPEC requires before and after every reducer or decoder change
// ("Mail output is byte-identical on `EmailFixtureCorpus` and `FormatEdgeCorpus`"). Each case's
// output is hashed and compared with a digest recorded from one run on the baseline tree
// (`3cdc97fb`). A failure prints the actual output, not only the digest, so a divergence can be
// read rather than guessed at.
//
// Beside the two corpora, variants aimed at exactly what Task 4 changes: a CRLF that reaches a
// line or paragraph break, upper- and mixed-case closers, non-ASCII characters next to and inside
// a near-match closer, whitespace-only paragraphs made of non-ASCII spaces, boundary lines with
// trailing whitespace, a nested boundary that extends the outer one, and a multipart with no
// closing delimiter.

struct MailByteCase: Sendable, CustomStringConvertible {
    enum Input: Sendable {
        /// An HTML body through `HTMLTextReducer.reduce`.
        case html(String)
        /// A whole RFC 822 message through `MIMEDecoder.decode`, every part serialized.
        case message(String)
        /// Raw part bytes through `MIMEDecoder.decodeText`.
        case text(bytes: Data, transferEncoding: String?, charset: String)
        /// One header value through `EncodedWord.decode`.
        case encodedWord(String)
        /// A header block through `EmailHeaderParser.parse`, its subject.
        case subjectOf(String)
        /// One MIME parameter through `MIMEParameter.value`.
        case parameter(name: String, raw: String)
    }

    let name: String
    let input: Input
    var description: String { name }

    /// The output as one string: the reducer's text, the decoded text, or every decoded part
    /// with its headers and payload bytes.
    var output: String {
        switch input {
        case .html(let html): HTMLTextReducer.reduce(html)
        case .message(let message): Self.serialized(MIMEDecoder.decode(Data(message.utf8)))
        case .text(let bytes, let transferEncoding, let charset):
            MIMEDecoder.decodeText(bytes, transferEncoding: transferEncoding, charset: charset)
        case .encodedWord(let value): EncodedWord.decode(value)
        case .subjectOf(let block): EmailHeaderParser.parse(block).subject ?? "<nil>"
        case .parameter(let name, let raw): MIMEParameter.value(name, in: raw) ?? "<nil>"
        }
    }

    private static func serialized(_ parts: [MIMEPart]) -> String {
        parts.map { part in
            var lines = [
                "kind: \(part.kind)",
                "content-type: \(part.contentType)",
                "part-number: \(part.partNumber)",
                "filename: \(part.filename ?? "<nil>")",
            ]
            lines += part.headers.map { "header: \($0.name.debugDescription): \($0.value.debugDescription)" }
            lines.append("text: \(part.decodedText?.debugDescription ?? "<nil>")")
            lines.append("data: \(part.decodedData?.base64EncodedString() ?? "<nil>")")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n--part--\n")
    }
}

enum MailByteCorpus {
    private static let smallImage = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])

    static let emailFixtureHTML: [MailByteCase] = [
        ("htmlParagraphsAndBreak", EmailFixtureCorpus.htmlParagraphsAndBreak),
        ("htmlUnorderedList", EmailFixtureCorpus.htmlUnorderedList),
        ("htmlOrderedList", EmailFixtureCorpus.htmlOrderedList),
        ("htmlLink", EmailFixtureCorpus.htmlLink),
        ("htmlBold", EmailFixtureCorpus.htmlBold),
        ("htmlTable", EmailFixtureCorpus.htmlTable),
        ("htmlWithStyleAndScript", EmailFixtureCorpus.htmlWithStyleAndScript),
        ("htmlRemoteImage", EmailFixtureCorpus.htmlRemoteImage),
        ("htmlTrackingPixel", EmailFixtureCorpus.htmlTrackingPixel),
    ].map { MailByteCase(name: "fixture/\($0.0)", input: .html($0.1)) }

    static let emailFixtureMessages: [MailByteCase] = [
        ("completeMessage", EmailFixtureCorpus.completeMessageRFC822),
        ("headersOnlyMessage", EmailFixtureCorpus.headersOnlyMessageRFC822),
        ("mixedMultipartMessage", EmailFixtureCorpus.mixedMultipartMessageRFC822),
        ("singleAttachment", EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "att@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes(pages: 2)
        )),
        ("singleInlineImage", EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "inline@rossi-spa.it", contentID: "logo@rossi", imageBytes: smallImage
        )),
        ("htmlInlineImages", EmailFixtureCorpus.htmlInlineImagesMessageRFC822(
            messageID: "html@rossi-spa.it",
            images: [.init(contentID: "a@x", bytes: smallImage), .init(contentID: "b@x", bytes: Data())]
        )),
        ("htmlInlineImagesWithPlainAlternative", EmailFixtureCorpus.htmlInlineImagesWithPlainAlternativeRFC822(
            messageID: "alt@rossi-spa.it", images: [.init(contentID: "c@x", bytes: smallImage)]
        )),
        ("signatureInlineImagesReply", EmailFixtureCorpus.signatureInlineImagesReplyRFC822(
            messageID: "reply@rossi-spa.it",
            newTextImage: .init(contentID: "new@x", bytes: smallImage),
            quotedImage: .init(contentID: "quoted@x", bytes: smallImage),
            signatureImage: .init(contentID: "sig@x", bytes: Data())
        )),
        ("zeroByteAttachment", EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "zero@rossi-spa.it", filename: "vuoto.pdf"
        )),
        ("truncatedAttachment", EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "trunc@rossi-spa.it", filename: "troncato.pdf"
        )),
        ("mixedValidAndTruncated", EmailFixtureCorpus.mixedValidAndTruncatedAttachmentsRFC822(
            messageID: "mixed@rossi-spa.it"
        )),
    ].map { MailByteCase(name: "fixture/\($0.0)", input: .message($0.1)) }

    static let emailFixtureText: [MailByteCase] = [
        MailByteCase(name: "fixture/sevenBit", input: .text(
            bytes: EmailFixtureCorpus.sevenBitASCIIBytes, transferEncoding: "7bit", charset: "us-ascii"
        )),
        MailByteCase(name: "fixture/eightBit", input: .text(
            bytes: EmailFixtureCorpus.eightBitUTF8Bytes, transferEncoding: "8bit", charset: "utf-8"
        )),
        MailByteCase(name: "fixture/quotedPrintable", input: .text(
            bytes: EmailFixtureCorpus.quotedPrintableUTF8Bytes, transferEncoding: "quoted-printable", charset: "utf-8"
        )),
        MailByteCase(name: "fixture/base64", input: .text(
            bytes: EmailFixtureCorpus.base64PlainBytes, transferEncoding: "base64", charset: "utf-8"
        )),
        MailByteCase(name: "fixture/iso88591", input: .text(
            bytes: EmailFixtureCorpus.iso88591Bytes, transferEncoding: nil, charset: "iso-8859-1"
        )),
        MailByteCase(name: "fixture/windows1252", input: .text(
            bytes: EmailFixtureCorpus.windows1252Bytes, transferEncoding: nil, charset: "windows-1252"
        )),
        MailByteCase(name: "fixture/undecodable", input: .text(
            bytes: EmailFixtureCorpus.undecodableUTF8Bytes, transferEncoding: nil, charset: "utf-8"
        )),
    ]

    /// Every case of `FormatEdgeCorpus.mail`, each through the function its own input names.
    static let formatEdge: [MailByteCase] = FormatEdgeCorpus.mail.map { mail in
        let input: MailByteCase.Input = switch mail.input {
        case .html(let html): .html(html)
        case .part(let bytes, let charset): .text(bytes: Data(bytes), transferEncoding: nil, charset: charset)
        case .encodedWord(let value): .encodedWord(value)
        case .parameter(let name, let raw): .parameter(name: name, raw: raw)
        case .subjectOf(let block): .subjectOf(block)
        }
        return MailByteCase(name: "edge/\(mail.name)", input: input)
    }

    /// What Task 4's reducer change touches: CRLF at a break, closer case, non-ASCII near a
    /// closer (the Kelvin sign U+212A, `ſ` U+017F, `İ` U+0130, a combining acute), and
    /// whitespace-only paragraphs of U+00A0, U+2028 and U+3000.
    static let reducerVariants: [MailByteCase] = [
        ("crlfBeforeParagraphClose", "<p>a\r\n</p><p>b</p>"),
        ("crlfBeforeBreak", "<div>x\r\n<br></div>"),
        ("crlfEverywhere", "<p>uno\r\n</p>\r\n<p>due\r\n\r\n</p>\r\n<div>tre\r\n<br>\r\n</div>"),
        ("crlfOnlyParagraph", "<p>a</p><p>\r\n</p><p>b</p>"),
        ("upperCaseStyle", "<STYLE>p { color: red; }</STYLE><p>testo</p>"),
        ("mixedCaseScript", "<ScRiPt>alert('x')</sCrIpT><p>dopo</p>"),
        ("mixedCaseComment", "<!-- MiXeD cAsE --><p>commento</p><!-- ancora -- ><p>fine</p>"),
        ("unterminatedComment", "<p>prima</p><!-- mai chiuso"),
        ("kelvinAfterCloser", "<style>a</style>\u{212A}<p>\u{212A}elvin</p>"),
        ("longSInsideCloser", "<style>x</\u{017F}tyle>y</style><p>z</p>"),
        ("dottedIInsideCloser", "<script>x</scr\u{0130}pt>y</script><p>z</p>"),
        ("combiningMarkOnCloser", "<style>a</style\u{0301}>b</style><p>c</p>"),
        ("combiningMarkAfterCloser", "<style>a</style>\u{0301}<p>e\u{0301}</p>"),
        ("nbspParagraph", "<p>\u{00A0}</p><p>a</p><p>\u{00A0}\u{00A0}</p><p>b</p>"),
        ("lineSeparatorParagraph", "<p>\u{2028}</p><p>b</p><div>\u{2028}</div><p>c</p>"),
        ("ideographicSpaceParagraph", "<p>\u{3000}</p><p>c</p><br>\u{3000}<br><p>d</p>"),
        ("entityNbspParagraph", "<p>&nbsp;</p><p>e</p>"),
        ("breaksAfterEmptyStart", "<br><br><p></p><p>primo</p>"),
    ].map { MailByteCase(name: "variant/\($0.0)", input: .html($0.1)) }

    /// What Task 4's decoder change touches: the delimiter-line comparison.
    static let decoderVariants: [MailByteCase] = [
        ("boundaryTrailingWhitespace", """
        Content-Type: multipart/mixed; boundary="B1"\r\n\r\n--B1 \r\nContent-Type: text/plain\r\n\r\nuno\r\n\
        --B1\t\r\nContent-Type: text/plain\r\n\r\ndue\r\n--B1 \t \r\nContent-Type: text/plain\r\n\r\ntre\r\n--B1--  \r\n
        """),
        ("boundaryBareLF", "Content-Type: multipart/mixed; boundary=\"B2\"\n\n"
            + "--B2\nContent-Type: text/plain\n\nuno\n--B2--\n"),
        ("boundaryWithTrailingText", """
        Content-Type: multipart/mixed; boundary="B3"\r\n\r\n--B3\r\nContent-Type: text/plain\r\n\r\nuno\r\n\
        --B3 no\r\nancora uno\r\n--B3-- \r\n
        """),
        ("nestedBoundaryExtendsOuter", """
        Content-Type: multipart/mixed; boundary="----=_X"\r\n\r\n------=_X\r\n\
        Content-Type: multipart/alternative; boundary="----=_X-alt"\r\n\r\n------=_X-alt\r\n\
        Content-Type: text/plain\r\n\r\npiano\r\n------=_X-alt\r\nContent-Type: text/html\r\n\r\n<p>ricco</p>\r\n\
        ------=_X-alt--\r\n------=_X\r\nContent-Type: text/plain\r\n\r\nfine\r\n------=_X--\r\n
        """),
        ("noClosingDelimiter", """
        Content-Type: multipart/mixed; boundary="B4"\r\n\r\n--B4\r\nContent-Type: text/plain\r\n\r\nuno\r\n\
        --B4\r\nContent-Type: text/plain\r\n\r\ndue senza chiusura\r\n
        """),
        ("noClosingDelimiterEmptyTail", """
        Content-Type: multipart/mixed; boundary="B5"\r\n\r\n--B5\r\nContent-Type: text/plain\r\n\r\nuno\r\n--B5\r\n
        """),
        ("nonASCIIBoundaryBody", """
        Content-Type: multipart/mixed; boundary="B6"\r\n\r\n--B6\r\nContent-Type: text/plain; charset=utf-8\r\n\
        Content-Transfer-Encoding: 8bit\r\n\r\ncittà €\r\n--B6--\r\n
        """),
    ].map { MailByteCase(name: "variant/\($0.0)", input: .message($0.1)) }

    static let cases: [MailByteCase] = emailFixtureHTML + emailFixtureMessages + emailFixtureText
        + formatEdge + reducerVariants + decoderVariants
}

private func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// Recorded from one run on the baseline tree, `3cdc97fb`, before Task 4 changed anything.
private let recordedDigests: [String: String] = [
    "edge/adjacentWords": "c2260f66233557b4b18f875b1f7a55dd33592bb105e193eb33a5e98dfa3c2354",
    "edge/foldedSubject": "ec62f0aa45bcdf6ba6b40350cdc04fe8dddca901de6d5b413eceb24ec657b2ca",
    "edge/latin9Part": "593845566b0cd4a66cd2e56e97414587768b6eb8b09bac2a86c49d5cf6df92f2",
    "edge/latin9Word": "0c6c5b80ba07c62ff61408265cf9e45b97d1489baf00bfe952a74f544127192a",
    "edge/nestedUnclosed": "fea4c5ce720c1d6a1cbc47c1607cc4ea172a69de8948e76d67910120597950fc",
    "edge/quotedSemicolon": "d107942d38b694463325c13ee21ee3a0ee80d5a8b353886f248015ea05c95b9f",
    "edge/rfc2231Continuations": "713381f2037a7499fe06f8b95f063e3f6288e67bb544ada4e2bfa736da8daf2b",
    "edge/rfc2231Filename": "cc26d70cdafa6e076aa7ad75b48266e20251cfa9e90875b75c9cd3ee8b4f1ab7",
    "edge/unclosedAnchor": "a18ae90d527afd480681bc35ebd0a7ea57be1f075a9a7dbadae3dadbb924f00a",
    "edge/unclosedCells": "e4a6c0e512f16c906c527fcdf06ca4e7bec4528d802f675f679051a004d9d68d",
    "edge/unpaddedBWord": "b133a0c0e9bee3be20163d2ad31d6248db292aa6dcb1ee087a2aa50e0fc75ae2",
    "fixture/base64": "36c134e76a8e9135435f5ea55ea67c57bd60dcb5941d617de5eb7745df6b4ff8",
    "fixture/completeMessage": "60ec84b75b56b81604176d82fa2f3ffac58f8d9a6ed84941e924ae353016e03a",
    "fixture/eightBit": "74486d610c94568c13bdf76de467bf3fb915a5f6023979874dcd4cca877c0649",
    "fixture/headersOnlyMessage": "3ee616e777d0fe845788120e893a3fb01eb57a3d6ea2cafe525fd9f083be5e39",
    "fixture/htmlBold": "bc80c4a71b860ef5414a2747e839e48aed16959fd957f147e2344eaeb6d2f2f4",
    "fixture/htmlInlineImages": "306d75eb577daafcf5e0876202c2dc00d4fa0c41b946c5a4bb8381fa37bc855d",
    "fixture/htmlInlineImagesWithPlainAlternative": "d5cb3c44c4ad13f77cd43ba020c6332bb2a009b9a2f8e9738acac2e3e12b366b",
    "fixture/htmlLink": "6f683fe9fb36430de45062ab3d71a2497e6d7258d38f159ef93fc711011edd50",
    "fixture/htmlOrderedList": "243b8d876da7ce1493c9a9bf6435653f9dc7a721bf6accb4dcdeedf4eea9aefb",
    "fixture/htmlParagraphsAndBreak": "0601a5c519376dc6d81247d178c8f573ff409eec45f2fbd29c1ec0f5fd3dd458",
    "fixture/htmlRemoteImage": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "fixture/htmlTable": "259580fdf7897df891cfa2478597629befebd5ec1f8374160754502c683b6213",
    "fixture/htmlTrackingPixel": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "fixture/htmlUnorderedList": "7e705050e737eb3edc033d56cbdf4e31cd27af7edee74f7fa423ac33651b8235",
    "fixture/htmlWithStyleAndScript": "06f0d4112678197c9b468c7aee24607e8e87d85ce0102125d63ffdc901e49bda",
    "fixture/iso88591": "74486d610c94568c13bdf76de467bf3fb915a5f6023979874dcd4cca877c0649",
    "fixture/mixedMultipartMessage": "ba531f5755c80e117a23895047a6d6f20a2dc6f282c9751a35278d699e3ee114",
    "fixture/mixedValidAndTruncated": "03f6e35ac167f83faedca51cdd89a47621395fd8a2867daeeede2f82d9ef08b5",
    "fixture/quotedPrintable": "74486d610c94568c13bdf76de467bf3fb915a5f6023979874dcd4cca877c0649",
    "fixture/sevenBit": "231e0ff1f71c698c378b089ff6a33ec52b0d49a425684aff229e79f487dbe58e",
    "fixture/signatureInlineImagesReply": "e5859c68affc2a990c0bd7e70fc6cb3913963ea53d5fc0ae92534d228f333a4c",
    "fixture/singleAttachment": "5bc69dbe4b94bb61f3efe63cc799955e2ba1d776404915dead2726587e942b21",
    "fixture/singleInlineImage": "3f2ef5b58365fe8043039f3f1c96c9170793bb5ff819ba739503e544f0b5fb2a",
    "fixture/truncatedAttachment": "b4b3c6f505463dbe55b7cdef36d5b15cc61b985e2ae8cdb8c554b89390d3a17e",
    "fixture/undecodable": "b9070035264f4bad638fbb193b6a0e0a1453a4a7b340a3907e06c43c3f7c19b4",
    "fixture/windows1252": "c7c6f386f6e67fd01f80ac8c11a6f8ae88b3024d1e6610f97c7e4b6f5d38e09d",
    "fixture/zeroByteAttachment": "b7f9b934f58699f54add1f3ade8f89b01839ac5e2585c1c290e57116ec4293db",
    "variant/boundaryBareLF": "f503d172c5c977875d4567702220c58dffe33e6890fc30a424f6240564a97a58",
    "variant/boundaryTrailingWhitespace": "30103d53506ab042c1ee0daeed1896a1f8382b1e909d694705169e2dff5e61aa",
    "variant/boundaryWithTrailingText": "57b6bfd0143782e9008dec99a11f55f6c7f7ad71dde0ee79977f69ac66e1da9d",
    "variant/breaksAfterEmptyStart": "ae4987f717baa7a0a79b14de868330c364628a3245c09313150b6fe0687e1f66",
    "variant/combiningMarkAfterCloser": "bf12767b0f2a56b2190075bae8169f656e3ce8d6357d4aff184bc6c7ea48f9f6",
    "variant/combiningMarkOnCloser": "2e7d2c03a9507ae265ecf5b5356885a53393a2029d241394997265a1a25aefc6",
    "variant/crlfBeforeBreak": "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881",
    "variant/crlfBeforeParagraphClose": "265cdacabc27022b40401e011437ec7552b75daafe3491c8009865c8329596db",
    "variant/crlfEverywhere": "05d13c3b2f8739f8217a5a692d08b57ed8829261e7f799d3831ceab39af44349",
    "variant/crlfOnlyParagraph": "38022fd2b8dbc5cb3d2cee74e083edbf59e3d4e13d067ebcb5db633d4cff4d8c",
    "variant/dottedIInsideCloser": "594e519ae499312b29433b7dd8a97ff068defcba9755b6d5d00e84c524d67b06",
    "variant/entityNbspParagraph": "3f79bb7b435b05321651daefd374cdc681dc06faa65e374e38337b88ca046dea",
    "variant/ideographicSpaceParagraph": "2cc29fc1646acc5644ae081517dccb621d14ab6f4e901a75aafc550d3644bcdd",
    "variant/kelvinAfterCloser": "c6dd4d0176809e060c6c4a8e4ade1709fcb321ec9d996cb2b9837041a307b02e",
    "variant/lineSeparatorParagraph": "f392520376c0647a0200f3068a4ca2767b61312e928f496ed59c5b5b4a677642",
    "variant/longSInsideCloser": "594e519ae499312b29433b7dd8a97ff068defcba9755b6d5d00e84c524d67b06",
    "variant/mixedCaseComment": "bb992fbbd5fa9f2e7436e2b5bfa9ff682a5be0dbd0b0dc6008ca3976b3acaba4",
    "variant/mixedCaseScript": "88c80da5cadb0542310ab1716fabd3c37b70854a1ec47e86b31425ba7d2f39b4",
    "variant/nbspParagraph": "38022fd2b8dbc5cb3d2cee74e083edbf59e3d4e13d067ebcb5db633d4cff4d8c",
    "variant/nestedBoundaryExtendsOuter": "c69023af3e7ff1dc4f42d6406b015abc30cb9f1f6345631aa3ce8379f918e17f",
    "variant/noClosingDelimiter": "dd5fc64b287b2a89c0d83cef79ec3baa47fe1d9527ad4a500ac4d3444cc0de0a",
    "variant/noClosingDelimiterEmptyTail": "f503d172c5c977875d4567702220c58dffe33e6890fc30a424f6240564a97a58",
    "variant/nonASCIIBoundaryBody": "69c13882029ef20e8fb4b2d422d3e369329a0b40a640bfe1ea2c8714b5ab7838",
    "variant/unterminatedComment": "51365d01e295763226b90cadb302b717b086f77b8fab3384996038163c2baf7d",
    "variant/upperCaseStyle": "7ca0172850c53065046beeac3cdec3fe921532dbfebdf7efeb5c33d019cd7798",
]

@Test(arguments: MailByteCorpus.cases)
func mailOutputIsByteIdenticalToTheBaselineRun(_ byteCase: MailByteCase) {
    let output = byteCase.output
    let digest = sha256Hex(output)
    #expect(
        recordedDigests[byteCase.name] == digest,
        "RECORD \(byteCase.name)=\(digest) output: \(output.debugDescription)"
    )
}

@Test func everyMailByteCaseHasAUniqueName() {
    let names = MailByteCorpus.cases.map(\.name)
    #expect(Set(names).count == names.count)
    #expect(Set(names) == Set(recordedDigests.keys))
}
