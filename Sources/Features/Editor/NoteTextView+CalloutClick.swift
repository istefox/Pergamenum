import AppKit

/// A click on a callout title's chevron (ADR-0087 §D8), asked in the `onClickInMargin` chain after
/// `unfold`. It claims only a plain click inside the chevron, so a click on the title places the caret
/// and a modified click is left to the text view, as an embed chip's is (`isPlainClick`). `modifiers`
/// are the click's flags; nil reads them off the current event, which is what the click chain passes.
extension NoteTextView.Coordinator {
    func toggleCallout(
        at point: CGPoint, in textView: NSTextView, modifiers: NSEvent.ModifierFlags? = nil
    ) -> Bool {
        // Every header holds `[!`: a note without one walks no fragment for a click.
        guard Self.isPlainClick(modifiers ?? NSApp.currentEvent?.modifierFlags ?? []),
              let onToggleCallout = parent.outline.onToggleCallout,
              (textView.string as NSString).range(of: "[!").location != NSNotFound
        else { return false }
        let inContainer = Self.inContainer(point, of: textView)
        return Self.decoration(in: textView) { (fragment: CalloutTitleFragment) in
            guard fragment.chevronFrameInContainer?.contains(inContainer) == true else { return false }
            onToggleCallout(fragment.calloutOffset)
            return true
        }
    }
}
