import AppKit
import Testing
@testable import Pergamenum

/// What a finished drag writes into the note (ADR-0019, plan
/// 2026-08-23-ridimensionamento-maniglie-embed-editor, Task 7). Split out of
/// `EmbedCaretTests` alongside `EmbedResizeGestureTests`, which had grown past SwiftLint's
/// `type_body_length` error threshold; the fixtures are shared through
/// `EmbedEditorFixtures` (`EmbedEditorTestSupport.swift`), not duplicated.
///
/// `.ended`'s production implementation (`NoteTextView+EmbedResize.swift`) currently only
/// removes the overlay and clears the drag state - it writes nothing to `NSTextStorage`.
/// Every test below except the CommonMark one is expected to fail red on an assertion
/// about the note's own text or its selection once the drag completes, never on a compile
/// error: `EmbedResize.rewritten(run:to:natural:)` (Task 2) and the generalisation of
/// `deleteAtomically` to `replaceAtomically(_:with:in:)` this task's coder half adds are
/// both things this file only calls, never declares. The CommonMark test fails red for a
/// different, pre-existing reason: Task 6's `grabbedEmbed(at:in:)` does not yet distinguish
/// the two spellings, so `.began` currently claims a CommonMark embed's handle too.
@MainActor
@Suite struct EmbedResizeCommit {
    /// R-03: several `.moved` steps that keep the drag proportional to the picture's own
    /// aspect ratio (which is exactly the natural image's ratio - `EmbedResize.resolved`'s
    /// own guarantee, Task 2) commit a width-only suffix. Computed from the real `box` this
    /// fixture measures rather than a literal like `"|450"`, so this test does not depend on
    /// exactly what pixel size `QLThumbnailGenerator` happens to hand back for the synthetic
    /// PNG on the machine running it - only `sizedNote`'s written `300` is depended on,
    /// and that is deterministic (`EmbedResize.resolved(written: .width(300), …)`, no image
    /// measurement in the width term at all).
    @Test func resizeEndedRewritesTheRunWithAWidthOnlySuffixWhenTheDragKeepsTheAspectRatio() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.sizedNote
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))

        // Ratio read off the overlay's own starting frame (`grabbed.picture`, what
        // `beginResize(at:in:)` seeds it with) rather than `box`
        // (`fragmentFrame(at:in:)`, the layout fragment): the two differ by a few points
        // in height for this fixture, identical in width, so a ratio computed from `box`
        // lands the proportional height only within a fraction of a point of what the
        // gesture actually measures - a margin `suffix(for:natural:)`'s own `> 1` guard
        // is not meant to be relied on this tightly.
        let pictureFrame = try #require(textView.subviews.last).frame
        let ratio = pictureFrame.height / pictureFrame.width
        let finalWidth = pictureFrame.width + 150
        let finalHeight = (finalWidth * ratio).rounded()
        let dx = finalWidth - pictureFrame.width
        let dy = finalHeight - pictureFrame.height

        for step in 1...3 {
            let t = CGFloat(step) / 3
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t), constrained: false), in: textView
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.sizedNote
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        #expect(coordinator.resizeEmbed(.began(began), in: textView))

        // The gesture's own deltas are measured against `grabbed.picture`
        // (`beginResize(at:in:)` seeds the overlay's frame with it verbatim), not `box`
        // (`fragmentFrame(at:in:)`, the layout fragment) - the two differ by a few points
        // in height for this fixture (the line's own descent below the attachment
        // baseline), identical in width. Reading the overlay's own starting frame back
        // here, rather than computing from `box`, keeps this test's arithmetic exactly
        // proportional to what the production gesture actually measures.
        let pictureFrame = try #require(textView.subviews.last).frame
        let ratio = pictureFrame.height / pictureFrame.width
        let finalWidth = pictureFrame.width + 150
        let proportionalHeight = (finalWidth * ratio).rounded()
        let finalHeight = proportionalHeight + 100
        let dx = finalWidth - pictureFrame.width
        let dy = finalHeight - pictureFrame.height

        for step in 1...4 {
            let t = CGFloat(step) / 4
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t), constrained: false), in: textView
            )
        }
        // `.ended` writes `drag.size`, the last clamp `.moved` resolved - exactly the
        // overlay's own frame right before `.ended` takes it away
        // (`continueResize(to:in:)` sets both together). Read from there instead of
        // trusting a second, independent computation of the same arithmetic, so this
        // assertion tracks the real committed geometry rather than a copy of it that
        // could drift.
        let committed = try #require(textView.subviews.last).frame
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: began.x + dx, y: began.y + dy)), in: textView)

        let expectedWidth = Int(committed.width.rounded())
        let expectedHeight = Int(committed.height.rounded())
        #expect(textView.string == "prima\n![[foto.png|\(expectedWidth)x\(expectedHeight)]]\ndopo\n")
    }

    /// The bullet the plan states literally: an embed already written `|300` dragged to a
    /// (proportional) 400 reads `|400` - the existing suffix replaced, never a second pipe
    /// appended alongside it.
    @Test func resizeEndedOnAnAlreadySizedEmbedReplacesTheExistingSuffixRatherThanAppending() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.sizedNote
        )
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
        _ = coordinator.resizeEmbed(
            .moved(CGPoint(x: began.x + dx, y: began.y + dy), constrained: false), in: textView
        )
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
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.sizedNote
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)
        let before = textView.string
        #expect(before == EmbedEditorFixtures.sizedNote)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)
        let dx: CGFloat = 60
        let dy: CGFloat = 40

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        for step in 1...moves {
            let t = CGFloat(step) / CGFloat(moves)
            _ = coordinator.resizeEmbed(
                .moved(CGPoint(x: began.x + dx * t, y: began.y + dy * t), constrained: false), in: textView
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
    /// answers nil (the formatted suffix equals what `sizedNote` already carries), so
    /// nothing is written; the picture behaves like a click on the run instead, per D6's own
    /// "a click on the handle behaves like a click on the picture rather than like a dead
    /// zone."
    @Test func beganImmediatelyFollowedByEndedAtTheSamePointWritesNothingAndSelectsTheRun() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.sizedNote
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.ended(began), in: textView)

        #expect(textView.string == EmbedEditorFixtures.sizedNote)
        let runLength = ("![[foto.png|300]]" as NSString).length
        #expect(
            textView.selectedRange()
                == NSRange(location: EmbedEditorFixtures.embedOffset, length: runLength)
        )
    }

    /// D6's zero-movement case again, on the embed that carries **no** suffix at all - the
    /// case the guarantee is worth the most on, and the one the sized fixture above cannot
    /// see. `EmbedResize.rewritten(run:to:natural:)` compares the suffix it formats against
    /// the one already written, and "no suffix" never equals a computed one, so a plain
    /// click on the handle of `![[foto.png]]` must not be allowed to reach it: the note
    /// would come back as `![[foto.png|720]]` with nothing having been dragged, which is
    /// D6's "rewrites nothing" read as "rewrites whatever the picture happens to measure".
    @Test func beganImmediatelyFollowedByEndedOnAnUnsizedEmbedWritesNothingAndSelectsTheRun() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(
            root: root, text: EmbedEditorFixtures.note
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)

        #expect(coordinator.resizeEmbed(.began(began), in: textView))
        _ = coordinator.resizeEmbed(.ended(began), in: textView)

        #expect(textView.string == EmbedEditorFixtures.note)
        #expect(
            textView.selectedRange() == NSRange(
                location: EmbedEditorFixtures.embedOffset, length: EmbedEditorFixtures.runLength
            )
        )
    }

    /// D7: Obsidian's verified sizing syntax exists only for the wikilink spelling, so a
    /// CommonMark `![alt](foto.png)` embed - which still draws a picture, per ADR-0018 §D3 -
    /// gets no handle at all, and `.began` must decline it rather than start a gesture that
    /// `EmbedResize.rewritten(run:to:natural:)` would refuse to commit anyway.
    @Test func resizeEmbedBeganReturnsFalseForACommonMarkEmbed() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "prima\n![alt](foto.png)\ndopo\n"
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root, text: text)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        #expect(box.width > 0)

        let hitRect = EmbedResize.handleHitRect(in: box)
        let began = CGPoint(x: hitRect.midX, y: hitRect.midY)

        #expect(!coordinator.resizeEmbed(.began(began), in: textView))
    }
}
