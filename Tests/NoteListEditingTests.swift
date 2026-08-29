import AppKit
import Testing
@testable import Pergamenum

/// Return inside a list, in the note editor (ADR-0028, plan
/// `2026-08-29-wysiwyg-markdown-in-workspace`, Task 4, R-07, R-08, R-12).
///
/// What is under test here is the *wiring*, not the arithmetic: `ListContinuation.newline`
/// and `.renumbered` are pure, already implemented and already covered by
/// `Tests/ListContinuationTests.swift` (Task 2). This file asserts that a Return key
/// command reaching a real `CompletingTextView` - wired exactly the way the app wires it -
/// turns into that function's answer, as **one** edit on the storage and therefore one
/// undo step.
///
/// The fixture calls `NoteTextView.wire(_:to:)` rather than assigning `claimsCommand`
/// itself. That is deliberate: the seam Task 4 extends is the closure inside that method
/// (`NoteTextView.swift:207`), and a fixture that assigned its own copy of the closure
/// would be asserting against the copy - green here, broken in the app, or red forever
/// whatever the coder writes. `Tests/EmbedEditorTestSupport.swift` holds exactly such a
/// copy for the embed suites; this file does not repeat that.
///
/// RED, expected, until Task 4's coder extends that closure to claim
/// `#selector(insertNewline(_:))` when `ListContinuation.newline` returns non-nil:
/// `returnAtTheEndOfABulletItemContinuesTheList`, `returnOnAnEmptyItemLeavesTheList`,
/// `returnInsideAnOrderedRunRenumbersTheRestOfItInTheSameEdit`,
/// `oneUndoTakesBackTheWholeContinuation` and
/// `oneUndoTakesBackTheContinuationAndItsRenumberingTogether` all fail on today's build,
/// where Return falls through to AppKit and inserts a bare newline.
/// `returnOnALineThatIsNotAListItemInsertsAPlainNewlineAndNothingElse` is green on
/// arrival - it is the fall-through case, and it is here to pin that the claim stays
/// narrow once the rest goes green.

// MARK: - Fixture

@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    /// Never read for its own sake: it exists so `textView.undoManager` resolves through
    /// the responder chain to something, the same reason `EmbedEditorFixtures` keeps one.
    let window: NSWindow
}

/// A real `CompletingTextView` holding `text` with a caret at `caret`, wired and configured
/// the way `NoteTextView.makeNSView` configures the one the app draws - delegate, undo,
/// decoration delegates and `wire(_:to:)` - inside an offscreen window that is never
/// ordered front.
///
/// The same offscreen shape `Tests/CardFormattingTests.swift:28` uses for
/// `FormattingTextView`, plus the window and the coordinator, which a key command needs and
/// a formatting call does not.
@MainActor
private func editor(_ text: String, caret: Int) -> Editor {
    let view = NoteTextView(
        text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)

    let window = NSWindow(
        contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = textView
    // Assigning `.string` posts no `textDidChange`, so the text is in place before anything
    // the delegate does can see it - and it registers no undo action either, which is what
    // makes "one undo returns to this" an assertion about the keystroke alone.
    textView.string = text
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    window.makeFirstResponder(textView)
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

/// The Return key as it reaches a text view: the selector `NSTextView.doCommand(by:)` is
/// handed, never a synthesised `NSEvent`.
@MainActor
private func pressReturn(_ fixture: Editor) {
    fixture.textView.doCommand(by: #selector(NSTextView.insertNewline(_:)))
}

/// The offset just past `line`'s last character - where a caret sits when Return is pressed
/// at the end of that line.
private func endOf(_ line: String, in text: String) -> Int {
    NSMaxRange((text as NSString).range(of: line))
}

/// The leading ordinal of every line that carries one, in document order. Reads the run's
/// contiguity off the text itself rather than off a hard-coded expected string.
private func ordinals(in text: String) -> [Int] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
        Int($0.prefix { $0.isNumber })
    }
}

// MARK: - The suite

@MainActor
@Suite struct NoteListEditing {
    // MARK: R-07: continuing and leaving a bullet list

    @Test func returnAtTheEndOfABulletItemContinuesTheList() {
        let fixture = editor("- primo", caret: 7)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        #expect(fixture.textView.string == "- primo\n- ")
        // Past the marker it just wrote, not before it: the next character typed is the
        // item's text.
        #expect(fixture.textView.selectedRange() == NSRange(location: 10, length: 0))
    }

    @Test func returnOnAnEmptyItemLeavesTheList() {
        // The state the test above ends in, set up directly rather than by pressing Return
        // twice: this is R-07's *exit* rule and it has to be able to fail on its own.
        let fixture = editor("- primo\n- ", caret: 10)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        // The empty item's prefix goes and no line is inserted - one blank paragraph after
        // "- primo", not two.
        #expect(fixture.textView.string == "- primo\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test func returnOnALineThatIsNotAListItemInsertsAPlainNewlineAndNothingElse() {
        let text = "prosa normale"
        let fixture = editor(text, caret: (text as NSString).length)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        // The claim has to stay narrow: everywhere that is not a list item, Return is
        // AppKit's Return and writes exactly one newline.
        #expect(fixture.textView.string == "prosa normale\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: 14, length: 0))
    }

    // MARK: R-08: an ordered run stays contiguous

    @Test func returnInsideAnOrderedRunRenumbersTheRestOfItInTheSameEdit() throws {
        let text = "1. uno\n2. due\n3. tre"
        let caret = endOf("2. due", in: text)
        // Derived from the pure function Task 2 already tested, not hand-written: what is
        // asserted here is that the view ends up holding that exact answer, and a
        // hand-copied string would only be asserting this test's own arithmetic.
        let expected = try #require(
            ListContinuation.newline(in: text, at: NSRange(location: caret, length: 0))
        )
        let fixture = editor(text, caret: caret)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        #expect(fixture.textView.string == expected.text)
        #expect(fixture.textView.selectedRange() == expected.selection)
        // R-08 spelled out: four items, numbered 1 to 4, no gap left where the new one
        // went in.
        #expect(ordinals(in: fixture.textView.string) == [1, 2, 3, 4])
    }

    // MARK: R-12: one press, one undo

    @Test func oneUndoTakesBackTheWholeContinuation() throws {
        let fixture = editor("- primo", caret: 7)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)

        pressReturn(fixture)
        #expect(fixture.textView.string == "- primo\n- ")

        undo.undo()

        #expect(fixture.textView.string == "- primo")
    }

    @Test func oneUndoTakesBackTheContinuationAndItsRenumberingTogether() throws {
        let text = "1. uno\n2. due\n3. tre"
        let caret = endOf("2. due", in: text)
        let expected = try #require(
            ListContinuation.newline(in: text, at: NSRange(location: caret, length: 0))
        )
        let fixture = editor(text, caret: caret)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)

        pressReturn(fixture)
        // Asserted before the undo on purpose: without it this test would pass on a build
        // where Return only inserts a bare newline, since one undo takes *that* back too.
        // What has to be undone in one step is the renumbering as well.
        #expect(fixture.textView.string == expected.text)

        // One call, not two: the insertion and the renumbering it forced are one
        // replacement, so a person pressing Cmd+Z once is back where they were rather than
        // halfway - a list numbered 1/2/3/4 with the new item gone.
        undo.undo()

        #expect(fixture.textView.string == text)
    }
}
