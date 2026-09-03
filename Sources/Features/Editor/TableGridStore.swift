import AppKit

/// Vends the one `TableGridView` a table keeps across every styling pass (ADR-0029 §D6;
/// plan `2026-09-02-editor-wysiwyg-unification`, Task 4).
///
/// `@MainActor` and owned by the Coordinator, exactly as `EmbedTable` is
/// (`NoteTextView+Coordinator.swift:77`) - `EditorDecorationDelegate` cannot hold this
/// store itself (it is not `@MainActor`, ADR §Context constraint 3), so the Coordinator
/// asks it for a view per table and hands the finished `[Int: TableGridView]` map to the
/// delegate through `apply(tableViews:)`.
///
/// **The same view instance across layout passes is the whole point.** A grid rebuilt on
/// every restyle would lose first responder on every keystroke that triggers one - which,
/// through `textDidChange` → `applyStyling`, is every keystroke. Keyed by the table's
/// identity, the header paragraph's own UTF-16 offset - the same key space every other
/// decoration table in this file already uses (`hiddenMarkers`, `embedRenditions`,
/// `tableRowOffsets`) - since a table's shape is re-read from the live characters on every
/// pass rather than carried anywhere stable of its own.
@MainActor
final class TableGridStore {
    /// The grid already built for each table identity. Never pruned by this property's own
    /// accessors: `views(for:in:)` below is the one call that decides which identities are
    /// still on screen, so a grid is dropped exactly once per styling pass rather than
    /// whenever a lookup happens to miss.
    private var grids: [Int: TableGridView] = [:]

    /// The grid for `identity`, built on first ask and handed back unchanged after that.
    ///
    /// `textView` is read for one thing only, and only when a grid is actually built: the
    /// new grid's `resignToTextView` closure, which Tab-from-the-last-cell and Escape both
    /// call to hand first responder back to the enclosing editor. Held weakly, so a grid
    /// outliving its text view resigns to nothing rather than to a dangling view.
    func view(for identity: Int, in textView: NSTextView) -> TableGridView {
        if let existing = grids[identity] { return existing }
        let grid = TableGridView()
        grid.resignToTextView = { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        grids[identity] = grid
        return grid
    }

    /// The grids for every table the note spells right now, and **only** those - the
    /// identities absent from `identities` are dropped here.
    ///
    /// Pruning belongs on this call rather than on `view(for:in:)` because a styling pass
    /// is the one moment that knows the whole set: a note whose tables are edited for an
    /// afternoon would otherwise accumulate a grid per offset any table ever started at,
    /// each holding an `NSView` hierarchy. The map it returns is what the Coordinator hands
    /// to `EditorDecorationDelegate.apply(tableViews:)` as a finished value (ADR-0029 §D6).
    func views(for identities: [Int], in textView: NSTextView) -> [Int: TableGridView] {
        var kept: [Int: TableGridView] = [:]
        for identity in identities {
            kept[identity] = view(for: identity, in: textView)
        }
        grids = kept
        return kept
    }
}
