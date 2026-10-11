import AppKit
import Testing
@testable import Pergamenum

// PG-219, R-05, R-06 (route C, ADR-0090): what a text view applies reaches `NSCursor.current`.
//
// The two text views decide through `pointer(at:)` and `EditorPointer.apply()` draws, from
// `cursorUpdate(with:)` and again after `super.mouseMoved(with:)`. A synthetic event does not
// reproduce NSTextView's own I-beam reset, so the sequence over a moving real mouse is the hand
// check's (ADR-0090 §D9); what is pinned here is the mapping and the one door both views use.

@MainActor
@Suite struct EditorPointerCursorMapping {
    @Test func eachPointerIsItsOwnCursor() { // (R-06)
        #expect(EditorPointer.text.cursor == NSCursor.iBeam)
        #expect(EditorPointer.link.cursor == NSCursor.pointingHand)
    }

    @Test func applyMakesTheCursorTheCurrentOne() { // (R-06)
        NSCursor.arrow.set()
        EditorPointer.link.apply()
        #expect(NSCursor.current == NSCursor.pointingHand)
        EditorPointer.text.apply()
        #expect(NSCursor.current == NSCursor.iBeam)
        NSCursor.arrow.set()
    }
}

@MainActor
@Suite struct NoteEditorAppliesThePointer {
    private static let text = "riga semplice abbastanza lunga\n[[Seconda nota]]"

    @Test func aLinkAppliesTheHandAndPlainTextTheIBeam() throws { // (R-06)
        let fixture = PointerFixtures.note(text: Self.text)
        let textView = fixture.textView
        PointerFixtures.layOut(textView)
        let link = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: textView))
        let plain = try #require(PointerFixtures.midpoint(of: "riga semplice", in: textView))

        NSCursor.arrow.set()
        #expect(textView.applyPointer(at: link) == .link)
        #expect(NSCursor.current == NSCursor.pointingHand)

        #expect(textView.applyPointer(at: plain) == .text)
        #expect(NSCursor.current == NSCursor.iBeam)
    }

    @Test func nothingIsAppliedOutsideTheView() { // (R-05)
        let fixture = PointerFixtures.note(text: Self.text)
        let textView = fixture.textView
        PointerFixtures.layOut(textView)
        NSCursor.arrow.set()
        let outside = CGPoint(x: -20, y: -20)
        #expect(textView.applyPointer(at: outside) == nil)
        #expect(NSCursor.current == NSCursor.arrow)
    }
}

/// The overrides themselves, in a window that is not key (ADR-0090 §D4). The fixtures' windows are
/// offscreen and never key, so a hand over a link here could only come from a missing guard. That the
/// overrides do apply in a key window, and in what order, is the hand check's.
@MainActor
@Suite struct TheOverridesLeaveANonKeyWindowAlone {
    private static func event(_ type: NSEvent.EventType, at point: CGPoint, in textView: NSView, window: NSWindow) throws -> NSEvent {
        let location = textView.convert(point, to: nil)
        switch type {
        case .cursorUpdate:
            return try #require(NSEvent.enterExitEvent(
                with: .cursorUpdate, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            ))
        default:
            return try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
        }
    }

    @Test func aNoteEditorAppliesNothingFromCursorUpdateOrMouseMoved() throws { // (R-06)
        let fixture = PointerFixtures.note(text: "riga semplice\n[[Seconda nota]]")
        let textView = fixture.textView
        PointerFixtures.layOut(textView)
        try #require(!fixture.window.isKeyWindow, "the fixture window is key: the case proves nothing")
        let link = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: textView))
        // Control: the same point answers `.link` when asked directly.
        try #require(textView.pointer(at: link) == .link)

        NSCursor.arrow.set()
        textView.cursorUpdate(with: try Self.event(.cursorUpdate, at: link, in: textView, window: fixture.window))
        #expect(NSCursor.current != NSCursor.pointingHand)
        NSCursor.arrow.set()
        textView.mouseMoved(with: try Self.event(.mouseMoved, at: link, in: textView, window: fixture.window))
        #expect(NSCursor.current != NSCursor.pointingHand)
        NSCursor.arrow.set()
    }

    @Test func aCardAppliesNothingFromCursorUpdateOrMouseMoved() throws { // (R-06)
        let card = PointerFixtures.card(text: "riga semplice\n[[Seconda nota]]", editable: true)
        PointerFixtures.layOut(card.textView)
        try #require(!card.window.isKeyWindow, "the fixture window is key: the case proves nothing")
        let link = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: card.textView))
        try #require(card.textView.pointer(at: link) == .link)

        NSCursor.arrow.set()
        card.textView.cursorUpdate(with: try Self.event(.cursorUpdate, at: link, in: card.textView, window: card.window))
        #expect(NSCursor.current != NSCursor.pointingHand)
        NSCursor.arrow.set()
        card.textView.mouseMoved(with: try Self.event(.mouseMoved, at: link, in: card.textView, window: card.window))
        #expect(NSCursor.current != NSCursor.pointingHand)
        NSCursor.arrow.set()
    }
}

@MainActor
@Suite struct CardAppliesThePointer {
    private static let text = "riga semplice\n[[Seconda nota]]"

    @Test func anEditableCardAppliesTheHandOnALinkAndTheIBeamOnText() throws { // (R-06)
        let card = PointerFixtures.card(text: Self.text, editable: true)
        PointerFixtures.layOut(card.textView)
        let link = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: card.textView))
        let plain = try #require(PointerFixtures.midpoint(of: "riga semplice", in: card.textView))

        NSCursor.arrow.set()
        #expect(card.textView.applyPointer(at: link) == .link)
        #expect(NSCursor.current == NSCursor.pointingHand)
        #expect(card.textView.applyPointer(at: plain) == .text)
        #expect(NSCursor.current == NSCursor.iBeam)
    }

    @Test func aCardNotBeingEditedAppliesNothing() throws { // (R-05)
        let card = PointerFixtures.card(text: Self.text, editable: false)
        PointerFixtures.layOut(card.textView)
        let link = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: card.textView))
        NSCursor.arrow.set()
        #expect(card.textView.applyPointer(at: link) == nil)
        #expect(NSCursor.current == NSCursor.arrow)
    }
}
