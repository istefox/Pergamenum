import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// The pointer over editor text (PG-219, #445, note-workflow R-09): an I-beam over text and a
// pointing hand over a link, decided by the view from the same `.editorLink` geometry hover
// and clicks already share, and handed to SwiftUI through `onPointerChange`, because AppKit's
// own cursor calls never reached the screen in this window (the CursorRects files' headers).
//
// What no test here can assert: the cursor the Window Server actually draws. That is a hand
// check on the Debug build (the plan's Task 8). What is asserted is the decision and the
// callback, which is everything the view owns.

private let tagText = "#client-acme"
private let dayText = ">2026-10-14"
private let wikilinkURL = MarkdownAttributedText.noteURL(for: "Destinazione")

/// A text view in an offscreen window, with the geometry the tracking areas read laid out.
@MainActor
private struct Host<TextView: NSTextView> {
    let view: TextView
    /// Kept alive for the length of the test; never ordered front.
    let window: NSWindow

    /// The view-space frame of `range`, the rectangle `linkTrackingAreas` is built from.
    func frame(of range: NSRange) -> CGRect {
        guard let layout = view.textLayoutManager, let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return .null }
        var union = CGRect.null
        layout.enumerateTextSegments(in: textRange, type: .standard) { _, segment, _, _ in
            union = union.union(segment)
            return true
        }
        guard !union.isNull else { return .null }
        let origin = view.textContainerOrigin
        return union.offsetBy(dx: origin.x, dy: origin.y)
    }

    func midpoint(of range: NSRange) -> NSPoint {
        let rect = frame(of: range)
        return NSPoint(x: rect.midX, y: rect.midY)
    }
}

/// What `onPointerChange` was called with, in order.
@MainActor
private final class PointerLog {
    var calls: [EditorPointer] = []
}

/// The geometry the pointer reads is there before the pointer is asked: a tracking area of the
/// view's own covers `point`. Green on the base, so a red below is the answer and not the fixture.
@MainActor
private func expectLinkArea(
    _ areas: [NSTrackingArea], covers point: NSPoint, _ word: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        areas.contains { $0.rect.contains(point) },
        "nessuna area di tracking copre «\(word)»", sourceLocation: sourceLocation
    )
}

private func range(of word: String, in text: String) -> NSRange {
    (text as NSString).range(of: word)
}

// MARK: - The note editor's view

@MainActor
private func noteEditor(text: String, linking word: String) throws -> Host<CompletingTextView> {
    let view = CompletingTextView(usingTextLayoutManager: true)
    view.textContainerInset = NSSize(width: 24, height: 20)
    view.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    view.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    view.string = text
    view.textStorage?.addAttribute(.editorLink, value: wikilinkURL, range: range(of: word, in: text))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    view.textLayoutManager?.ensureLayout(for: try #require(view.textLayoutManager).documentRange)
    view.layoutSubtreeIfNeeded()
    view.updateTrackingAreas()
    return Host(view: view, window: window)
}

/// The note editor's own styling pass puts the `.editorLink` run on a tag or a date, as it does
/// in the app (`TagDateClickTargetTests`' fixture).
@MainActor
private func styledNoteEditor(text: String) throws -> Host<CompletingTextView> {
    let fixture = EmbedEditorFixtures.editor(text: text, hidesMarkup: false, root: nil, thumbnails: nil)
    fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
    let layout = try #require(fixture.textView.textLayoutManager)
    layout.ensureLayout(for: layout.documentRange)
    fixture.textView.layoutSubtreeIfNeeded()
    fixture.textView.updateTrackingAreas()
    return Host(view: fixture.textView, window: fixture.window)
}

@MainActor
@Suite struct NoteEditorPointer {
    @Test func theAnswerIsLinkAtARunsMidpointAndTextOverPlainText() throws { // (note-workflow R-09)
        let text = "Prima di tutto vedi Destinazione e basta"
        let host = try noteEditor(text: text, linking: "Destinazione")

        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: "Destinazione", in: text)), "Destinazione")
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "Destinazione", in: text))) == .link)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "Prima", in: text))) == .text)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "basta", in: text))) == .text)
    }

    @Test func aCmdClickableTagIsALinkToThePointerToo() throws { // (note-workflow R-09)
        let text = "Vedi \(tagText) e poi basta"
        let host = try styledNoteEditor(text: text)
        // The run carries the editor's own link attribute, which is what the pointer reads.
        let storage = try #require(host.view.textStorage)
        #expect(storage.attribute(.editorLink, at: range(of: tagText, in: text).location, effectiveRange: nil) != nil)

        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: tagText, in: text)), tagText)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: tagText, in: text))) == .link)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "basta", in: text))) == .text)
    }

    @Test func aCmdClickableScheduledDateIsALinkToThePointerToo() throws { // (note-workflow R-09)
        let text = "- [ ] Fare \(dayText) e basta"
        let host = try styledNoteEditor(text: text)
        let storage = try #require(host.view.textStorage)
        #expect(storage.attribute(.editorLink, at: range(of: dayText, in: text).location, effectiveRange: nil) != nil)

        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: dayText, in: text)), dayText)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: dayText, in: text))) == .link)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "basta", in: text))) == .text)
    }

    @Test func trackingTheMouseReportsEachChangeOnceAndNeverARepeat() throws { // (note-workflow R-09)
        let text = "Prima di tutto vedi Destinazione e basta"
        let host = try noteEditor(text: text, linking: "Destinazione")
        let log = PointerLog()
        host.view.onPointerChange = { log.calls.append($0) }
        let overLink = host.midpoint(of: range(of: "Destinazione", in: text))
        let overText = host.midpoint(of: range(of: "Prima", in: text))
        expectLinkArea(host.view.linkTrackingAreas, covers: overLink, "Destinazione")

        host.view.trackPointer(at: overLink)
        host.view.trackPointer(at: overText)
        host.view.trackPointer(at: overText)

        #expect(log.calls == [.link, .text])
    }
}

