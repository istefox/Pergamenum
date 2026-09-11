import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-05.
//
// `MIMEDecoder` extends `EmailHeaderParser` (SPEC "Components"); it does not replace
// it. Every fixture here is synthetic (`Tests/EmailFixtureCorpus.swift`) - no test
// reads `~/Library/Mail`.

@Suite struct MIMEDecoderTests {
    // MARK: - Transfer encodings

    @Test func decodes7bitAsIs() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.sevenBitASCIIBytes, transferEncoding: "7bit", charset: "utf-8"
        )
        #expect(text == "Ciao mondo")
    }

    @Test func decodes8bitAsUTF8() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.eightBitUTF8Bytes, transferEncoding: "8bit", charset: "utf-8"
        )
        #expect(text == "città")
    }

    @Test func decodesQuotedPrintable() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.quotedPrintableUTF8Bytes, transferEncoding: "quoted-printable", charset: "utf-8"
        )
        #expect(text == "città")
    }

    @Test func decodesBase64() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.base64PlainBytes, transferEncoding: "base64", charset: "utf-8"
        )
        #expect(text == "Ciao mondo!")
    }

    // MARK: - Charsets

    @Test func decodesISOLatin1() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.iso88591Bytes, transferEncoding: "8bit", charset: "iso-8859-1"
        )
        #expect(text == "città")
    }

    @Test func decodesWindows1252() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.windows1252Bytes, transferEncoding: "8bit", charset: "windows-1252"
        )
        // 0x92 is the curly apostrophe U+2019 in CP1252, a control character in Latin-1.
        #expect(text.unicodeScalars.contains(Unicode.Scalar(0x2019)!))
    }

    @Test func undecodableBytesBecomeTheReplacementCharacter() {
        let text = MIMEDecoder.decodeText(
            EmailFixtureCorpus.undecodableUTF8Bytes, transferEncoding: "8bit", charset: "utf-8"
        )
        #expect(text.contains("\u{FFFD}"))
    }

    // MARK: - Part classification (R-05)

    @Test func classifiesEveryPartOfAMixedMultipartMessage() {
        let parts = MIMEDecoder.decode(Data(EmailFixtureCorpus.mixedMultipartMessageRFC822.utf8))
        #expect(parts.contains { $0.kind == .textPlain })
        #expect(parts.contains { $0.kind == .textHTML })
        #expect(parts.contains { $0.kind == .inlineImage(contentID: "logo1") })
        #expect(parts.contains { if case .attachment(filename: "offerta.pdf") = $0.kind { true } else { false } })
        #expect(parts.contains { if case .attachment(filename: "winmail.dat") = $0.kind { true } else { false } })
    }

    @Test func aPlainMessageWithNoBoundaryIsExactlyOnePart() {
        let parts = MIMEDecoder.decode(Data(EmailFixtureCorpus.completeMessageRFC822.utf8))
        #expect(parts.count == 1)
        #expect(parts.first?.kind == .textPlain)
    }
}
