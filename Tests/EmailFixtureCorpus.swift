import CoreGraphics
import Foundation
import ImageIO

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-04,
// R-05, R-06, R-07.
//
// Every byte in this file is authored here, by hand - nothing is copied out of
// `~/Library/Mail` or out of anybody's real correspondence, the same rule
// `Tests/MailStoreFixture.swift` follows for the index (ADR §D7). Names, addresses and
// subjects are placeholders ("Rossi", "rossi-spa.it") already used elsewhere in this
// ADR's own worked examples.

enum EmailFixtureCorpus {
    // MARK: - `.emlx` container (R-04)

    /// `"<N>\n" + N bytes of RFC 822 + a trailing plist` - the container format
    /// `EMLXReader.parse(_:)` reads (ADR §D4 follow-up).
    static func emlxContainer(rfc822: String, plist: Data = samplePlist) -> Data {
        let body = Data(rfc822.utf8)
        var data = Data("\(body.count)\n".utf8)
        data.append(body)
        data.append(plist)
        return data
    }

    static let samplePlist = Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>flags</key><integer>16777222</integer></dict></plist>
        """.utf8
    )

    /// A complete message: headers, a blank line, and a body.
    static let completeMessageRFC822 = """
    From: Mario Rossi <m.rossi@rossi-spa.it>\r
    To: Stefano Ferri <stefano@stefer.it>\r
    Subject: Richiesta offerta\r
    Message-Id: <abc123@rossi-spa.it>\r
    Date: Wed, 10 Jun 2026 14:06:10 +0200\r
    \r
    Buongiorno,\r
    le scrivo per una richiesta di offerta.\r
    """

    /// A `.partial.emlx`-shaped message: headers, then nothing - Exchange's
    /// not-yet-downloaded body (SPEC "The `.emlx` container and «body not
    /// downloaded»").
    static let headersOnlyMessageRFC822 = """
    From: Mario Rossi <m.rossi@rossi-spa.it>\r
    To: Stefano Ferri <stefano@stefer.it>\r
    Subject: Richiesta offerta (corpo in arrivo)\r
    Message-Id: <pending123@rossi-spa.it>\r
    Date: Wed, 10 Jun 2026 14:06:10 +0200\r
    \r
    """

    // MARK: - MIME transfer encodings and charsets (R-05)
    //
    // Tested directly against `MIMEDecoder.decodeText(_:transferEncoding:charset:)`,
    // which takes raw part bytes - no envelope needed for these.

    static let sevenBitASCIIBytes = Data("Ciao mondo".utf8)

    /// Already UTF-8 - `8bit` means "no transfer encoding was applied", not "not
    /// UTF-8".
    static let eightBitUTF8Bytes = Data("città".utf8)

    /// `quoted-printable` for "città" (UTF-8 charset): `=C3=A0` is the UTF-8 encoding
    /// of `à`.
    static let quotedPrintableUTF8Bytes = Data("citt=C3=A0".utf8)

    /// `base64` for "Ciao mondo!".
    static let base64PlainBytes = Data(Data("Ciao mondo!".utf8).base64EncodedString().utf8)

    /// Raw `iso-8859-1` bytes for "città": `0xE0` is `à` in that charset (not valid
    /// UTF-8 on its own).
    static let iso88591Bytes = Data([0x63, 0x69, 0x74, 0x74, 0xE0])

    /// Raw `windows-1252` bytes for "Sì’" - `0xEC` is one way this fixture spells `ì`. `0x92` is the curly
    /// apostrophe CP1252 puts where Latin-1 has a control character.
    static let windows1252Bytes = Data([0x53, 0x69, 0x92])

    /// `0xFF` is not valid UTF-8 on its own - the undecodable-bytes case (R-05: "→
    /// U+FFFD").
    static let undecodableUTF8Bytes = Data([0x41, 0xFF, 0x42])

    // MARK: - Part classification (R-05)

    static let classificationBoundary = "----=_Pergamenum_Test_Boundary"

    /// One `multipart/mixed` message carrying, in order: a `multipart/alternative`
    /// (plain + HTML), an inline `cid:` image, a normal attachment, and a
    /// `winmail.dat`/TNEF attachment (kept as-is, never decoded).
    static let mixedMultipartMessageRFC822 = """
    From: Mario Rossi <m.rossi@rossi-spa.it>\r
    To: Stefano Ferri <stefano@stefer.it>\r
    Subject: Offerta con allegati\r
    Message-Id: <mixed1@rossi-spa.it>\r
    Content-Type: multipart/mixed; boundary="\(classificationBoundary)"\r
    \r
    --\(classificationBoundary)\r
    Content-Type: multipart/alternative; boundary="\(classificationBoundary)-alt"\r
    \r
    --\(classificationBoundary)-alt\r
    Content-Type: text/plain; charset=utf-8\r
    Content-Transfer-Encoding: 7bit\r
    \r
    Buongiorno, in allegato la nostra offerta.\r
    --\(classificationBoundary)-alt\r
    Content-Type: text/html; charset=utf-8\r
    Content-Transfer-Encoding: 7bit\r
    \r
    <p>Buongiorno, in allegato la nostra offerta.</p>\r
    --\(classificationBoundary)-alt--\r
    --\(classificationBoundary)\r
    Content-Type: image/png\r
    Content-Transfer-Encoding: base64\r
    Content-ID: <logo1>\r
    Content-Disposition: inline; filename="logo.png"\r
    \r
    aGVsbG8=\r
    --\(classificationBoundary)\r
    Content-Type: application/pdf\r
    Content-Transfer-Encoding: base64\r
    Content-Disposition: attachment; filename="offerta.pdf"\r
    \r
    \(pdfBytes().base64EncodedString())\r
    --\(classificationBoundary)\r
    Content-Type: application/ms-tnef; name="winmail.dat"\r
    Content-Transfer-Encoding: base64\r
    Content-Disposition: attachment; filename="winmail.dat"\r
    \r
    dG5lZi1ieXRlcw==\r
    --\(classificationBoundary)--\r
    """

    // MARK: - HTML → light markdown (R-06)

    static let htmlParagraphsAndBreak = "<p>Prima riga.<br>Seconda riga.</p><p>Secondo paragrafo.</p>"
    static let htmlUnorderedList = "<ul><li>Uno</li><li>Due</li></ul>"
    static let htmlOrderedList = "<ol><li>Uno</li><li>Due</li></ol>"
    static let htmlLink = #"<a href="https://vibrofer.it">il sito</a>"#
    static let htmlBold = "<b>importante</b> e <strong>anche questo</strong>"
    static let htmlTable = """
    <table><tr><th>Nome</th><th>Prezzo</th></tr><tr><td>Staffa</td><td>12</td></tr></table>
    """
    static let htmlWithStyleAndScript = """
    <style>p { color: red; }</style><script>alert('x')</script><p>testo vero</p>
    """
    static let htmlRemoteImage = #"<img src="https://tracker.example.test/logo.png" width="200" height="80">"#
    static let htmlTrackingPixel = #"<img src="https://tracker.example.test/pixel.gif" width="1" height="1">"#

    // MARK: - Quoted-text rules (R-07): at least five separator styles

    /// Italian Mail.app: "Il giorno … ha scritto:".
    static let italianMailQuote = """
    Va bene, grazie mille.

