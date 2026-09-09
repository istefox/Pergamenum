import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - §D9.

/// The one `message://` URL builder shared by `EmailHeaders.mailURL` and
/// `MailLink.url(forMessageID:)` (ADR-0036 §D9), so the two encodings this repo
/// shipped before this chain (`%40` in one, `%3C…%3E` in the other, C5) cannot drift
/// apart again.
///
/// Which encoding Mail actually accepts is decided by a one-time, on-device
/// measurement with Stefano present (ADR-0036 §D9): build both forms for one real
/// message id and `NSWorkspace.open` each. That measurement, and therefore this
/// function's body, is coder-owned — this stub always answers `nil`, which is
/// deliberately wrong, so the delegation tests in `Tests/EmailTests.swift` stay red
/// until the measurement lands and both call sites are repointed here.
enum MailURL {
    static func forMessageID(_ messageID: String?) -> URL? {
        nil
    }
}
