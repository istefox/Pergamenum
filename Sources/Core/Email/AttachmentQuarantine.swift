import CoreServices
import Foundation

// PG-123 (2026-09-14): an attachment written into `allegati/` by `PraticaSyncEngine`
// carried no `com.apple.quarantine`, so a hostile `.command`/`.dmg` launched from the chip
// with none of the Gatekeeper first-run prompt the same file gets from Mail or a browser.
// The bytes came out of a mail store, and macOS treats mail attachments as downloads:
// this file makes the copy say so.

/// Stamps the quarantine attribute Gatekeeper reads on a file this app copied out of
/// Mail. Foundation + CoreServices only - no AppKit, no `UTType`: it compiles into
/// `perg` and `pergamenum-mcp` as well as into the app (ADR-0001 §D1), like the rest of
/// `Sources/Core/Email`.
///
/// Applied *after* the atomic write, never before: `.atomic` writes a temporary sibling
/// and renames it over the target, and an extended attribute set on a URL that does not
/// exist yet is an error, not a no-op.
enum AttachmentQuarantine {
    /// The agent the attribute names when the running process has no bundle identifier
    /// (a unit test runner, the CLI): the app's own, so Gatekeeper's «scaricato da» line
    /// always reads the same.
    static let fallbackAgentBundleIdentifier = "it.stefer.pergamenum"

    /// Sets `com.apple.quarantine` on `url` as an email attachment received now, agent
    /// `agentBundleIdentifier`. Idempotent in effect: a file already quarantined gets
    /// its properties rewritten, never a second attribute.
    static func apply(
        to url: URL,
        agentBundleIdentifier: String = Bundle.main.bundleIdentifier ?? fallbackAgentBundleIdentifier
    ) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Pergamenum",
            kLSQuarantineAgentBundleIdentifierKey as String: agentBundleIdentifier,
            kLSQuarantineTypeKey as String: kLSQuarantineTypeEmailAttachment as String,
            kLSQuarantineTimeStampKey as String: Date(),
        ]
        var target = url
        try target.setResourceValues(values)
    }

    /// Whether `url` carries a quarantine attribute at all - what a test reads back,
    /// and what a future retroactive sweep of an older `allegati/` would consult.
    static func isApplied(to url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties) != nil
    }
}
