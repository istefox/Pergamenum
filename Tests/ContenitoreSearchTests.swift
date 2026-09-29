import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D9, plan docs/plans/contenitore.md, Task 5 - R-10. Global search
// returns a scheda for a word found only in its document's extracted text, through the
// synchronous door, the cooperative door and the connector's `VaultAPI.search`; clearing the
// derived cache removes the hit and changes no vault file.

private let hash = String(repeating: "c", count: 64)
private let schedaPath = "Contenitore/2026/20260929 scansione.md"
private let filePath = "Contenitore/2026/20260929 scansione.pdf"
private let extractedLine = "Preventivo fornitura guarnizioni"

/// A vault with one scheda whose text says nothing of the queried word, its file beside it, one
/// unrelated note, and the scheda's extracted text pre-seeded in the cache.
@MainActor
private func seededSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let day = try #require(CalendarDate(year: 2026, month: 9, day: 29))
    try vault.write(
        ContenitoreScheda.render(date: day, fileName: "20260929 scansione.pdf", originalName: "scansione.pdf", sha256: hash),
        to: schedaPath
    )
    try vault.write("pdf", to: filePath)
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nNiente da vedere.\n", to: "Altra.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    try session.extractedTexts.write(
        ExtractedText(method: .ocr, status: .done, text: "Intestazione\n\(extractedLine)\nFine"),
        sha256: hash
    )
    return session
}

/// Every regular file under the vault root, by relative path, with its bytes.
private func snapshot(of root: URL) throws -> [String: Data] {
    let base = root.resolvingSymlinksInPath().path(percentEncoded: false)
    var files: [String: Data] = [:]
    let enumerator = try #require(FileManager.default.enumerator(at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]))
    for case let url as URL in enumerator {
        guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
        let path = url.path(percentEncoded: false)
        files[String(path.dropFirst(base.count + (base.hasSuffix("/") ? 0 : 1)))] = try Data(contentsOf: url)
    }
    return files
}

@MainActor
@Test func theSynchronousDoorReturnsTheSchedaForAWordOnlyInItsExtractedText() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    let results = session.search(SearchQuery("guarnizioni"))

    #expect(results.map(\.path) == [schedaPath])
    #expect(results.first?.excerpt == extractedLine)
}

@MainActor
@Test func theCooperativeDoorReturnsTheSameHitAndExcerpt() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    let results = try await session.searchCooperatively(SearchQuery("guarnizioni"), chunkSize: 1) {}

    #expect(results.map(\.path) == [schedaPath])
    #expect(results.first?.excerpt == extractedLine)
    #expect(results == session.search(SearchQuery("guarnizioni")))
}

@MainActor
@Test func theConnectorSearchReturnsTheSchedaToo() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    let hits = try VaultAPI.search(session, "guarnizioni", limit: nil)

    #expect(hits.map(\.path) == [schedaPath])
    #expect(hits.first?.excerpt == extractedLine)
}

@MainActor
@Test func aWordInNoSchedaNorItsExtractedTextFindsNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    #expect(session.search(SearchQuery("parolainesistente")).isEmpty)
}

@MainActor
@Test func anEmptyExtractionAddsNoTextToTheScheda() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)
    try session.extractedTexts.write(ExtractedText(method: .none, status: .failed, text: ""), sha256: hash)

    #expect(session.search(SearchQuery("guarnizioni")).isEmpty)
}

@MainActor
@Test func removingTheCacheDropsTheHitOnEveryDoorAndChangesNoVaultFile() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)
    let before = try snapshot(of: vault.root)
    #expect(session.search(SearchQuery("guarnizioni")).count == 1)

    try session.extractedTexts.removeAll()

    #expect(session.search(SearchQuery("guarnizioni")).isEmpty)
    #expect(try await session.searchCooperatively(SearchQuery("guarnizioni")).isEmpty)
    #expect(try VaultAPI.search(session, "guarnizioni", limit: nil).isEmpty)
    let after = try snapshot(of: vault.root)
    #expect(Set(after.keys) == Set(before.keys))
    #expect(after == before, "removing the derived cache changed a vault file")
    #expect(!before.isEmpty)
}
