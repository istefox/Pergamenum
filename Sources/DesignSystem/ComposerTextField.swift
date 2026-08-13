import AppKit
import SwiftUI

/// The single-line field the two composers type into.
///
/// An `NSTextField` rather than SwiftUI's, for one reason found by using it: SwiftUI
/// restores focus to a `TextField` by selecting the whole of it, so coming back from a
/// date popover left the task text selected and the next keystroke replaced it. Here
/// the caret goes to the end of what is already written, which is where a person who
/// was interrupted expects to carry on.
struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let color: NSColor
    /// Bumped to put the caret in this field. Zero means "never asked".
    var focusRequest = 0
    var identifier: String?
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        if let identifier { field.setAccessibilityIdentifier(identifier) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.font = font
        field.textColor = color

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            context.coordinator.takeFocus(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ComposerTextField
        var lastFocusRequest = 0

        init(parent: ComposerTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }

        /// First responder with the caret at the end, retried once because a field
        /// built in this same update is not in a window yet.
        func takeFocus(_ field: NSTextField) {
            guard field.window?.makeFirstResponder(field) == true else {
                Task { @MainActor [weak field] in
                    guard let field, field.window?.makeFirstResponder(field) == true else { return }
                    Self.placeCaretAtEnd(in: field)
                }
                return
            }
            Self.placeCaretAtEnd(in: field)
        }

        private static func placeCaretAtEnd(in field: NSTextField) {
            let end = (field.stringValue as NSString).length
            field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
        }
    }
}
