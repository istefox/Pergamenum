import AppKit

/// Which of a card's lines a fold takes out of the layout (ADR-0028 §D8, R-09).
///
/// A file of its own for the reason `CardTextView+Reveal.swift` and `CardTextView+ListEditing.swift`
/// are: `CardTextView.swift` is already at the length SwiftLint warns at, and a coordinator concern
/// that grows goes beside it rather than into it.
///
/// The rule is not restated here. `NoteFolding.layout(in:foldedEntries:)` is the note editor's own
/// pure function, called over a card's markdown exactly as it is called over a note's - unchanged,
/// unadapted, with no card-shaped overload - which is the whole of ADR-0028 §D8's premise and what
/// `Tests/CardFoldTests.swift` asserts directly. `FoldedHeadingFragment`, which draws the badge and
/// answers where it is, is used unchanged for the same reason.
extension CardTextView.Coordinator {
    /// Recomputes this card's fold and makes the layout read it again.
    ///
    /// The card's half of `NoteTextView+Coordinator.applyFolding(to:folded:theme:)`
    /// (`:148-166`), the same three moves in the same order: the pure layout, the shared
    /// delegate, and the document-wide `edited(.editedAttributes,…)` that re-runs the content
    /// manager's enumeration without a character changing - the only way a paragraph already laid
    /// out is asked again whether it should be enumerated at all. `invalidateLayout` after it,
    /// because dropping a paragraph changes every frame below it.
    ///
    /// Skipped entirely when nothing is folded and nothing was, so a board of ordinary cards -
    /// which is every board until somebody folds something - pays a set-emptiness check per update
    /// and nothing else. The badge's own colours are not set here: `applyStyling` already writes
    /// them on every pass (`CardTextView.swift`, the two lines above `decorations.apply(hiddenMarkers:
    /// hidingMarkup:)`), so a fold arriving between two styling passes still draws themed.
    func applyFolding(to textView: NSTextView) {
        guard decorations.isFolding || !parent.foldedEntries.isEmpty else { return }
        let layout = NoteFolding.layout(in: textView.string, foldedEntries: parent.foldedEntries)
        guard layout != lastFoldLayout else { return }
        lastFoldLayout = layout

        decorations.apply(hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings)

        let length = (textView.string as NSString).length
        textView.textContentStorage?.textStorage?.edited(
            .editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0
        )
        if let manager = textView.textLayoutManager {
            manager.invalidateLayout(for: manager.documentRange)
        }
        rescueCaret(in: textView, from: layout)
    }

    /// Moves the caret out of a section that has just been folded.
    ///
    /// The folded lines are not in the layout, so a caret left inside one is an insertion point
    /// with nowhere to be drawn and nowhere to type. It goes to the heading that swallowed it,
    /// which is where a person would look for it.
    ///
    /// Reachable on a card in the one state the note editor is always in: «Ripiega titoli» is on
    /// the command bar of the selected card, and a card can be selected while it is being written
    /// into. A card at rest has no visible caret to strand, and this costs it nothing - the guard
    /// below returns before reading a selection whenever nothing was hidden.
    private func rescueCaret(in textView: NSTextView, from layout: NoteFolding.Layout) {
        guard !layout.hiddenLineOffsets.isEmpty else { return }
        let text = textView.string as NSString
        let caret = textView.selectedRange().location
        guard caret <= text.length else { return }
        let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        guard layout.hiddenLineOffsets.contains(line) else { return }

        let heading = layout.foldedHeadings.keys.filter { $0 <= caret }.max() ?? 0
        textView.setSelectedRange(NSRange(location: heading, length: 0))
    }
}
