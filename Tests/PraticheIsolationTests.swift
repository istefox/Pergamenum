import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-38, ADR §D19.
//
// "The connectors compile the Mail-store files (they live under `Sources/Core/**`)
// but are structurally forbidden to call them: `SharedSourcesPurityTests` asserts no
// file under `Sources/Connector`, `Sources/CLI` or `Sources/MCPServer` names
// `MailStore`, `EMLXReader` or `SQLite3`." Modeled on `PlaudIsolationTests`'s own
// repo walk from `#filePath`. Green from the first run, since neither connector has
// any Mail-store-named file yet (that only becomes possible once Task 9 adds
// `Sources/Connector/VaultPratiche.swift`, which must never be one) - this is the
// guard, not the red, the same shape `SharedSourcesPurityTests.
// noCoreOrConnectorFileImportsAppKitOrSwiftUI` already documents for its own check.
@Suite struct PraticheIsolationTests {
    private static let guardedDirectories = [
        "Sources/Connector",
        "Sources/CLI",
        "Sources/MCPServer",
    ]

    private static let forbiddenNameFragments = ["MailStore", "EMLXReader", "SQLite3"]

    @Test func noConnectorOrFrontEndFileNamesTheMailStore() throws {
        let sourcesRoot = try Self.resolvedSourcesRoot()
        var offendingFiles: [String] = []

        for directory in Self.guardedDirectories {
            let directoryURL = sourcesRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL, includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let name = fileURL.lastPathComponent
                if Self.forbiddenNameFragments.contains(where: { name.contains($0) }) {
                    offendingFiles.append(fileURL.path)
                }
            }
        }

        #expect(offendingFiles.isEmpty, "Mail-store-named file found under a connector/front-end directory: \(offendingFiles)")
    }

    /// Mirrors `PlaudIsolationTests.resolvedSourcesRoot()`.
    private static func resolvedSourcesRoot() throws -> URL {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoot = thisFileURL
            .deletingLastPathComponent() // PraticheIsolationTests.swift -> Tests/
            .deletingLastPathComponent() // Tests/ -> repository root
            .appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: candidateRoot.path) else {
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
            return "Could not resolve Sources/ from #filePath. Candidate tried: \(candidate)"
        }
    }
}
