import AppKit
import Testing
@testable import Pergamenum

// ADR-0082 §D7, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-17).
//
// Growing the view to fit lays out up to the caret's fragment and the viewport, not the whole
// document. The scope test is the one that was red on the old code (`growToFitTheText` ensured
// layout for `documentRange`; its control proves the witness sees that); the others are the
// three-part acceptance ADR-0082 §D7 names, kept green by the change: the caret stays visible
// when typing at the end and in the middle of a long note, and the end of the note is reachable
// when it is approached. Never `layoutSubtreeIfNeeded`
// (the header of `NoteTextView+Coordinator.growToFitTheText`'s history warns against it): the
// end is brought into view the app's way, `moveToEndOfDocument(nil)` and `layoutViewport()`.

/// About 2,000 lines: a heading, a blank line and three prose lines, four hundred times, ending
/// in a line that names itself so a test can find the last fragment.
private let longNote: String = {
    var lines: [String] = []
    for section in 1...400 {
        lines.append("# Sezione \(section)")
        lines.append("")
        lines.append("Prima riga della sezione \(section), con **grassetto** e un [[Nota \(section)]].")
        lines.append("Seconda riga della sezione \(section), con #project-av\(section % 20) e >2026-10-04.")
        lines.append("Terza riga della sezione \(section), senza nulla di particolare.")
    }
    lines.append("Ultima riga della nota lunga.")
    return lines.joined(separator: "\n")
}()

/// The end of the first paragraph line after `marker`: a place where one `x` changes no construct.
private func endOfLine(after marker: String, in text: String) -> Int {
    let nsText = text as NSString
    let found = nsText.range(of: marker)
    return nsText.lineRange(for: found).upperBound - 1
}

/// Which paragraphs TextKit has been asked to build a layout fragment for, recorded by standing
/// between the layout manager and the editor's own delegate and forwarding every request to it. A
/// fragment is requested when a paragraph is laid out, so this is a witness that reads nothing: the
/// obvious probes (`NSTextLayoutFragment.state` through an enumeration, `textLayoutFragment(for:)`)
/// lay out what they read, measured 2026-10-06, and a bare enumeration from a mid-document location
/// reported `.layoutAvailable` on a note nothing had laid out.
///
/// Nonisolated and `@unchecked Sendable`, as `EditorDecorationDelegate` itself is: TextKit calls it
/// on the main thread, where the tests read it.
private final class FragmentRequestLog: NSObject, NSTextLayoutManagerDelegate, @unchecked Sendable {
    private let inner: EditorDecorationDelegate
    /// The character offset of the start of every paragraph a fragment was requested for since
    /// the last `reset()`.
    nonisolated(unsafe) private(set) var offsets: Set<Int> = []

    init(forwardingTo inner: EditorDecorationDelegate) { self.inner = inner }

    func reset() { offsets = [] }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        if let content = textLayoutManager.textContentManager {
            offsets.insert(content.offset(from: content.documentRange.location, to: location))
        }
        return inner.textLayoutManager(textLayoutManager, textLayoutFragmentFor: location, in: textElement)
    }
}

/// The start of the line holding `marker` in `text`.
private func lineStart(of marker: String, in text: String) -> Int {
    let nsText = text as NSString
    return nsText.lineRange(for: nsText.range(of: marker)).location
}

