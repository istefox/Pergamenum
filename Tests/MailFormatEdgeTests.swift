import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D7/§D8.2, plan docs/plans/format-edge-hardening.md, Tasks 4 and 5 - R-10, R-11,
// R-12, R-13, R-15.
//
// Mail input is read only: faithful means the decoded value is the one the sender meant
// (ADR-0065 §Context). Every fixture is synthetic, in `EmailFixtureCorpus`'s spirit.

private let latin9 = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue))
)

// MARK: - R-10: an unclosed tag keeps the text after it

@Test func anUnclosedAnchorKeepsTheTextAfterIt() {
    let reduced = HTMLTextReducer.reduce(#"<p>Vedi <a href="https://x">Preventivo 2026 allegato"#)
    #expect(reduced.contains("Vedi"))
    #expect(reduced.contains("Preventivo 2026 allegato"))
}

@Test func anUnclosedCellKeepsTheTextAfterIt() throws {
    let reduced = HTMLTextReducer.reduce("<table><tr><td>Totale<td>1.250,00")
    let totale = try #require(reduced.range(of: "Totale")?.lowerBound)
    let amount = try #require(reduced.range(of: "1.250,00")?.lowerBound)
    #expect(totale < amount)
}

@Test func nestedUnclosedTagsKeepTheirOrder() throws {
    let reduced = HTMLTextReducer.reduce(#"<td>A <a href="x">B"#)
    let first = try #require(reduced.range(of: "A")?.lowerBound)
    let second = try #require(reduced.range(of: "B")?.lowerBound)
    #expect(first < second)
}

// MARK: - R-11: Latin-9

@Test func latin9PartDecodesTheEuroSign() {
    #expect(MIMEDecoder.decodeText(Data([0x31, 0x20, 0xA4]), transferEncoding: nil, charset: "ISO-8859-15") == "1 €")
}

@Test func latin9HeaderDecodesTheEuroSign() {
    #expect(EncodedWord.decode("=?ISO-8859-15?Q?1.250,00_=A4?=") == "1.250,00 €")
}

@Test func latin9AliasesAgree() {
    for alias in ["ISO-8859-15", "iso-8859-15", "ISO_8859-15", "LATIN9"] {
        #expect(MailCharset.encoding(for: alias) == latin9, "\(alias)")
    }
    #expect(MailCharset.encoding(for: "ISO-8859-2") == .isoLatin2)
}

@Test func everyOldAliasStillMaps() {
    let expected: [(String, String.Encoding)] = [
        ("UTF-8", .utf8), ("UTF8", .utf8), ("utf-8", .utf8),
        ("ISO-8859-1", .isoLatin1), ("ISO8859-1", .isoLatin1), ("LATIN1", .isoLatin1),
        ("ISO_8859-1", .isoLatin1), ("iso-8859-1", .isoLatin1),
        ("WINDOWS-1252", .windowsCP1252), ("CP1252", .windowsCP1252), ("CP-1252", .windowsCP1252),
        ("windows-1252", .windowsCP1252),
        ("US-ASCII", .ascii), ("ASCII", .ascii), ("us-ascii", .ascii),
        ("x-unknown", .utf8),
    ]
    for (alias, encoding) in expected {
        #expect(MailCharset.encoding(for: alias) == encoding, "\(alias)")
    }
}

// MARK: - R-12: RFC 2047 §6.2 and B padding

@Test func adjacentEncodedWordsJoin() {
    #expect(EncodedWord.decode("=?UTF-8?Q?artic?= =?UTF-8?Q?oli?=") == "articoli")
}

@Test func aFoldedSubjectHasNoSpaceMidWord() {
    let headers = EmailHeaderParser.parse(
        "Subject: =?UTF-8?Q?Preventivo_fornitura_artic?=\r\n =?UTF-8?Q?oli_tecnici?=\r\nFrom: a@b.test\r\n\r\n"
    )
    #expect(headers.subject == "Preventivo fornitura articoli tecnici")
    #expect(headers.from?.address == "a@b.test")
}

@Test func anEncodedWordBesidePlainTextKeepsItsSpace() {
    #expect(EncodedWord.decode("=?UTF-8?Q?Ciao?= mondo") == "Ciao mondo")
}

@Test func aFailingWordKeepsItsSpace() {
    #expect(EncodedWord.decode("=?UTF-8?X?rotto?= =?UTF-8?Q?bene?=") == "=?UTF-8?X?rotto?= bene")
}

@Test func aBWordWithoutPaddingDecodes() {
    #expect(EncodedWord.decode("=?UTF-8?B?Y2lhbw?=") == "ciao")
    #expect(EncodedWord.decode("=?UTF-8?B?Y2lhbw==?=") == "ciao")
}

// MARK: - R-13: parameters

@Test func anRFC2231FilenameWithCharsetDecodes() {
    #expect(
        MIMEParameter.value("filename", in: "attachment; filename*=UTF-8''Preventivo%20%E2%82%AC.pdf")
            == "Preventivo €.pdf"
    )
}

@Test func continuedRFC2231SegmentsJoin() {
    #expect(
        MIMEParameter.value("filename", in: "attachment; filename*0*=UTF-8''Relazione%20; filename*1*=finale.pdf")
            == "Relazione finale.pdf"
    )
    #expect(
        MIMEParameter.value("filename", in: #"attachment; filename*0="Relazione "; filename*1="finale.pdf""#)
            == "Relazione finale.pdf"
    )
}

