import AppKit
import Testing
@testable import Pergamenum

// The caret trap a GFM table with nothing laid out below its grid falls into
// (`NoteTextView+TableCaret.swift`, ADR-0029 §D4/§D5): every click or caret move inside a
// table's hidden delimiter/body rows resolves to the same text-storage offset, the header
// paragraph's own end, and Return there used to insert `\n` *inside* the table's own
// source - breaking `GFMTable.parse`'s contiguity, a real corruption rather than a
// rendering hiccup.
//
// The fixture calls `NoteTextView.wire(_:to:)` rather than assigning `claimsCommand`
// itself, on `Tests/NoteListEditingTests.swift`'s own precedent: the seam under test is the
// closure inside that method, and a fixture holding its own copy would be asserting against
// the copy rather than the app's real wiring.

// MARK: - Fixture

@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    /// Never read for its own sake: it exists so `textView.undoManager` resolves through
    /// the responder chain to something, the same reason `NoteListEditingTests`' own
    /// fixture keeps one.
    let window: NSWindow
}

/// A real `CompletingTextView` holding `text`, wired and configured the way
/// `NoteTextView.makeNSView` configures the one the app draws, with a table styling pass
/// already run so `decorations.tableViews` is populated the way a real editing session
/// would have it by the time a key reaches the view.
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
    textView.string = text
    coordinator.applyStyling(to: textView, theme: .emergency)
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    window.makeFirstResponder(textView)
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

