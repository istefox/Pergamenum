import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 §D3, Task 4 — "Three vault walks become one, built from the boundary" (R-03).
// `VaultWalk` unifies `VaultScanner.scan()`, `CanvasStore.walk()` and
// `FolderFileOperations.walk(_:)`, which had drifted into three copies of the same
// `FileManager.enumerator` + `VaultLayout.isExcludedDirectory` + `skipDescendants()` dance.
//
// Declared signature (Tester declares, per the task brief):
//
//   struct VaultWalk: Sendable {
//       struct Entry: Sendable {
//           let url: URL
//           let relativePath: String
//           let name: String
//           let isDirectory: Bool
//           let byteSize: Int?
//           let modifiedAt: Date?
//       }
//       init(boundary: VaultBoundary, subfolder: String = "", keys: Set<URLResourceKey> = []) throws
//       func forEach(_ body: (Entry) -> Void)
//   }

// MARK: - Fixture

/// Kept local on purpose (ADR-0051 §D4, PG-176). It is the same shape as `CanvasTemporaryRoot`
/// (`url` and `makeFile`, with no caller reading the `URL` this `makeFile` returns), but that
/// fixture is named and documented for canvas suites and nothing here touches a board;
/// adopting it would make a walk test read as a canvas test, and renaming it costs every canvas
/// suite. If a neutral name for the plain-directory fixture is ever wanted, this is the first
/// candidate to fold into it.
private struct VaultWalkFixture: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-vaultwalk-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func makeFile(_ relativePath: String, _ contents: String = "x") throws -> URL {
        let fileURL = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }
}

/// Free function rather than a method on the fixture or on `VaultWalk`: `#expect` captures
/// the whole expression, and the fixture above is non-copyable.
private func collectRelativePaths(_ walk: VaultWalk, includeDirectories: Bool = false) -> Set<String> {
    var paths = Set<String>()
    walk.forEach { entry in
        if includeDirectories || !entry.isDirectory {
            paths.insert(entry.relativePath)
        }
    }
    return paths
}

private let fourResourceKeys: Set<URLResourceKey> = [
    .isDirectoryKey, .nameKey, .fileSizeKey, .contentModificationDateKey,
]

// MARK: - Dot-directory exclusion, with `skipDescendants` semantics (not a filter)

@Test func dotDirectoriesAreExcludedEntirelyIncludingTheirDescendants() throws {
    let fixture = try VaultWalkFixture()
    // Direct children of each excluded directory...
    try fixture.makeFile(".git/config")
    try fixture.makeFile(".obsidian/workspace.json")
    try fixture.makeFile(".pergamenum/settings.json")
    try fixture.makeFile(".trash/deleted.md")
    // ...and content nested *inside* them, two levels deep. A check that only tests the
    // directory's own name (a filter) rather than calling `skipDescendants()` still
    // descends into these — this is what tells the two apart.
    try fixture.makeFile(".git/objects/aa/blob.dat")
    try fixture.makeFile(".trash/Sotto/Vecchia.md")
    // A normal folder, so the test is red for "nothing walked", not vacuously green
    // because the walk returned nothing at all.
    try fixture.makeFile("Normal.md")
    try fixture.makeFile("Folder/Inside.md")

    let boundary = VaultBoundary(root: fixture.url)
    let walk = try VaultWalk(boundary: boundary)
    let paths = collectRelativePaths(walk)

    #expect(paths.contains("Normal.md"))
    #expect(paths.contains("Folder/Inside.md"))

    for excludedPrefix in [".git/", ".obsidian/", ".pergamenum/", ".trash/"] {
        let leaked = paths.contains { $0.hasPrefix(excludedPrefix) }
        #expect(!leaked, "expected no entry under \(excludedPrefix), found one in \(paths)")
    }
}

// MARK: - `subfolder:` scoping, relative paths still measured from the vault root

@Test func subfolderScopingYieldsOnlyThatSubtreeWithRootMeasuredRelativePaths() throws {
    let fixture = try VaultWalkFixture()
    try fixture.makeFile("01 Progetti/Progetto A.md")
    try fixture.makeFile("01 Progetti/Sub/Annidata.md")
    try fixture.makeFile("02 Aree/Area A.md")

    let boundary = VaultBoundary(root: fixture.url)
    let walk = try VaultWalk(boundary: boundary, subfolder: "01 Progetti")
    let paths = collectRelativePaths(walk)

    // Scoped to "01 Progetti" only...
    #expect(!paths.contains("02 Aree/Area A.md"))
    // ...but every relative path still carries the "01 Progetti/" prefix - measured from
    // the vault root, not from the subfolder passed in.
    #expect(paths == Set(["01 Progetti/Progetto A.md", "01 Progetti/Sub/Annidata.md"]))
}

// MARK: - `subfolder: "../escape"` throws via the inherited boundary

@Test func subfolderEscapingTheVaultThrowsViaTheInheritedBoundary() throws {
    let fixture = try VaultWalkFixture()
    try fixture.makeFile("Normal.md")
    let boundary = VaultBoundary(root: fixture.url)

    do {
        _ = try VaultWalk(boundary: boundary, subfolder: "../escape")
        Issue.record("expected VaultWalk.init to throw for a subfolder that escapes the vault")
    } catch VaultBoundary.Violation.outsideVault(let path) {
        #expect(path == "../escape")
    } catch {
        Issue.record("expected VaultBoundary.Violation.outsideVault, got \(error)")
    }
}

// MARK: - Symlinked vault root

