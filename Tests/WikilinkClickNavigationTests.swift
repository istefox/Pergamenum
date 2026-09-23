import AppKit
import Testing
@testable import Pergamenum

/// Cmd+click and "Apri collegamento" (issue #188, R-07), driven against real AppKit.
///
/// `Coordinator.modifierFlags` (ADR-0053 §D2 seam #4) is what makes the first suite below
/// possible: before the seam, `textView(_:clickedOnLink:at:)` read the live
/// `NSEvent.modifierFlags` directly, which no test can hold at a fixed value without a real
/// mouse. `EmbedEditorFixtures.editor(...)`'s `followedLinks` (`LinkFollowSpy`) is the other
/// half - it captures what `onFollowLink` was called with instead of the fixture's old
/// `{ _ in }` discard, so "did it navigate" is a value read back rather than a side effect
/// with nowhere to land.
@MainActor
@Suite struct WikilinkClickNavigation {
    @Test func aPlainClickDoesNotNavigateAndACmdClickFollowsTheSameLink() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        // No Cmd held: this method is never invoked by AppKit on its own any more (issue
        // #191, `.editorLink`'s doc comment has the full history - clickable spans no
        // longer carry the standard `.link` AppKit keys its own automatic gesture off of),
        // so the only caller is this app's own Cmd-gated `followLinkIfPresent(at:)`. The
        // `false`/`true` returned here are back to their plain `NSTextViewDelegate` meaning
        // ("did this navigate"), with no `NSWorkspace.open(url)` fallback to defend against.
        coordinator.modifierFlags = { [] }
        let navigated = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(!navigated)
        #expect(fixture.followedLinks.titles.isEmpty)

        // Cmd held, read live at the moment the method runs - the same closure, a
        // different answer.
        coordinator.modifierFlags = { .command }
        let followed = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(followed)
        #expect(fixture.followedLinks.titles == ["Destinazione"])
    }

    @Test func otherModifiersHeldWithoutCommandDoNotNavigate() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        coordinator.modifierFlags = { [.shift, .option] }
        let navigated = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(!navigated)
        #expect(fixture.followedLinks.titles.isEmpty)
    }
}

/// `CompletingTextView.placeCaretForPlainClick(at:)` (issue #191): a plain single click on
/// link-attributed text must place the caret and reveal-on-caret on that first click, since
/// `applyReveal`'s only trigger is the selection-changed notification `setSelectedRange`
/// posts. Every prior reveal test is pure `MarkupReveal`/`InlineSpanReveal` arithmetic with no
/// `NSTextView`, and `WikilinkClickNavigation` above bypasses reveal entirely by calling the
/// delegate method directly - this suite is the first to assert the two meet.
@MainActor
@Suite struct WikilinkPlainClickCaretReveal {
    @Test func aPlainClickOnAWikilinkTargetPlacesTheCaretAndReveals() {
        let fixture = Self.wikilinkFixture()
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        // This window is never ordered front (`EmbedEditorFixtures.editor`'s own doc
        // comment), so nothing has yet forced the legacy `NSLayoutManager` bridge
        // `characterIndexForInsertion(at:)` reads through to sync with the TextKit 2
        // layout `fragmentFrame` above already computed - without this, the first
        // hit-test in a test run resolves past the last character (measured: index equal
        // to the string's own length) and only a second one, after this sync, lands
        // inside the word. A real, visible window's own display pass already does this
        // before any click reaches it, so production code needs no equivalent call.
        fixture.textView.layoutSubtreeIfNeeded()

        let placed = fixture.textView.placeCaretForPlainClick(at: CGPoint(x: frame.midX, y: frame.midY))

        #expect(placed)
        let selection = fixture.textView.selectedRange()
        #expect(selection.length == 0)
        #expect(selection.location < (fixture.textView.string as NSString).length)
        #expect(fixture.coordinator.decorations.revealedParagraphs.contains(0))
    }

    @Test func aPlainClickOnACommonMarkLinkLabelPlacesTheCaretAndReveals() {
        // A one-word line carrying a real `.editorLink`, the same shape `clickable(...)`
        // produces for a CommonMark label's own span (`MarkdownAttributedText.swift:104-141`)
        // - the attribute is what the fix and this test key on, not the raw `[text](url)`
        // source.
        let fixture = EmbedEditorFixtures.editor(
            text: "testo", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textStorage?.addAttribute(
            .editorLink, value: URL(string: "https://example.com")!,
            range: NSRange(location: 0, length: (fixture.textView.string as NSString).length)
        )
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        fixture.textView.layoutSubtreeIfNeeded() // see the comment above, same reason

        let placed = fixture.textView.placeCaretForPlainClick(at: CGPoint(x: frame.midX, y: frame.midY))

        #expect(placed)
        #expect(fixture.coordinator.decorations.revealedParagraphs.contains(0))
    }

    @Test func aPlainClickAwayFromAnyLinkPlacesNothing() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Nessun link qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)

        let placed = fixture.textView.placeCaretForPlainClick(at: CGPoint(x: frame.midX, y: frame.midY))

