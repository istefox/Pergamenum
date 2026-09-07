import AppKit
import Testing
@testable import Pergamenum

// ADR-0033 §D15 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5):
// `rescueCaret`'s/`tableCaretRescue`'s third twin - a caret placed programmatically inside a
// body line a styling pass is about to take out of the layout has nowhere to be drawn and
// nowhere to type, and must move to the opening fence line's own offset, after the storage's
// editing transaction closes, never inside it. `NoteTextView+Tables.swift`'s own
// `tableCaretRescue`/`refreshTableGrids` is the shape copied here.
//
// `ViewBlockCaretRescue` below (Task 5) is now fully implemented and green: Task 5's coder
// wired `applyViewBlocks`/`applyStyling` for real, so a caret placed inside the body line is
// rescued exactly as asserted.
//
// ADR-0033 §D4/§D5 (Task 6): reveal on the fence's whole source range, and the re-render on
// exit. `Coordinator.revealedViewBlock(in:selection:)` is declared below **stubbed to always
// return `nil`** (this task's own tester declaration, ADR-0049 - the coder implements the real
// predicate and wires it into `applyViewBlocks`/`textViewDidChangeSelection`). Its own doc
// comment explains why it takes a plain `String` and an `NSRange` rather than an `NSTextView`:
// `MarkupReveal.paragraphs`' own shape, chosen so `ViewBlockRevealPredicate` below can assert
// against it with no `NSTextView` at all. Every assertion in `ViewBlockRevealPredicate` that
// expects a non-nil answer is therefore red against the stub; the two that expect `nil` (the
// lines immediately above/below the fence) are green with the stub already, for the same
// reason a `nil`-returning stub trivially satisfies "reveals nothing" - noted per-test below,
// not hidden. `ViewBlockRevealIntegration`'s three tests drive the full `applyStyling`
// pipeline and are red for the pipeline-level reason `applyViewBlocks` does not yet consult
// `revealedViewBlock` at all, so a fence with the caret inside is drawn exactly as one with
// the caret elsewhere.

// MARK: - Fixture

@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    /// Never read for its own sake: it exists so `textView.undoManager` resolves through the
    /// responder chain to something, `Tests/TableCaretTests.swift`'s own fixture's reason.
    let window: NSWindow
}

/// Mirrors `Tests/TableCaretTests.swift`'s own `editor(_:caret:)` fixture: a real text view,
/// wired the way `NoteTextView.makeNSView` wires the one the app draws, with the caret placed
/// *before* the one real styling pass runs - unlike that fixture, which places the caret
/// after an initial pass to reach a trap a second, user-triggered pass falls into. Here the
/// caret is already inside the line the first and only pass is about to hide, which is
/// exactly the scenario ADR §D15 names: "a programmatic selection - a find match, an outline
/// jump, `onScrollApplied` - can put the caret in a body line without going through the
/// reveal path."
@MainActor
private func editor(_ text: String, caret: Int, hidesMarkup: Bool = true) -> Editor {
    let view = NoteTextView(
        text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: hidesMarkup, onFollowLink: { _ in }
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
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    coordinator.applyStyling(to: textView, theme: .emergency)
    window.makeFirstResponder(textView)
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

/// A closed `pergamenum-view` fence, one body line, then an ordinary paragraph - the same
/// fixture text `Tests/ViewBlockRenderingTests.swift`'s own `ViewBlockFixture` uses.
private enum ViewBlockCaretFixture {
    static let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
    static let openingFenceOffset = 6
    static let bodyLineOffset = openingFenceOffset + 19
    /// A few characters into the body line, deliberately not at its very start - "inside a
    /// body line", not merely at its boundary.
    static let insideBodyLine = bodyLineOffset + 4
    static let closingFenceOffset = bodyLineOffset + 14
    static let afterOffset = closingFenceOffset + 4
    /// The fence's whole source range (ADR §D4): opening backticks through the closing
    /// fence's own last backtick, inclusive of the backtick but not its trailing newline -
    /// `NSMaxRange` of this is `afterOffset - 1`, since "```\n" is four characters and the
    /// trailing newline is excluded the same way `CodeFence.Region.range` excludes it
    /// (`CodeFence.swift`'s own `lineRanges` comment).
    static let fenceRange = NSRange(location: openingFenceOffset, length: afterOffset - 1 - openingFenceOffset)
}

/// Two closed `pergamenum-view` fences in one note, `ViewBlockCaretFixture.note`'s own prefix
/// repeated once more after an ordinary paragraph - `ViewBlockRevealIntegration`'s own fixture
/// for the SPEC Edge cases claim under test: "no shared state between them."
private enum TwoViewBlockCaretFixture {
    static let note = "prima\n```pergamenum-view\nrender: table\n```\nmezzo\n```pergamenum-view\nrender: gallery\n```\ndopo\n"
    static let firstOpening = 6
    /// "```pergamenum-view\n" (19) - the first fence's body line.
    static let firstBody = firstOpening + 19
    /// A few characters into the first fence's body line, matching
    /// `ViewBlockCaretFixture.insideBodyLine`'s own convention.
    static let insideFirstBody = firstBody + 4
    /// "render: table\n" (14) + "```\n" (4) + "mezzo\n" (6) - the second fence's opening line.
    static let secondOpening = firstBody + 14 + 4 + 6
    /// "```pergamenum-view\n" (19) - the second fence's body line.
    static let secondBody = secondOpening + 19
}

/// The UTF-16 offsets of every paragraph a real layout pass actually lays out, given
/// `delegate`'s current registered state - `Tests/ViewBlockRenderingTests.swift`'s own helper
/// of this name, copied rather than imported on that file's own precedent
/// (`TableRenderingTests.swift`/`EmbedDrawingTests.swift`/`MarkupHidingTests.swift`): each test
/// file keeps its own copy rather than sharing one.
@MainActor
private func laidOutOffsets(of delegate: EditorDecorationDelegate, text: String) -> Set<Int> {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var offsets: Set<Int> = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        offsets.insert(content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location))
        return true
    }
    return offsets
}

