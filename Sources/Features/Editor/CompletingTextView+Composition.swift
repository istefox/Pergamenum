import AppKit

/// A composition step, handed to the coordinator (ADR-0093 §D7).
///
/// Its own file because `CompletingTextView` is at the length the linter allows.
extension CompletingTextView {
    /// Starting or replacing marked text changes the storage and posts no `textDidChange`, measured on
    /// the real path (ADR-0093, "The real edit path"): `onComposedTextChanged` lets the coordinator
    /// replay the edit path for it. The marked range and the selection are `super`'s and are not
    /// touched here; the commit is an ordinary `insertText` and reaches `textDidChange` by itself.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onComposedTextChanged?()
    }
}
