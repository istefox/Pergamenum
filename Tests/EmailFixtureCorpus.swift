import Foundation

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
    cGRmLWJ5dGVz\r
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
        Content-Disposition: inline; filename="inline.png"\r
        \r
        \(imageBytes.base64EncodedString())\r
        --\(boundary)--\r
        """
    }
}
