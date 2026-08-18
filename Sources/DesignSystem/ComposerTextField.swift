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
    /// Shift+Return, which the find bar reads as «la corrispondenza precedente». Defaults to
    /// `onSubmit`, so a field that has no backwards meaning behaves as it always did.
    var onSubmitBackwards: (() -> Void)?
    /// Escape. Nil where the field has nothing to cancel, and then the key falls through to
    /// whoever else wants it rather than being quietly eaten.
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        if let identifier { field.setAccessibilityIdentifier(identifier) }
        apply(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        apply(to: field)

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            context.coordinator.takeFocus(field)
        }
    }

    /// Everything about the field that can change while it is on screen.
    ///
    /// Called from both `makeNSView` and `updateNSView`, and it exists as a method rather
    /// than as two copies because the copies drifted: `placeholderString` was set only at
    /// creation, so the capture panel kept saying "Titolo della nota, poi il testo" after
    /// the user had switched to Task. The two older composers never showed it - their
    /// placeholder never changes - and neither did any test, because `updateNSView` takes
    /// an `NSViewRepresentableContext` a test cannot build. This one can be called
    /// directly, which is the point.
    func apply(to field: NSTextField) {
        if field.stringValue != text { field.stringValue = text }
        field.font = font
        field.textColor = color
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
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
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift+Return arrives as `insertNewline` with the modifier still on the
                // event, not as a selector of its own: AppKit maps both to the same command
                // and only the event knows which was pressed.
                let isBackwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if isBackwards, let onSubmitBackwards = parent.onSubmitBackwards {
                    onSubmitBackwards()
                } else {
                    parent.onSubmit()
                }
                return true
            // Escape reaches a field as either of these depending on what else is installed,
            // so both are caught rather than the one that happened to work - the same pair
            // `CompletingTextView.doCommand(by:)` catches for the completion panel.
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
                guard let onCancel = parent.onCancel else { return false }
                onCancel()
                return true
            default:
                return false
            }
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
