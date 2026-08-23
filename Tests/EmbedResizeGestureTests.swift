import AppKit
import Testing
@testable import Pergamenum

/// The resize handle's hit-test and the drag itself (ADR-0019, plan
/// 2026-08-23-ridimensionamento-maniglie-embed-editor, Tasks 5 and 6). Split out of
/// `EmbedCaretTests`, which had grown past SwiftLint's `type_body_length` error threshold;
/// the fixtures both files drive are shared through `EmbedEditorFixtures`
/// (`EmbedEditorTestSupport.swift`), not duplicated. What is under test here is the same
/// thing as there: the wiring from a real rendition down to the gesture, driven through a
/// real `NSTextView` offscreen and a real `ThumbnailStore` render.
@MainActor
@Suite struct EmbedResizeGesture {
    // MARK: - Resize handle hit-test (Task 5)

    /// R-01: with `hidesMarkup` on and a landed render, the handle's hit rect exists and
    /// sits inside the picture's own frame - `fragmentFrame(at:in:)` reports the whole
    /// paragraph's frame, which for a standalone embed paragraph is the picture's frame,
    /// the same equivalence `aClickOnTheDrawnPictureSelectsItsWholeRun` in `EmbedCaret`
    /// already leans on. The probed point is the picture's own bottom-right corner, where
    /// `EmbedResize.handleRect(in:)` paints the square.
    @Test func handleRectAnswersARectInsideThePictureFrameWhenMarkupIsHidden() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = EmbedEditorFixtures.fragmentFrame(
            at: EmbedEditorFixtures.embedOffset, in: textView
        )
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: false, root: root, thumbnails: thumbnails
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // No file written at all: `assente.png` resolves synchronously to `.missing`,
        // the same fixture `EmbedResolutionTests.aMissingFileResolvesToMissingWithoutTouchingTheRenderer`
        // already relies on.
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let text = "prima\n![[assente.png]]\ndopo\n"
        let fixture = EmbedEditorFixtures.editor(
            text: text, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        let offset = (text as NSString).range(of: "![[assente.png]]").location
        #expect(coordinator.embeds.renditions[offset] == .missing(name: "assente.png"))
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = EmbedEditorFixtures.fragmentFrame(at: offset, in: textView)
        #expect(box.width > 0)
        #expect(coordinator.handleRect(forEmbedAt: CGPoint(x: box.midX, y: box.midY), in: textView) == nil)
    }

    /// Nothing landed yet, synchronously: the same first-pass state
    /// `EmbedResolutionTests.anImageEmbedResolvesToADrawnRenditionWithARealRender` asserts
    /// before awaiting the render. No entry in `embeds.renditions` means
    /// `drawnEmbedRange(atParagraphStart:in:)` itself answers nil, so there is nothing for
    /// the handle to sit on regardless of where `point` falls.
    @Test func handleRectAnswersNilBeforeARenditionLands() throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        #expect(coordinator.embeds.renditions[EmbedEditorFixtures.embedOffset] == nil)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        #expect(coordinator.handleRect(forEmbedAt: CGPoint(x: 50, y: 20), in: textView) == nil)
    }

    // MARK: - Drag (Task 6)
    //
    // `resizeEmbed(_:in:)` is declared but not yet implemented
    // (`NoteTextView+EmbedResize.swift`, stub returning `false`) - every test below is
    // expected to fail red, not to fail to compile, until the coder fills it in. Driven the
    // way `selectEmbed(at:in:)` already is in `EmbedCaret`: directly, no `NSEvent` synthesis.

    /// R-02/ADR-0019 §D6's coexistence rule: `.began` claims a point only inside
    /// `EmbedResize.handleHitRect(in:)`, the 22-point square around the handle - not
    /// `handleRect(in:)`, the smaller 14-point square it paints - and declines everywhere
    /// else on the picture, which is what leaves `onClickInMargin`/`selectEmbed(at:in:)`
    /// free to claim an ordinary click on the rest of it.
    @Test func resizeEmbedBeganClaimsOnlyTheHandleHitRectNotElsewhereOnThePicture() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
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
}
