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

    // MARK: - `partNumber` (ADR-0048): RFC 3501 body-part numbering, not decode order

    @Test func aFlatMultipartMixedNumbersItsAttachmentTwo() {
        // `singleAttachmentMessageRFC822` is one `multipart/mixed` with two direct
        // children, no nesting: text/plain, then the attachment.
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "flat@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes()
        )
        let parts = MIMEDecoder.decode(Data(message.utf8))
        #expect(parts.first { $0.kind == .textPlain }?.partNumber == "1")
        let attachment = parts.first {
            if case .attachment(filename: "offerta.pdf") = $0.kind { true } else { false }
        }
        #expect(attachment?.partNumber == "2")
    }

    @Test func aNestedAlternativeNumbersItsChildrenUnderTheSlotItConsumesInItsParent() {
        let boundary = "----=_Pergamenum_PartNumber_Mixed"
        let altBoundary = "----=_Pergamenum_PartNumber_Alt"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con alternativa e allegato\r
        Message-Id: <nested-alt@rossi-spa.it>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: multipart/alternative; boundary="\(altBoundary)"\r
        \r
        --\(altBoundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato la nostra offerta.\r
        --\(altBoundary)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        <p>Buongiorno, in allegato la nostra offerta.</p>\r
        --\(altBoundary)--\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="offerta.pdf"\r
        \r
        \(EmailFixtureCorpus.pdfBytes().base64EncodedString())\r
        --\(boundary)--\r
        """
        let parts = MIMEDecoder.decode(Data(message.utf8))

        // The alternative container consumes slot "1" of the outer `multipart/mixed`
        // but produces no `MIMEPart` of its own - only its two children do, numbered
        // "1.1"/"1.2" - and the sibling attachment, `mixed`'s own second child, is
        // "2", not "3": the container's slot is spent, never inherited by what follows.
        #expect(parts.first { $0.kind == .textPlain }?.partNumber == "1.1")
        #expect(parts.first { $0.kind == .textHTML }?.partNumber == "1.2")
        let attachment = parts.first {
            if case .attachment(filename: "offerta.pdf") = $0.kind { true } else { false }
        }
        #expect(attachment?.partNumber == "2")
    }

    @Test func aThreeLevelNestingNumbersEachDepthRecursively() {
        let mixedBoundary = "----=_Pergamenum_PartNumber_Mixed3"
        let relatedBoundary = "----=_Pergamenum_PartNumber_Related3"
        let altBoundary = "----=_Pergamenum_PartNumber_Alt3"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con struttura a tre livelli\r
        Message-Id: <nested-three@rossi-spa.it>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(mixedBoundary)"\r
        \r
        --\(mixedBoundary)\r
        Content-Type: multipart/related; boundary="\(relatedBoundary)"\r
        \r
        --\(relatedBoundary)\r
        Content-Type: multipart/alternative; boundary="\(altBoundary)"\r
        \r
        --\(altBoundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, vedi immagine inline.\r
        --\(altBoundary)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        <p>Buongiorno, vedi immagine inline.</p>\r
        --\(altBoundary)--\r
        --\(relatedBoundary)\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <img1>\r
        Content-Disposition: inline; filename="img1.png"\r
        \r
        aW1nLWJ5dGVz\r
        --\(relatedBoundary)--\r
        --\(mixedBoundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="offerta.pdf"\r
        \r
        \(EmailFixtureCorpus.pdfBytes().base64EncodedString())\r
        --\(mixedBoundary)--\r
        """
        let parts = MIMEDecoder.decode(Data(message.utf8))

        // `mixed` › `related` (slot "1") › `alternative` (slot "1.1"): the two
        // container levels each consume one slot in their own parent's numbering and
        // produce no `MIMEPart`, so the plain/html pair lands three levels deep.
        #expect(parts.first { $0.kind == .textPlain }?.partNumber == "1.1.1")
        #expect(parts.first { $0.kind == .textHTML }?.partNumber == "1.1.2")
        #expect(parts.first { $0.kind == .inlineImage(contentID: "img1") }?.partNumber == "1.2")
        let attachment = parts.first {
            if case .attachment(filename: "offerta.pdf") = $0.kind { true } else { false }
        }
        #expect(attachment?.partNumber == "2")
    }
}
