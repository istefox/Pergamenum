import AppKit
import Testing
@testable import Pergamenum

// Return inside a list, in the note editor (ADR-0028, plan
// `2026-08-29-wysiwyg-markdown-in-workspace`, Task 4, R-07, R-08, R-12).
//
// What is under test here is the *wiring*, not the arithmetic: `ListContinuation.newline`
// and `.renumbered` are pure, already implemented and already covered by
// `Tests/ListContinuationTests.swift` (Task 2). This file asserts that a Return key
// command reaching a real `CompletingTextView` - wired exactly the way the app wires it -
// turns into that function's answer, as **one** edit on the storage and therefore one
// undo step.
//
// The fixture calls `NoteTextView.wire(_:to:)` rather than assigning `claimsCommand`
// itself. That is deliberate: the seam Task 4 extends is the closure inside that method
// (`NoteTextView.swift:207`), and a fixture that assigned its own copy of the closure
// would be asserting against the copy - green here, broken in the app, or red forever
// whatever the coder writes. `Tests/EmbedEditorTestSupport.swift` holds exactly such a
// copy for the embed suites; this file does not repeat that.
//
// RED, expected, until Task 4's coder extends that closure to claim
// `#selector(insertNewline(_:))` when `ListContinuation.newline` returns non-nil:
// `returnAtTheEndOfABulletItemContinuesTheList`, `returnOnAnEmptyItemLeavesTheList`,
// `returnInsideAnOrderedRunRenumbersTheRestOfItInTheSameEdit`,
// `oneUndoTakesBackTheWholeContinuation` and
// `oneUndoTakesBackTheContinuationAndItsRenumberingTogether` all fail on today's build,
// where Return falls through to AppKit and inserts a bare newline.
// `returnOnALineThatIsNotAListItemInsertsAPlainNewlineAndNothingElse` is green on
// arrival - it is the fall-through case, and it is here to pin that the claim stays
// narrow once the rest goes green.

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

    // MARK: ADR-0074 G2 H2: a delete, not a Return, renumbers through `textDidChange`

    /// G2 H2: the entry is `deleteBackward` -> `Coordinator.textDidChange` ->
    /// `renumberLists(in:)`, not `claimsListCommand`. Deleting a selected middle item leaves
    /// "1. / 3. / 4." behind, and the run has to come back contiguous, with one undo taking
    /// the deletion and the renumbering back together. The undo half catches a missing undo
    /// registration, not a split within one event: event grouping merges those in production
    /// too. The card's twin is `CardFormattingTests.deletingAMiddleItemOfACardsOrderedRun...`.
    @Test func deletingAMiddleItemOfAnOrderedRunRenumbersTheRestAndOneUndoRestoresBoth() throws {
        let text = "1. uno\n2. due\n3. tre\n4. qua"
        let fixture = editor(text, caret: 0)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        let victim = (text as NSString).range(of: "2. due\n")
        #expect(victim.location != NSNotFound, "premessa: la riga da cancellare deve esistere")
        fixture.textView.setSelectedRange(victim)

        fixture.textView.deleteBackward(nil)

        #expect(fixture.textView.string == "1. uno\n2. tre\n3. qua")
        #expect(ordinals(in: fixture.textView.string) == [1, 2, 3])

        undo.undo()

        #expect(fixture.textView.string == text)
    }

    // MARK: The digit-width-shrink caret (ADR-0082 §D6, n2-page R-16)

    /// Restated 2026-10-06 (plan docs/plans/pg-385-n2-page.md, Task 2). The reason, stated first:
    /// this test pinned the documented gap that the whole-text `renumberLists(in:)` leaves the
    /// caret one character ahead of the text once a run's trailing item shrinks (49), and its own
    /// comment asked that closing the gap "should update this assertion deliberately rather than
    /// break it by accident". The SPEC (N2, PG-385) decides that move on purpose: renumbering
    /// rewrites only the edited run and maps the caret through the edit, so the caret lands at 48.
    /// The 49 is not lost, it is the documented fallback and is pinned by the next test.
    ///
    /// Text as it stands right after a manual delete of a run's ninth item ("9. i\n") from a
    /// correctly numbered ten-item list: eight untouched items, then the former tenth still
    /// carrying its two-digit "10." marker, then a plain trailing line the run does not extend
    /// into. The edit sits at "10." (location 40), `ListContinuation.renumbered(_:touching:)`
    /// shrinks that one marker from "10" to "9", and the caret, parked inside the trailing line
    /// after "pro", is carried back one character with it.
    @Test func renumberingTheEditedRunMapsTheCaretThroughTheShrink() throws {
        // (n2-page R-16)
        let text = "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n10. j\nprosa"
        let caret = 49
        let fixture = editor(text, caret: caret)
        defer { fixture.window.orderOut(nil) }
        // Derived, not hand-written, for the same reason the Return tests above derive from
        // `ListContinuation.newline`: a hand-copied string would only assert this test's own
        // arithmetic.
        let expected = try #require(ListContinuation.renumbered(text))

        fixture.coordinator.renumberLists(in: fixture.textView, touching: NSRange(location: 40, length: 0))

        #expect(fixture.textView.string == expected)
        #expect(
            fixture.textView.selectedRange() == NSRange(location: caret - 1, length: 0),
            "il caret va mappato attraverso la modifica: 48, fra «pro» e «sa»"
        )
    }

    /// (n2-page R-16) The fallback ADR-0082 §D6 keeps for an edit nobody recorded - an undo, a
    /// programmatic replacement: the whole text is renumbered and the caret is clamped, unshifted,
    /// exactly as before this chain. The one character it leaves the caret ahead is documented,
    /// not ideal.
    @Test func withNoEditedRangeTheWholeTextFallbackKeepsTheCaretClamped() throws {
        let text = "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n10. j\nprosa"
        let caret = 49
        let fixture = editor(text, caret: caret)
        defer { fixture.window.orderOut(nil) }
        let expected = try #require(ListContinuation.renumbered(text))

        fixture.coordinator.renumberLists(in: fixture.textView)

        #expect(fixture.textView.string == expected)
        #expect(fixture.textView.selectedRange() == NSRange(location: caret, length: 0))
    }

    /// (n2-page R-16) The keystroke path records the edited range: a real delete through
    /// `insertText("", replacementRange:)` with the delegate wired reaches `textDidChange` with the
    /// range the delete touched, the scoped renumber rewrites the run, and one `undo()` takes the
    /// deletion and the renumbering back together.
    @Test func aRealDeleteRenumbersThroughTheRecordedRangeInOneUndoStep() throws {
        let before = "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n9. i\n10. j\nprosa"
        let fixture = editor(before, caret: 54)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        let victim = (before as NSString).range(of: "9. i\n")
        #expect(victim == NSRange(location: 40, length: 5), "premessa: la riga da cancellare è dove ci si aspetta")
        let afterDelete = (before as NSString).replacingCharacters(in: victim, with: "")
        let expected = try #require(ListContinuation.renumbered(afterDelete))

        fixture.textView.insertText("", replacementRange: victim)

        #expect(fixture.textView.string == expected)
        // The caret AppKit leaves after the delete is 49, one character into "prosa" after "pro"
        // (the delete removed five characters before it); the scoped renumber maps it through the
        // shrink of "10." to "9." and lands on 48.
        #expect(
            fixture.textView.selectedRange() == NSRange(location: 48, length: 0),
            "il caret dopo la cancellazione e il renumber deve essere 48"
        )

        undo.undo()

        #expect(fixture.textView.string == before, "un solo undo riporta il testo prima della cancellazione")
    }
}