        #expect(!placed)
    }

    /// The reflow case (issue #191 follow-up): click 1 reveals `[[…]]`, which pushes every
    /// glyph after it sideways, so click 2 at the same screen point resolves elsewhere.
    /// `selectRevealedLink(clickCount:)` must select from the *stored* index instead - proved
    /// here by never handing it a point at all, only the index click 1 recorded.
    ///
    /// Driven through the helper directly, never through `mouseDown`: `NSTextView.mouseDown`
    /// runs its own nested mouse-tracking loop until a `mouseUp` arrives, which a unit test
    /// has no way to deliver - calling it would hang the suite rather than fail it.
    @Test func aDoubleClickSelectsTheWordAtTheIndexTheFirstClickStored() {
        let fixture = Self.wikilinkFixture()
        fixture.textView.layoutSubtreeIfNeeded()
        // What `mouseDown`'s click-1 branch records, taken from the link's own range rather
        // than from a point, so the assertion below cannot pass by the point happening to
        // resolve correctly.
        fixture.textView.revealedLinkClick = 4
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let selected = fixture.textView.selectRevealedLink(clickCount: 2)

        #expect(selected)
        let selection = fixture.textView.selectedRange()
        #expect(selection.length == (fixture.textView.string as NSString).length)
        #expect(selection.location == 0)
    }

    @Test func aStaleStoredIndexSelectsNothingAndLeavesTheSelectionAlone() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Nessun link qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        // An index with no `.editorLink` at it - a value the text moved on from. The guard
        // must degrade to "not handled", so the caller falls through to `super`.
        fixture.textView.revealedLinkClick = 3
        let before = NSRange(location: 2, length: 0)
        fixture.textView.setSelectedRange(before)

        let selected = fixture.textView.selectRevealedLink(clickCount: 2)

        #expect(!selected)
        #expect(fixture.textView.selectedRange() == before)
    }

    /// A one-word line with a real `.editorLink` over its own whole range -
    /// `WikilinkContextMenu.linkedFixture()`'s shape, wired the same way so a click
    /// anywhere on the fragment resolves inside the link.
    private static func wikilinkFixture() -> EmbedEditorFixtures.Fixture {
        let fixture = EmbedEditorFixtures.editor(
            text: "Destinazione", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textStorage?.addAttribute(
            .editorLink, value: MarkdownAttributedText.noteURL(for: "Destinazione"),
            range: NSRange(location: 0, length: (fixture.textView.string as NSString).length)
        )
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        return fixture
    }
}

/// `CompletingTextView.menu(for:)` and "Apri collegamento" (R-07/R-08): a real right-click
/// event, called directly on the view the way AppKit itself would dispatch it - never
/// through `NSApp.sendEvent`/`window.sendEvent`, which R-15 forbids (ADR-0053 §D1's "no
/// test-only door" is the same rule read the other way: this is the production method,
/// called the way `doCommand(by:)` already is throughout this suite).
@MainActor
@Suite struct WikilinkContextMenu {
    /// A one-word line so any point inside its own laid-out fragment resolves, via
    /// `characterIndexForInsertion(at:)`, to an index inside the link's own range - there
    /// is nothing else on the line for it to land on.
    private static func linkedFixture() -> EmbedEditorFixtures.Fixture {
        let fixture = EmbedEditorFixtures.editor(
            text: "Destinazione", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textStorage?.addAttribute(
            .editorLink, value: MarkdownAttributedText.noteURL(for: "Destinazione"),
            range: NSRange(location: 0, length: (fixture.textView.string as NSString).length)
        )
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        return fixture
    }

    private static func rightMouseDownEvent(
        at point: CGPoint, in fixture: EmbedEditorFixtures.Fixture
    ) -> NSEvent {
        // `point` arrives in `textView`'s own *flipped* view coordinates - what
        // `EmbedEditorFixtures.fragmentFrame` returns (its own doc comment). `NSEvent
        // .locationInWindow` is always the window's own base coordinate system, which is
        // never flipped regardless of what sits underneath it in the view hierarchy - so
        // handing it the raw view-local point landed a right-click near the *bottom* of an
        // 800pt-tall never-shown window instead of on the one-line fragment near its top,
        // confirmed by printing both `point` and `textView.convert(point, from: nil)` side
        // by side (measured, not assumed). Converting through the text view itself
        // (`convert(_:to: nil)`, view → window) is what `menu(for:)`'s own `convert(
        // event.locationInWindow, from: nil)` (window → view) is built to invert.
        let windowPoint = fixture.textView.convert(point, to: nil)
        return NSEvent.mouseEvent(
            with: .rightMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1
        )!
    }

    @Test func aRightClickOverTheLinkOffersApriCollegamentoFirst() {
        let fixture = Self.linkedFixture()
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        let event = Self.rightMouseDownEvent(at: CGPoint(x: frame.midX, y: frame.midY), in: fixture)

        let menu = fixture.textView.menu(for: event)
        #expect(menu?.items.first?.title == "Apri collegamento")
    }

    @Test func aRightClickAwayFromAnyLinkOffersNoApriCollegamento() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Nessun link qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.textView.delegate = fixture.coordinator
        fixture.textView.textLayoutManager?.ensureLayout(
            for: fixture.textView.textLayoutManager!.documentRange
        )
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        let event = Self.rightMouseDownEvent(at: CGPoint(x: frame.midX, y: frame.midY), in: fixture)

        let menu = fixture.textView.menu(for: event)
        #expect(menu?.items.contains { $0.title == "Apri collegamento" } != true)
    }

    @Test func openLinkFromMenuNavigatesWithNoCmdHeld() {
        let fixture = Self.linkedFixture()
        // No Cmd anywhere in this test - «Apri collegamento» is the non-modifier
        // alternative to Cmd+click (R-07) and must not need `modifierFlags` at all.
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        let event = Self.rightMouseDownEvent(at: CGPoint(x: frame.midX, y: frame.midY), in: fixture)

        let item = fixture.textView.menu(for: event)?.items.first { $0.title == "Apri collegamento" }
        #expect(item != nil)
        guard let item, let action = item.action else { return }
        _ = fixture.textView.perform(action, with: item)

        #expect(fixture.followedLinks.titles == ["Destinazione"])
    }
}
