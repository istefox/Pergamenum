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
// `Coordinator.applyViewBlocks(to:runs:markers:&)` is **stubbed to do nothing**
// (`NoteTextView+ViewBlocks.swift`, Task 5's own tester declaration) and `applyStyling`
// (`NoteTextView+Coordinator.swift`) does not yet collect `.viewBlockRun` spans or call it at
// all - both the coder's wiring work. Every assertion below is therefore red: the pipeline
// this file drives, `Coordinator.applyStyling(to:theme:)`, does not touch a view block at all
// yet, so a caret placed inside the body line simply stays there.

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
