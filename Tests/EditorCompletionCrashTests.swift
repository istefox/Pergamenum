import AppKit
import Testing
@testable import Pergamenum

/// The stack-overflow regression `EditorCompletionUITests.swift:59`'s one test guarded on
/// screen (`b52c3ed`, "typing a # at the start of a line no longer takes the app down"):
/// AppKit's own `complete(nil)` used to write its first candidate into the text as it
/// opened the list, which fired `textDidChange` straight back into a context that was
/// still a completion one - `#area-training` is a tag prefix exactly as `#a` was - and
/// the app died on a stack overflow.
///
/// **What changed since, and what this test can and cannot still prove.** `complete(nil)`
/// itself is gone: the completion trigger today is `CompletionPanel.refreshCompletion`
/// (`NoteTextView+Coordinator.swift:389-399`), whose own comment says why it cannot
/// recur - "the panel writes nothing until a row is chosen, so there is no edit to come
/// back". That is a structural difference from the code `b52c3ed` fixed, not only a
/// guarded one, so there is no longer a single line whose reversion reproduces the
/// original stack overflow on this tree; a red-on-revert demonstration for that exact
/// historical mechanism is not available here; this is driven the same way the retired
/// GUI test was, through the real text view, and it is what stands in its place.
///
/// Hosted the way `Tests/EditorHeightTests.swift:49-55` is: a titled `NSWindow`, laid out
/// once, never ordered front (ADR-0053 §D5).
@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let window: NSWindow
}

@MainActor
private func hostedEditor(_ text: String) -> Editor {
    let view = NoteTextView(
        text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
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
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)

    let window = NSWindow(
        contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = textView
    textView.string = text
    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    window.makeFirstResponder(textView)
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

@MainActor
@Test func typingAHashAtTheStartOfALineDoesNotTakeTheProcessDown() {
    let editor = hostedEditor("Prima riga.")
    defer { editor.window.orderOut(nil) }
    let textView = editor.textView

    // One character at a time, the way XCUITest's `typeText` and AppKit's own key
    // handling both do: each `insertText` is a real edit and posts a real
    // `NSText.didChangeNotification`, exactly what the regression recursed on when the
    // trigger still wrote back into the storage it was reacting to.
    for character in "\n## Titolo\n#area-training\n" {
        textView.insertText(String(character), replacementRange: textView.selectedRange())
    }

    // The assertion the retired GUI test could only make indirectly ("the app is still
    // there to answer"): the loop above returned rather than exhausting the stack, and
    // every character landed exactly once.
    #expect(textView.string == "Prima riga.\n## Titolo\n#area-training\n")
}
