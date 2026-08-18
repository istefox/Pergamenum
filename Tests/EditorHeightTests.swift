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
/// **What these tests do not prove.** A text view built here grows from the `ensureLayout`
/// inside `growToFitTheText` alone, so removing the `layoutViewport()` that makes the app
/// behave leaves them green. They hold the postcondition - after the call the view is tall
/// enough for what it draws - and that is worth holding, but the defect itself only shows in
/// a real window. `CompletionPanelUITests` and a look at the screen are what caught it and
/// what would catch it again.

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
        onFollowLink: { _ in }, transclusions: nil
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
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

@MainActor
@Test func stylingLeavesTheTextViewTallEnoughForWhatItDraws() {
    let editor = editorInAWindow(noteEndingInAHeading)
    let (textView, coordinator, window) = (editor.textView, editor.coordinator, editor.window)
    defer { window.orderOut(nil) }
    guard let layout = textView.textLayoutManager else { return }

    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    layout.ensureLayout(for: layout.documentRange)

    let needed = layout.usageBoundsForTextContainer.height + textView.textContainerInset.height * 2
    #expect(textView.frame.height >= needed)
}

@MainActor
@Test func theLastLineOfANoteIsInsideTheScrollableArea() {
    // The same fact said the way the user meets it: the final paragraph has to be somewhere
    // the scroll view can reach, or it does not exist as far as anyone typing is concerned.
    let editor = editorInAWindow(noteEndingInAHeading)
    let (textView, coordinator, window) = (editor.textView, editor.coordinator, editor.window)
    defer { window.orderOut(nil) }
    guard let layout = textView.textLayoutManager, let content = layout.textContentManager else { return }

    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    layout.ensureLayout(for: layout.documentRange)

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
