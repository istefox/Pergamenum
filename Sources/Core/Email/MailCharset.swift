import Foundation

// ADR-0064 (Every on-disk format round-trips faithfully or is refused), plan
// docs/plans/format-edge-hardening.md, Task 4 - R-11; ADR §D7.2.

/// The one charset table mail decoding reads, for a MIME part (`MIMEDecoder.decodeText`) and for
/// an RFC 2047 header word (`EncodedWord`) alike.
///
/// It replaces two private tables that had drifted apart, and is their union, so neither decoder
/// loses an alias. Both had mapped ISO-8859-15 to Latin-2, which decodes cleanly and wrongly:
/// byte `0xA4` is `€` in Latin-9 and `¤` in Latin-2. Latin-9 has no `String.Encoding` constant of
/// its own, so it is reached through Core Foundation, which `import Foundation` brings on this
/// platform - `Sources/Core` stays buildable in both command-line tools.
enum MailCharset {
    static let isoLatin9 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue))
    )

    /// The encoding a charset label names, case-insensitive. Anything unlisted reads as UTF-8,
    /// which degrades to U+FFFD rather than to nothing.
    static func encoding(for charset: String) -> String.Encoding {
        switch charset.trimmingCharacters(in: .whitespaces).uppercased() {
        case "UTF-8", "UTF8": .utf8
        case "ISO-8859-1", "ISO8859-1", "LATIN1", "ISO_8859-1": .isoLatin1
        case "ISO-8859-15", "ISO8859-15", "ISO_8859-15", "LATIN9", "LATIN-9": isoLatin9
        case "ISO-8859-2", "ISO8859-2", "ISO_8859-2", "LATIN2": .isoLatin2
        case "WINDOWS-1252", "CP1252", "CP-1252": .windowsCP1252
        case "US-ASCII", "ASCII": .ascii
        default: .utf8
        }
    }
}
