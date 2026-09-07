import AppKit

/// The view-block half of `EditorDecorationDelegate`'s re-read machinery (ADR-0033 §D1/§D6/§D7;
/// plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5) - split out on its own
/// the way `+TableRendering.swift`/`+QuoteRendering.swift`/`+ListRendering.swift`/
/// `+CheckboxRendering.swift` already are.
///
/// This file's job, once real, is `EditorDecorationDelegate+TableRendering.swift`'s own: the
/// static "is a closed, still-valid fence really here" check that both the drawing pass and a
/// later commit-style read can share without re-implementing the rule twice.
extension EditorDecorationDelegate {
    /// The view block whose opening fence starts exactly at `offset`, read from the
    /// characters as they are right now, with the UTF-16 range of its whole source (opening
    /// backticks through closing ones, inclusive) beside it.
    ///
    /// `tableRun(in:atParagraphStart:)`'s own shape (`EditorDecorationDelegate+TableRendering.swift`):
    /// `static`, in UTF-16, and taking an `NSString` rather than reading `self` - the drawing
    /// side is on no actor at all and a future commit-style caller would be `@MainActor`, so
    /// nothing here may touch this object's state, and both sides already hold the text as an
    /// `NSString`.
    ///
    /// Nil whenever there is nothing left to draw: the fence is not closed at this offset any
    /// more (ADR §D6, C5 - `CodeFence.regions(in:)`'s own precondition, re-read here rather
    /// than trusted from the last styling pass), or its body no longer parses through
    /// `ViewBlock.parse` (ADR §D7, R-08's fallback to raw text). Both preconditions collapse
    /// into one `nil` here, exactly the way a table's own structural failure and its
    /// `GFMTable.parse` failure both collapse into `tableRun`'s one `nil`.
    ///
    /// **Stub.** The tester's own declaration (plan Task 5): the real body, together with the
    /// substitution branch of `textContentStorage(_:textParagraphWith:)` that calls both this
    /// and `viewBlockParagraph(at:storage:)` (declared on `EditorDecorationDelegate` itself,
    /// Task 2's own stub), is the coder's.
    static func viewBlockRun(
        in text: NSString, atParagraphStart offset: Int
    ) -> (block: ViewBlock, range: NSRange)? {
        // Task 5, coder.
        nil
    }
}
