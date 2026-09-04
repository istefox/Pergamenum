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

    /// Fails - returns `nil` - only for what cannot be described any other way: an absent
    /// `SUFeedURL`, or one that is not parsable as a `URL` at all. Everything else that is
    /// wrong is reported by `problems` on a value that exists, because a test that can read
    /// the offending value back says more than one that got nothing.
    init?(infoDictionary: [String: Any]) {
        guard let rawFeedURL = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: rawFeedURL) else { return nil }
        self.feedURL = feedURL
        // Absent and empty are the same defect here, and `problems` names it either way.
        self.publicEDKey = infoDictionary["SUPublicEDKey"] as? String ?? ""
        // A missing flag is the value this app wants, so its absence is not a problem:
        // the keys exist to pin Sparkle's own defaults down, not to be read for state.
        self.checksAutomatically = infoDictionary["SUEnableAutomaticChecks"] as? Bool ?? false
        self.sendsSystemProfile = infoDictionary["SUSendsSystemProfile"] as? Bool ?? false
    }

    /// Every way the four keys can be present and still wrong, reported non-fatally and
    /// one line each. The feed problem quotes the offending URL verbatim: the value is the
    /// only part of that message worth reading.
    var problems: [String] {
        var problems: [String] = []
        if feedURL.scheme?.lowercased() != "https" {
            problems.append("SUFeedURL must use https, found: \(feedURL.absoluteString)")
        }
        if publicEDKey.isEmpty {
            problems.append("SUPublicEDKey is empty: the appcast signature cannot be verified")
        }
        // R-03: checks are manual-only, so the key exists precisely to be false.
        if checksAutomatically {
            problems.append("SUEnableAutomaticChecks must be false: update checks are manual-only")
        }
        // R-04: the one place CLAUDE.md principle 2's exception must not widen into telemetry.
        if sendsSystemProfile {
            problems.append("SUSendsSystemProfile must be false: no system profile is ever sent")
        }
        return problems
    }
}
