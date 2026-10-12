import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D1 and ADR-0091 §D1, plan docs/plans/sublinear-offset-state-pg-405.md, Task 2 (PG-405, R-15).
//
// The shared type is a pure type: its four source files import Foundation and nothing else, and its
// tests import only the test framework and the app module. No dependency is added.

@Suite struct OffsetStoreImportGuardTests {
    /// The import lines of a file, as written, each trimmed.
    private static func imports(of path: String) throws -> [String] {
        let url = try resolvedRepoRoot().appendingPathComponent(path)
        let source = try String(contentsOf: url, encoding: .utf8)
        return source.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
    }

    private static func source(of path: String) throws -> String {
        try String(contentsOf: resolvedRepoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    // (R-15) The four source files of the task import exactly Foundation.
    @Test(arguments: [
        "Sources/Features/Editor/StepBuffer.swift", "Sources/Features/Editor/OffsetTable.swift",
        "Sources/Features/Editor/OffsetRanges.swift", "Sources/Features/Editor/StorageEdit.swift",
    ])
    func theSourceFilesImportFoundationOnly(path: String) throws {
        #expect(try Self.imports(of: path) == ["import Foundation"], "\(path)")
    }

    // (R-15) The model and the two test files import the test framework, the app module and Foundation,
    // and name neither of the UI frameworks.
    @Test(arguments: [
        "Tests/OffsetStoreModel.swift", "Tests/OffsetStoreModelTests.swift", "Tests/OffsetStoreBoundsTests.swift",
    ])
    func theTestFilesImportOnlyTheTestFrameworkAndTheApp(path: String) throws {
        let allowed: Set<String> = ["import Foundation", "import Testing", "@testable import Pergamenum"]
        let found = try Self.imports(of: path)
        #expect(Set(found).isSubset(of: allowed), "\(path): \(found)")
        #expect(found.contains("@testable import Pergamenum"), "\(path): \(found)")
        let text = try Self.source(of: path)
        for name in ["App" + "Kit", "Swift" + "UI"] {
            #expect(!text.contains(name), "\(path) names \(name)")
        }
    }
}
