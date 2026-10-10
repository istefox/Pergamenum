import AppKit
import Testing
@testable import Pergamenum

// ADR-0082 §D7 (amended 2026-10-10), plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-17).
//
// Restated 2026-10-10, the reason first. This file first pinned that growing the view to fit lays out
// the caret's fragment and the viewport, not the whole document. The G-grow hand check on a 50 KB
// Release note showed that is wrong while every update invalidates the whole layout: after Cmd+Down
// a click scrolled the note to text far above it and selected all of it. Growing to fit lays out the
// whole document again (as before ADR-0082 §D7), the scope test says so, and a new test pins the
// symptom: the view stays on the same text across the passes a click runs. The other tests, the
// caret visible when typing at the end and in the middle and the end reachable when approached, are
// unchanged. Never `layoutSubtreeIfNeeded` (the header of `NoteTextView+Coordinator.growToFitTheText`'s
// history warns against it): the end is brought into view the app's way, `moveToEndOfDocument(nil)`
// and `layoutViewport()`.

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

@MainActor
@Suite(.serialized) struct EditorGrowToFitScope {
    // MARK: The scope

    // (n2-page R-17, restated 2026-10-10) After the passes a keystroke runs, no height in the note
    // is an estimate any more: laying out the whole document again changes nothing. This replaces
    // two tests that pinned the opposite design, growing to fit over the caret's fragment and the
    // viewport only, and counted the fragments TextKit was asked for. That design failed the G-grow
    // hand check (the test below, and the note in `NoteTextView+Coordinator.growToFitTheText`), and
    // the counting probe cannot see the new one: once the layout has been invalidated TextKit reuses
    // its fragments and requests none. The usage height is the direct witness, since an estimate is
    // exactly a height that changes when the rest is laid out.
    @Test func afterTheKeystrokePassesNoHeightInTheNoteIsAnEstimate() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        let layout = try #require(fixture.textView.textLayoutManager)
        fixture.openLikeTheApp()
        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))

        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        fixture.coordinator.growToFitTheText(fixture.textView, revealingCaret: true)
        let grown = layout.usageBoundsForTextContainer.height
        layout.ensureLayout(for: layout.documentRange)
        let complete = layout.usageBoundsForTextContainer.height

        #expect(abs(grown - complete) < 0.5, "the note measured \(grown) pt after growing to fit and \(complete) pt laid out whole")
    }

    // MARK: The view stays where the person put it

    // Found by hand on 2026-10-10 (G-grow, 50 KB Release note): Cmd+Down, then a click on a line.
    // The click's own update runs the passes, `applyStyling` rewrites every attribute and
    // invalidates the layout of the whole note, and a grow-to-fit that lays out only the caret and
    // the viewport leaves everything above as an estimate. The estimate is shorter than the real
    // height, the same scroll offset then shows text far above where the person was (section 62 for
    // 104 in the note that was tried), the mouse is still down and sits over other text, and the
    // click became a selection of the whole note, which the next key replaces.
    // (n2-page R-17) The paragraph at the top of the view is the same before and after the passes
    // a click runs.
    @Test func thePassesAClickRunsLeaveTheViewOnTheSameText() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        let layout = try #require(fixture.textView.textLayoutManager)
        fixture.openLikeTheApp()
        fixture.textView.moveToEndOfDocument(nil)
        layout.textViewportLayoutController.layoutViewport()
        fixture.textView.scrollRangeToVisible(fixture.textView.selectedRange())
        layout.textViewportLayoutController.layoutViewport()

        func topOfTheView() -> Int {
            let top = CGPoint(x: fixture.textView.bounds.midX, y: fixture.textView.visibleRect.minY + 4)
            return fixture.textView.characterIndexForInsertion(at: top)
        }
        let before = topOfTheView()

        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        fixture.coordinator.growToFitTheText(fixture.textView)

        let after = topOfTheView()
        let text = fixture.textView.string as NSString
        #expect(
            abs(after - before) < 200,
            "the view moved from \"\(text.substring(with: text.lineRange(for: NSRange(location: before, length: 0))))\" to \"\(text.substring(with: text.lineRange(for: NSRange(location: after, length: 0))))\""
        )
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
