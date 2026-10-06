import AppKit
import Testing
@testable import Pergamenum

/// How tall the editor's text view is, which decides how much of a note can be reached.
///
/// Styling changes heights: a heading carries paragraph spacing and a transcluded line
/// reserves room under itself. A vertically resizable `NSTextView` under TextKit 2 does not
/// notice, so the scroll view kept the height the note had *before* its attributes went on
/// and the end of the note was unreachable - the note appeared to stop at its last heading,
/// a click low in the pane landed lines above where it was aimed, and text typed at the end
/// went into the file without ever appearing. Found by looking at the screen on 2026-08-18
/// and measured: 1431 points needed against 1244 given.
///
/// **What these tests do not prove.** `growToFitTheText` no longer lays out the whole document
/// on a keystroke (ADR-0082 §D7): it lays out the caret's fragment and the viewport, and the
/// first two tests reach the end the app's way, Cmd+Down and `layoutViewport()`, before they
/// measure. They hold the postcondition - once the end is approached the view is tall enough
/// for what it draws - and that is worth holding, but the defect itself only shows in a real
/// window. `CompletionPanelUITests`, `EditorGrowToFitScopeTests` and a look at the screen with a
/// long note are what caught it and what would catch it again.

@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let window: NSWindow
}

@MainActor
private func editorInAWindow(_ body: String) -> Editor {
    let view = NoteTextView(
        text: .constant(body), theme: .emergency, noteTitles: [], tagSuggestions: [],
        onFollowLink: { _ in }, vault: .init(transclusions: nil)
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = body
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]

    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = scroll
    window.layoutIfNeeded()
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

private let noteEndingInAHeading = ([
    "# In fondo alla pagina", "",
] + (1...40).flatMap { ["Riga di riempimento numero \($0), senza altro scopo.", ""] }
  + ["## Prova qui sotto", "", "Ultima riga della nota.", ""]).joined(separator: "\n")

/// One keystroke that changes no construct, at the end of the first filler line, so the delegate
/// path (`shouldChangeText`, `textDidChange`, `applyStyling`, `growToFitTheText`) runs as it does
/// for a key.
@MainActor
private func typeAKeystroke(in textView: NSTextView) {
    let first = (textView.string as NSString).range(of: "Riga di riempimento numero 1,")
    let at = (textView.string as NSString).lineRange(for: first).upperBound - 1
    textView.setSelectedRange(NSRange(location: at, length: 0))
    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// What a person does to reach the end of a note: Cmd+Down, and the viewport lays out what the
/// scroll brought into view. The app's way (ADR-0082 §D7), and never `layoutSubtreeIfNeeded`.
@MainActor
private func bringTheEndIntoView(_ textView: NSTextView, _ layout: NSTextLayoutManager) {
    textView.moveToEndOfDocument(nil)
    layout.textViewportLayoutController.layoutViewport()
}

// (n2-page R-17) Restated: ADR-0082 §D7 removes the whole-document layout the old test relied on
// (a test-side `ensureLayout(for: documentRange)` right after one keystroke), so the property is
// now "after the keystroke, bring the end into view, then the view is tall enough for what
// TextKit reports it draws".
@MainActor
@Test func stylingLeavesTheTextViewTallEnoughForWhatItDraws() {
    let editor = editorInAWindow(noteEndingInAHeading)
    let (textView, window) = (editor.textView, editor.window)
    defer { window.orderOut(nil) }
    guard let layout = textView.textLayoutManager else { return }

    typeAKeystroke(in: textView)
    bringTheEndIntoView(textView, layout)

    let needed = layout.usageBoundsForTextContainer.height + textView.textContainerInset.height * 2
    #expect(textView.frame.height >= needed)
}

// (n2-page R-17) Restated for the same reason: the end is reached the app's way, not by a
// whole-document layout made in the test.
@MainActor
@Test func theLastLineOfANoteIsInsideTheScrollableArea() {
    // The same fact said the way the user meets it: the final paragraph has to be somewhere
    // the scroll view can reach, or it does not exist as far as anyone typing is concerned.
    let editor = editorInAWindow(noteEndingInAHeading)
    let (textView, window) = (editor.textView, editor.window)
    defer { window.orderOut(nil) }
    guard let layout = textView.textLayoutManager, let content = layout.textContentManager else { return }

    typeAKeystroke(in: textView)
    bringTheEndIntoView(textView, layout)

    let tail = (textView.string as NSString).range(of: "Ultima riga della nota.")
    guard let location = content.location(content.documentRange.location, offsetBy: tail.location),
          let fragment = layout.textLayoutFragment(for: location)
    else {
        Issue.record("l'ultima riga della nota non ha nemmeno un fragment")
        return
    }
    #expect(fragment.layoutFragmentFrame.maxY <= textView.frame.height)
}

@MainActor
@Test func typingAtTheEndOfANoteBringsTheCaretIntoView() {
    // The other half of the same complaint. With the height fixed the last line exists;
    // this is what puts it in front of the person who just typed it.
    let editor = editorInAWindow(noteEndingInAHeading)
    let (textView, coordinator, window) = (editor.textView, editor.coordinator, editor.window)
    defer { window.orderOut(nil) }

    let end = (textView.string as NSString).length
    textView.setSelectedRange(NSRange(location: end, length: 0))
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    let caret = textView.caretRectOnScreen()
    #expect(caret.height > 0)
    // Back into the text view's own space to compare with `visibleRect`: `documentVisibleRect`
    // is measured in the document's coordinates, so converting it through the scroll view
    // gives a rectangle that means nothing.
    let inView = textView.convert(window.convertFromScreen(caret), from: nil)
    #expect(
        textView.visibleRect.contains(CGPoint(x: inView.midX, y: inView.midY)),
        "il caret in fondo alla nota non è nell'area visibile"
    )
}
