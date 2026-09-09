import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-05.

/// Walks a (possibly multipart) RFC 822 message and decodes its parts.
///
/// **Extends `EmailHeaderParser`, does not replace it** (SPEC "Components"):
/// `EmailHeaderParser.parse` still owns header parsing, folding and RFC 2047 decoding
/// for both the top-level message and each part; this type adds only what
/// `EmailHeaderParser` never had to do, because it stops at the blank line ending the
/// headers - the multipart boundary walk, transfer-encoding decode and charset
/// handling.
enum MIMEDecoder {
    /// Walks `rfc822`'s body and returns its parts, decoded and classified
    /// (text/plain, text/html, inline `Content-ID`, attachment). A non-multipart
    /// message is returned as exactly one part.
    static func decode(_ rfc822: Data) -> [MIMEPart] {
        // Coder-owned: multipart boundary walk keyed off `Content-Type`'s `boundary=`
        // parameter, recursing into `multipart/alternative`/`multipart/mixed`/
        // `multipart/related`. Stubbed empty so every classification assertion in
        // `Tests/MIMEDecoderTests.swift` is red until it exists.
        []
    }

    /// Decodes one part's raw body bytes given its `Content-Transfer-Encoding`
    /// (`7bit`/`8bit`/`quoted-printable`/`base64`, case-insensitive, `nil` treated as
    /// `7bit`) and charset (`utf-8`/`iso-8859-1`/`windows-1252`, `nil` treated as
    /// `utf-8`). A byte sequence the charset cannot decode becomes U+FFFD, never a
    /// thrown error or a dropped part (R-05).
    static func decodeText(_ data: Data, transferEncoding: String?, charset: String?) -> String {
        // Coder-owned. Stubbed empty rather than force-decoding as UTF-8, so an
        // encoding/charset mismatch in the fixture corpus cannot pass by accident.
        ""
    }
}
