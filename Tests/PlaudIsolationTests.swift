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
        var filesMentioningURLSession: [String] = []

        // The tree is read once per test run, shared with the other source guards (R-19). A tree
        // that could not be walked throws here, as the enumerator's `nil` recorded an issue.
        for file in try SourceTreeSnapshot.files(under: "Sources") {
            guard let contents = file.contents else {
                    // PG-128: a file this guard cannot read is a file it cannot vouch for.
                    Issue.record("unreadable source file: \(file.path)")
                    continue
                }
            if contents.contains("URLSession") {
                filesMentioningURLSession.append(file.path)
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
}
