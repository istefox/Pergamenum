import AppKit
import Testing
@testable import Pergamenum

// The editor's half of resolving an embed to a picture (ADR-0018 slice 3, Step 2): what
// `NoteTextView.Coordinator.applyEmbeds` does with the `.embedRun` lines `applyStyling`
// already found. Driven through a real `NSTextView` offscreen, the same way
// `TranscludedLineTests` and `MarkupCoordinator` check their own Coordinator methods -
// `Attachment.resolve` and `ThumbnailStore` are both real here, never stubbed, because the
// whole point of this step is wiring the three of them together correctly.
//
// Extended for ADR-0019 ("A drawn embed is resized by dragging it, and the size is
// written into the note") - plan
// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 4:
// "the render is asked for at the size it will be drawn at".
@MainActor
@Suite struct EmbedResolutionTests {
    /// The text view `applyStyling` and `applyEmbeds` run against, minus SwiftUI and minus
    /// the frame/container sizing `TranscludedLineTests` needs for its own layout
    /// assertions: nothing here reads a fragment's geometry, only the render table. Not
    /// `EmbedEditorFixtures.editor(...)`: it builds no window and leaves `hidesMarkup` at
    /// `NoteTextView`'s own default, where the shared one always passes it (ADR-0051 §D4).
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

    /// Every paragraph-start offset of a line matching `needle`, in the order they occur -
    /// `EmbedTable.apply(runs:...)`'s own arithmetic (`text.paragraphRange(for:)` on the
    /// match location) so a second unsized `![[foto.png]]` on a later line is told apart
    /// from the first by the offset the render table actually keys on, not by content.
    private static func offsets(ofSubstring needle: String, in text: String) -> [Int] {
        let ns = text as NSString
        var found: [Int] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.length > 0 {
            let match = ns.range(of: needle, options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            let paragraphStart = ns.paragraphRange(for: NSRange(location: match.location, length: 0)).location
            found.append(paragraphStart)
            let nextStart = match.location + match.length
            searchRange = NSRange(location: nextStart, length: ns.length - nextStart)
        }
        return found
    }

    @Test func anImageEmbedResolvesToADrawnRenditionWithARealRender() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
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

        guard case .drawn(let image) = await EmbedEditorFixtures.waitForRendition(at: offset, in: coordinator) else {
            Issue.record("expected the embed to resolve to a drawn rendition")
            return
        }
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func aMissingFileResolvesToMissingWithoutTouchingTheRenderer() throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
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

    // MARK: - Task 4: the render is asked for at the size it will be drawn at (R-06, R-08)

    @Test func anEmbedWrittenWithAWidthSuffixRendersAndCachesAtItsOwnBucketedWidth() async throws {
        // A fact about `ThumbnailStore` alone, load-bearing for the assertion below: `|300`
        // is expected to land in the 320 bucket, never in 720's own 960.
        #expect(ThumbnailStore.bucket(for: 300) == 320)

        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let thumbnails = ThumbnailStore(root: root, directory: cacheDirectory)

        let text = "testo\n![[foto.png|300]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset = (text as NSString).range(of: "![[foto.png|300]]").location
        guard case .drawn = await EmbedEditorFixtures.waitForRendition(at: offset, in: coordinator) else {
            Issue.record("expected the embed written |300 to resolve to a drawn rendition")
            return
        }

        // R-08: the render was requested at the width the run itself names, bucketed by
        // `ThumbnailStore` - not at `EmbedTable.renderWidth`'s constant 720 (bucket 960).
        // The cache file's own name is `ThumbnailStore`'s proof of the width it was asked
        // to render at, independent of anything `EmbedTable` keeps in memory.
        let expectedKey = ThumbnailStore.cacheKey(relativePath: "foto.png", bucket: 320)
        let expectedFile = cacheDirectory.appending(path: "\(expectedKey).png", directoryHint: .notDirectory)
        #expect(
            FileManager.default.fileExists(atPath: expectedFile.path(percentEncoded: false)),
            "an embed written |300 should render into the 320-bucket cache file, not the 960 one \(cacheDirectory.path(percentEncoded: false)) unsized embeds render at"
        )
    }

    @Test func anUnsizedEmbedStillRendersThroughTheDefaultWidthAndSharesItsEntryWithASecondUnsizedEmbed() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let thumbnails = ThumbnailStore(root: root, directory: cacheDirectory)

        // Two lines, same unsized embed: R-06's "no write, nothing changes" - an embed
        // with no suffix keeps drawing at `EmbedTable.renderWidth` exactly as it did
        // before this feature, and the two still share one render between them.
        let text = "prima\n![[foto.png]]\nmezzo\n![[foto.png]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offsets = Self.offsets(ofSubstring: "![[foto.png]]", in: text)
        #expect(offsets.count == 2)
        guard offsets.count == 2 else { return }

        guard case .drawn(let first) = await EmbedEditorFixtures.waitForRendition(at: offsets[0], in: coordinator),
              case .drawn(let second) = await EmbedEditorFixtures.waitForRendition(at: offsets[1], in: coordinator)
        else {
            Issue.record("expected both unsized embeds to resolve to a drawn rendition")
            return
        }
        // `EmbedRendition.==` compares `.drawn` by object identity - the same image
        // object, not two independent renders of the same file at the same width.
        #expect(first === second)

        let expectedKey = ThumbnailStore.cacheKey(relativePath: "foto.png", bucket: 960)
        let expectedFile = cacheDirectory.appending(path: "\(expectedKey).png", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: expectedFile.path(percentEncoded: false)))
    }

    @Test func twoEmbedsOfOneFileAtDifferentWrittenWidthsThatBucketTogetherProduceOneRender() async throws {
        #expect(ThumbnailStore.bucket(for: 300) == 320)
        #expect(ThumbnailStore.bucket(for: 310) == 320)

        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let thumbnails = ThumbnailStore(root: root, directory: cacheDirectory)

        let text = "prima\n![[foto.png|300]]\nmezzo\n![[foto.png|310]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset300 = (text as NSString).range(of: "![[foto.png|300]]").location
        let offset310 = (text as NSString).range(of: "![[foto.png|310]]").location

        guard case .drawn(let renderedAt300) = await EmbedEditorFixtures.waitForRendition(at: offset300, in: coordinator),
              case .drawn(let renderedAt310) = await EmbedEditorFixtures.waitForRendition(at: offset310, in: coordinator)
        else {
            Issue.record("expected both sized embeds to resolve to a drawn rendition")
            return
        }
        // 300 and 310 both bucket to 320: one render between the two, the same object -
        // not two cache entries for one file that `ThumbnailStore` would answer
        // identically (ADR-0019 §D4).
        #expect(renderedAt300 === renderedAt310)

        let expectedKey = ThumbnailStore.cacheKey(relativePath: "foto.png", bucket: 320)
        let expectedFile = cacheDirectory.appending(path: "\(expectedKey).png", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: expectedFile.path(percentEncoded: false)))
    }
}
