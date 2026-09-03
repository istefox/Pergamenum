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
    /// Stub for Task 4 (tester): never caches, so two requests for the same identity are
    /// two different `TableGridView` instances - the coder's own deliverable is keeping a
    /// `[Int: TableGridView]` (or equivalent) here and returning the same one back, exactly
    /// as `EmbedTable`'s own render cache already does for a resolved picture.
    ///
    /// `textView` is not read by this stub. The real implementation uses it the way the
    /// probe's own `tableProbeGrid` lazy property already did in
    /// `NoteTextView+Coordinator.swift`, before this task removed it: wiring a freshly
    /// created grid's `resignToTextView` closure back to `textView.window?.makeFirstResponder(textView)`.
    func view(for identity: Int, in textView: NSTextView) -> TableGridView {
        TableGridView()
    }
}