@Test func symlinkedVaultRootYieldsCorrectRelativePathsAndNoEntryEscapes() throws {
    let realRoot = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-vaultwalk-real-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: realRoot) }

    try FileManager.default.createDirectory(
        at: realRoot.appending(path: "Cartella", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    try Data("x".utf8).write(to: realRoot.appending(path: "Documento.md", directoryHint: .notDirectory))
    try Data("x".utf8).write(
        to: realRoot.appending(path: "Cartella/Nota.md", directoryHint: .notDirectory)
    )

    let symlinkRoot = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-vaultwalk-link-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)
    defer { try? FileManager.default.removeItem(at: symlinkRoot) }

    let boundary = VaultBoundary(root: symlinkRoot)
    let walk = try VaultWalk(boundary: boundary)
    let paths = collectRelativePaths(walk)

    #expect(paths == Set(["Documento.md", "Cartella/Nota.md"]))

    var sawEscapedEntry = false
    walk.forEach { entry in
        if !boundary.contains(entry.url) { sawEscapedEntry = true }
    }
    #expect(!sawEscapedEntry)
}

/// The one entry in `walk` at `relativePath`, or nil - a plain helper rather than an
/// inline closure, since `#require`'s macro expansion captures its argument's source text.
private func entry(at relativePath: String, in walk: VaultWalk) -> VaultWalk.Entry? {
    var found: VaultWalk.Entry?
    walk.forEach { if $0.relativePath == relativePath { found = $0 } }
    return found
}

// MARK: - `keys: []` vs. the four-key set

@Test func emptyKeysYieldNilMetadataWhileTheFourKeySetPopulatesIt() throws {
    let fixture = try VaultWalkFixture()
    try fixture.makeFile("Nota.md", "contenuto di prova")

    let boundary = VaultBoundary(root: fixture.url)

    let bare = try VaultWalk(boundary: boundary)
    let bareEntry = try #require(entry(at: "Nota.md", in: bare))
    #expect(bareEntry.byteSize == nil)
    #expect(bareEntry.modifiedAt == nil)

    let full = try VaultWalk(boundary: boundary, keys: fourResourceKeys)
    let fullEntry = try #require(entry(at: "Nota.md", in: full))
    #expect(fullEntry.byteSize != nil)
    #expect(fullEntry.modifiedAt != nil)
}

// MARK: - Equivalence against current `VaultScanner.scan()` behaviour (the important one)

@Test func newWalkMatchesVaultScannerIndexingBeforeThisTask() throws {
    let fixture = try VaultWalkFixture()

    // Fifteen `.md` files across three levels (root, folder, subfolder)...
    try fixture.makeFile("Nota Radice.md")
    try fixture.makeFile("01 Progetti/Progetto A.md")
    try fixture.makeFile("01 Progetti/Progetto B.md")
    try fixture.makeFile("01 Progetti/Sub/Annidata Uno.md")
    try fixture.makeFile("01 Progetti/Sub/Annidata Due.md")
    try fixture.makeFile("01 Progetti/Sub/Annidata Tre.md")
    try fixture.makeFile("02 Aree/Area A.md")
    try fixture.makeFile("02 Aree/Area B.md")
    try fixture.makeFile("02 Aree/Sub2/Profonda Uno.md")
    try fixture.makeFile("02 Aree/Sub2/Profonda Due.md")
    try fixture.makeFile("03 Archivio/Vecchia A.md")
    try fixture.makeFile("03 Archivio/Vecchia B.md")
    try fixture.makeFile("03 Archivio/Vecchia C.md")
    try fixture.makeFile("04 Altro/Extra Uno.md")
    try fixture.makeFile("04 Altro/Extra Due.md")
    // ...plus two dot-directories, which must contribute nothing to either side.
    try fixture.makeFile(".git/config")
    try fixture.makeFile(".obsidian/workspace.json")

    // The frozen snapshot: what `VaultScanner.scan()` indexes today, over exactly this
    // fixture, recorded *before* Task 4 rewires `scan()` onto `VaultWalk` - so the
    // comparison stays a real regression check rather than the walk being checked
    // against a wrapper around itself once the rewrite lands.
    let expected: Set<String> = [
        "Nota Radice.md",
        "01 Progetti/Progetto A.md",
        "01 Progetti/Progetto B.md",
        "01 Progetti/Sub/Annidata Uno.md",
        "01 Progetti/Sub/Annidata Due.md",
        "01 Progetti/Sub/Annidata Tre.md",
        "02 Aree/Area A.md",
        "02 Aree/Area B.md",
        "02 Aree/Sub2/Profonda Uno.md",
        "02 Aree/Sub2/Profonda Due.md",
        "03 Archivio/Vecchia A.md",
        "03 Archivio/Vecchia B.md",
        "03 Archivio/Vecchia C.md",
        "04 Altro/Extra Uno.md",
        "04 Altro/Extra Due.md",
    ]
    #expect(expected.count == 15)

    // Self-check: confirms the fixture actually produces the frozen snapshot above under
    // today's (pre-Task-4) `VaultScanner.scan()`, so a drift in the fixture itself is
    // caught here rather than silently weakening the comparison below.
    let recordedByCurrentScanner = Set(VaultScanner(root: fixture.url).scan().records.map(\.relativePath))
    #expect(recordedByCurrentScanner == expected)

    let boundary = VaultBoundary(root: fixture.url)
    let walk = try VaultWalk(boundary: boundary)
    let walkedMDPaths = Set(
        walk.forEachYielding().filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "md" }
            .map(\.relativePath)
    )
    #expect(walkedMDPaths == expected)
}

/// `forEach` collected into an array, so the equivalence test above can `.filter`/`.map`
/// rather than hand-rolling another accumulation loop.
extension VaultWalk {
    fileprivate func forEachYielding() -> [Entry] {
        var entries: [Entry] = []
        forEach { entries.append($0) }
        return entries
    }
}
