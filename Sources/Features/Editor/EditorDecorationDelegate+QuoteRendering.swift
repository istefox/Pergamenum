import AppKit

/// The blockquote-rendering half of `EditorDecorationDelegate`'s substitution mechanism
/// (ADR-0029 §D1; plan `2026-09-02-editor-wysiwyg-unification`, Task 2), split out on its
/// own the way `+ListRendering.swift` and `+CheckboxRendering.swift` already are - one
/// self-contained concern, one `extension` file (`type_body_length`).
extension EditorDecorationDelegate {
    /// The blockquote branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// meant to draw a `>`/`>>`/`>>>` run as one `▏` per nesting level, character for
    /// character - the file's own `>` count *is* the depth (R-03, unbounded), so a bar is a
    /// straight one-for-one substitution and never a computed indent the way `.list`'s glyph
    /// is. `Self.survivors(among:of:in:)` is what the coder reuses here to collapse any other
    /// marker sharing the same paragraph (a bold run inside a quote, the SPEC's coexistence
    /// case) - the same reuse `listParagraph(at:storage:)` already makes.
    ///
    /// **Declared by the tester (Task 2), stubbed to `nil`** - no substitution, i.e. the raw
    /// `>` source stays on screen exactly as today - so every `Tests/QuoteRenderingTests.swift`
    /// assertion that expects a bar-substituted paragraph is red until the coder fills this
    /// in, the same way `listParagraph`/`checkboxParagraph` already work.
    func quoteParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        nil
    }
}
