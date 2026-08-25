import Foundation

/// The drawn embed's own context menu (ADR-0023 §D9, R-08): a one-item menu whose delete
/// **is** the Backspace path, not a second one that happens to agree with it.
///
/// `import Foundation` only, deliberately: this file is the pure part a test can read
/// without `NSMenu`/`NSTextView` - `NoteTextView+EmbedCaret.swift` is the AppKit half that
/// turns `items()` into real `NSMenuItem`s and asks `deletionRange(forRun:textLength:)`
/// before calling `replaceAtomically(_:with:in:)`, the app's one edit path.
///
/// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 8.
enum EmbedContextMenu {
    /// The menu's entries, titled for display. Exactly one today (R-08: "Elimina"); a
    /// `[String]` rather than a case-per-command enum because there is only the one
    /// command to name, unlike `CardCommand`'s nine.
    ///
    /// The word is written here and nowhere else: `embedMenu(at:in:)` builds its
    /// `NSMenuItem`s by walking this array rather than from a literal of its own, which is
    /// all "named once, rendered twice" can mean for a cluster whose second surface -
    /// Backspace - carries no title at all.
    static func items() -> [String] {
        ["Elimina"]
    }

    /// What deleting this run from the context menu removes, or `nil` when the run is
    /// stale (its own recorded extent no longer fits `textLength`) - the same guard
    /// `EmbedNavigation.deletionRange` already applies, asked here so the menu never asks
    /// `replaceAtomically` for a bad write.
    ///
    /// **Calls** `EmbedNavigation.deletionRange`, never reimplements it (ADR-0023 §D9):
    /// the menu's delete is the Backspace path, placing a zero-length selection at the
    /// run's own far edge and asking the same backward-deletion rule Backspace asks.
    ///
    /// So the paragraph's own trailing newline goes with the picture here too (D-1:
    /// deleting a drawn embed must not leave an empty line in its place), and the note's
    /// very last line with no newline after it is clamped rather than over-read - neither
    /// is decided in this file, and that is the point of it.
    ///
    /// `drawnRuns` is the single run the click landed on, never the paragraphs around a
    /// caret that `drawnEmbedRuns(near:in:)` collects: a right-click has already named its
    /// picture, so there is nothing to search for and no neighbouring run that could
    /// answer in its place.
    static func deletionRange(forRun run: NSRange, textLength: Int) -> NSRange? {
        EmbedNavigation.deletionRange(
            selection: NSRange(location: NSMaxRange(run), length: 0),
            direction: .backward,
            drawnRuns: [run],
            textLength: textLength
        )
    }
}
