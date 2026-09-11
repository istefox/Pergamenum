import Foundation
import Testing
@testable import Pergamenum

private let realisticEml = """
Return-Path: <marco.rossi@rossimpianti.test>
Received: from mail.rossimpianti.test (mail.rossimpianti.test [203.0.113.8])
\tby mx.example.test with ESMTPS id abc123
\tfor <stefano@stefer.it>; Tue, 4 Aug 2026 09:15:02 +0200 (CEST)
Message-ID: <8f2c1a44-9d3e-4c11-9a77-2b6f0e5d1c33@rossimpianti.test>
Date: Tue, 4 Aug 2026 09:15:00 +0200
From: "Rossi, Marco" <marco.rossi@rossimpianti.test>
To: Stefano Ferri <stefano@stefer.it>, ufficio@vibrofer.test
Subject: Richiesta offerta supporti antivibranti
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Buongiorno Stefano,
allego i dati di targa.
"""

@Test func parsesTheHeadersOfARealisticMessage() {
    let headers = EmailHeaderParser.parse(realisticEml)

    #expect(headers.from?.address == "marco.rossi@rossimpianti.test")
    #expect(headers.from?.name == "Rossi, Marco")
    #expect(headers.subject == "Richiesta offerta supporti antivibranti")
    #expect(headers.messageID == "8f2c1a44-9d3e-4c11-9a77-2b6f0e5d1c33@rossimpianti.test")
    #expect(headers.to.count == 2)
    #expect(headers.to.map(\.address) == ["stefano@stefer.it", "ufficio@vibrofer.test"])
}

@Test func stopsAtTheBlankLineEndingTheHeaders() {
    // A message with a 20 MB attachment must cost the same as an empty one, and a
    // body line that looks like a header must not become one.
    let message = realisticEml + "\n\nSubject: non e un header\n"
    let headers = EmailHeaderParser.parse(message)
    #expect(headers.subject == "Richiesta offerta supporti antivibranti")
}

@Test func unfoldsContinuationLines() {
    // RFC 5322 folding: real subjects are wrapped constantly, and a parser that
    // misses this truncates them mid-word.
    let message = """
    Subject: Richiesta offerta per i supporti
     antivibranti della pressa 4
    From: a@b.test

    corpo
    """
    #expect(EmailHeaderParser.parse(message).subject
        == "Richiesta offerta per i supporti antivibranti della pressa 4")
}

@Test func parsesTheDateWithItsOffset() throws {
    let headers = EmailHeaderParser.parse(realisticEml)
    let date = try #require(headers.date)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 3600))
    let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    #expect(components.year == 2026)
    #expect(components.month == 8)
    #expect(components.day == 4)
    #expect(components.hour == 9)
}

@Test func parsesADateEvenWithATrailingZoneComment() {
    // Some senders append "(CEST)" after the offset.
    #expect(RFC5322Date.parse("Tue, 4 Aug 2026 09:15:00 +0200 (CEST)") != nil)
    #expect(RFC5322Date.parse("4 Aug 2026 09:15:00 +0200") != nil)
    #expect(RFC5322Date.parse("Tue, 4 Aug 2026 09:15 +0200") != nil)
    #expect(RFC5322Date.parse("non una data") == nil)
}

// MARK: - Encoded words

@Test func decodesBase64EncodedWords() {
    // Any Italian subject with an accent arrives encoded; showing the raw form on a
    // card is worse than showing nothing.
    #expect(EncodedWord.decode("=?UTF-8?B?UmljaGllc3RhIHBlciBsJ3VmZmljaW8=?=")
        == "Richiesta per l'ufficio")
}

@Test func decodesQuotedPrintableEncodedWords() {
    #expect(EncodedWord.decode("=?UTF-8?Q?Trasmissibilit=C3=A0?=") == "Trasmissibilità")
    // Inside an encoded word `_` means a space, not an underscore.
    #expect(EncodedWord.decode("=?UTF-8?Q?due_parole?=") == "due parole")
}

@Test func decodesSeveralEncodedWordsInOneField() {
    let raw = "=?UTF-8?Q?Prima?= parte e =?UTF-8?B?c2Vjb25kYQ==?= parte"
    #expect(EncodedWord.decode(raw) == "Prima parte e seconda parte")
}

@Test func leavesPlainTextAlone() {
    #expect(EncodedWord.decode("Testo normale") == "Testo normale")
    #expect(EncodedWord.decode("") == "")
}

