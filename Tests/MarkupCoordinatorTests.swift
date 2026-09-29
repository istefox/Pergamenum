import AppKit
import Testing
@testable import Pergamenum

// MARK: - Coordinator-level (ADR-0018)

/// Driven through a real `NSTextView` offscreen, like `SpellCheckTests`'s
/// `spellingState(over:in:)` and `FoldBadgeClickTests`'s `editor(folded:onToggleFold:)`:
/// `applyStyling` and `applyReveal` are methods of `NoteTextView.Coordinator`, and the
/// fastest way to lie to a test is to reimplement the thing it is checking.
@MainActor
@Suite struct MarkupCoordinator {
    private static let threeHeadingNote = "# Uno\ncorpo **uno**\n# Due\ncorpo due\n# Tre\ncorpo tre\n"

    private static func editor(hidesMarkup: Bool) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(threeHeadingNote), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = threeHeadingNote
        coordinator.applyStyling(to: textView, theme: .emergency)
        // `applyStyling` rewrites every attribute in the storage, and on a headless text
        // view with no window that leaves the selection at the very end of the text
        // rather than at the start - a harness artifact, not something the running app
        // does (its own call sites manage the selection separately). Pinned here so the
        // reveal tests below start from a known caret.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return (textView, coordinator)
    }

    /// "# Due"'s own paragraph start, for tests that need a genuine selection change.
    /// "# Uno\n" (6) + "corpo **uno**\n" (14).
    private static let headingDue = 20

    @Test func stylingAThreeHeadingNotePopulatesAllDelegateEntries() {
        let (_, coordinator) = Self.editor(hidesMarkup: true)
        // Three heading markers plus the two `**` delimiters of "**uno**".
        #expect(coordinator.decorations.hiddenMarkerCount == 5)
    }

    @Test func callingApplyRevealTwiceWithoutASelectionChangeDoesNotReinvalidateTheSecondTime() throws {
        let (textView, coordinator) = Self.editor(hidesMarkup: true)
        let storage = try #require(textView.textStorage)

        // `NSTextStorageDidProcessEditing` is what `storage.edited(…)` plus `endEditing()`
        // fires - the observable half of "did this actually touch the layout", the same
        // way `SpellCheckTests` reads the layout manager's rendering attribute rather than
        // trusting the delegate's own return value.
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        // A genuine change first, so what follows tests a real transition rather than two
        // no-ops in a row. `setSelectedRange` fires `textViewDidChangeSelection` - the same
        // path a real arrow key takes - which is wired to call `applyReveal` itself.
        textView.setSelectedRange(NSRange(location: Self.headingDue, length: 0))
        let afterTheChange = counter.count
        #expect(afterTheChange > 0)

        // The same selection again: nothing moved, so the second call must be a no-op.
        coordinator.applyReveal(to: textView)
        #expect(counter.count == afterTheChange)
    }

    /// Principle 1, checked at the coordinator level rather than only in
    /// `MarkdownStylerTests` and `MarkupHidingTests`: styling and revealing a note must
    /// never touch `textView.string`, whatever else they change about how it is drawn.
    @Test func theStringIsByteIdenticalAfterStylingAndReveal() {
        let (textView, coordinator) = Self.editor(hidesMarkup: true)
        coordinator.applyReveal(to: textView)
        #expect(textView.string == Self.threeHeadingNote)
    }
}

/// `NotificationCenter`'s handler closure is `@Sendable`, and every call in this file
/// happens synchronously on the main actor anyway - the observer fires from inside
/// `storage.endEditing()`, called directly by `applyReveal` above. `@unchecked Sendable`
/// says so, rather than fighting the compiler over a `var` a `@Sendable` closure cannot
/// capture.
private final class NotificationCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

// MARK: - The note editor's own wiring (ADR-0037 §D6/§D7; plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 5)
//
// Drives a real `NoteTextView.Coordinator` + `NSTextView`, the shape `MarkupCoordinator`
// above already uses. `EditorDecorationDelegate.revealedSpans` has no test accessor - that
// file is out of this task's budget (ADR-0049) - so "the span table names exactly one
// paragraph key with exactly one range" is read back through `coordinator.reveal.lastRevealedSpans`
// instead: it is assigned the very value handed to `decorations.apply(revealedSpans:)` right
// before that call, in `NoteTextView+Reveal.swift`, so the two can never disagree.
@MainActor
@Suite struct MarkupCoordinatorInlineSpans {
    /// Two bold runs, neither touching the note's very first character - unlike
    /// `MarkupHidingInlineSpans`'s "**uno** e **due**\n" fixture, whose first run starts at
    /// offset 0 and would already be (adjacency-)revealed by the harness's own baseline
    /// caret placement (ADR §D5's closed interval), leaving a test that moves the caret
    /// *into* that run unable to observe a real transition.
    private static let note = "inizio **uno** e **due** fine\n"
    /// Inside "uno", well within the first run's whole construct `[7, 14)`.
    private static let insideFirstRun = 10
    /// "e" between the two runs: 15 > `NSMaxRange(firstBoldSpan)` (14) and 15 < the second
    /// run's own start (17).
    private static let outsideBothRuns = 15
    private static let firstBoldSpan = NSRange(location: 7, length: 7)

    private static func editor(revealsInlineSpans: Bool) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, revealsInlineSpans: revealsInlineSpans, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = Self.note
        coordinator.applyStyling(to: textView, theme: .emergency)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return (textView, coordinator)
    }

    @Test func aCaretInsideOneBoldRunNamesExactlyThatParagraphAndSpan() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))

        #expect(coordinator.reveal.lastRevealedSpans.count == 1)
        #expect(coordinator.reveal.lastRevealedSpans[0] == [Self.firstBoldSpan])
    }

    @Test func movingTheCaretOutOfBothRunsEmptiesTheTable() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        #expect(!coordinator.reveal.lastRevealedSpans.isEmpty)

        textView.setSelectedRange(NSRange(location: Self.outsideBothRuns, length: 0))
        #expect(coordinator.reveal.lastRevealedSpans.isEmpty)
    }

    @Test func flippingTheSettingOffWithTheCaretStillInsideARunEmptiesTheTable() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        #expect(!coordinator.reveal.lastRevealedSpans.isEmpty)

        // The caret never moves - only the setting does, so nothing but the flag flip can
        // be what empties the table.
        coordinator.parent.revealsInlineSpans = false
        coordinator.applyReveal(to: textView)
        #expect(coordinator.reveal.lastRevealedSpans.isEmpty)
    }

    @Test func callingApplyRevealTwiceWithoutASelectionChangeInvalidatesNothingTheSecondTime() throws {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        let storage = try #require(textView.textStorage)

        // Same mechanism as `MarkupCoordinator`'s own test above: the notification is what
        // `storage.edited(…)` plus `endEditing()` fires, the observable half of "did this
        // actually touch the layout".
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        // A genuine change first - moving into the first run touches the span table, unlike
        // `MarkupCoordinator`'s heading-only fixture.
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        let afterTheChange = counter.count
        #expect(afterTheChange > 0)

        // The same selection again, with the setting also unchanged: both `lastRevealed`
        // and `lastRevealedSpans` must already match, so this call is a no-op.
        coordinator.applyReveal(to: textView)
        #expect(counter.count == afterTheChange)
    }
}