// MARK: - The suite

@MainActor
@Suite struct ViewBlockCaretRescue {
    /// ADR §D15: a caret programmatically placed inside the body line a fence is about to
    /// hide is rescued to the opening fence line's own offset once the pass that hides it has
    /// run.
    @Test func aCaretInsideTheBodyLineIsRescuedToTheOpeningFenceOffset() {
        let fixture = editor(ViewBlockCaretFixture.note, caret: ViewBlockCaretFixture.insideBodyLine)
        defer { fixture.window.orderOut(nil) }

        #expect(
            fixture.textView.selectedRange() == NSRange(location: ViewBlockCaretFixture.openingFenceOffset, length: 0),
            "il caret nella riga nascosta non è stato spostato sulla riga di apertura del fence"
        )
    }

    /// The boundary this rescue must not overreach: a caret already on the opening fence line
    /// - the line that stays in the layout, carrying the attachment - is left exactly where it
    /// was. Never rescued, because it was never in danger.
    @Test func aCaretOnTheOpeningFenceLineIsLeftWhereItWas() {
        let caret = ViewBlockCaretFixture.openingFenceOffset + 3
        let fixture = editor(ViewBlockCaretFixture.note, caret: caret)
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.textView.selectedRange() == NSRange(location: caret, length: 0))
    }

    /// The other boundary: a caret on the paragraph right after the fence, never touched by
    /// this pass at all, is left exactly where it was.
    @Test func aCaretOnTheLineAfterTheFenceIsLeftWhereItWas() {
        let caret = ViewBlockCaretFixture.afterOffset + 1
        let fixture = editor(ViewBlockCaretFixture.note, caret: caret)
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.textView.selectedRange() == NSRange(location: caret, length: 0))
    }

    /// D12's own escape hatch reaching this rescue too: with `hidesMarkup` off nothing is
    /// hidden in the first place, so a caret inside what would be the body line with markup
    /// showing is never rescued - there is nothing to rescue it from.
    @Test func withHidesMarkupOffACaretInsideTheBodyLineIsNeverRescued() {
        let fixture = editor(
            ViewBlockCaretFixture.note, caret: ViewBlockCaretFixture.insideBodyLine, hidesMarkup: false
        )
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.textView.selectedRange() == NSRange(location: ViewBlockCaretFixture.insideBodyLine, length: 0))
    }
}

// MARK: - The reveal predicate, pure (ADR §D4; Task 6)