    Il giorno 9 giu 2026, alle ore 18:02, Mario Rossi <m.rossi@rossi-spa.it> ha scritto:
    > Buongiorno, quando arriva la consegna?
    """

    /// Italian Outlook: the "Da:/Inviato:/A:/Oggetto:" header block.
    static let italianOutlookQuote = """
    Confermo per giovedì.

    Da: Mario Rossi <m.rossi@rossi-spa.it>
    Inviato: martedì 9 giugno 2026 18:02
    A: Stefano Ferri <stefano@stefer.it>
    Oggetto: Richiesta offerta

    Buongiorno, quando arriva la consegna?
    """

    /// English Gmail: "On … wrote:".
    static let englishGmailQuote = """
    Sounds good, thank you.

    On Tue, 9 Jun 2026 at 18:02, Mario Rossi <m.rossi@rossi-spa.it> wrote:
    > Good morning, when does the delivery arrive?
    """

    /// Bare `>` quoting, no separator line at all - every remaining non-empty line
    /// starts with `>`.
    static let bareAngleBracketQuote = """
    Perfetto, a giovedì allora.

    > Buongiorno, quando arriva la consegna?
    > Fatemi sapere appena possibile.
    """

    /// Outlook's underscore divider.
    static let outlookUnderscoreDividerQuote = """
    Confermo ricevuto.

