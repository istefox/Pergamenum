import AppKit

// The folding pass's own state (ADR-0074 §D2). A file of its own because the pass and its caret
// rescue used to sit in `NoteTextView+Coordinator.swift`, which has no room for them. The
// Coordinator keeps `applyFolding(to:folded:theme:)` as a one-line forward under the name
// `updateNSView` calls (ADR-0074 §D5).

/// The last fold layout applied, so an unchanged fold does not invalidate the layout on every
/// view update, and the folding pass with its caret rescue.
@MainActor
final class FoldController {
    /// Held for ADR-0074 §D3's uniform shape (every controller receives the provider at `init`)
    /// and unused today: the pass takes `folded` and `theme` as parameters, which `updateNSView`
    /// reads and hands down through `applyFolding`. A future read goes through it at the moment
    /// of use.
    private let parent: () -> NoteTextView?
    private let decorations: EditorDecorationDelegate

    /// The fold already applied, so an unchanged one does not invalidate the layout on every
    /// view update.
    private(set) var lastFoldLayout = NoteFolding.Layout()

    init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate) {
        self.parent = parent
        self.decorations = decorations
    }

    /// Recomputes the fold and makes the layout read it again.
    ///
    /// `edited(.editedAttributes,…)` is what re-runs the content manager's enumeration
    /// without a character changing - the same trick the reveal-on-caret probe used in
    /// the TextKit study. Skipped entirely when nothing is folded and nothing was, so
    /// an ordinary note pays nothing for this.
    func apply(to textView: NSTextView, folded: Set<Int>, theme: Theme) {
        guard decorations.isFolding || !folded.isEmpty else { return }
        let layout = NoteFolding.layout(in: textView.string, foldedEntries: folded)
        guard layout != lastFoldLayout else { return }
        lastFoldLayout = layout

        decorations.badgeColor = NSColor(theme.color(.textTertiary))
        decorations.badgeBackground = NSColor(theme.color(.backgroundTertiary))
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
    /// The folded lines are not in the layout, so a caret left inside one is an
    /// insertion point with nowhere to be drawn and nowhere to type. It goes to the
    /// heading that swallowed it, which is where a person would look for it. The rule is
    /// `CaretRescue`'s (ADR-0074 §D8); the owner is the nearest folded heading at or
    /// above the caret, and the caret is placed at once rather than after `endEditing`.
    private func rescueCaret(in textView: NSTextView, from layout: NoteFolding.Layout) {
        let selection = textView.selectedRange()
        let heading = CaretRescue.target(
            for: selection, hidden: layout.hiddenLineOffsets, in: textView.string as NSString
        ) { _ in
            layout.foldedHeadings.keys.filter { $0 <= selection.location }.max() ?? 0
        }
        CaretRescue.place(heading, in: textView)
    }
}