/// `Coordinator.revealedViewBlock(in:selection:)` against a plain `String` - no `NSTextView`,
/// no styling pass, `MarkupRevealTests.swift`'s own precedent for `MarkupReveal.paragraphs`.
/// Stubbed to always return `nil` (this file's own header comment): every assertion below that
/// expects a non-nil fence range is red against the stub; the two that expect `nil` (the lines
/// immediately above and below the fence) are green with the stub already, and must stay green
/// once the coder implements the real body - a `nil`-returning stub trivially satisfies
/// "reveals nothing," which is also the *correct* answer at those two positions.
@Suite struct ViewBlockRevealPredicate {
    /// R-05: a caret on the opening fence line reveals the block.
    @Test func aCaretOnTheOpeningFenceLineRevealsTheFence() {
        let caret = NSRange(location: ViewBlockCaretFixture.openingFenceOffset + 3, length: 0)
        #expect(
            NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: caret)
                == ViewBlockCaretFixture.fenceRange
        )
    }

    /// C3's own reason this predicate exists at all: a caret on a **body** line reveals the
    /// block too - the one case a paragraph-keyed reveal (the table mechanism's own shape)
    /// cannot satisfy, since a hidden body line is not in the layout at all to place a caret
    /// on. This predicate is range-keyed against the raw source, so it does not need the body
    /// line to be laid out to answer correctly.
    @Test func aCaretOnTheBodyLineRevealsTheFenceToo() {
        let caret = NSRange(location: ViewBlockCaretFixture.insideBodyLine, length: 0)
        #expect(
            NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: caret)
                == ViewBlockCaretFixture.fenceRange
        )
    }

    /// A caret on the closing fence line reveals the block too - the run is inclusive of both
    /// its own delimiter lines (ADR §D4: "opening line through closing line, inclusive").
    @Test func aCaretOnTheClosingFenceLineRevealsTheFence() {
        let caret = NSRange(location: ViewBlockCaretFixture.closingFenceOffset + 1, length: 0)
        #expect(
            NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: caret)
                == ViewBlockCaretFixture.fenceRange
        )
    }

    /// The boundary this predicate must not overreach: the line right before the fence opens
    /// reveals nothing. Already green with the stub (see this suite's own header) and must stay
    /// green once the real predicate lands.
    @Test func aCaretOnTheLineImmediatelyAboveTheFenceRevealsNothing() {
        let caret = NSRange(location: 2, length: 0) // inside "prima"
        #expect(NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: caret) == nil)
    }

    /// The other boundary: the line right after the fence closes reveals nothing either.
    /// Already green with the stub and must stay green once the real predicate lands.
    @Test func aCaretOnTheLineImmediatelyBelowTheFenceRevealsNothing() {
        let caret = NSRange(location: ViewBlockCaretFixture.afterOffset + 1, length: 0) // inside "dopo"
        #expect(NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: caret) == nil)
    }

    /// ADR-0018 §D2's trigger 2 arriving by a different road (ADR §D4): a non-empty selection
    /// that starts outside the fence and ends inside it reveals the block, exactly as a caret
    /// already inside it would.
    @Test func aSelectionSpanningFromOutsideIntoTheFenceRevealsIt() {
        // Starts at offset 2, inside "prima" (outside the fence); 30 characters reaches offset
        // 32, inside "render: table" (the body line, inside the fence).
        let selection = NSRange(location: 2, length: 30)
        #expect(
            NoteTextView.Coordinator.revealedViewBlock(in: ViewBlockCaretFixture.note, selection: selection)
                == ViewBlockCaretFixture.fenceRange
        )
    }
}

// MARK: - Registration side effects of a revealed fence, and the re-render on exit (ADR §D4/§D5; Task 6)

