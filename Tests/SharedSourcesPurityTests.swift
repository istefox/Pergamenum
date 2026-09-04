import Foundation
import Testing
@testable import Pergamenum

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 2.
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
        let repoRoot = try Self.resolvedRepoRoot()
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

    /// One `deletingLastPathComponent()` off this file's own directory (`Tests/`) gives the
    /// repository root. If the candidate does not contain a `Sources` directory, this
    /// throws naming the path tried - it never skips silently.
    private static func resolvedRepoRoot() throws -> URL {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoot = thisFileURL
            .deletingLastPathComponent() // SharedSourcesPurityTests.swift -> Tests/
            .deletingLastPathComponent() // Tests/ -> repository root
        guard FileManager.default.fileExists(atPath: candidateRoot.appendingPathComponent("Sources").path) else {
            throw RepoRootResolutionError.notFound(candidate: candidateRoot.path)
        }
        return candidateRoot
    }
}

private enum RepoRootResolutionError: Error, CustomStringConvertible {
    case notFound(candidate: String)

    var description: String {
        switch self {
        case let .notFound(candidate):
            return "Could not resolve the repository root from #filePath. Candidate tried: \(candidate)"
        }
    }
}
