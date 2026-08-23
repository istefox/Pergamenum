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

    /// The shared setup every resize-drag test below needs: a landed render, real layout,
    /// and the drawn picture's own frame - the same three steps every test above already
    /// repeats by hand (`waitForRendition` then `ensureLayout` then `fragmentFrame`),
    /// factored once here because Task 6 adds enough new tests that copying it a further
    /// six times would grow this already-over-`type_body_length` file for no reason a
    /// reader would thank later.
    ///
    /// `text` defaults to `Self.note` (the unsized embed every Task 5/6 test still wants);
    /// Task 7's commit tests pass `Self.sizedNote` or a CommonMark spelling instead, always
    /// keeping the "prima\n" prefix so `Self.embedOffset` stays valid for both.
    private static func landedEmbed(
        root: URL, text: String = Self.note
    ) async throws -> (fixture: Fixture, box: CGRect) {
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(text: text, hidesMarkup: true, root: root, thumbnails: thumbnails)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return (fixture, Self.fragmentFrame(at: Self.embedOffset, in: textView))
    }

    private static let note = "prima\n![[foto.png]]\ndopo\n"
    /// "prima\n" is six characters; the embed's own paragraph starts right after it.
    private static let embedOffset = 6
    /// "![[foto.png]]", the run's own length.
    private static let runLength = 13
    /// An embed already carrying a written width - Task 7's commit tests start most of
    /// their gestures from here, so a drag's resolved width is `EmbedResize.resolved(
    /// written: .width(300), …)`'s exact, deterministic answer (`clamped(300, column)`,
    /// no dependence on whatever pixel size the real `QLThumbnailGenerator` render
    /// happens to come back as) rather than the unsized case's natural-image size, which
    /// is real and asynchronous and not this file's to predict.
    private static let sizedNote = "prima\n![[foto.png|300]]\ndopo\n"

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

    // MARK: - Drag (ADR-0019, plan 2026-08-23-ridimensionamento-maniglie-embed-editor, Task 6)
    //
    // `resizeEmbed(_:in:)` is declared but not yet implemented
    // (`NoteTextView+EmbedResize.swift`, stub returning `false`) - every test below is
    // expected to fail red, not to fail to compile, until the coder fills it in. Driven the
    // way `selectEmbed(at:in:)` already is above: directly, no `NSEvent` synthesis.

    /// R-02/ADR-0019 §D6's coexistence rule: `.began` claims a point only inside
    /// `EmbedResize.handleHitRect(in:)`, the 22-point square around the handle - not
    /// `handleRect(in:)`, the smaller 14-point square it paints - and declines everywhere
    /// else on the picture, which is what leaves `onClickInMargin`/`selectEmbed(at:in:)`
    /// free to claim an ordinary click on the rest of it.
    @Test func resizeEmbedBeganClaimsOnlyTheHandleHitRectNotElsewhereOnThePicture() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let onTheHandle = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let elsewhereOnThePicture = CGPoint(x: box.minX + 4, y: box.minY + 4)
        #expect(!hitRect.contains(elsewhereOnThePicture))

        #expect(coordinator.resizeEmbed(.began(onTheHandle), in: textView))
        #expect(!coordinator.resizeEmbed(.began(elsewhereOnThePicture), in: textView))
    }

    /// R-02: nothing about the source text changes between `.began` and `.moved` - only an
    /// overlay appears, so `textView.string` stays byte-identical and the text view gains
    /// exactly one subview (ADR-0019 §D7's overlay, whatever its own declared type turns
    /// out to be - this reads only `NSView.subviews.count`, never a cast).
    @Test func draggingFromBeganThroughMovedLeavesTheSourceTextUnchangedAndAddsOneSubview() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let before = textView.string
        let subviewsBefore = textView.subviews.count

        let hitRect = EmbedResize.handleHitRect(in: box)
        #expect(coordinator.resizeEmbed(.began(CGPoint(x: hitRect.midX, y: hitRect.midY)), in: textView))
        _ = coordinator.resizeEmbed(.moved(CGPoint(x: box.maxX + 20, y: box.maxY + 20)), in: textView)

        #expect(textView.string == before)
        #expect(textView.subviews.count == subviewsBefore + 1)
    }

    /// R-05, the clamp's low boundary, live during the drag rather than only at commit
    /// (ADR-0019 §D3's three call sites): a point implying a width far below the floor
    /// still leaves the overlay at `EmbedResize.minimumSide`, never narrower.
    @Test func movedToAPointImplyingAWidthBelowTheFloorClampsTheOverlayToTheMinimumSide() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        #expect(coordinator.resizeEmbed(.began(CGPoint(x: hitRect.midX, y: hitRect.midY)), in: textView))
        _ = coordinator.resizeEmbed(.moved(CGPoint(x: box.minX + 10, y: box.minY + 10)), in: textView)

        let overlay = try #require(textView.subviews.last)
        #expect(overlay.frame.width == EmbedResize.minimumSide)
    }

    /// R-05, the clamp's other boundary: a point past the editor's own column leaves the
    /// overlay exactly at `EmbedResize.column(of:)`'s own answer for this fixture's
    /// container, never wider, whatever the pointer's own x-coordinate is.
    @Test func movedToAPointPastTheRightMarginClampsTheOverlayToTheColumnWidth() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let column = EmbedResize.column(of: textView.textContainer)

        let hitRect = EmbedResize.handleHitRect(in: box)
        #expect(coordinator.resizeEmbed(.began(CGPoint(x: hitRect.midX, y: hitRect.midY)), in: textView))
        _ = coordinator.resizeEmbed(
            .moved(CGPoint(x: box.minX + column + 500, y: box.minY + 20)), in: textView
        )

        let overlay = try #require(textView.subviews.last)
        #expect(overlay.frame.width == column)
    }

    /// `.ended` removes the overlay - the other half of ADR-0019 §D7's "one edit is made
    /// and the overlay goes", whichever way the edit resolves.
    @Test func endedRemovesTheOverlaySubview() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let subviewsBefore = textView.subviews.count

        let hitRect = EmbedResize.handleHitRect(in: box)
        #expect(coordinator.resizeEmbed(.began(CGPoint(x: hitRect.midX, y: hitRect.midY)), in: textView))
        let dragPoint = CGPoint(x: box.maxX + 20, y: box.maxY + 20)
        _ = coordinator.resizeEmbed(.moved(dragPoint), in: textView)
        _ = coordinator.resizeEmbed(.ended(dragPoint), in: textView)

        #expect(textView.subviews.count == subviewsBefore)
    }

    // MARK: - Commit (ADR-0019, plan 2026-08-23-ridimensionamento-maniglie-embed-editor, Task 7)
    //
    // `.ended`'s production implementation (`NoteTextView+EmbedResize.swift`) currently only
    // removes the overlay and clears the drag state - it writes nothing to `NSTextStorage`.
    // Every test below except the CommonMark one is expected to fail red on an assertion
    // about the note's own text or its selection once the drag completes, never on a compile
    // error: `EmbedResize.rewritten(run:to:natural:)` (Task 2) and the generalisation of
    // `deleteAtomically` to `replaceAtomically(_:with:in:)` this task's coder half adds are
    // both things this file only calls, never declares. The CommonMark test fails red for a
    // different, pre-existing reason: Task 6's `grabbedEmbed(at:in:)` does not yet distinguish
    // the two spellings, so `.began` currently claims a CommonMark embed's handle too.

    /// R-03: several `.moved` steps that keep the drag proportional to the picture's own
    /// aspect ratio (which is exactly the natural image's ratio - `EmbedResize.resolved`'s
    /// own guarantee, Task 2) commit a width-only suffix. Computed from the real `box` this
    /// fixture measures rather than a literal like `"|450"`, so this test does not depend on
    /// exactly what pixel size `QLThumbnailGenerator` happens to hand back for the synthetic
    /// PNG on the machine running it - only `Self.sizedNote`'s written `300` is depended on,
    /// and that is deterministic (`EmbedResize.resolved(written: .width(300), …)`, no image
    /// measurement in the width term at all).
    @Test func resizeEndedRewritesTheRunWithAWidthOnlySuffixWhenTheDragKeepsTheAspectRatio() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root, text: Self.sizedNote)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let ratio = box.height / box.width
        let finalWidth = box.width + 150
        let finalHeight = (finalWidth * ratio).rounded()
        let dx = finalWidth - box.width
        let dy = finalHeight - box.height

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        for step in 1...3 {
            let t = CGFloat(step) / 3
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t)), in: textView
            )
        }
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)

        let expectedWidth = Int(finalWidth.rounded())
        #expect(textView.string == "prima\n![[foto.png|\(expectedWidth)]]\ndopo\n")
    }

    /// R-03's other half: a drag whose final height is deliberately pushed 100 points past
    /// the proportional height for the same width commits `|WxH`, not `|W` - the "otherwise"
    /// half of `EmbedResize.suffix(for:natural:)`'s own rule, again driven through the real
    /// gesture rather than asserted on the pure function alone.
    @Test func resizeEndedRewritesTheRunWithAWidthAndHeightSuffixWhenTheDragChangesTheAspectRatio() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root, text: Self.sizedNote)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let ratio = box.height / box.width
        let finalWidth = box.width + 150
        let proportionalHeight = (finalWidth * ratio).rounded()
        let finalHeight = proportionalHeight + 100
        let dx = finalWidth - box.width
        let dy = finalHeight - box.height

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        for step in 1...4 {
            let t = CGFloat(step) / 4
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t)), in: textView
            )
        }
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)

        let expectedWidth = Int(finalWidth.rounded())
        let expectedHeight = Int(finalHeight.rounded())
        #expect(textView.string == "prima\n![[foto.png|\(expectedWidth)x\(expectedHeight)]]\ndopo\n")
    }

    /// The bullet the plan states literally: an embed already written `|300` dragged to a
    /// (proportional) 400 reads `|400` - the existing suffix replaced, never a second pipe
    /// appended alongside it.
    @Test func resizeEndedOnAnAlreadySizedEmbedReplacesTheExistingSuffixRatherThanAppending() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root, text: Self.sizedNote)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let ratio = box.height / box.width
        let finalWidth = box.width + 100 // this fixture's box.width is 300, so this is "300 to 400".
        let finalHeight = (finalWidth * ratio).rounded()
        let dx = finalWidth - box.width
        let dy = finalHeight - box.height

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.moved(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)

        let expectedWidth = Int(finalWidth.rounded())
        #expect(textView.string == "prima\n![[foto.png|\(expectedWidth)]]\ndopo\n")
        #expect(!textView.string.contains("300|\(expectedWidth)"))
    }

    /// R-04: one `undo()` after `.ended` restores the note exactly to what it was before
    /// `.began`, and a second `undo()` does not reach further into the document - whatever
    /// the number of `.moved` steps the gesture took in between. Parameterised over 1 and 40
    /// so the assertion is about the *count* of edits `.ended` made (one, regardless of drag
    /// length), never about one particular path through the gesture.
    @Test(arguments: [1, 40])
    func oneUndoAfterResizeEndedRestoresTheNoteExactlyRegardlessOfMoveCount(moves: Int) async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root, text: Self.sizedNote)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let before = textView.string
        #expect(before == Self.sizedNote)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let dx: CGFloat = 60
        let dy: CGFloat = 40

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        for step in 1...moves {
            let t = CGFloat(step) / CGFloat(moves)
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t)), in: textView
            )
        }
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)

        #expect(textView.string != before) // R-04's premise: there is something to undo.

        textView.undoManager?.undo()
        #expect(textView.string == before)

        textView.undoManager?.undo()
        #expect(textView.string == before) // a second undo does not reach past this gesture.
    }

    /// D6's zero-movement case: `.began` immediately followed by `.ended` at the same point
    /// - no `.moved` in between at all - resolves to the picture's own current size, which
    /// for an embed already written `|300` is the size already on screen. `rewritten` then
    /// answers nil (the formatted suffix equals what `Self.sizedNote` already carries), so
    /// nothing is written; the picture behaves like a click on the run instead, per D6's own
    /// "a click on the handle behaves like a click on the picture rather than like a dead
    /// zone."
    @Test func beganImmediatelyFollowedByEndedAtTheSamePointWritesNothingAndSelectsTheRun() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await Self.landedEmbed(root: root, text: Self.sizedNote)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.ended(began), in: textView)

        #expect(textView.string == Self.sizedNote)
        let runLength = ("![[foto.png|300]]" as NSString).length
        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset, length: runLength))
    }

    /// D7: Obsidian's verified sizing syntax exists only for the wikilink spelling, so a
    /// CommonMark `![alt](foto.png)` embed - which still draws a picture, per ADR-0018 §D3 -
    /// gets no handle at all, and `.began` must decline it rather than start a gesture that
    /// `EmbedResize.rewritten(run:to:natural:)` would refuse to commit anyway.
    @Test func resizeEmbedBeganReturnsFalseForACommonMarkEmbed() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "prima\n![alt](foto.png)\ndopo\n"
        let (fixture, box) = try await Self.landedEmbed(root: root, text: text)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)

        #expect(!coordinator.resizeEmbed(.began(began), in: textView))
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