@MainActor
private func pressReturn(_ fixture: Editor) {
    fixture.textView.doCommand(by: #selector(NSTextView.insertNewline(_:)))
}

@MainActor
private func pressForwardDelete(_ fixture: Editor) {
    fixture.textView.doCommand(by: #selector(NSTextView.deleteForward(_:)))
}

// MARK: - The suite

@MainActor
@Suite struct TableCaretTrap {
    /// A two-column, two-body-row table with nothing after it in the note at all - no
    /// trailing newline, no blank paragraph - the exact reproduction from the bug report:
    /// a table that is the last block in the file.
    private static let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
    /// "prima\n" is six characters; the header paragraph starts right after it.
    private static let headerOffset = 6
    /// "| a | b |\n" is ten characters - the header paragraph's own end, and the one
    /// offset every click or caret move inside the hidden delimiter/body rows collapses
    /// onto (the trap this claimant redirects).
    private static let trapOffset = headerOffset + 10
    /// The table's true end: the whole note, since the last body row carries no trailing
    /// newline here.
    private static let tableEnd = (note as NSString).length

    @Test func returnAtTheTrapOffsetAppendsAfterTheTableInsteadOfCorruptingItsDelimiterRow() {
        let fixture = editor(Self.note, caret: Self.trapOffset)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        // The table's own source, character for character, is untouched - the new
        // paragraph landed after it, not inside it.
        #expect(fixture.textView.string == Self.note + "\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: Self.tableEnd + 1, length: 0))
        // The redirect must leave `CompletingTextView` unambiguously first responder - one
        // of the two proxies this suite can assert for the caret actually being visible
        // and blinking at the new location, which no unit test can observe directly.
        #expect(fixture.window.firstResponder === fixture.textView)
        // Neither `firstRect(forCharacterRange:)` nor its `caretRectOnScreen()` TextKit-2
        // fallback is a usable headless probe at this specific location - tried and
        // confirmed degenerate for both, even after `growToFitTheText`'s `ensureLayout`:
        // the redirected caret sits exactly at the new trailing paragraph's own end (the
        // document's own end), and `NSTextLayoutFragment` legitimately has nothing to
        // report for a location with no character segment of its own, whether or not the
        // fix is present. This is a harness/geometry-at-end-of-document ceiling, not a
        // signal this test can read either way - see `table-caret-blink-after-redirect`
        // and `textkit2-attachment-view-accessibility` (debugger memory) for the general
        // pattern. First responder and `selectedRange()` above remain the only two proxies
        // this suite can assert on; whether the caret actually blinks needs a live check.

        // `GFMTable.parse` still succeeds on the original table lines: the delimiter row
        // is still `|---|---|`, not `` (an inserted blank line) or `-|` (a split pipe).
        let recognised = EditorDecorationDelegate.tableRun(
            in: fixture.textView.string as NSString, atParagraphStart: Self.headerOffset
        )
        #expect(recognised?.table.header == ["a", "b"])
        #expect(recognised?.table.rows == [["1", "2"], ["3", "4"]])
        #expect(recognised?.range == NSRange(location: Self.headerOffset, length: Self.tableEnd - Self.headerOffset))
    }

    @Test func oneUndoTakesBackTheAppendedParagraph() throws {
        let fixture = editor(Self.note, caret: Self.trapOffset)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)

        pressReturn(fixture)
        #expect(fixture.textView.string == Self.note + "\n")

        undo.undo()

        #expect(fixture.textView.string == Self.note)
    }

    @Test func forwardDeleteAtTheTrapOffsetDoesNothingRatherThanEatingTheDelimiterRowsPipe() {
        let fixture = editor(Self.note, caret: Self.trapOffset)
        defer { fixture.window.orderOut(nil) }

        pressForwardDelete(fixture)

        // The trap offset is also the table's true end here (no trailing newline), so
        // there is nothing after it to delete - exactly what forward Delete at a real
        // document end already does, and the delimiter row's own `|` survives untouched.
        #expect(fixture.textView.string == Self.note)
    }

    /// The header paragraph's own content end - one character short of `trapOffset`, right
    /// before the header line's own trailing newline. Empirically confirmed
    /// (`ScratchTableDiagnosticTests.swift`'s probe, removed after use) as what a click past
    /// `TableGridView`'s own real hosted frame - beside the grid, at the same height as its
    /// rows, not below the whole table - resolves to: the control pills make that frame wider
    /// than the drawn border for a narrow table, and `TableGridView`'s own unoverridden
    /// `mouseDown` swallows anything landing inside the frame itself, so only a point past its
    /// right edge ever reaches ordinary point-to-character hit testing.
    private static let contentEndOffset = trapOffset - 1

    @Test func returnAtTheContentEndOffsetAppendsAfterTheTableInsteadOfCorruptingItsHeaderLine() {
        let fixture = editor(Self.note, caret: Self.contentEndOffset)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        #expect(fixture.textView.string == Self.note + "\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: Self.tableEnd + 1, length: 0))
        // Same proxy as the `end`-offset case above: first responder must land on
        // `CompletingTextView`, not be left stale on whatever had it before the click that
        // resolved to `contentEndOffset` (`TableGridView`'s own frame swallows a click
        // without changing first responder - the doc comment's own R6). No caret-rect
        // assertion here either, for the reason documented on the `end`-offset test above:
        // neither `firstRect` nor its TextKit-2 fallback reads anything but a degenerate
        // rect at this exact end-of-document location, fix present or not.
        #expect(fixture.window.firstResponder === fixture.textView)

        let recognised = EditorDecorationDelegate.tableRun(
            in: fixture.textView.string as NSString, atParagraphStart: Self.headerOffset
        )
        #expect(recognised?.table.header == ["a", "b"])
        #expect(recognised?.table.rows == [["1", "2"], ["3", "4"]])
        #expect(recognised?.range == NSRange(location: Self.headerOffset, length: Self.tableEnd - Self.headerOffset))
    }

    @Test func forwardDeleteAtTheContentEndOffsetDoesNotMergeTheHeaderAndDelimiterParagraphs() {
        let note = Self.note + "\ndopo"
        let fixture = editor(note, caret: Self.contentEndOffset)
        defer { fixture.window.orderOut(nil) }

        pressForwardDelete(fixture)

        // Redirected to the table's true end, which here is not the document's own end (there
        // is a real paragraph after it): the character actually removed is the blank line's
        // own newline immediately after the table, not the header's trailing newline.
        #expect(fixture.textView.string == "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |dopo")

        let recognised = EditorDecorationDelegate.tableRun(
            in: fixture.textView.string as NSString, atParagraphStart: Self.headerOffset
        )
        #expect(recognised?.table.header == ["a", "b"])
        #expect(recognised?.table.rows == [["1", "2"], ["3", "4"]])
    }

    /// A table with an ordinary paragraph directly after it, no blank line - the case the
    /// fix must not regress: the caret there is on a real, separately laid-out paragraph,
    /// never the header's own end, so Return behaves exactly as it always has.
    @Test func returnOnTheParagraphRightAfterATableInsertsAPlainNewlineAndNothingElse() {
        let note = Self.note + "\ndopo"
        let caret = (note as NSString).length
        let fixture = editor(note, caret: caret)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        #expect(fixture.textView.string == note + "\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: caret + 1, length: 0))
    }

    /// A table with a blank paragraph already after it - clicking/pressing Return there
    /// must behave normally too, on the same reasoning: that offset is a real laid-out
    /// paragraph's own start, not the header's end.
    @Test func returnOnAnExistingBlankParagraphAfterATableInsertsAPlainNewlineAndNothingElse() {
        let note = Self.note + "\n\n"
        let caret = (note as NSString).length
        let fixture = editor(note, caret: caret)
        defer { fixture.window.orderOut(nil) }

        pressReturn(fixture)

        #expect(fixture.textView.string == note + "\n")
        #expect(fixture.textView.selectedRange() == NSRange(location: caret + 1, length: 0))
    }
}
