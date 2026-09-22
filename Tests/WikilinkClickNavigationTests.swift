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
    @Test func aPlainClickIsRefusedAndACmdClickFollowsTheSameLink() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        // No Cmd held: AppKit's own automatic gesture can and does call this delegate
        // method unprompted (the comment above `textView(_:clickedOnLink:at:)` explains
        // why), and it must refuse to navigate - the whole of issue #188's fix.
        coordinator.modifierFlags = { [] }
        let refused = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(!refused)
        #expect(fixture.followedLinks.titles.isEmpty)

        // Cmd held, read live at the moment the method runs - the same closure, a
        // different answer.
        coordinator.modifierFlags = { .command }
        let followed = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(followed)
        #expect(fixture.followedLinks.titles == ["Destinazione"])
    }

    @Test func otherModifiersHeldWithoutCommandStillRefuse() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        coordinator.modifierFlags = { [.shift, .option] }
        let refused = coordinator.textView(fixture.textView, clickedOnLink: url, at: 5)
        #expect(!refused)
        #expect(fixture.followedLinks.titles.isEmpty)
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
            .link, value: MarkdownAttributedText.noteURL(for: "Destinazione"),
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
