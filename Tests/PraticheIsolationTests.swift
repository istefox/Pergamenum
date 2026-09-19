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

    @Test func noConnectorOrFrontEndFileReferencesTheMailStore() throws {
        let repoRoot = try resolvedRepoRoot()
        var offendingFiles: [String] = []
        var scannedAnyFile = false

        for directory in Self.guardedDirectories {
            // `Self.guardedDirectories` already reads `"Sources/Connector"` etc - the
            // repo root is what those paths are relative to. Appending them to a root
            // that already ended in `Sources` (as the old `resolvedSourcesRoot()` did)
            // built `Sources/Sources/Connector`, which never exists: the enumerator
            // came back `nil`, and the loop's own `guard ... else { continue }` made
            // that read as "nothing to scan", never as "the guard did not run".
            let directoryURL = repoRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL, includingPropertiesForKeys: nil
            ) else {
                Issue.record("Could not enumerate guarded directory: \(directoryURL.path)")
                continue
            }
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                scannedAnyFile = true
                // The file's NAME alone missed a forbidden reference sitting inside an
                // ordinarily named file - an innocuous `VaultPratiche.swift` importing
                // `MailStoreReader` passed this guard unnoticed. Search the SOURCE
                // instead, with comments and string literals stripped first so an
                // explanatory mention (this very file's own header, or a doc comment
                // quoting the forbidden name) never counts as a violation.
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let source = Self.strippingCommentsAndStringLiterals(text)
                if Self.forbiddenNameFragments.contains(where: { source.contains($0) }) {
                    offendingFiles.append(fileURL.path)
                }
            }
        }

        // The guard itself has to prove it looked at something: an enumerator that
        // silently visits zero files is indistinguishable from a broken path (exactly
        // what this test shipped with) unless something insists on a positive count.
        #expect(scannedAnyFile, "Scanned zero files under \(Self.guardedDirectories) - the guard did not run.")
        #expect(offendingFiles.isEmpty, "Mail-store reference found in a connector/front-end source file: \(offendingFiles)")
    }

    /// A forbidden reference hiding inside a file whose NAME gives no hint - the exact
    /// gap the filename-only guard had. Regression fixture for that gap: a temporary
    /// file named plainly (`Helper.swift`) that still calls `MailStoreReader(...)`
    /// must be caught once the guard reads source instead of names.
    @Test func aForbiddenReferenceInsideAnOrdinarilyNamedFileIsDetected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-isolation-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "Helper.swift", directoryHint: .notDirectory)
        try """
        // A comment mentioning MailStoreReader must NOT trip the guard on its own.
        struct Helper {
            func read() { _ = MailStoreReader(storeURL: URL(fileURLWithPath: "/tmp")) }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let text = try String(contentsOf: file, encoding: .utf8)
        let source = Self.strippingCommentsAndStringLiterals(text)

        #expect(
            !source.contains("A comment mentioning MailStoreReader"),
            "the comment line must be stripped before the scan, or the guard would flag every explanatory mention"
        )
        #expect(
            Self.forbiddenNameFragments.contains(where: { source.contains($0) }),
            "the real call site, outside any comment or string, must still be detected"
        )
    }

    /// The three expressions `strippingCommentsAndStringLiterals` applies, compiled once
    /// rather than per scanned file: that function runs over every Swift file under the
    /// guarded directories. `compactMap` keeps the same "a pattern that will not compile
    /// is skipped" behaviour the loop's `try?`/`continue` had.
    private static let strippingPatterns: [NSRegularExpression] =
        ["/\\*[\\s\\S]*?\\*/", "\"([^\"\\\\]|\\\\.)*\"", "//[^\n]*"]
            .compactMap { try? NSRegularExpression(pattern: $0) }

    /// Comments (`//` and `/* */`) and string-literal contents removed before the
    /// forbidden-name search, so a doc comment or a log message that merely NAMES one
    /// of the forbidden identifiers is never mistaken for a real source reference.
    /// Deliberately simple (no nested block comments, no raw strings) - matching this
    /// repo's own `weakening-scan.sh` precedent (CLAUDE.md "Working agreements") of a
    /// pragmatic heuristic over a full Swift lexer for a guard, not a compiler.
    private static func strippingCommentsAndStringLiterals(_ text: String) -> String {
        var result = text
        for regex in strippingPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
    }
}