@Test func aQuotedSemicolonDoesNotSplit() {
    #expect(MIMEParameter.value("filename", in: #"attachment; filename="Report; finale.pdf""#) == "Report; finale.pdf")
}

@Test func theExtendedFormWins() {
    #expect(
        MIMEParameter.value("filename", in: #"attachment; filename="vecchio.pdf"; filename*=UTF-8''nuovo%20%C3%A8.pdf"#)
            == "nuovo è.pdf"
    )
}

@Test func boundaryAndCharsetStillParse() {
    #expect(MIMEParameter.value("boundary", in: #"multipart/mixed; boundary="a;b=c""#) == "a;b=c")
    #expect(MIMEParameter.value("charset", in: "text/plain; charset=utf-8") == "utf-8")
    #expect(MIMEParameter.value("CHARSET", in: "text/plain; Charset=\"ISO-8859-15\"") == "ISO-8859-15")
}

@Test func anRFC2231NameReachesTheAttachment() {
    let message = "Content-Type: multipart/mixed; boundary=\"b;1\"\r\n\r\n"
        + "--b;1\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nCiao\r\n"
        + "--b;1\r\nContent-Type: application/pdf\r\n"
        + "Content-Disposition: attachment; filename*=UTF-8''Preventivo%20%E2%82%AC.pdf\r\n"
        + "Content-Transfer-Encoding: base64\r\n\r\nJVBERi0=\r\n--b;1--\r\n"
    let parts = MIMEDecoder.decode(Data(message.utf8))
    let attachment = parts.first { if case .attachment = $0.kind { true } else { false } }
    #expect(attachment?.filename == "Preventivo €.pdf")
    #expect((attachment?.filename as NSString?)?.pathExtension == "pdf")
    #expect(parts.first { $0.kind == .textPlain }?.decodedText?.contains("Ciao") == true)
}

// MARK: - R-15 (Task 5): the sender's zone offset, ADR-0065 §D8.2

@Test func numericZoneOffsets() {
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 +0900") == 32400)
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 -0500") == -18000)
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 +0000") == 0)
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 -0000") == nil)
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 +0530") == 19800)
}

@Test(arguments: [
    ("GMT", 0), ("UT", 0), ("EST", -18000), ("EDT", -14400), ("PST", -28800), ("PDT", -25200),
    ("CEST", nil), ("A", nil),
] as [(String, Int?)])
func obsoleteZoneNames(_ zone: String, _ expected: Int?) {
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 \(zone)") == expected)
}

@Test func aTrailingCommentDoesNotHideTheOffset() {
    #expect(RFC5322Date.offset(of: "Sat, 26 Sep 2026 10:00:00 +0200 (CEST)") == 7200)
}

@Test func theHeaderParserRecordsTheOffset() {
    let headers = EmailHeaderParser.parse("Date: Sat, 26 Sep 2026 10:00:00 +0900\r\nSubject: Offerta\r\n\r\n")
    #expect(headers.dateOffset == 32400)
    #expect(EmailHeaderParser.parse("Subject: Offerta\r\n\r\n").dateOffset == nil)
}
