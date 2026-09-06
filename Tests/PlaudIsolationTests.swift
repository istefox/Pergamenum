import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 2 -
// R-15's mechanical half, ADR §D1, §D14's enforcement.
//
// `URLSession` may appear in exactly one file in the whole repository,
// `Sources/Features/Recordings/PlaudHTTPClient.swift` - the only permitted network client,
// scoped to the loopback exception ADR-0032 §D14 records. Modeled on
// `Tests/SharedSourcesPurityTests.swift`'s own repo walk from `#filePath`
// (ADR-0031 §D2's shape for the same kind of claim about Sparkle).
@Suite struct PlaudIsolationTests {
    @Test func urlSessionAppearsInExactlyOneFileUnderSources() throws {
        let sourcesRoot = try Self.resolvedSourcesRoot()
        var filesMentioningURLSession: [String] = []

        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate \(sourcesRoot.path)")
            return
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if contents.contains("URLSession") {
                filesMentioningURLSession.append(fileURL.path)
            }
        }

        #expect(filesMentioningURLSession.count == 1, "URLSession found in: \(filesMentioningURLSession)")
        #expect(
            filesMentioningURLSession.first?
                .hasSuffix("Sources/Features/Recordings/PlaudHTTPClient.swift") == true
        )
    }

    /// ADR §D2: the one permitted force-unwrap-shaped construct, guarded here rather than
    /// left to crash unseen at the client's first call.
    @Test func baseURLIsWellFormedAndLoopback() {
        let base = PlaudHTTPClient.base
        #expect(base.scheme == "http")
        #expect(base.host == "127.0.0.1")
        #expect(base.port == 3777)
    }

    /// One `deletingLastPathComponent()` off this file's own directory (`Tests/`) gives the
    /// repository root, then down into `Sources`.
    private static func resolvedSourcesRoot() throws -> URL {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoot = thisFileURL
            .deletingLastPathComponent() // PlaudIsolationTests.swift -> Tests/
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
