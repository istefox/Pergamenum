import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 implementation notes (hand check, «Sposta in…»): `standardizedFileURL` drops a
// leading `/private` only from a path that exists, so under a root spelled `/private/tmp/…`
// a file not yet created standardized to a different spelling than its root, failed the
// prefix test and came back as its bare last component - the vault root.

/// The temporary directory in the spelling the system itself resolves to (`/private/var/…`),
/// plus a fresh folder in it - created, so the root exists exactly as a real vault does.
private func privateSpelledRoot() throws -> URL {
    let plain = FileManager.default.temporaryDirectory
        .appending(path: "relative-path-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    let path = plain.path(percentEncoded: false)
    let spelled = path.hasPrefix("/private/") ? path : "/private" + path
    return URL(fileURLWithPath: spelled, isDirectory: true)
}

@Suite struct VaultScannerRelativePathTests {
    @Test func aMissingFileUnderAPrivateRootIsStillVaultRelative() throws {
        let root = try privateSpelledRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appending(path: "Rossi/email/msg.md", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: existing.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: existing)
        let missing = root.appending(path: "Bianchi/email/msg.md", directoryHint: .notDirectory)

        #expect(VaultScanner.relativePath(of: existing, under: root) == "Rossi/email/msg.md")
        #expect(
            VaultScanner.relativePath(of: missing, under: root) == "Bianchi/email/msg.md",
            "a move target does not exist yet, and must not fall back to the vault root"
        )
    }

    @Test func everySpellingOfRootAndFileAgrees() throws {
        let privateRoot = try privateSpelledRoot()
        defer { try? FileManager.default.removeItem(at: privateRoot) }
        let plainRoot = URL(
            fileURLWithPath: String(privateRoot.path(percentEncoded: false).dropFirst("/private".count)),
            isDirectory: true
        )
        for root in [privateRoot, plainRoot] {
            for base in [privateRoot, plainRoot] {
                let file = base.appending(path: "01 Progetti/Nuova.md", directoryHint: .notDirectory)
                #expect(
                    VaultScanner.relativePath(of: file, under: root) == "01 Progetti/Nuova.md",
                    "root \(root.path(percentEncoded: false)), file \(file.path(percentEncoded: false))"
                )
            }
        }
    }

    @Test func aFileOutsideTheRootStillFallsBackToItsName() throws {
        let root = try privateSpelledRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = URL(fileURLWithPath: "/Users/someone/Altrove/nota.md", isDirectory: false)

        #expect(VaultScanner.relativePath(of: outside, under: root) == "nota.md")
    }
}
