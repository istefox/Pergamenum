import AppKit
import Testing
@testable import Pergamenum

// A click on a task line's checkbox glyph toggles its state without ever exposing the
// raw `- [ ]` syntax (PG-101-adjacent chain, `NoteTextView+CheckboxClick.swift`).
//
// Driven through a real `NSTextView` offscreen, the same shape `FoldBadgeClickTests` uses
// for the same reason: the glyph's rectangle is in the text container's coordinates and a
// click arrives in the view's, so a hit test built without going through real layout looks
// exactly like a feature that was never wired.

@MainActor
@Suite struct CheckboxToggle {
    private static func editor(note: String) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = note
        coordinator.applyStyling(to: textView, theme: .emergency)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return (textView, coordinator)
    }

    /// The glyph's rectangle, in the view's coordinates - what a click carries. `stateOffset`
    /// is the marker's own fourth character (`- [x]`: dash, space, bracket, state, bracket),
    /// always 3 for an unindented task line.
    private static func glyphRect(in textView: NSTextView, stateOffset: Int = 3) -> CGRect {
        guard let manager = textView.textLayoutManager,
              let start = manager.location(manager.documentRange.location, offsetBy: stateOffset),
              let end = manager.location(start, offsetBy: 1),
              let range = NSTextRange(location: start, end: end)
        else { return .null }
        var found: CGRect = .null
        manager.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
            found = frame
            return true
        }
        guard !found.isNull else { return .null }
        let origin = textView.textContainerOrigin
        return found.offsetBy(dx: origin.x, dy: origin.y)
    }

    @Test func aClickOnTheGlyphTogglesOpenToDoneOnTheSameLine() {
        let (textView, coordinator) = Self.editor(note: "- [ ] prova\n")
        let box = Self.glyphRect(in: textView)
        #expect(box.width > 0)

        #expect(coordinator.toggleCheckbox(at: CGPoint(x: box.midX, y: box.midY), in: textView))

        let lines = textView.string.split(separator: "\n", omittingEmptySubsequences: false)
        // The whole point of the fix: `@done(...)` lands on the task's own line, never on a
        // line of its own - the regression a stray `\n` folded into `TaskItem.rawLine` caused.
        #expect(lines.count == 2, "riga spezzata: \(textView.string.debugDescription)")
        #expect(lines[0].hasPrefix("- [x] prova @done("))
        #expect(lines[0].hasSuffix(")"))
    }

    @Test func aSecondClickTogglesDoneBackToOpenAndDropsDone() {
        let (textView, coordinator) = Self.editor(note: "- [x] prova @done(2026-01-01)\n")
        let box = Self.glyphRect(in: textView)

        #expect(coordinator.toggleCheckbox(at: CGPoint(x: box.midX, y: box.midY), in: textView))

        #expect(textView.string == "- [ ] prova\n")
    }

    @Test func aClickOnTheTaskTextFallsThroughWithoutToggling() {
        let (textView, coordinator) = Self.editor(note: "- [ ] prova\n")
        let box = Self.glyphRect(in: textView)
        let onTheText = CGPoint(x: box.maxX + 40, y: box.midY)

        #expect(!coordinator.toggleCheckbox(at: onTheText, in: textView))
        #expect(textView.string == "- [ ] prova\n")
    }
}
