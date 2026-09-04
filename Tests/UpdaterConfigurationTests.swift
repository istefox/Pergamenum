import Foundation
import Testing
@testable import Pergamenum

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 1.
//
// `UpdaterConfiguration` is a pure reader over the four `SU*` Info.plist keys (ADR §D6):
// exercised here against literal fixtures (R-03, R-04) and, once, against the real,
// shipped `Info.plist` of the built app (R-08) - because the manifest is not what ships.
@Suite struct UpdaterConfigurationTests {
    private static let validFeedURL = "https://istefox.github.io/pergamenum-updates/appcast.xml"

    private static func fixture(
        feedURL: String? = validFeedURL,
        publicEDKey: String? = "some-generated-ed25519-public-key",
        automaticChecks: Bool = false,
        sendsSystemProfile: Bool = false
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "SUEnableAutomaticChecks": automaticChecks,
            "SUSendsSystemProfile": sendsSystemProfile,
        ]
        if let feedURL { dict["SUFeedURL"] = feedURL }
        if let publicEDKey { dict["SUPublicEDKey"] = publicEDKey }
        return dict
    }

    // MARK: - Fixtures

    @Test func allFourKeysPresentAndValidProducesANonNilConfigurationWithNoProblems() {
        let config = UpdaterConfiguration(infoDictionary: Self.fixture())
        #expect(config != nil)
        #expect(config?.problems.isEmpty == true)
    }

    @Test func missingSUFeedURLReturnsNil() {
        let dictionary = Self.fixture(feedURL: nil)
        #expect(UpdaterConfiguration(infoDictionary: dictionary) == nil)
    }

    @Test func aFeedURLOnPlainHTTPProducesOneProblemNamingIt() {
        let plainHTTPFeed = "http://istefox.github.io/pergamenum-updates/appcast.xml"
        let dictionary = Self.fixture(feedURL: plainHTTPFeed)
        let config = UpdaterConfiguration(infoDictionary: dictionary)
        #expect(config != nil)
        #expect(config?.problems.count == 1)
        #expect(config?.problems.first?.contains(plainHTTPFeed) == true)
    }

    @Test func anEmptySUPublicEDKeyProducesOneProblem() {
        let dictionary = Self.fixture(publicEDKey: "")
        let config = UpdaterConfiguration(infoDictionary: dictionary)
        #expect(config != nil)
        #expect(config?.problems.count == 1)
    }

    @Test func automaticChecksEnabledProducesOneProblem() {
        // R-03's assertion: `SUEnableAutomaticChecks: true` must be reported as a problem.
        let dictionary = Self.fixture(automaticChecks: true)
        let config = UpdaterConfiguration(infoDictionary: dictionary)
        #expect(config != nil)
        #expect(config?.problems.count == 1)
    }

    @Test func sendsSystemProfileEnabledProducesOneProblem() {
        // R-04's assertion: `SUSendsSystemProfile: true` must be reported as a problem.
        let dictionary = Self.fixture(sendsSystemProfile: true)
        let config = UpdaterConfiguration(infoDictionary: dictionary)
        #expect(config != nil)
        #expect(config?.problems.count == 1)
    }

    // MARK: - The real, shipped Info.plist (R-08)

    @Test func theBuiltAppsInfoPlistDeclaresAllFourKeysValidly() throws {
        let dictionary = try Self.resolvedHostBundleInfoDictionary()
        let config = UpdaterConfiguration(infoDictionary: dictionary)
        #expect(config != nil, "UpdaterConfiguration(infoDictionary:) returned nil for the real Info.plist")
        #expect(config?.problems.isEmpty == true, "Real Info.plist has unexpected problems: \(config?.problems ?? [])")
    }

    /// Resolves the bundle that actually carries the built app's `Info.plist`. It is not
    /// certain which bundle `Bundle.main` is under a Tuist-hosted unit test, so `Bundle.main`
    /// is used only when it is already the `.app` bundle; otherwise this walks three levels
    /// up from the test bundle's own location, since the test bundle sits at
    /// `Pergamenum.app/Contents/PlugIns/PergamenumTests.xctest`
    /// (`ThemeEngine.swift:303`'s two-candidate probe is this repo's precedent). If neither
    /// candidate resolves to a `.app`, this throws naming both paths - it never skips
    /// silently.
    private static func resolvedHostBundleInfoDictionary() throws -> [String: Any] {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.infoDictionary ?? [:]
        }
        let testBundleURL = Bundle(for: BundleAnchor.self).bundleURL
        let walkedUpURL = testBundleURL
            .deletingLastPathComponent() // PlugIns/
            .deletingLastPathComponent() // Contents/
            .deletingLastPathComponent() // Pergamenum.app
        guard walkedUpURL.pathExtension == "app", let hostBundle = Bundle(url: walkedUpURL) else {
            throw HostBundleResolutionError.notFound(
                mainCandidate: Bundle.main.bundleURL.path,
                walkedUpCandidate: walkedUpURL.path
            )
        }
        return hostBundle.infoDictionary ?? [:]
    }
}

/// Anchors `Bundle(for:)` to whichever bundle this test file was compiled into.
private final class BundleAnchor {}

private enum HostBundleResolutionError: Error, CustomStringConvertible {
    case notFound(mainCandidate: String, walkedUpCandidate: String)

    var description: String {
        switch self {
        case let .notFound(mainCandidate, walkedUpCandidate):
            return "Could not resolve the host app bundle from either candidate: " +
                "Bundle.main = \(mainCandidate), walked-up candidate = \(walkedUpCandidate)"
        }
    }
}
