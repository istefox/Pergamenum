import AppKit

/// The table-rendering half of `EditorDecorationDelegate`'s substitution mechanism
/// (ADR-0029 §D4; plan `2026-09-02-editor-wysiwyg-unification`, Task 4), split out on its
/// own the way `+QuoteRendering.swift`/`+ListRendering.swift`/`+CheckboxRendering.swift`
/// already are - one self-contained concern, one `extension` file (`type_body_length`).
///
/// Replaces the Step 4.5 tracer-bullet probe that used to live here (a fixed trigger word,
/// "tableprobe", substituted for a `TableAttachment` with no grammar behind it) now that
/// probe 2 (ADR §D16) has already answered its one question - nested first-responder focus
/// inside an `NSTextAttachmentViewProvider` view works in a real `CompletingTextView`. This
/// file's own job is the real one: reading a `.table` `HiddenMarker` back and drawing the
/// grid `TableGridStore` already vended for it.
extension EditorDecorationDelegate {
    /// The table branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// meant to swap the header line's first character for `\u{FFFC}` carrying a
    /// `TableAttachment` wrapping `tableViews[range.location]`, collapsing the rest of the
    /// header line into `collapsedFont` - one character out, one in, the paragraph's own
    /// length unmoved, `embedParagraph(at:storage:)`'s own arithmetic
    /// (`NSTextContentManager.h:120`).
    ///
    /// Stub for Task 4 (tester): always nil, so no header paragraph is substituted, until
    /// the coder reads the `.table` marker back, re-validates it against a fresh
    /// `GFMTable.parse` of the live characters at `range` (this delegate's own
    /// `stillSpells` re-check contract, the same discipline `embedParagraph` and
    /// `listParagraph` already keep - a `.table` marker whose characters no longer parse as
    /// a table must draw nothing, per D8's reload guard), and builds the real
    /// `TableAttachment` from `tableViews[range.location]`.
    ///
    /// Nil whenever there is nothing to draw: `hidesMarkup` off (checked by the caller,
    /// `textContentStorage(_:textParagraphWith:)`'s own guard), no `.table` marker at this
    /// offset, no grid vended yet for it, or the marker gone stale against the real
    /// characters since the last styling pass (§D9).
    func tableParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        nil
    }
}
