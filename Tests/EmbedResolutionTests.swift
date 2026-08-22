import AppKit
import Testing
@testable import Pergamenum

// The editor's half of resolving an embed to a picture (ADR-0018 slice 3, Step 2): what
// `NoteTextView.Coordinator.applyEmbeds` does with the `.embedRun` lines `applyStyling`
// already found. Driven through a real `NSTextView` offscreen, the same way
// `TranscludedLineTests` and `MarkupCoordinator` check their own Coordinator methods -
// `Attachment.resolve` and `ThumbnailStore` are both real here, never stubbed, because the
// whole point of this step is wiring the three of them together correctly.
@MainActor
@Suite struct EmbedResolutionTests {
    private static func makeTempVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-embed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A tiny real PNG, the same way `EmbedAttachmentProbeTests.syntheticImage` builds one
    /// for a probe, written to disk here because `Attachment.resolve` and `ThumbnailStore`
    /// both read a real file rather than an in-memory image.
    private static func writeImage(named name: String, in root: URL) throws {
        let image = NSImage(size: CGSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 40, height: 30)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: root.appending(path: name, directoryHint: .notDirectory))
    }

    /// The text view `applyStyling` and `applyEmbeds` run against, minus SwiftUI and minus
    /// the frame/container sizing `TranscludedLineTests` needs for its own layout
    /// assertions: nothing here reads a fragment's geometry, only the render table.
    private static func editor(
        text: String, root: URL?, thumbnails: ThumbnailStore?
    ) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in }, vaultRoot: root, notePath: "Nota.md", thumbnails: thumbnails
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = text
        return (textView, coordinator)
    }

    /// Polls `embeds.renditions` until the offset appears or the bound runs out. The
    /// render is a real, asynchronous call into the `ThumbnailStore` actor - not a
    /// stand-in - so this test waits for it rather than assuming one run-loop turn is
    /// enough, the same way `Task.sleep` yields the main actor for any other pending job
    /// queued on it.
    private static func waitForRendition(
        at offset: Int, in coordinator: NoteTextView.Coordinator
    ) async -> EmbedRendition? {
        for _ in 0..<100 {
            if let rendition = coordinator.embeds.renditions[offset] { return rendition }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return coordinator.embeds.renditions[offset]
    }

    @Test func anImageEmbedResolvesToADrawnRenditionWithARealRender() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )

        let text = "testo\n![[foto.png]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset = (text as NSString).range(of: "![[foto.png]]").location
        // Nothing yet, synchronously: the first pass never blocks on the render.
        #expect(coordinator.embeds.renditions[offset] == nil)

        guard case .drawn(let image) = await Self.waitForRendition(at: offset, in: coordinator) else {
            Issue.record("expected the embed to resolve to a drawn rendition")
            return
        }
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func aMissingFileResolvesToMissingWithoutTouchingTheRenderer() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )

        let text = "prima\n![[assente.png]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset = (text as NSString).range(of: "![[assente.png]]").location
        // Resolved synchronously to `.missing`, unlike the drawn case above: a file that
        // is not in the vault at all never reaches `ThumbnailStore`.
        #expect(coordinator.embeds.renditions[offset] == .missing(name: "assente.png"))
    }

    @Test func aFileWhoseTypeIsNeitherAPictureNorAPDFIsNeverEnteredInTheTable() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("appunti".utf8).write(to: root.appending(path: "appunti.txt", directoryHint: .notDirectory))
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )

        let text = "prima\n![[appunti.txt]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset = (text as NSString).range(of: "![[appunti.txt]]").location
        // Not `.missing` either - D3's own filter, resolved but not drawable, stays out of
        // the table entirely rather than being reported as broken.
        #expect(coordinator.embeds.renditions[offset] == nil)
    }

    @Test func withoutAVaultBehindItNoEmbedIsEverResolved() {
        // The Diario preview and the mockups build a `NoteTextView` with no vault at all -
        // `vaultRoot`/`thumbnails` default to nil - and the honest behaviour there is to
        // leave every embed exactly as it is today, matching `spellCheck`'s own default.
        let text = "prima\n![[foto.png]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: nil, thumbnails: nil)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        #expect(coordinator.embeds.renditions.isEmpty)
    }
}
