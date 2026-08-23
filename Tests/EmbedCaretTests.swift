import AppKit
import Testing
@testable import Pergamenum

/// The caret, Backspace/Delete and a click, taught a drawn embed's run (ADR-0018 slice
/// 3, Step 4). Driven through a real `NSTextView` offscreen and a real `ThumbnailStore`
/// render, the same way `EmbedDrawingCoordinator`/`EmbedResolutionTests` already are:
/// what is under test here is the wiring from a real rendition down to
/// `selectedRange`/the storage, not `EmbedNavigation`'s own arithmetic, already covered
/// offscreen in `EmbedNavigationTests`.
@MainActor
@Suite struct EmbedCaret {
    private static func makeTempVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-embed-caret-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A tiny real PNG, the same way `EmbedResolutionTests.writeImage` builds one: the
    /// render has to be real for `EmbedTable` to resolve to `.drawn` rather than stall.
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

    /// `editor(...)`'s three parts, named rather than a bare tuple: `window` is never
    /// read for its own sake, only kept alive so `textView.undoManager` resolves to
    /// something for the length of a test.
    private struct Fixture {
        let textView: CompletingTextView
        let coordinator: NoteTextView.Coordinator
        let window: NSWindow
    }

    /// A real `CompletingTextView` with `claimsCommand` wired the same way
    /// `NoteTextView.wire(_:to:)` wires it, and a real, offscreen `NSWindow` so
    /// `undoManager` resolves to something - the same shape `InlineFormatTests` already
    /// uses for a text view built outside `makeNSView`. Never ordered front: the window
    /// exists only to complete the responder chain, not to be seen.
    private static func editor(
        text: String, hidesMarkup: Bool, root: URL?, thumbnails: ThumbnailStore?
    ) -> Fixture {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }, vaultRoot: root, notePath: "Nota.md",
            thumbnails: thumbnails
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        textView.claimsCommand = { [weak textView] selector in
            guard let textView else { return false }
            return coordinator.claimsEmbedCommand(selector, in: textView)
        }
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        return Fixture(textView: textView, coordinator: coordinator, window: window)
    }

    /// Polls `embeds.renditions` until the render lands, the same shape
    /// `EmbedResolutionTests.waitForRendition` already uses for the same real,
    /// asynchronous `ThumbnailStore` call.
    private static func waitForRendition(
        at offset: Int, in coordinator: NoteTextView.Coordinator
    ) async -> EmbedRendition? {
        for _ in 0..<100 {
            if let rendition = coordinator.embeds.renditions[offset] { return rendition }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return coordinator.embeds.renditions[offset]
    }

    /// The fragment whose paragraph starts at `offset`, in the view's own coordinates -
    /// what a click carries. The same two-step conversion `FoldBadgeClickTests.badge`
    /// already does for a different decoration.
    private static func fragmentFrame(at offset: Int, in textView: NSTextView) -> CGRect {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return .null }
        var found: CGRect = .null
        let start = manager.documentRange.location
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let fragmentStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            guard fragmentStart == offset else { return true }
            found = fragment.layoutFragmentFrame
            return false
        }
        guard !found.isNull else { return .null }
        let origin = textView.textContainerOrigin
        return found.offsetBy(dx: origin.x, dy: origin.y)
    }

    private static let note = "prima\n![[foto.png]]\ndopo\n"
    /// "prima\n" is six characters; the embed's own paragraph starts right after it.
    private static let embedOffset = 6
    /// "![[foto.png]]", the run's own length.
    private static let runLength = 13

    // MARK: - Deleting

    @Test func backspaceAtTheRightEdgeOfADrawnEmbedRemovesItWholeInOneUndoStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\ndopo\n")
        textView.undoManager?.undo()
        #expect(textView.string == Self.note)
    }

    @Test func deleteAtTheLeftEdgeOfADrawnEmbedRemovesItWhole() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        #expect(textView.string == "prima\ndopo\n")
    }

    /// The most important test in this file (R4): with `hidesMarkup` off the run is raw
    /// text, and Backspace at the same position must remove exactly one character - not
    /// the twenty-seven of ADR-0018's own motivating defect. A regression here reads as
    /// file corruption, not as a missing feature.
    @Test func withHidingMarkupOffBackspaceRemovesOnlyOneCharacter() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\n![[foto.png]\ndopo\n")
    }

    // MARK: - Moving

    @Test func movingRightFromTheRunsLeftEdgeSkipsItInOneStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset + Self.runLength, length: 0))
    }

    @Test func movingLeftIntoTheRunFromTheRightEdgeSkipsItInOneStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset, length: 0))
    }

    /// R4 for movement, symmetric to the Backspace test above: with `hidesMarkup` off
    /// the same arrow key must move one character, not skip the run.
    @Test func withHidingMarkupOffMovingRightIsOrdinary() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset + 1, length: 0))
    }

    // MARK: - Clicking

    @Test func aClickOnTheDrawnPictureSelectsItsWholeRun() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: Self.embedOffset, in: textView)
        #expect(box.width > 0)
        #expect(coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset, length: Self.runLength))
    }

    @Test func aClickOnOrdinaryProseDoesNotClaimAnything() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: 0, in: textView) // "prima\n"
        #expect(box.width > 0)
        #expect(!coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
    }

    /// R4 for the click, completing the guard already checked for Backspace and
    /// movement above: with `hidesMarkup` off the run is raw, unselected text, and a
    /// click there must behave exactly as ordinary text selection would - `selectEmbed`
    /// itself is what refuses (`guard decorations.hidesMarkup`), this only proves it.
    @Test func aClickOnAnUnrenderedRunDoesNotClaimAnything() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: Self.embedOffset, in: textView)
        #expect(box.width > 0)
        #expect(!coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
    }

    // MARK: - Resize handle hit-test (ADR-0019, plan 2026-08-23-ridimensionamento-maniglie-embed-editor, Task 5)

    /// R-01: with `hidesMarkup` on and a landed render, the handle's hit rect exists and
    /// sits inside the picture's own frame - `fragmentFrame(at:in:)` reports the whole
    /// paragraph's frame, which for a standalone embed paragraph is the picture's frame,
    /// the same equivalence `aClickOnTheDrawnPictureSelectsItsWholeRun` above already
    /// leans on. The probed point is the picture's own bottom-right corner, where
    /// `EmbedResize.handleRect(in:)` paints the square.
    @Test func handleRectAnswersARectInsideThePictureFrameWhenMarkupIsHidden() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: Self.embedOffset, in: textView)
        #expect(box.width > 0)
        let corner = CGPoint(x: box.maxX - 5, y: box.maxY - 5)
        let handle = try #require(coordinator.handleRect(forEmbedAt: corner, in: textView))
        // Grown by half a point either side: the two frames come from independent
        // arithmetic (the fragment walk vs. `frameForTextAttachment(at:)`), and this
        // assertion is about containment, not about matching floating-point rounding.
        #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(handle))
    }

    /// R-07: with `hidesMarkup` off nothing is drawn at all - the run stays raw text - so
    /// there is no handle anywhere, at any point.
    @Test func handleRectAnswersNilWhenMarkupIsNotHidden() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        #expect(coordinator.handleRect(forEmbedAt: CGPoint(x: 50, y: 20), in: textView) == nil)
    }

    /// A `.missing` embed draws a placeholder, not a real picture - "there is nothing
    /// downstream that would notice" is D1's own phrase for the size, and D8 gives the
    /// same answer to the handle: `guard case .drawn` refuses before any geometry is
    /// computed.
    @Test func handleRectAnswersNilForAMissingEmbed() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // No file written at all: `assente.png` resolves synchronously to `.missing`,
        // the same fixture `EmbedResolutionTests.aMissingFileResolvesToMissingWithoutTouchingTheRenderer`
        // already relies on.
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let text = "prima\n![[assente.png]]\ndopo\n"
        let fixture = Self.editor(text: text, hidesMarkup: true, root: root, thumbnails: thumbnails)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        let offset = (text as NSString).range(of: "![[assente.png]]").location
        #expect(coordinator.embeds.renditions[offset] == .missing(name: "assente.png"))
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: offset, in: textView)
        #expect(box.width > 0)
        #expect(coordinator.handleRect(forEmbedAt: CGPoint(x: box.midX, y: box.midY), in: textView) == nil)
    }

    /// Nothing landed yet, synchronously: the same first-pass state
    /// `EmbedResolutionTests.anImageEmbedResolvesToADrawnRenditionWithARealRender` asserts
    /// before awaiting the render. No entry in `embeds.renditions` means
    /// `drawnEmbedRange(atParagraphStart:in:)` itself answers nil, so there is nothing for
    /// the handle to sit on regardless of where `point` falls.
    @Test func handleRectAnswersNilBeforeARenditionLands() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        #expect(coordinator.embeds.renditions[Self.embedOffset] == nil)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        #expect(coordinator.handleRect(forEmbedAt: CGPoint(x: 50, y: 20), in: textView) == nil)
    }

    // MARK: - Accessibility (ADR-0018 slice 3, Step 6 fix)

    /// The regression this whole fix exists for: a drawn embed used to have no stop at
    /// all in the accessibility tree, because `EditorDecorationDelegate` built its own
    /// `NSAccessibilityElement` with `parent: nil` and AppKit never adopted it. Lives
    /// here rather than in `EmbedDrawingTests`, which is entirely offscreen by
    /// construction - a bare `NSTextContentStorage`, no `NSTextView`, no window, nothing
    /// to grow a real accessibility tree from - and this is the one fixture in the suite
    /// that already builds a real `CompletingTextView` inside a real `NSWindow`
    /// (`editor(text:hidesMarkup:root:thumbnails:)` above) with a landed render.
    @Test func aDrawnEmbedIsAReachableAccessibilityElement() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let children = try #require(textView.accessibilityChildren())
        let embeds = children.compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityIdentifier() == "editor-embed" }
        let embed = try #require(embeds.first)
        #expect(embeds.count == 1)
        #expect(embed.accessibilityLabel() == "foto.png")
        #expect(embed.accessibilityFrame() != .zero)
    }

    /// R4's own accessibility half: with `hidesMarkup` off the raw `![[foto.png]]` stays
    /// plain text, so there is nothing for `CompletingTextView.accessibilityChildren()`
    /// to build an element for - `drawnEmbedRange`'s own `hidesMarkup` guard is what
    /// refuses, the same guard every other embed feature in this file already leans on.
    @Test func rawSyntaxWithHidingMarkupOffHasNoAccessibilityElement() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let children = textView.accessibilityChildren() ?? []
        let embeds = children.compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityIdentifier() == "editor-embed" }
        #expect(embeds.isEmpty)
    }
}