@Test func leavesAMalformedEncodedWordVisibleRatherThanEatingIt() {
    // Better a strange-looking subject than a silently empty one.
    #expect(EncodedWord.decode("=?UTF-8?X?boh?=") == "=?UTF-8?X?boh?=")
    #expect(EncodedWord.decode("=?non chiuso") == "=?non chiuso")
}

@Test func decodesAnEncodedSenderName() {
    let message = """
    From: =?UTF-8?Q?Niccol=C3=B2_Rossi?= <n.rossi@test.test>
    Subject: x

    corpo
    """
    let headers = EmailHeaderParser.parse(message)
    #expect(headers.from?.name == "Niccolò Rossi")
    #expect(headers.from?.address == "n.rossi@test.test")
}

// MARK: - Addresses

@Test(arguments: [
    ("Mario Rossi <m@test.test>", "Mario Rossi", "m@test.test"),
    ("<m@test.test>", nil, "m@test.test"),
    ("m@test.test", nil, "m@test.test"),
    ("\"Rossi, Mario\" <m@test.test>", "Rossi, Mario", "m@test.test"),
])
func parsesAddressForms(_ testCase: (raw: String, name: String?, address: String)) {
    let parsed = EmailHeaderParser.parseAddress(testCase.raw)
    #expect(parsed?.name == testCase.name)
    #expect(parsed?.address == testCase.address)
}

@Test func doesNotSplitAnAddressListOnACommaInsideAQuotedName() {
    let list = EmailHeaderParser.parseAddressList("\"Rossi, Mario\" <m@test.test>, b@test.test")
    #expect(list.count == 2)
    #expect(list[0].name == "Rossi, Mario")
    #expect(list[1].address == "b@test.test")
}

@Test func rejectsSomethingThatIsNotAnAddress() {
    #expect(EmailHeaderParser.parseAddress("") == nil)
    #expect(EmailHeaderParser.parseAddress("nessuna chiocciola") == nil)
}

// MARK: - message:// links
//
// ADR-0036 §D9 (plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2): one
// `message://` builder, `MailURL.forMessageID(_:)`, shared by `EmailHeaders.mailURL`
// and `MailLink.url(forMessageID:)` - which encoding it emits is decided by an
// on-device measurement with Stefano present, not by this test, so these assert
// delegation only.

@Test func buildsTheMailURLByDelegatingToMailURL() {
    let headers = EmailHeaderParser.parse(realisticEml)
    #expect(headers.mailURL == MailURL.forMessageID(headers.messageID))
}

@Test func hasNoMailURLWithoutAMessageID() {
    let headers = EmailHeaderParser.parse("From: a@b.test\nSubject: x\n\ncorpo")
    #expect(headers.mailURL == MailURL.forMessageID(headers.messageID))
    #expect(headers.mailURL == nil)
}

@Test func mailLinkURLDelegatesToMailURL() {
    let messageID = "abc@rossi-spa.it"
    #expect(MailLink.url(forMessageID: messageID) == MailURL.forMessageID(messageID)?.absoluteString)
}

// MARK: - Thumbnail cache keys

@Test func quantisesThumbnailWidthsIntoBuckets() {
    // Without buckets every pixel of a resize drag would be its own render and its
    // own cache file.
    #expect(ThumbnailStore.bucket(for: 100) == 160)
    #expect(ThumbnailStore.bucket(for: 160) == 160)
    #expect(ThumbnailStore.bucket(for: 161) == 240)
    #expect(ThumbnailStore.bucket(for: 5000) == 1280)
}

@Test func buildsFileSafeCacheKeys() {
    let key = ThumbnailStore.cacheKey(relativePath: "01 Progetti/città/doc é.pdf", bucket: 320)
    // The path becomes a digest, so slashes and accents cannot reach the file name.
    #expect(!key.contains("/"))
    #expect(key.hasSuffix("@320"))
    #expect(key.allSatisfy { $0.isHexDigit || $0 == "@" || $0.isNumber })
}

@Test func cacheKeysDifferByPathAndBySize() {
    let a = ThumbnailStore.cacheKey(relativePath: "a.pdf", bucket: 320)
    let b = ThumbnailStore.cacheKey(relativePath: "b.pdf", bucket: 320)
    let c = ThumbnailStore.cacheKey(relativePath: "a.pdf", bucket: 640)
    #expect(a != b)
    #expect(a != c)
}
