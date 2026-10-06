import AppKit
@testable import Pergamenum

// ADR-0082 §D5/§D7 and ADR-0081, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385).
//
// One hosted editor shared by the restyle budget, the grow-to-fit tests and the gutter tests: a
// `NoteTextView` coordinator wired the way `NoteTextView.makeNSView` wires it - delegate, undo,
// both decoration delegates, `wire(_:to:)` - on a `CompletingTextView(usingTextLayoutManager:)`
// inside an `NSScrollView` in an offscreen `NSWindow` that is never ordered front. It mirrors
// `EditorHeightTests`' window shape and adds what that fixture lacks: `textView.delegate`, so a
// keystroke reaches `shouldChangeText` and `textDidChange` the way it does in the app.

@MainActor
struct ScrolledEditorFixture {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let scrollView: NSScrollView
    let window: NSWindow

    init(
        text: String, width: CGFloat = 900, height: CGFloat = 700,
        hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency,
        queries: ViewQuerySource? = nil
    ) {
        let view = NoteTextView(
            text: .constant(text), theme: theme, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, readableWidth: readableWidth,
            onFollowLink: { _ in }, vault: .init(transclusions: nil, queries: queries)
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
        textView.textContainerInset = NSSize(
            width: NoteTextView.Coordinator.minimumHorizontalInset,
            height: NoteTextView.Coordinator.verticalInset
        )
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [:]
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.wire(textView, to: coordinator)

        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        coordinator.textView = textView

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = scrollView
        window.layoutIfNeeded()

        coordinator.applyReadableWidth(to: textView)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        // Assigning `.string` posts no `textDidChange` and registers no undo action, so the text
        // is in place before anything the delegate does can see it.
        textView.string = text
        coordinator.applyStyling(to: textView, theme: theme)
        window.makeFirstResponder(textView)

        self.textView = textView
        self.coordinator = coordinator
        self.scrollView = scrollView
        self.window = window
    }

    /// The state the app's text view is in by the time a person types: the note open and the
    /// passes through, whose last step is `growToFitTheText`. That step sizes the frame to what
    /// TextKit reports, and the app runs it on every update, so by a keystroke the frame is as tall
    /// as the note and has stopped moving. Here it is run until the height settles (at most five
    /// times), so a keystroke meets a frame already as tall as the note, not the 700 pt this
    /// fixture was built with (`(n2-page R-17)`).
    func openLikeTheApp() {
        var previous = textView.frame.height
        for _ in 0..<5 {
            coordinator.growToFitTheText(textView)
            if abs(textView.frame.height - previous) <= 0.5 { break }
            previous = textView.frame.height
        }
    }

    /// A keystroke: the selection set at `location`, then `insertText(_:replacementRange:)` over
    /// it, so `shouldChangeText` and `textDidChange` run as they do for a key.
    func type(_ string: String, at location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}
