import Foundation

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 1.
//
// Reads the four `SU*` Info.plist keys back as a pure value type (ADR §D6) so that R-03,
// R-04 and R-08 are unit tests rather than promises. Takes a dictionary, not a `Bundle`,
// for one reason: a `Bundle` cannot be faked in a test and a dictionary can, so the same
// type is exercised against literal fixtures *and* against the real `Info.plist` of the
// built app (`Tests/UpdaterConfigurationTests.swift`). No `import Sparkle` here - the
// keys are strings, and reading them must not drag a framework into a test that has no
// business linking one.
struct UpdaterConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicEDKey: String
    let checksAutomatically: Bool
    let sendsSystemProfile: Bool

    /// Stub declaration (ADR-0155 §D1): the tester owns this signature, the coder fills
    /// the body. Must eventually succeed when `SUFeedURL` is a valid `https://` URL and
    /// `SUPublicEDKey` is present, and fail (return `nil`) when either key is missing or
    /// malformed beyond what `problems` can describe (e.g. `SUFeedURL` unparsable as a
    /// `URL` at all). Currently always returns `nil`.
    init?(infoDictionary: [String: Any]) {
        return nil
    }

    /// Stub declaration: the coder fills this in. Must eventually report, non-fatally:
    /// `SUFeedURL` not using `https://`; `SUPublicEDKey` empty; `SUEnableAutomaticChecks`
    /// `true` (R-03); `SUSendsSystemProfile` `true` (R-04). Currently always empty.
    var problems: [String] { [] }
}