    ________________________________
    Da: Mario Rossi <m.rossi@rossi-spa.it>
    Inviato: martedì 9 giugno 2026 18:02
    Oggetto: Richiesta offerta

    Buongiorno, quando arriva la consegna?
    """

    /// No recognised separator at all - the body must stay whole.
    static let noQuoteAtAll = """
    Buongiorno, confermo la disponibilità per giovedì alle 15:00.
    Restiamo in contatto.
    """

    /// A signature after the standard `-- ` marker (dash, dash, space - the trailing
    /// space is significant to the rule, so it is appended explicitly rather than
    /// relying on a multiline literal to keep it), with no quoted history at all.
    static let signatureOnlyNoQuote =
        "Buongiorno, confermo la disponibilità per giovedì.\n"
        + "-- \n"
        + "Mario Rossi\n"
        + "Ufficio acquisti\n"
        + "Rossi S.p.A."

    // MARK: - Task 4 (R-09, R-10): one controllable attachment or inline image
    //
    // `mixedMultipartMessageRFC822` above fixes its own filenames/content/sizes;
    // these two let a sync test control exactly one attachment's or one inline
    // image's name, bytes and size, which is what R-10's naming, SHA-256 linking,
    // collision and threshold rules need to exercise independently of each other.

    /// One `multipart/mixed` message carrying a single ordinary attachment part.
    static func singleAttachmentMessageRFC822(
        messageID: String,
        subject: String = "Con allegato",
        attachmentFilename: String,
        attachmentBytes: Data,
        boundary: String = "----=_Pergamenum_Attachment_Boundary"
    ) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: \(subject)\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato.\r
        --\(boundary)\r
        Content-Type: application/octet-stream\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="\(attachmentFilename)"\r
        \r
        \(attachmentBytes.base64EncodedString())\r
        --\(boundary)--\r
        """
    }

    /// One `multipart/related` message carrying a single inline image, referenced
    /// from the plain-text body by `cid:<contentID>` (R-10's inline-image rule).
    static func singleInlineImageMessageRFC822(
        messageID: String,
        subject: String = "Con immagine inline",
        contentID: String,
        imageBytes: Data,
        filename: String = "inline.png",
        boundary: String = "----=_Pergamenum_Inline_Boundary"
    ) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: \(subject)\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/related; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, vedi immagine cid:\(contentID)\r
        --\(boundary)\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <\(contentID)>\r
        Content-Disposition: inline; filename="\(filename)"\r
        \r
        \(imageBytes.base64EncodedString())\r
        --\(boundary)--\r
        """
    }

    // MARK: - ADR-0042 (Pratiche inline image placeholders) — Task 3, R-11
    //
    // A real HTML+inline-images mail nests `multipart/alternative` (plain, html) inside
    // `multipart/related`, with the inline image parts as further `related` siblings -
    // the shape `htmlToMarkdown`/`bodyText` and the decode loop actually have to walk,
    // not a flattened stand-in for it.

    /// One inline image descriptor for the HTML fixtures below: `contentID` is what the
    /// HTML's `<img src="cid:…">` and the part's own `Content-ID` header both carry;
    /// `bytes` empty means "Mail hasn't downloaded this part yet" (ADR-0040 §D1).
    struct InlineImageSpec {
        let contentID: String
        let filename: String
        let bytes: Data

        init(contentID: String, filename: String = "img.png", bytes: Data) {
            self.contentID = contentID
            self.filename = filename
            self.bytes = bytes
        }
    }

    private static func inlineImagePart(_ image: InlineImageSpec, boundary: String) -> String {
        """
        --\(boundary)\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <\(image.contentID)>\r
        Content-Disposition: inline; filename="\(image.filename)"\r
        \r
        \(image.bytes.base64EncodedString())\r

        """
    }

    private static func alternativePart(
        plainText: String, html: String, boundary: String
    ) -> String {
        """
        Content-Type: multipart/alternative; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        \(plainText)\r
        --\(boundary)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        \(html)\r
        --\(boundary)--\r

        """
    }

    /// Case 1 (ADR-0042 finding 1, part A): the HTML part embeds every `image` through
    /// `<img src="cid:…">`, and the plain-text alternative is empty - so `bodyText`
    /// falls through to the HTML reduction and the body really carries `![alt](cid:…)`
    /// constructs (R-11).
    static func htmlInlineImagesMessageRFC822(
        messageID: String,
        subject: String = "Newsletter con immagini inline",
        images: [InlineImageSpec],
        outerBoundary: String = "----=_Pergamenum_Related_Boundary",
        altBoundary: String = "----=_Pergamenum_Alternative_Boundary"
    ) -> String {
        let imageTags = images.map { "<img src=\"cid:\($0.contentID)\">" }.joined(separator: "<br>")
        let imageParts = images.map { inlineImagePart($0, boundary: outerBoundary) }.joined()
        return """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: \(subject)\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/related; boundary="\(outerBoundary)"\r
        \r
        --\(outerBoundary)\r
        \(alternativePart(plainText: "", html: "<html><body><p>Ciao,</p>\(imageTags)</body></html>", boundary: altBoundary))\(imageParts)--\(outerBoundary)--\r
        """
    }

    /// Case 2 (ADR-0042 finding 1, part B - the reported defect): identical to
    /// `htmlInlineImagesMessageRFC822`, except the plain-text alternative is a real body
    /// that never mentions any `cid:` id - because `bodyText` prefers `text/plain` when
    /// it is non-empty, none of the images' ids are ever referenced, and R-03 requires
    /// no placeholder, no pending state, at all.
    static func htmlInlineImagesWithPlainAlternativeRFC822(
        messageID: String,
        subject: String = "Newsletter con immagini inline",
        plainText: String = "Ciao, questa è la versione testuale della newsletter.",
        images: [InlineImageSpec],
        outerBoundary: String = "----=_Pergamenum_Related_Boundary",
        altBoundary: String = "----=_Pergamenum_Alternative_Boundary"
    ) -> String {
        let imageTags = images.map { "<img src=\"cid:\($0.contentID)\">" }.joined(separator: "<br>")
        let imageParts = images.map { inlineImagePart($0, boundary: outerBoundary) }.joined()
        return """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: \(subject)\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/related; boundary="\(outerBoundary)"\r
        \r
        --\(outerBoundary)\r
        \(alternativePart(plainText: plainText, html: "<html><body><p>Ciao,</p>\(imageTags)</body></html>", boundary: altBoundary))\(imageParts)--\(outerBoundary)--\r
        """
    }

    /// Case 3 (ADR-0042 §D6): a reply whose new text, quoted history and signature each
    /// reference one distinct inline image - `newText`'s id is the *last* MIME part and
    /// `signature`'s id is the *first*, so a test asserting `pendingInlineImages` in file
    /// order (new text, quoted, signature) fails if the code ever used MIME/decode order
    /// instead of the post-`QuoteSplitter.split` render order.
    static func signatureInlineImagesReplyRFC822(
        messageID: String,
        subject: String = "Re: Richiesta offerta",
        newTextImage: InlineImageSpec,
        quotedImage: InlineImageSpec,
        signatureImage: InlineImageSpec,
        outerBoundary: String = "----=_Pergamenum_Reply_Boundary",
        altBoundary: String = "----=_Pergamenum_ReplyAlternative_Boundary"
    ) -> String {
        // MIME order deliberately reversed against reading order: the signature image's
        // part comes first, the new-text image's part comes last.
        //
        // `QuoteSplitter.split` only ever looks for a `-- ` signature marker inside the
        // text BEFORE its own quote cut (`withSignature` is applied to that chunk alone)
        // - so the one plain-text layout that actually produces all three of newText,
        // signature and quotedHistory is signature-before-quote, not the top-posted
        // "quote then signature" shape a real client would send. This fixture exists to
        // exercise the render-order invariant (ADR-0042 §D6), not to model a realistic
        // reply.
        let plainText = """
        Buongiorno,

        confermo quanto sotto, vedi immagine cid:\(newTextImage.contentID)
        --
        Mario Rossi
        cid:\(signatureImage.contentID)

        > Il giorno 9 giu 2026, alle ore 18:02, Stefano Ferri ha scritto:
        > cid:\(quotedImage.contentID)
        """
        let imageParts = [signatureImage, quotedImage, newTextImage]
            .map { inlineImagePart($0, boundary: outerBoundary) }.joined()
        return """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: \(subject)\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/related; boundary="\(outerBoundary)"\r
        \r
        --\(outerBoundary)\r
        \(alternativePart(plainText: plainText, html: "", boundary: altBoundary))\(imageParts)--\(outerBoundary)--\r
        """
    }

    /// Rebuilds `rfc822` with `oldContentID`'s inline part's bytes replaced by
    /// `newBytes`, keeping every other byte identical - the second `.emlx` a two-sync
    /// arrival test needs, differing from the first only in that one part's payload
    /// (Task 5).
    static func fillingInlineImageBytes(
        in rfc822: String, contentID: String, with newBytes: Data
    ) -> String {
        let marker = "Content-ID: <\(contentID)>\r\n"
        guard let markerRange = rfc822.range(of: marker) else { return rfc822 }
        guard let blankLineRange = rfc822.range(of: "\r\n\r\n", range: markerRange.upperBound..<rfc822.endIndex)
        else { return rfc822 }
        let payloadStart = blankLineRange.upperBound
        guard let payloadEnd = rfc822.range(of: "\r\n", range: payloadStart..<rfc822.endIndex)
        else { return rfc822 }
        return rfc822.replacingCharacters(
            in: payloadStart..<payloadEnd.lowerBound,
            with: newBytes.base64EncodedString()
        )
    }

    // MARK: - `AttachmentIntegrity` fixtures (ADR-0040 §D1, §D2 — Task 2, R-01, R-02, R-03, R-15)
    //
    // Byte sequences with the right head/tail for `AttachmentIntegrity.verdict` to read
    // (§D2), never a real PDF document — a real one is not what the six ordered rules
    // inspect.

    /// `%PDF-1.7`, some filler that varies with `pages` (so two different `pages` values
    /// produce genuinely different bytes, for the collision-vs-identical distinction in
    /// `Tests/PraticaSyncTests.swift`), `%%EOF`.
    static func pdfBytes(pages: Int = 1) -> Data {
        var text = "%PDF-1.7\n"
        for page in 1...Swift.max(pages, 1) {
            text += "obj \(page) 0 R /Type /Page\n"
        }
        text += "%%EOF\n"
        return Data(text.utf8)
    }

    /// The same head and filler as `pdfBytes(pages:)`, with no `%%EOF` at all.
    static func truncatedPDFBytes() -> Data {
        Data("%PDF-1.7\nobj 1 0 R /Type /Page\n".utf8)
    }

    /// R-15's first case: one `multipart/mixed` message whose single attachment part is
    /// empty.
    static func zeroByteAttachmentMessageRFC822(messageID: String, filename: String) -> String {
        singleAttachmentMessageRFC822(
            messageID: messageID, subject: "Allegato vuoto",
            attachmentFilename: filename, attachmentBytes: Data()
        )
    }

    /// R-15's second case: one `multipart/mixed` message whose single attachment part
    /// has non-empty bytes that fail the check for their declared type.
    static func truncatedAttachmentMessageRFC822(messageID: String, filename: String) -> String {
        singleAttachmentMessageRFC822(
            messageID: messageID, subject: "Allegato troncato",
            attachmentFilename: filename, attachmentBytes: truncatedPDFBytes()
        )
    }

    /// R-15's third case: two attachment parts under distinct filenames, one whose bytes
    /// pass the check and one whose bytes fail it.
    static func mixedValidAndTruncatedAttachmentsRFC822(
        messageID: String,
        boundary: String = "----=_Pergamenum_MixedAttachments_Boundary"
    ) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con due allegati\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato due file.\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="valido.pdf"\r
        \r
        \(pdfBytes().base64EncodedString())\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="troncato.pdf"\r
        \r
        \(truncatedPDFBytes().base64EncodedString())\r
        --\(boundary)--\r
        """
    }

    // MARK: - Real, ImageIO-decodable PNG bytes (`InlineImageClassifier` R-10 amendment)

    /// A solid-color PNG of the given pixel size, decodable by `CGImageSourceCreateWithData`
    /// like a real pasted image - unlike the placeholder byte blobs the other fixtures use, a
    /// classifier reading pixel dimensions needs bytes that are actually a PNG. A solid fill
    /// compresses tightly regardless of pixel dimensions, so this can produce a fixture that is
    /// light in bytes but large in pixels - the exact shape a real screenshot or photo takes.
    static func solidColorPNG(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            fatalError("EmailFixtureCorpus.solidColorPNG: CGContext/CGImage creation failed")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            fatalError("EmailFixtureCorpus.solidColorPNG: CGImageDestination creation failed")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("EmailFixtureCorpus.solidColorPNG: CGImageDestinationFinalize failed")
        }
        return data as Data
    }

    /// A pixel-noisy PNG of the given size, real and `CGImageSourceCreateWithData`-decodable
    /// like `solidColorPNG` - but where a solid fill compresses to almost nothing regardless of
    /// dimensions, deflate cannot meaningfully shrink uncorrelated pixel bytes, so this stays
    /// over `InlineImageClassifier.weightThreshold` at a moderate, fast-to-generate dimension.
    /// For a fixture that needs to be genuinely heavy in byte size while still passing
    /// `AttachmentIntegrity`'s real-PNG check (signature + `IEND`) and an actual ImageIO decode.
    static func noisyPNG(width: Int, height: Int) -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        // A small deterministic LCG, not `SystemRandomNumberGenerator` - the fixture must
        // produce the same bytes on every run. Alpha is left at the initial 0xFF fill so
        // every pixel stays opaque; only the RGB triplet is randomized.
        var state: UInt32 = 0x9E37_79B9
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8((state >> 24) & 0xFF)
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index + 1] = UInt8((state >> 24) & 0xFF)
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index + 2] = UInt8((state >> 24) & 0xFF)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Context, image and PNG encoding all happen inside the buffer's own lifetime -
        // `CGContext(data:)` wraps `pixels`' storage directly rather than copying it, so
        // nothing may read from the image after `pixels` could be deallocated or moved.
        let pngData: Data? = pixels.withUnsafeMutableBytes { rawBuffer -> Data? in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let image = context.makeImage()
            else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }
        guard let pngData else {
            fatalError("EmailFixtureCorpus.noisyPNG: CGContext/CGImageDestination pipeline failed")
        }
        return pngData
    }
}
