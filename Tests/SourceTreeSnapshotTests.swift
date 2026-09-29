import Foundation
import Testing

// Plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 7 - R-19.
//
// The snapshot the source guards read instead of walking the tree themselves. A snapshot that
// silently came back empty would turn all three guards green without looking at anything.

@Suite struct SourceTreeSnapshotTests {
    @Test func theSnapshotHoldsTheSourceTree() throws {
        let files = try SourceTreeSnapshot.files()

        #expect(!files.isEmpty)
        #expect(files.allSatisfy { $0.relativePath.hasPrefix("Sources/") && $0.relativePath.hasSuffix(".swift") })
        let connection = files.first { $0.relativePath == "Sources/Core/Email/MailStoreConnection.swift" }
        #expect(connection?.contents?.contains("final class MailStoreConnection") == true)
        #expect(connection?.path.hasSuffix("/Sources/Core/Email/MailStoreConnection.swift") == true)
    }

    @Test func aDirectorySelectsOnlyItsOwnFiles() throws {
        let core = try SourceTreeSnapshot.files(under: "Sources/Core")

        #expect(!core.isEmpty)
        #expect(core.allSatisfy { $0.relativePath.hasPrefix("Sources/Core/") })
        // A prefix, not a substring: `Sources/CoreX` would not belong to `Sources/Core`.
        #expect(try SourceTreeSnapshot.files(under: "Sources/Cor").isEmpty)
    }
}
