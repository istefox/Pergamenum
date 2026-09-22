import Foundation
import Testing
@testable import Pergamenum

// ADR-0055 (note write guard and the dead rename performer), plan
// docs/plans/pg-205-pg-206-note-write-guard.md - R-03: "No `VaultPlanApplication.apply` call
// site in the repository writes through an unguarded `store.write` after this chain."
//
// Before this chain, `BoardFileOperations.renameBoard` and `FolderFileOperations
// .renameFolder` both spelled the note-writer argument as
// `VaultPlanApplication.apply(plan.noteChanges) { try store.write($0.after, to: $0.path) }` -
// an unconditional write with no precondition. §D1/§D2 replace both with `writing: store
// .writeGuarded`. This turns Task 4's own manual verification step ("`rg -n "\.write\(to:"
// --type swift Sources/ | rg -i canvas` must show no raw `.canvas` byte write outside
// `CanvasStore.swift`", generalized here to the note half) into a test that fires every run,
// the same move `Tests/SharedSourcesPurityTests.swift` already made for its own two
// manifest facts - rather than a command a future contributor has to remember to type before
// adding an eighth `VaultPlanApplication.apply` call site.
//
// Green from the first run against this chain's own diff, since every one of the eight call
// sites already writes through `store.writeGuarded`, `writeGuarded`, `writeFileGuarded` or
// `canvas.writeRepoint`/`CanvasStore(...).writeRepoint` (ADR-0055 §D1/§D2, ADR-0054 §D6) -
// this is the guard against regression, not a red this chain leaves behind.
@Suite struct VaultPlanApplicationWriterPurityTests {
    private static let marker = "VaultPlanApplication.apply("
    private static let guardedWriterNames = ["writeGuarded", "writeFileGuarded", "writeRepoint"]

    @Test func everyApplyCallSiteNamesAGuardedWriter() throws {
        let repoRoot = try resolvedRepoRoot()
        let sourcesURL = repoRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesURL, includingPropertiesForKeys: nil
        ) else {
            Issue.record("could not enumerate \(sourcesURL.path)")
            return
        }

        var offendingCalls: [String] = []
        var callSiteCount = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for call in Self.callSites(in: contents, matching: Self.marker) {
                callSiteCount += 1
                let namesAGuardedWriter = Self.guardedWriterNames.contains { call.contains($0) }
                if !namesAGuardedWriter {
                    offendingCalls.append("\(fileURL.lastPathComponent): \(call)")
                }
            }
        }

        // A file-scan test that silently matched nothing would pass for the wrong reason
        // (ADR-0055's own §D9-adjacent worry about a vacuous test) - assert the scan actually
        // found the eight call sites the plan's own preamble grepped, not zero.
        #expect(callSiteCount >= 8, "expected to find at least the eight known apply call sites, found \(callSiteCount)")
        #expect(
            offendingCalls.isEmpty,
            "VaultPlanApplication.apply call site(s) not naming a guarded writer: \(offendingCalls)"
        )
    }

    /// Every balanced-paren call starting at each occurrence of `marker` in `contents`,
    /// `marker` included - simple paren-depth counting, not a real Swift parser, but every
    /// call site this scans is a plain argument list with no parenthesized string literal or
    /// comment inside it, so depth counting resolves it correctly.
    private static func callSites(in contents: String, matching marker: String) -> [String] {
        var results: [String] = []
        var searchStart = contents.startIndex
        while let markerRange = contents.range(of: marker, range: searchStart..<contents.endIndex) {
            var depth = 1 // `marker` itself ends just past the call's opening "("
            var index = markerRange.upperBound
            while index < contents.endIndex, depth > 0 {
                let character = contents[index]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                }
                index = contents.index(after: index)
            }
            results.append(String(contents[markerRange.lowerBound..<index]))
            searchStart = index
        }
        return results
    }
}
