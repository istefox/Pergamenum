import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// R-20 (ADR-0083 §D7): the production presenter's configuration and its two documented refusals,
/// and the keyboard-loss rule the controller samples around a show. No popover is ever shown on
/// screen here: `NSPopover.show` is never reached, which is exactly what the refusals assert.
@MainActor
@Suite struct LinkPreviewPopoverConfiguration {
    private static let content = LinkPreviewContent(kind: .board(name: "Piano"))

    @Test func theBehaviourIsApplicationDefinedSoNothingDismissesItBehindTheEditorsBack() {
        #expect(LinkPreviewPopover().popover.behavior == .applicationDefined)
    }

    @Test func itDoesNotAnimate() {
        #expect(LinkPreviewPopover().popover.animates == false)
    }

    @Test func itsContentIsAHostedLinkPreviewView() {
        let controller = LinkPreviewPopover().popover.contentViewController
        #expect(controller is NSHostingController<LinkPreviewView>)
    }

    @Test func aTextViewWithNoWindowIsRefusedWithoutShowing() {
        let presenter = LinkPreviewPopover()
        let textView = CompletingTextView(usingTextLayoutManager: true)

        let shown = presenter.show(Self.content, anchoredTo: NSRect(x: 0, y: 0, width: 40, height: 14), in: textView)

        #expect(!shown)
        #expect(!presenter.popover.isShown)
        #expect(!presenter.isShowing)
    }

    @Test func anEmptyRectIsRefusedWithoutShowing() {
        let presenter = LinkPreviewPopover()
        let fixture = EmbedEditorFixtures.editor(text: "Vedi [[A]]", hidesMarkup: false, root: nil, thumbnails: nil)

        let shown = presenter.show(Self.content, anchoredTo: .zero, in: fixture.textView)

        #expect(!shown)
        #expect(!presenter.popover.isShown)
    }

    @Test func hidingAPresenterThatWasNeverShownIsANoOp() {
        let presenter = LinkPreviewPopover()

        presenter.hide()

        #expect(!presenter.isShowing)
        #expect(!presenter.popover.isShown)
    }
}

@Suite struct LinkPreviewFocusRule {
    private static func focus(_ key: Bool, _ responder: Bool) -> LinkPreviewFocus {
        LinkPreviewFocus(windowIsKey: key, textViewIsFirstResponder: responder)
    }

    @Test func theWindowNoLongerBeingKeyIsALoss() {
        #expect(LinkPreviewFocus.lostKeyboard(before: Self.focus(true, true), after: Self.focus(false, true)))
    }

    @Test func theTextViewNoLongerBeingFirstResponderIsALoss() {
        #expect(LinkPreviewFocus.lostKeyboard(before: Self.focus(true, true), after: Self.focus(true, false)))
    }

    @Test func bothGoneIsALoss() {
        #expect(LinkPreviewFocus.lostKeyboard(before: Self.focus(true, true), after: Self.focus(false, false)))
    }

    @Test func nothingChangedIsNotALoss() {
        #expect(!LinkPreviewFocus.lostKeyboard(before: Self.focus(true, true), after: Self.focus(true, true)))
    }

    @Test func nothingHeldBeforeIsNotALoss() {
        #expect(!LinkPreviewFocus.lostKeyboard(before: Self.focus(false, false), after: Self.focus(false, false)))
        #expect(!LinkPreviewFocus.lostKeyboard(before: Self.focus(false, false), after: Self.focus(true, true)))
    }
}
