import Foundation
import Testing
@testable import Pergamenum

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 2 — R-01:
// Sparkle is linked into the app target and into nothing else.
//
// Sparkle enters through exactly one file, `Sources/App/SparkleUpdateController.swift`
// (ADR §D2). This walks the repository from `#filePath` and asserts that none of the
// shared-source directories `perg`/`pergamenum-mcp` compile from ever import it - turning
// a manifest fact ("Sources/App/** is not in sharedSources") into a test that fires every
// turn, instead of a build that only breaks when somebody deliberately runs it. Green from
// the first run, since nothing imports Sparkle yet - this is the guard, not the red.
@Suite struct SharedSourcesPurityTests {
    private static let guardedDirectories = [
        "Sources/Core",
        "Sources/Connector",
        "Sources/Index",
        "Sources/Calendar",
        "Sources/Vault",
        "Sources/CLI",
        "Sources/MCPServer",
    ]

    @Test func noGuardedSharedSourceFileImportsSparkle() throws {
        let repoRoot = try resolvedRepoRoot()
        var offendingFiles: [String] = []

        for directory in Self.guardedDirectories {
            let directoryURL = repoRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                if contents.contains("import Sparkle") {
                    offendingFiles.append(fileURL.path)
                }
            }
        }

        #expect(offendingFiles.isEmpty, "Sparkle imported outside Sources/App: \(offendingFiles)")
    }

    // ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
    // R-38: "No file under Sources/Core or Sources/Connector added by this feature
    // imports AppKit or SwiftUI" - both are compiled into `perg`/`pergamenum-mcp` through
    // `sharedSources` (Project.swift). Green from the first run, like
    // `noGuardedSharedSourceFileImportsSparkle` above - this is the guard, not the red.
    //
    // `MailLink.swift` is the one named, pre-existing exception (predates this chain -
    // added for the Workspace `.eml` card's menu wiring, `git log --follow` shows its
    // first commit as "feat(menus): add the Vista, Calendario, Inserisci and Aiuto
    // menus", long before ADR-0036): it imports AppKit behind `#if canImport(AppKit)`
    // for `NSWorkspace`/pasteboard access, and this chain's own SPEC explicitly reuses
    // it as-is ("`MailLink` already reads Mail's selection this way"). Matching
    // `MailStoreConnection.swift`'s own named-exception shape for the sqlite3_ check
    // (`Tests/MailStoreReaderTests.swift`), the exception is a file name, not a blanket
    // opt-out of the directory.
    //
    // Only an actual `import` line counts - a doc comment that merely *mentions*
    // "import AppKit" (as `InlineFormat.swift`/`CodeSyntax.swift` do, explaining why
    // they must not) is not a violation, so comment lines are skipped.
    @Test func noCoreOrConnectorFileImportsAppKitOrSwiftUI() throws {
        let repoRoot = try resolvedRepoRoot()
        var offendingFiles: [String] = []
        let exceptions: Set<String> = ["MailLink.swift"]

        for directory in ["Sources/Core", "Sources/Connector"] {
            let directoryURL = repoRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                guard !exceptions.contains(fileURL.lastPathComponent) else { continue }
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let importsAppKitOrSwiftUI = contents
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.hasPrefix("//") }
                    .contains { $0 == "import AppKit" || $0 == "import SwiftUI" }
                if importsAppKitOrSwiftUI {
                    offendingFiles.append(fileURL.path)
                }
            }
        }

        #expect(offendingFiles.isEmpty, "AppKit/SwiftUI imported under Sources/Core or Sources/Connector: \(offendingFiles)")
    }
}
