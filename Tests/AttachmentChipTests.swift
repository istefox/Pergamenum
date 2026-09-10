import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 §D16/§D18 (over-threshold attachments stay in Mail's own store, recorded as
// `MessageDocument.StoreReference` rather than copied - R-10), plan
// docs/superpowers/plans/2026-09-09-pratiche.md Task 6 - R-27.
//
// `AttachmentChipModel` is a tester-declared boundary (ADR-0155): every test below exercises
// the real (non-stubbed) implementation, since the extraction needed no placeholder body.
// A temporary directory stands in for `allegati/` and for Mail's own store - never
// `~/Library/Mail`.

@Suite struct AttachmentChipModelTests {
    private static func withTemporaryFile(_ body: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-chip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: - R-27: a copied file present on disk

    @Test func aLocalFileOnDiskGetsThePaperclipSymbolAndPreviewsOpensAndReveals() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))

            #expect(AttachmentChipModel.symbol(for: content, fileExists: Self.fileExists) == "paperclip")
            #expect(AttachmentChipModel.previewURL(for: content, fileExists: Self.fileExists) == url)
            #expect(AttachmentChipModel.openURL(for: content, fileExists: Self.fileExists) == url)
            #expect(AttachmentChipModel.revealURL(for: content, fileExists: Self.fileExists) == url)
            #expect(AttachmentChipModel.copyItems(for: content, fileExists: Self.fileExists) == [url])
        }
    }

    // MARK: - R-27: a file reference whose copy is not on disk

    @Test func aMissingLocalFileGetsTheQuestionMarkSymbolAndEveryTargetIsNil() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-chip-missing-\(UUID().uuidString)/offerta.pdf")
        let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))

        #expect(AttachmentChipModel.symbol(for: content, fileExists: Self.fileExists) == "questionmark.folder")
        #expect(AttachmentChipModel.previewURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.openURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.copyItems(for: content, fileExists: Self.fileExists).isEmpty)
    }

    // MARK: - R-10/R-27: a store reference whose store path still resolves

    @Test func aStoreReferenceWithAnExistingStorePathGetsTheCloudSlashSymbolButNoPreview() throws {
        try Self.withTemporaryFile { root in
            let storeURL = root.appending(path: "allegato-grande.zip", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: storeURL)
            let reference = MessageDocument.StoreReference(
                name: "allegato-grande.zip", size: 400_000_000, storePath: storeURL.path(percentEncoded: false)
            )
            let content = AttachmentChip.Content.storeReference(reference)

            #expect(AttachmentChipModel.symbol(for: content, fileExists: Self.fileExists) == "icloud.slash")
            // A store reference never previews in place (R-27): it opens from its store
            // path instead, which is a different action from Quick Look.
            #expect(AttachmentChipModel.previewURL(for: content, fileExists: Self.fileExists) == nil)
            #expect(AttachmentChipModel.openURL(for: content, fileExists: Self.fileExists) == storeURL)
            #expect(AttachmentChipModel.revealURL(for: content, fileExists: Self.fileExists) == storeURL)
            #expect(AttachmentChipModel.copyItems(for: content, fileExists: Self.fileExists) == [storeURL])
        }
    }

    // MARK: - R-10/R-27: a store reference whose store path is gone

    @Test func aStoreReferenceWithAnAbsentStorePathResolvesToNothing() {
        let storePath = "/Volumes/gone/allegato-grande.zip"
        let reference = MessageDocument.StoreReference(
            name: "allegato-grande.zip", size: 400_000_000, storePath: storePath
        )
        let content = AttachmentChip.Content.storeReference(reference)

        #expect(AttachmentChipModel.symbol(for: content, fileExists: Self.fileExists) == "icloud.slash")
        #expect(AttachmentChipModel.previewURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.openURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, fileExists: Self.fileExists) == nil)
        #expect(AttachmentChipModel.copyItems(for: content, fileExists: Self.fileExists).isEmpty)
    }

    // MARK: - R-27: the context menu's exact wording and order

    @Test func theContextMenuOffersExactlyMostraNelFinderAndCopia() {
        #expect(AttachmentChipModel.contextMenuTitles == ["Mostra nel Finder", "Copia"])
    }
}