@MainActor
@Suite(.serialized) struct EditorGrowToFitScope {
    /// A fixture in the state the app is in when `textDidChange` reaches its last step: the note
    /// open, the frame settled, and one character typed at the top with the passes that follow a
    /// keystroke (`applyStyling` and the rest) not yet run, so what a test measures next is
    /// `growToFitTheText` and nothing else. `applyStyling` rewrites every attribute and lays out
    /// about 1,250 of this note's 2,000 paragraphs on its own (measured 2026-10-06), which would
    /// drown the call this suite is about.
    private func afterTheKeystrokeBeforeGrowing() throws -> (ScrolledEditorFixture, NSTextLayoutManager, FragmentRequestLog) {
        let fixture = ScrolledEditorFixture(text: longNote)
        let layout = try #require(fixture.textView.textLayoutManager)
        let log = FragmentRequestLog(forwardingTo: fixture.coordinator.decorations)
        layout.delegate = log
        fixture.openLikeTheApp()
        fixture.textView.delegate = nil
        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))
        log.reset()
        return (fixture, layout, log)
    }

    /// The paragraphs a whole-document layout reaches and a scoped one must not: from the middle of
    /// the note up to, and not including, its very last paragraph. AppKit lays out the last
    /// fragment itself whenever it resizes the frame (see the test below), so that one says nothing.
    private func requestsBetweenTheMiddleAndTheLastParagraph(_ log: FragmentRequestLog, in text: String) -> [Int] {
        let middle = lineStart(of: "Seconda riga della sezione 200,", in: text)
        let last = lineStart(of: "Ultima riga della nota lunga.", in: text)
        return log.offsets.filter { $0 >= middle && $0 < last }.sorted()
    }

    // MARK: The probe itself

    // (n2-page R-17) Control: the witness is sensitive. From the same state, a whole-document
    // `ensureLayout` (what `growToFitTheText` did before ADR-0082 §D7) requests fragments for the
    // paragraphs between the middle and the end (400 measured), so the test below goes red on the
    // old behaviour and not by accident of the probe.
    @Test func theWitnessSeesAWholeDocumentLayout() throws {
        let (fixture, layout, log) = try afterTheKeystrokeBeforeGrowing()
        defer { fixture.window.orderOut(nil) }

        layout.ensureLayout(for: layout.documentRange)

        let reached = requestsBetweenTheMiddleAndTheLastParagraph(log, in: fixture.textView.string)
        #expect(reached.count > 300, "a whole-document layout reached only \(reached.count) paragraphs past the middle")
    }

    // MARK: The scope

    // (n2-page R-17) Red on the old code: growing to fit, right after a keystroke at the top of a
    // 2,000-line note, lays out no paragraph from the middle to the one before the last, since it
    // asks for the caret's fragment and the viewport only.
    //
    // Restated 2026-10-06, the reason first. The first version typed a whole keystroke into a
    // fixture whose frame was still the 700 pt it was built with and asked whether the note's very
    // last fragment was laid out. Three things were wrong. (1) The app's frame is already as tall
    // as the note when a person types, because the open pass sized it, so the fixture is first
    // brought there (`openLikeTheApp`). (2) Whenever the frame is resized, the open pass or a later
    // grow-to-fit whose estimate moved by a few points once the viewport had laid out (59,260 pt
    // against 58,920 here), AppKit lays out the note's last fragment to do it: that one fragment
    // is laid out in the app too and says nothing about this method's scope (the 1 MB hand check,
    // G-grow, prices it). (3) A whole keystroke runs `applyStyling` before this method, and
    // that pass alone lays out about 1,250 of the 2,000 paragraphs, so a keystroke-level probe
    // cannot say what `growToFitTheText` did. The test now measures that one call, from the state
    // the keystroke leaves, over every paragraph between the middle and the last. R-17's words are
    // "growing the view to fit lays out up to the caret's fragment plus the viewport, not the whole
    // document", and that is what is asserted.
    @Test func growingToFitAfterAKeystrokeAtTheTopDoesNotLayOutTheRestOfTheNote() throws {
        let (fixture, _, log) = try afterTheKeystrokeBeforeGrowing()
        defer { fixture.window.orderOut(nil) }

        fixture.coordinator.growToFitTheText(fixture.textView, revealingCaret: true)

        let reached = requestsBetweenTheMiddleAndTheLastParagraph(log, in: fixture.textView.string)
        #expect(reached.isEmpty, "growing to fit laid out \(reached.count) paragraphs of the rest of the note, from \(reached.first ?? -1)")
    }

    // MARK: The caret stays visible

    private func expectTheCaretIsVisible(_ fixture: ScrolledEditorFixture, _ place: String) {
        let caret = fixture.textView.caretRectOnScreen()
        #expect(caret.height > 0, "\(place): no caret rectangle")
        let inView = fixture.textView.convert(fixture.window.convertFromScreen(caret), from: nil)
        #expect(
            fixture.textView.visibleRect.contains(CGPoint(x: inView.midX, y: inView.midY)),
            "\(place): the caret at \(inView) is outside the visible rect \(fixture.textView.visibleRect)"
        )
    }

    // (n2-page R-17) Typing at the very end of a long note leaves the caret in view.
    @Test func typingAtTheEndLeavesTheCaretInsideTheVisibleRect() {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }

        fixture.type("x", at: (longNote as NSString).length)

        expectTheCaretIsVisible(fixture, "end")
    }

    // (n2-page R-17) Typing in the middle of a long note, far below the viewport the note opened
    // on, leaves the caret in view.
    @Test func typingInTheMiddleLeavesTheCaretInsideTheVisibleRect() {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }

        fixture.type("x", at: endOfLine(after: "Seconda riga della sezione 200,", in: longNote))

        expectTheCaretIsVisible(fixture, "middle")
    }

    // MARK: The end is reachable when it is approached

    // (n2-page R-17) After a keystroke at the top, going to the end and letting the viewport lay
    // out puts the last line inside the view's frame.
    @Test func afterAKeystrokeAtTheTopTheEndIsInsideTheFrameOnceApproached() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        let layout = try #require(fixture.textView.textLayoutManager)
        let content = try #require(layout.textContentManager)

        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))
        fixture.textView.moveToEndOfDocument(nil)
        layout.textViewportLayoutController.layoutViewport()

        let tail = (fixture.textView.string as NSString).range(of: "Ultima riga della nota lunga.")
        let location = try #require(content.location(content.documentRange.location, offsetBy: tail.location))
        let fragment = try #require(layout.textLayoutFragment(for: location), "the last line has no fragment")
        #expect(
            fragment.layoutFragmentFrame.maxY <= fixture.textView.frame.height,
            "the last line ends at \(fragment.layoutFragmentFrame.maxY), the frame is \(fixture.textView.frame.height) tall"
        )
    }
}
