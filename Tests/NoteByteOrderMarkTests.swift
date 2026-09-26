import CryptoKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0064 §D4, plan docs/plans/format-edge-hardening.md, Task 2 - R-01, R-02 (G1.2).
//
// The byte-order mark belongs to the file, not to the text: one decode door strips it, the
// content hash skips it, and the write keeps it. The vault-level cases go through the session's
// own doors, in `CategoryLintTests`' shape (SPEC Test seam 2).

private let bom = Data([0xEF, 0xBB, 0xBF])

@MainActor
private func openSession(root: URL, stateBase: URL) async -> VaultSession {
    let opened = VaultSession(
        root: root, stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await opened.rescan()
    return opened
}

private func writeBytes(_ data: Data, to relativePath: String, in root: URL) throws {
    try data.write(to: root.appending(path: relativePath, directoryHint: .notDirectory))
}

private func bytes(of relativePath: String, in root: URL) throws -> Data {
    try Data(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory))
}

private func decodedWithoutBOM(_ data: Data) -> String? {
    String(data: data.starts(with: bom) ? data.dropFirst(3) : data, encoding: .utf8)
}

private let categoryLine = "pergamenum-category: presse\r\n"

private var crlfWithCategory: String {
    FormatEdgeCorpus.crlfWithFrontmatter.text
        .replacingOccurrences(of: "  - type-note\r\n---", with: "  - type-note\r\n" + categoryLine + "---")
}

// MARK: - The decode door and the hash

@Test func theDecodeDoorStripsOneLeadingBOM() {
    #expect(NoteStore.decodedText(bom + Data("---\n".utf8)) == "---\n")
    #expect(NoteStore.decodedText(Data("---\n".utf8)) == "---\n")
    #expect(NoteStore.decodedText(Data("a\u{FEFF}b".utf8)) == "a\u{FEFF}b")
}

@Test func theContentHashSkipsOneLeadingBOM() {
    let text = Data(FormatEdgeCorpus.crlfWithFrontmatter.text.utf8)
    #expect(NoteStore.hash(bom + text) == NoteStore.hash(text))
    // A BOM-less file's hash is its plain SHA-256: every hash already persisted stays valid.
    let plain = SHA256.hash(data: text).map { String(format: "%02x", $0) }.joined()
    #expect(NoteStore.hash(text) == plain)
}

/// Characterization, measured on the first run (macOS 27, 2026-09-26): the platform's UTF-8
/// decode strips a leading BOM. ADR-0064 §D4 does not depend on this answer - the decode door
/// strips it itself - the test only records which world this OS is in.
@Test func platformUTF8DecodeOfABOMIsRecorded() {
    let decoded = String(data: bom + Data("---\n".utf8), encoding: .utf8)
    #expect(decoded?.unicodeScalars.first != "\u{FEFF}")
    #expect(decoded == "---\n")
}

// MARK: - Through the session's write door

@MainActor
@Test func aCRLFNoteKeepsCRLFThroughTheSessionDoor() async throws {
    let vault = try TemporaryVault()
    try vault.write(FormatEdgeCorpus.crlfWithFrontmatter.text, to: "Nota.md")
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    let outcome = await session.linkCategory("presse", toNoteAt: "Nota.md")

    #expect(outcome.result != nil)
    let written = try #require(String(data: try bytes(of: "Nota.md", in: vault.root), encoding: .utf8))
    #expect(written == crlfWithCategory)
    #expect(written.components(separatedBy: "\n").dropLast().allSatisfy { $0.hasSuffix("\r") })
    #expect(written.components(separatedBy: "\n").filter { $0 == "---\r" }.count == 2)
}

@MainActor
@Test func aBOMNoteKeepsItsBOMThroughACategoryLink() async throws {
    let vault = try TemporaryVault()
    try writeBytes(bom + Data(FormatEdgeCorpus.crlfWithFrontmatter.text.utf8), to: "Nota.md", in: vault.root)
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    let outcome = await session.linkCategory("presse", toNoteAt: "Nota.md")

    #expect(outcome.result != nil)
    let data = try bytes(of: "Nota.md", in: vault.root)
    #expect(data.starts(with: bom))
    #expect(!data.dropFirst(3).starts(with: bom))
    let text = try #require(decodedWithoutBOM(data))
    #expect(text == crlfWithCategory)
    #expect(text.components(separatedBy: "\n").dropLast().allSatisfy { $0.hasSuffix("\r") })
}

@MainActor
@Test func aBOMNoteIsNotRefusedByTheLinkWriter() async throws {
    let vault = try TemporaryVault()
    let note = "---\ndate: 2026-09-26\ntags:\n  - type-note\n---\n\nCorpo.\n"
    try writeBytes(bom + Data(note.utf8), to: "Alfa.md", in: vault.root)
    try writeBytes(bom + Data(note.utf8), to: "Beta.md", in: vault.root)
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    let result = await session.addStructuralLink(
        from: "Alfa.md", to: "Beta", reason: "fornitura", reverseReason: "fornitura"
    )

    #expect(result.created)
    #expect(result.written.count == 2)
    #expect(session.problems.isEmpty)
    for path in ["Alfa.md", "Beta.md"] {
        #expect(try bytes(of: path, in: vault.root).starts(with: bom))
    }
    let source = try #require(decodedWithoutBOM(try bytes(of: "Alfa.md", in: vault.root)))
    #expect(NoteDocument.parse(source).frontmatter.related.contains("[[Beta]]"))
}

@MainActor
@Test func theAppsOwnWriteToABOMNoteIsNotAnExternalChange() async throws {
    let vault = try TemporaryVault()
    try writeBytes(bom + Data(FormatEdgeCorpus.crlfWithFrontmatter.text.utf8), to: "Nota.md", in: vault.root)
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    #expect(await session.linkCategory("presse", toNoteAt: "Nota.md").result != nil)

    #expect(await session.reconcile(["Nota.md"]).isEmpty)
}

@MainActor
@Test func theReadTextOfABOMNoteHasNoBOM() async throws {
    let vault = try TemporaryVault()
    try writeBytes(bom + Data(FormatEdgeCorpus.lfConformant.text.utf8), to: "Nota.md", in: vault.root)
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    let text = try session.read("Nota.md").text

    #expect(text.unicodeScalars.first != "\u{FEFF}")
    #expect(text == FormatEdgeCorpus.lfConformant.text)
}

@MainActor
@Test func aNewNoteNeverGetsABOM() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(root: vault.root, stateBase: vault.stateBase)

    try await session.createNote(title: "Nuova nota", date: try #require(CalendarDate(iso: "2026-09-26")))

    #expect(!(try bytes(of: "Nuova nota.md", in: vault.root)).starts(with: bom))
}
