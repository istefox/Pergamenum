import Foundation
import Testing
@testable import Pergamenum

// MARK: - Reading an embed

@Test func readsBothWaysOfEmbeddingAFile() {
    #expect(Attachment.embed(inLine: "![[foto.png]]") == .init(target: "foto.png", alt: nil))
    #expect(Attachment.embed(inLine: "![Pressa 4](foto.png)") == .init(target: "foto.png", alt: "Pressa 4"))
    // Obsidian sizes an embed after a pipe. The size is not ours to interpret yet, but
    // the name in front of it is still the file.
    #expect(Attachment.embed(inLine: "![[foto.png|300]]") == .init(target: "foto.png", alt: nil))
    // Indented, as it would be inside a list the user is building.
    #expect(Attachment.embed(inLine: "   ![[foto.png]]  ") == .init(target: "foto.png", alt: nil))
}

@Test func anEmbedInTheMiddleOfASentenceIsNotABlock() {
    #expect(Attachment.embed(inLine: "vedi ![[foto.png]] qui") == nil)
    #expect(Attachment.embed(inLine: "![[foto.png]] e altro") == nil)
    #expect(Attachment.embed(inLine: "[[Nota]]") == nil)
    #expect(Attachment.embed(inLine: "![alt](a.png) e ![alt](b.png)") == nil)
    #expect(Attachment.embed(inLine: "") == nil)
    #expect(Attachment.embed(inLine: "![[]]") == nil)
}

@Test func recognisesARemoteTargetSoItIsNeverFetched() {
    #expect(Attachment.isRemote("https://vibrofer.it/foto.png"))
    #expect(Attachment.isRemote("HTTP://vibrofer.it/foto.png"))
    #expect(!Attachment.isRemote("foto.png"))
    #expect(!Attachment.isRemote("cartella/foto.png"))
    // A file whose name contains a colon is still a file.
    #expect(!Attachment.isRemote("nota: appunti.png"))
}

// MARK: - Finding the file

private struct AttachmentVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
    }
}

@Test func findsTheFileBesideTheNoteFirst() throws {
    let vault = try AttachmentVault()
    try vault.write("01 Progetti/foto.png")
    try vault.write("foto.png")

    #expect(Attachment.resolve(
        "foto.png", nearNoteAt: "01 Progetti/Nota.md", inVaultAt: vault.root
    ) == "01 Progetti/foto.png")
}

@Test func fallsBackToTheVaultRootAndThenToTheName() throws {
    let vault = try AttachmentVault()
    try vault.write("Allegati/schema.png")

    // Written as a path from the root.
    #expect(Attachment.resolve(
        "Allegati/schema.png", nearNoteAt: "01 Progetti/Nota.md", inVaultAt: vault.root
    ) == "Allegati/schema.png")
    // Written as a bare name: moving the picture in the Finder must not blank it out.
    #expect(Attachment.resolve(
        "schema.png", nearNoteAt: "01 Progetti/Nota.md", inVaultAt: vault.root
    ) == "Allegati/schema.png")
}

@Test func readsANameThatArrivedPercentEncoded() throws {
    let vault = try AttachmentVault()
    try vault.write("foto pressa.png")

    #expect(Attachment.resolve(
        "foto%20pressa.png", nearNoteAt: "Nota.md", inVaultAt: vault.root
    ) == "foto pressa.png")
}

@Test func refusesToLeaveTheVault() throws {
    let vault = try AttachmentVault()
    try vault.write("dentro.png")

    #expect(Attachment.resolve("/etc/hosts", nearNoteAt: "Nota.md", inVaultAt: vault.root) == nil)
    #expect(Attachment.resolve("~/foto.png", nearNoteAt: "Nota.md", inVaultAt: vault.root) == nil)
    #expect(Attachment.resolve("../fuori.png", nearNoteAt: "Nota.md", inVaultAt: vault.root) == nil)
    #expect(Attachment.resolve(
        "../../Desktop/dentro.png", nearNoteAt: "01 Progetti/Nota.md", inVaultAt: vault.root
    ) == nil)
}

@Test func aMissingFileResolvesToNothingRatherThanAGuess() throws {
    let vault = try AttachmentVault()
    #expect(Attachment.resolve("assente.png", nearNoteAt: "Nota.md", inVaultAt: vault.root) == nil)
    // Remote is refused here too: this app makes no network call in any feature.
    #expect(Attachment.resolve(
        "https://vibrofer.it/foto.png", nearNoteAt: "Nota.md", inVaultAt: vault.root
    ) == nil)
}

@Test func aFolderIsNotAnAttachment() throws {
    let vault = try AttachmentVault()
    try FileManager.default.createDirectory(
        at: vault.root.appending(path: "foto.png", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    #expect(Attachment.resolve("foto.png", nearNoteAt: "Nota.md", inVaultAt: vault.root) == nil)
}