// MARK: - The Workspace card's view

@MainActor
private func cardEditor(attributed: NSAttributedString) throws -> Host<FormattingTextView> {
    let view = FormattingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.textStorage?.setAttributedString(attributed)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    let layout = try #require(view.textLayoutManager)
    layout.ensureLayout(for: layout.documentRange)
    view.layoutSubtreeIfNeeded()
    view.updateTrackingAreas()
    return Host(view: view, window: window)
}

/// A card's text with one wikilink run, set by hand: the attribute is all the pointer reads.
@MainActor
private func cardEditor(text: String, linking word: String) throws -> Host<FormattingTextView> {
    let attributed = NSMutableAttributedString(string: text)
    attributed.addAttribute(.editorLink, value: wikilinkURL, range: range(of: word, in: text))
    return try cardEditor(attributed: attributed)
}

@MainActor
@Suite struct CardPointer {
    @Test func theAnswerIsLinkAtARunsMidpointAndTextOverPlainText() throws { // (note-workflow R-09)
        let text = "Prima di tutto vedi Destinazione e basta"
        let host = try cardEditor(text: text, linking: "Destinazione")

        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: "Destinazione", in: text)), "Destinazione")
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "Destinazione", in: text))) == .link)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "Prima", in: text))) == .text)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "basta", in: text))) == .text)
    }

    @Test func aCmdClickableTagAndDateAreLinksToThePointerToo() throws { // (note-workflow R-09)
        let text = "Vedi \(tagText) e - [ ] fare \(dayText) poi basta"
        let host = try cardEditor(attributed: CardTextAttributes.attributed(text, theme: .emergency))

        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: tagText, in: text)), tagText)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: tagText, in: text))) == .link)
        expectLinkArea(host.view.linkTrackingAreas, covers: host.midpoint(of: range(of: dayText, in: text)), dayText)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: dayText, in: text))) == .link)
        #expect(host.view.pointer(at: host.midpoint(of: range(of: "basta", in: text))) == .text)
    }

    @Test func trackingTheMouseReportsEachChangeOnceAndNeverARepeat() throws { // (note-workflow R-09)
        let text = "Prima di tutto vedi Destinazione e basta"
        let host = try cardEditor(text: text, linking: "Destinazione")
        let log = PointerLog()
        host.view.onPointerChange = { log.calls.append($0) }
        let overLink = host.midpoint(of: range(of: "Destinazione", in: text))
        let overText = host.midpoint(of: range(of: "Prima", in: text))
        expectLinkArea(host.view.linkTrackingAreas, covers: overLink, "Destinazione")

        host.view.trackPointer(at: overLink)
        host.view.trackPointer(at: overText)
        host.view.trackPointer(at: overText)

        #expect(log.calls == [.link, .text])
    }
}

// MARK: - The SwiftUI style

@Suite struct EditorPointerStyle {
    // `PointerStyle` is not `Equatable`, so the styles are compared by what they print:
    // `PointerStyle(value: link)` and `PointerStyle(value: horizontalText)`.
    @Test func theLinkIsThePointingHandAndTheTextIsTheIBeam() { // (note-workflow R-09)
        #expect(String(describing: EditorPointer.link.style) == String(describing: PointerStyle.link))
        #expect(
            String(describing: EditorPointer.text.style) == String(describing: PointerStyle.horizontalText)
        )
    }
}
