import AppKit

/// Draws a `.rule` paragraph (`---`/`***`/`___`) as a real full-width line rather than as
/// three collapsed, invisible characters (ADR-0029 §D1) - the one ADR-0029 construct that
/// cannot length-preserve into a drawn line the way a blockquote bar or a strikethrough
/// delimiter can, so it needs its own `NSTextLayoutFragment` the way `FoldedHeadingFragment`
/// draws its badge and `TranscludedLineFragment` draws its card.
///
/// **Declared by the tester** (plan `2026-09-02-editor-wysiwyg-unification`, Task 2); the
/// coder fills `draw(at:in:)` and the branch in
/// `EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` that hands one
/// back for a paragraph carrying a still-valid `.rule` marker, the same way that method
/// already branches on `renditions[start]` and `foldedHeadings[start]`.
final class HorizontalRuleFragment: NSTextLayoutFragment {
    /// The line's own colour, pushed in from a theme token the way
    /// `FoldedHeadingFragment.badgeColor` and `EmbedAttachment.handleColor` already are -
    /// never hardcoded (CLAUDE.md's design-system rule: "no hardcoded colour in a view").
    nonisolated(unsafe) var ruleColor: NSColor = .separatorColor
}