/// Drives the full `applyStyling` pipeline through the same `editor(_:caret:)` fixture
/// `ViewBlockCaretRescue` uses above - these assertions are about registration side effects
/// (the marker, the hidden-line set, the host), not only the predicate, so a pure test cannot
/// reach them. Every test below is red against the current pipeline for the same reason:
/// `applyViewBlocks` does not yet consult `revealedViewBlock` at all (that wiring is Task 6's
/// own coder work), so a fence draws exactly the same whether the caret sits inside it or not.
@MainActor
@Suite struct ViewBlockRevealIntegration {
    /// R-05, first half: a revealed fence produces no marker, no hidden lines and no host - the
    /// raw source is on screen and the body line is back in the layout.
    @Test func aRevealedFenceProducesNoMarkerNoHiddenLinesAndNoHostAndLaysOutItsBodyLine() {
        let fixture = editor(ViewBlockCaretFixture.note, caret: ViewBlockCaretFixture.insideBodyLine)
        defer { fixture.window.orderOut(nil) }

        #expect(
            fixture.coordinator.drawnViewBlocks[ViewBlockCaretFixture.openingFenceOffset] == nil,
            "il fence rivelato ha comunque un host/marcatore registrato"
        )
        #expect(
            !fixture.coordinator.lastViewBlockLines.contains(ViewBlockCaretFixture.bodyLineOffset),
            "la riga del corpo è ancora nell'insieme delle righe nascoste"
        )
        #expect(
            !fixture.coordinator.lastViewBlockLines.contains(ViewBlockCaretFixture.closingFenceOffset),
            "la riga di chiusura è ancora nell'insieme delle righe nascoste"
        )
        let laidOut = laidOutOffsets(of: fixture.coordinator.decorations, text: ViewBlockCaretFixture.note)
        #expect(
            laidOut.contains(ViewBlockCaretFixture.bodyLineOffset),
            "la riga del corpo del fence rivelato non è nel layout"
        )
    }

    /// R-05, second half: editing the query while revealed and then moving the caret out
    /// re-registers the block against the **edited** source. The first assertion (still
    /// revealed, before the edit) is red for the same reason the test above is; the final
    /// assertion is already satisfiable today, since the current pipeline redraws on every
    /// edit regardless of the caret - it is included because it is part of R-05's own claim,
    /// not because it distinguishes red from green on its own. The method as a whole is red,
    /// because `#expect` failures do not short-circuit the rest of a Swift Testing test.
    @Test func movingTheCaretOutAfterEditingWhileRevealedRerendersAgainstTheEditedSource() {
        let fixture = editor(ViewBlockCaretFixture.note, caret: ViewBlockCaretFixture.insideBodyLine)
        defer { fixture.window.orderOut(nil) }

        #expect(
            fixture.coordinator.drawnViewBlocks[ViewBlockCaretFixture.openingFenceOffset] == nil,
            "il fence rivelato ha comunque un host/marcatore registrato prima della modifica"
        )

        // Edits the query while (nominally) revealed: "render: table" becomes "render: gallery".
        // The caret at `insideBodyLine` sits before "table" in the source, so the edit does not
        // invalidate it.
        let victim = (fixture.textView.string as NSString).range(of: "table")
        #expect(victim.location != NSNotFound, "premessa: la query da modificare deve esistere")
        #expect(
            fixture.textView.shouldChangeText(in: victim, replacementString: "gallery"),
            "premessa: la vista deve accettare la modifica"
        )
        fixture.textView.textStorage?.replaceCharacters(in: victim, with: "gallery")
        fixture.textView.didChangeText()

        // Moves the caret out of the fence entirely, onto "prima".
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: fixture.textView)
        )

        #expect(
            fixture.coordinator.drawnViewBlocks[ViewBlockCaretFixture.openingFenceOffset]?.source == "render: gallery",
            "il blocco non riflette la query modificata dopo l'uscita dal fence"
        )
    }

    /// SPEC Edge cases: "Multiple `pergamenum-view` blocks in one note... no shared state
    /// between them." A caret revealing the first fence must not touch the second: it stays
    /// drawn, marker and host both, exactly as it would if the first fence did not exist. Red
    /// today for the first fence's own reason (nothing is revealed yet); a regression this
    /// guards against once the coder's predicate lands is a global "something is revealed"
    /// flag that suppresses every fence instead of only the one containing the caret.
    @Test func revealingOneFenceLeavesTheOtherDrawn() {
        let fixture = editor(TwoViewBlockCaretFixture.note, caret: TwoViewBlockCaretFixture.insideFirstBody)
        defer { fixture.window.orderOut(nil) }

        #expect(
            fixture.coordinator.drawnViewBlocks[TwoViewBlockCaretFixture.firstOpening] == nil,
            "il primo fence rivelato ha comunque un host/marcatore registrato"
        )
        #expect(
            fixture.coordinator.drawnViewBlocks[TwoViewBlockCaretFixture.secondOpening]?.source == "render: gallery",
            "il secondo fence non è più disegnato mentre il primo è rivelato"
        )
        #expect(
            fixture.coordinator.lastViewBlockLines.contains(TwoViewBlockCaretFixture.secondBody),
            "la riga del corpo del secondo fence non è più nascosta: la rivelazione del primo ha soppresso anche lui"
        )
    }
}
