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
    /// sits inside the picture's own frame - `pictureFrame(at:in:coordinator:)` reports
    /// that frame directly (`Coordinator.drawnPictureFrame(at:in:)`), rather than
    /// `fragmentFrame(at:in:)`'s layout-fragment frame, which is taller than the picture by
    /// the prose font's descent since ADR-0030 (`EmbedEditorTestSupport.swift`). The probed
    /// point is the picture's own bottom-right corner, where `EmbedResize.handleRect(in:)`
    /// paints the square.
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

        let box = EmbedEditorFixtures.pictureFrame(
            at: EmbedEditorFixtures.embedOffset, in: textView, coordinator: coordinator
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
        _ = coordinator.resizeEmbed(
            .moved(CGPoint(x: box.maxX + 20, y: box.maxY + 20), constrained: false), in: textView
        )

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
        _ = coordinator.resizeEmbed(
            .moved(CGPoint(x: box.minX + 10, y: box.minY + 10), constrained: false), in: textView
        )

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
            .moved(CGPoint(x: box.minX + column + 500, y: box.minY + 20), constrained: false), in: textView
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
        _ = coordinator.resizeEmbed(.moved(dragPoint, constrained: false), in: textView)
        _ = coordinator.resizeEmbed(.ended(dragPoint), in: textView)

        #expect(textView.subviews.count == subviewsBefore)
    }

    // MARK: - Ctrl-constrained aspect-ratio lock (Task 10, ADR-0019 §D9, R-11)
    //
    // `EmbedResize.Phase.moved` now carries `constrained: Bool` (mechanical signature
    // change), but nothing downstream reads it yet - `NoteTextView+EmbedResize.swift`'s
    // `continueResize(to:in:)` still computes the same free-aspect resize regardless of
    // the flag, and `CompletingTextView+Pasteboard.swift`'s `mouseDragged` still always
    // passes `constrained: false`. Every test below that actually exercises the lock is
    // expected to fail red - not to fail to compile - until the coder half of Task 10
    // wires the natural-ratio override into `continueResize(to:in:)` and reads
    // `event.modifierFlags.contains(.control)` in `mouseDragged`.

    /// R-11's core claim: `.moved(p, constrained: true)`, after `.began` on a picture
    /// whose natural size is not square, leaves `EmbedDrag.size` with a height that is
    /// exactly the proportional height for the resolved width - `(width *
    /// naturalRatio).rounded()` - even though `p` was chosen to imply a very different,
    /// free-resize height (a large `dx`, a tiny `dy`). D9: "overrides the height to
    /// `(width * ratio).rounded()` **after** that clamp".
    @Test func movedWithConstrainedTrueLocksHeightToTheNaturalAspectRatio() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        let drag = try #require(coordinator.embedDrag)
        // The fixture's own PNG is written 40x30 (`EmbedEditorFixtures.writeImage`) -
        // deliberately not square - but the ratio is read off `drag.natural` rather than
        // assumed, since `ThumbnailStore`'s real render is what the gesture actually
        // measures (`EmbedResizeCommitTests`' own fixtures make the same point).
        #expect(drag.natural.width != drag.natural.height)
        let ratio = drag.natural.height / drag.natural.width
        let pictureFrame = drag.picture

        // A wide, barely-taller drag: free resize would leave the height nowhere near
        // proportional to the new width.
        let p = CGPoint(x: began.x + 150, y: began.y + 5)
        let column = EmbedResize.column(of: textView.textContainer)
        let requestedWidth = pictureFrame.width + p.x - began.x
        let requestedHeight = pictureFrame.height + p.y - began.y
        let unconstrained = EmbedResize.resolved(
            written: .both(requestedWidth, requestedHeight), natural: drag.natural, column: column
        )
        let expectedHeight = (unconstrained.width * ratio).rounded()
        // Sanity on the test's own premise: free resize really would answer something
        // else here, or this test could not distinguish "locked" from "not locked".
        #expect(unconstrained.height != expectedHeight)

        _ = coordinator.resizeEmbed(.moved(p, constrained: true), in: textView)

        let resolved = try #require(coordinator.embedDrag?.size)
        // The width clamp is unaffected by R-11 (D9: "composes with", not "instead of").
        #expect(resolved.width == unconstrained.width)
        #expect(resolved.height == expectedHeight)
    }

    /// R-11's regression guard: the very same `p`, on the very same gesture, with
    /// `constrained: false` reproduces today's free-resize result exactly -
    /// `EmbedResize.resolved(written: .both(...), ...)`'s own answer, unaltered. "R-11
    /// adds a branch, it does not change the unconstrained path."
    @Test func movedWithConstrainedFalseReproducesTheFreeResizeResultExactly() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        let drag = try #require(coordinator.embedDrag)
        let pictureFrame = drag.picture

        let p = CGPoint(x: began.x + 150, y: began.y + 5)
        let column = EmbedResize.column(of: textView.textContainer)
        let requestedWidth = pictureFrame.width + p.x - began.x
        let requestedHeight = pictureFrame.height + p.y - began.y
        let unconstrained = EmbedResize.resolved(
            written: .both(requestedWidth, requestedHeight), natural: drag.natural, column: column
        )

        _ = coordinator.resizeEmbed(.moved(p, constrained: false), in: textView)

        #expect(coordinator.embedDrag?.size == unconstrained)
    }

    /// R-11's "not only at the moment the handle is grabbed": a sequence of
    /// `.moved(p1, constrained: true)`, `.moved(p2, constrained: false)`,
    /// `.moved(p3, constrained: true)` ends on the same size a single
    /// `.moved(p3, constrained: true)` from a fresh `.began` at the same point would
    /// produce - nothing about `p1`/`p2` is latched into how `p3` resolves, and the
    /// constrained flag is read fresh on every call rather than cached from `.began`.
    /// The second `.began` below is a clean re-grab, not a continuation:
    /// `beginResize(at:in:)` calls `abandonResize()` first, so whatever the first
    /// sequence left open is discarded without being committed.
    @Test func constrainedStateIsReadFreshOnEveryMovedNotLatchedAtBegan() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let p1 = CGPoint(x: began.x + 40, y: began.y + 10)
        let p2 = CGPoint(x: began.x + 90, y: began.y + 60)
        let p3 = CGPoint(x: began.x + 150, y: began.y + 5)

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.moved(p1, constrained: true), in: textView)
        _ = coordinator.resizeEmbed(.moved(p2, constrained: false), in: textView)
        _ = coordinator.resizeEmbed(.moved(p3, constrained: true), in: textView)
        let sequenceResult = try #require(coordinator.embedDrag?.size)

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.moved(p3, constrained: true), in: textView)
        let singleCallResult = try #require(coordinator.embedDrag?.size)

        #expect(sequenceResult == singleCallResult)
    }

    /// R-05 composes with R-11, it does not stand in for it: a constrained drag past the
    /// right margin still clamps its width to `EmbedResize.column(of:)`'s own answer
    /// (the existing floor/column clamp, unaffected by D9), and the height locked to the
    /// natural ratio is computed from that already-clamped width, not from the
    /// unclamped, past-the-margin request.
    @Test func constrainedDragStillObeysTheColumnClampOnWidth() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let column = EmbedResize.column(of: textView.textContainer)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        let drag = try #require(coordinator.embedDrag)
        let ratio = drag.natural.height / drag.natural.width
        let expectedHeight = (column * ratio).rounded()

        _ = coordinator.resizeEmbed(
            .moved(CGPoint(x: box.minX + column + 500, y: box.minY + 20), constrained: true), in: textView
        )

        let resolved = try #require(coordinator.embedDrag?.size)
        #expect(resolved.width == column)
        #expect(resolved.height == expectedHeight)
    }

    /// D9's "no new suffix form": `.ended` after a `.moved(_, constrained: true)` commits
    /// a size whose `EmbedResize.suffix(for:natural:)` is the bare `|W` form, because the
    /// height the constrained drag ends on is, by construction, exactly the proportional
    /// height for its width - indistinguishable in the note from any other resize that
    /// happened to land on the natural ratio. The drag's own deltas (`dx: 150, dy: 5`)
    /// are deliberately non-proportional, so an unconstrained commit would answer `|WxH`
    /// instead - the failure this test is meant to catch before the lock exists.
    @Test func endedAfterAConstrainedMovedCommitsABareWidthSuffixNotWidthByHeight() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))

        let dragPoint = CGPoint(x: began.x + 150, y: began.y + 5)
        _ = coordinator.resizeEmbed(.moved(dragPoint, constrained: true), in: textView)
        _ = coordinator.resizeEmbed(.ended(dragPoint), in: textView)

        #expect(textView.string.hasPrefix("prima\n![[foto.png|"))
        // No suffix in this fixture's alphabet other than the one this drag would write
        // contains an "x" - `sizedNote`'s own `|300` doesn't either - so this is exactly
        // "the suffix has no `x`-separated height part", not a coincidence of the prose
        // around it.
        #expect(!textView.string.contains("x"))
    }
}
