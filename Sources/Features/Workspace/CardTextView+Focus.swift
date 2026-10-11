import AppKit

/// Where the keyboard goes as a card starts and stops being edited (ADR-0027 §D3).
///
/// A file of its own for the reason `CardTextView+Teardown.swift` is one: `CardTextView.swift`
/// reached SwiftLint's file length again (PG-395), and this concern reads nothing private to the
/// coordinator. Moved unchanged; `updateNSView` in `CardTextView.swift` is its one caller.
extension CardTextView.Coordinator {
    /// Puts the keyboard where the model says editing is happening.
    ///
    /// SwiftUI's `@FocusState` reaches a SwiftUI view; the first responder inside an
    /// `NSViewRepresentable` is AppKit's to hand out, so the card asks for it here. Resigning
    /// on the way out matters just as much: a text view left holding the keyboard after
    /// editing ends swallows every board shortcut aimed past it.
    func matchFocus(_ textView: FormattingTextView, editable: Bool) {
        guard let window = textView.window else {
            guard editable else { return }
            // No window yet - the very first update after a card is created. Ask again once
            // the view is in one, the retry `NoteTextView.takeFocus` makes for the same reason.
            Task { @MainActor [weak textView] in
                guard let textView, textView.isEditable else { return }
                textView.window?.makeFirstResponder(textView)
            }
            return
        }
        let isFirstResponder = window.firstResponder === textView
        if editable, !isFirstResponder {
            window.makeFirstResponder(textView)
        } else if !editable, isFirstResponder {
            window.makeFirstResponder(nil)
        }
    }
}
