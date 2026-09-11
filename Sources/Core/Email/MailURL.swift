import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - §D9.

/// The one `message://` URL builder shared by `EmailHeaders.mailURL` and
/// `MailLink.url(forMessageID:)` (ADR-0036 §D9), so the two encodings this repo
/// shipped before this chain (`%40` in one, `%3C…%3E` in the other, C5) cannot drift
/// apart again.
///
/// Measured on 2026-09-09, on this Mac, with Mail running (ADR-0036 §D9): one real
/// `Message-ID` read out of a temporary copy of the Envelope Index, both forms built
/// and handed to `NSWorkspace.open` one at a time.
///
/// - `message://%3C<id>%3E` with `@` left literal (`MailLink.url`'s encoding) opened
///   the message: `open` returned `true` and a new Mail window carrying that message's
///   subject appeared.
/// - `message://%3C<id>%3E` with `@` written `%40` (`EmailHeaders.mailURL`'s encoding)
///   did the same.
///
/// Both work, so §D9's stated default stands: the shared function emits the encoding
/// that ships in `MailLink.url(forMessageID:)`, which also keeps «Copia link» and
/// every `message://` already written into a note byte-identical.
enum MailURL {
    /// `nil` for a missing or empty id: a `message://` URL without one opens nothing,
    /// and a link that opens nothing is worse than no link.
    ///
    /// The angle brackets RFC 5322 writes around a message id are stripped if present
    /// and always put back percent-encoded, so both call sites can pass whichever form
    /// they hold (`EmailHeaders.messageID` drops them, the SPEC's frontmatter keeps
    /// them).
    static func forMessageID(_ messageID: String?) -> URL? {
        guard let messageID else { return nil }
        let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty else { return nil }
        // `%` is subtracted from the allowed set so an id that already contains a
        // percent sign is escaped rather than passed through as a broken escape.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%"))
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "message://%3C\(encoded)%3E")
    }
}
