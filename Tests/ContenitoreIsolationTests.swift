import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D9, plan docs/plans/contenitore.md, Task 5 - R-12: no network call is
// made by import, extraction or the pane. Modelled on `PraticheIsolationTests`: the source of every
// Contenitore file is scanned, comments and string literals stripped first, and the scan must prove
// it looked at something.
@Suite struct ContenitoreIsolationTests {
    private static let scannedDirectories = [
        "Sources/Core/Contenitore",
        "Sources/Features/Contenitore",
    ]

    /// The `Sources/Vault` files this feature added or is made of.
    private static let scannedFiles = [
        "Sources/Vault/ExtractedTextStore.swift",
        "Sources/Vault/VaultSession+Adopt.swift",
        "Sources/Vault/VaultSession+Contenitore.swift",
        "Sources/Index/IndexSnapshot+Contenitore.swift",
    ]

    private static let forbidden = [
        "URLSession", "URLRequest", "NWConnection", "import Network", "NWPathMonitor", "CFNetwork",
    ]

    private static func swiftFiles() throws -> [URL] {
        let repoRoot = try resolvedRepoRoot()
        var files: [URL] = []
        for directory in scannedDirectories {
            let url = repoRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
                Issue.record("Could not enumerate \(url.path)")
                continue
            }
            for case let file as URL in enumerator where file.pathExtension == "swift" { files.append(file) }
        }
        for path in scannedFiles {
            let url = repoRoot.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                files.append(url)
            } else {
                Issue.record("Expected file is missing: \(path)")
            }
        }
        return files
    }

    @Test func noContenitoreFileTouchesTheNetwork() throws {
        let files = try Self.swiftFiles()
        var offending: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let source = Self.strippingCommentsAndStringLiterals(text)
            if Self.forbidden.contains(where: { source.contains($0) }) { offending.append(file.lastPathComponent) }
        }

        // An enumerator that silently visits nothing reads as a pass; insist on a positive count.
        #expect(files.count >= 10, "Scanned only \(files.count) files - the guard did not run.")
        #expect(offending.isEmpty, "Network reference in a Contenitore source file: \(offending)")
    }

    @Test func aNetworkCallInsideAnOrdinarilyNamedFileIsDetected() {
        let source = Self.strippingCommentsAndStringLiterals("""
        // A comment about URLSession must not trip the guard.
        let note = "URLRequest inside a string"
        func fetch() { _ = URLSession.shared }
        """)

        #expect(!source.contains("A comment about"))
        #expect(!source.contains("inside a string"))
        #expect(Self.forbidden.contains(where: { source.contains($0) }))
    }

    private static let strippingPatterns: [NSRegularExpression] =
        ["/\\*[\\s\\S]*?\\*/", "\"([^\"\\\\]|\\\\.)*\"", "//[^\n]*"]
            .compactMap { try? NSRegularExpression(pattern: $0) }

    private static func strippingCommentsAndStringLiterals(_ text: String) -> String {
        var result = text
        for regex in strippingPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
    }
}
