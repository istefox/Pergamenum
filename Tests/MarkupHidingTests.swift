import AppKit
import Testing
@testable import Pergamenum

/// ADR-0018 §D1's mechanism, offscreen: hiding a heading's `#` marker (and the space
/// after it) costs no width and leaves the line height unchanged - the same kind of fact
/// `TransclusionLayoutTests` measured for the sibling mechanism that reserves space
/// instead of removing it, and the one `docs/20260817_TextKit2_live_editing.md` first
/// measured (32.12pt recovered over 4 hidden characters via a 0.01pt font).
///
/// Driven against the real `EditorDecorationDelegate`, not a test double: unlike
/// `TransclusionLayoutTests`'s `SpacingDelegate`, this hook carries logic worth testing on
/// its own account - the setting's on/off switch, the reveal set, and the re-check that
/// keeps a stale table from collapsing prose.

private struct Frame {
    let offset: Int
    let frame: CGRect
}

@MainActor
private func frames(
    text: String,
    markers: [Int: NSRange],
    hidesMarkup: Bool,
    revealed: Set<Int> = []
) -> (frames: [Frame], length: Int) {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    let delegate = EditorDecorationDelegate()
    delegate.apply(headingMarkers: markers, hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var collected: [Frame] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        collected.append(Frame(offset: offset, frame: fragment.layoutFragmentFrame))
        return true
    }
    // The length is the whole point: the file must not gain or lose a character.
    return (collected, content.textStorage?.length ?? -1)
}

/// Drives the hook by hand over the first paragraph of `note`, the way AppKit itself
/// would when laying it out - for the tests that check the hook's return value directly
/// rather than a measured frame.
@MainActor
private func substitutedParagraph(_ delegate: EditorDecorationDelegate, note: String) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
    return delegate.textContentStorage(storage, textParagraphWith: range)
}

@MainActor
@Suite struct MarkupHiding {
    private static let note = "# Titolo\ncorpo\n"
    private static let headingOffset = 0
    /// "# " - the hash and the one space after it, relative to the paragraph's own start.
    private static let marker = NSRange(location: 0, length: 2)

    @Test func aCollapsedMarkerCostsNoWidth() {
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
            text: Self.note, markers: [Self.headingOffset: Self.marker], hidesMarkup: true
        )

        let baseHeading = base.frames.first { $0.offset == Self.headingOffset }?.frame
        let collapsedHeading = collapsed.frames.first { $0.offset == Self.headingOffset }?.frame
        #expect(baseHeading != nil)
        #expect(collapsedHeading != nil)
        #expect((collapsedHeading?.width ?? 0) < (baseHeading?.width ?? 0))
        // Never a character added or removed, whatever is drawn.
        #expect(base.length == collapsed.length)
    }

    @Test func lineHeightIsUnchangedByTheCollapse() {
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
            text: Self.note, markers: [Self.headingOffset: Self.marker], hidesMarkup: true
        )

        let baseHeading = base.frames.first { $0.offset == Self.headingOffset }?.frame
        let collapsedHeading = collapsed.frames.first { $0.offset == Self.headingOffset }?.frame
        #expect(collapsedHeading?.height == baseHeading?.height)
    }

    @Test func theHookReturnsNilForARevealedParagraph() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(headingMarkers: [Self.headingOffset: Self.marker], hidingMarkup: true)
        _ = delegate.apply(revealedParagraphs: [Self.headingOffset])

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
    }

    @Test func aStaleTableEntryDoesNotCollapseProse() {
        // The table still says a heading marker sits at offset 0, but the text there has
        // since become plain prose - the last styling pass has not caught up with this
        // layout pass yet.
        let delegate = EditorDecorationDelegate()
        delegate.apply(headingMarkers: [0: NSRange(location: 0, length: 2)], hidingMarkup: true)

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(headingMarkers: [Self.headingOffset: Self.marker], hidingMarkup: false)

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
    }
}

// MARK: - Coordinator-level (ADR-0018)

/// Driven through a real `NSTextView` offscreen, like `SpellCheckTests`'s
/// `spellingState(over:in:)` and `FoldBadgeClickTests`'s `editor(folded:onToggleFold:)`:
/// `applyStyling` and `applyReveal` are methods of `NoteTextView.Coordinator`, and the
/// fastest way to lie to a test is to reimplement the thing it is checking.
@MainActor
@Suite struct MarkupCoordinator {
    private static let threeHeadingNote = "# Uno\ncorpo uno\n# Due\ncorpo due\n# Tre\ncorpo tre\n"

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
    private static let headingDue = 16

    @Test func stylingAThreeHeadingNotePopulatesThreeDelegateEntries() {
        let (_, coordinator) = Self.editor(hidesMarkup: true)
        #expect(coordinator.decorations.headingMarkerCount == 3)
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
