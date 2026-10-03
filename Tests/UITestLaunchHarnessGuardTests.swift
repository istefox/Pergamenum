import Foundation
import Testing

// PG-128 (#228): every UI-test class launches the app through `UITests/PergamenumUITestCase.swift`.
//
// Each file under `UITests/` used to spell its own temporary directories and isolation flags,
// and two of them drifted (`PraticheUITests` had no `-disablePlaud`, `WikilinkNavigationUITests`
// no `-mailStoreRoot`). The launcher now owns both; this guard fails if a file grows its own
// copy back. It reads the source, since the UI-test target cannot be linked into this one.
@Suite struct UITestLaunchHarnessGuardTests {
    private static let launcherFile = "PergamenumUITestCase.swift"

    /// Every `.swift` file directly under `UITests/`, by name. Throws when the directory cannot
    /// be listed, and a file that cannot be read is recorded, never skipped: a guard that read
    /// nothing would pass.
    private static func uiTestSources() throws -> [(name: String, contents: String)] {
        let directory = try resolvedRepoRoot().appendingPathComponent("UITests")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return names.compactMap { name in
            guard let contents = try? String(
                contentsOf: directory.appendingPathComponent(name), encoding: .utf8
            ) else {
                Issue.record("unreadable UI-test source: UITests/\(name)")
                return nil
            }
            return (name, contents)
        }
    }

    @Test func noUITestFileLaunchesTheAppOutsideTheLauncher() throws {
        let sources = try Self.uiTestSources()
        // The seventeen classes plus support files at the time of writing: far fewer means the
        // listing went wrong, not that the suite shrank.
        #expect(sources.count >= 10, "only \(sources.count) files read under UITests/")
        #expect(sources.contains { $0.name == Self.launcherFile }, "the launcher file is missing")

        var offences: [String] = []
        for source in sources where source.name != Self.launcherFile {
            for marker in ["XCUIApplication(", "launchArguments", "launchEnvironment", ": XCTestCase"]
            where source.contents.contains(marker) {
                offences.append("UITests/\(source.name) contains `\(marker)`")
            }
        }
        #expect(offences.isEmpty, "launch the app through PergamenumUITestCase: \(offences)")
    }

    /// Every test class under `UITests/` inherits the launcher, so it cannot opt out of the
    /// teardown or the flags by being a plain `XCTestCase` declared some other way.
    @Test func everyUITestClassInheritsTheLauncher() throws {
        let declaration = try Regex(#"class\s+(\w+)\s*:\s*(\w+)"#, as: (Substring, Substring, Substring).self)
        var classes: [String] = []
        var strays: [String] = []
        for source in try Self.uiTestSources() where source.name != Self.launcherFile {
            for match in source.contents.matches(of: declaration) {
                classes.append(String(match.1))
                if match.2 != "PergamenumUITestCase" {
                    strays.append("\(match.1): \(match.2) in UITests/\(source.name)")
                }
            }
        }
        #expect(classes.count >= 10, "only \(classes.count) UI-test classes found: \(classes)")
        #expect(strays.isEmpty, "UI-test classes not on PergamenumUITestCase: \(strays)")
    }

    /// The launcher passes every isolation flag CLAUDE.md requires of a UI-test launch.
    @Test func theLauncherCarriesEveryIsolationFlag() throws {
        let launcher = try #require(try Self.uiTestSources().first { $0.name == Self.launcherFile })
        for flag in [
            "\"-recentVaults\", \"(\\\"",
            "\"-disableCalendar\", \"YES\"",
            "\"-mailStoreRoot\"",
            "\"-disablePlaud\", \"YES\"",
            "\"-disableUpdater\", \"YES\"",
            "\"-disableContenitore\", \"YES\"",
            "\"-stateBase\"",
        ] {
            #expect(launcher.contents.contains(flag), "the launcher no longer passes \(flag)")
        }
    }
}
