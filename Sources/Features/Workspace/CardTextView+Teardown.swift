import AppKit

/// What a card lets go of when SwiftUI takes its view away (ADR-0027 §D2, ADR-0028 R-11).
///
/// A file of its own for the reason `CardTextView+Reveal.swift` and `CardTextView+ListEditing.swift`
/// are: `CardTextView.swift` reaches SwiftLint's file length again with every concern that arrives,
/// and this one moved out when the fold became the third table to release (ADR-0028 §D8). Moved
/// unchanged.
///
/// Its other half, `Coordinator.releaseDecorations()`, stays in `CardTextView.swift` and is not
/// merely left there: it empties `hiddenMarkers`, whose setter is `private(set)` to that file, so
/// the two cannot be filed together without widening an access level that exists to keep
/// `applyStyling` the only writer of that table.
extension CardTextView {
    /// Purges this text view's pending undo actions before SwiftUI releases it.
    ///
    /// Redundant given that the coordinator hands out an `UndoManager` of its own, which dies
    /// with it (ADR-0027 §D2) - and kept anyway, because the cost of being wrong about that is
    /// the `EXC_BAD_ACCESS` in `-[_NSUndoStack popAndInvoke]` that `a853e8e` fixed for the note
    /// editor. A card's text view is deallocated far more often than the editor's: once per card,
    /// and again every time a card crosses `BoardContentLayer.visibleNodes`' culling rect.
    ///
    /// The delegate's own tables go with them (R-11). They are the second thing this coordinator
    /// holds that describes a view about to disappear, and a table left behind is a table read on
    /// the next layout pass of whatever storage still points at this delegate - offsets measured
    /// against text that is gone.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.releaseDecorations()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.undoManager.removeAllActions(withTarget: textView)
        if let textStorage = textView.textStorage {
            coordinator.undoManager.removeAllActions(withTarget: textStorage)
        }
    }
}
