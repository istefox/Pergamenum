import AppKit

/// The two facts about a rendered list item that every surface drawing one has to agree
/// on: which glyph stands in for an unordered marker, and how far a given nesting level
/// is indented (ADR-0028; plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 3).
///
/// Stated once, here, rather than twice. `EditorDecorationDelegate` substitutes the glyph
/// into the *displayed* paragraph and collapses the indentation it replaces, while
/// `MarkdownAttributedText` and `CardTextAttributes` colour the source run - three call
/// sites that would drift the moment any one of them grew an indent step of its own, and
/// a list whose bullet and whose indentation disagree between Nota and a Workspace card is
/// exactly what this chain exists to prevent.
///
/// AppKit rather than Foundation only, and deliberately under `Sources/Features/` rather
/// than `Sources/Core/`: `NSParagraphStyle` and `NSFont` are AppKit types, and
/// `Sources/Core/**` is a `sharedSources` glob compiled into `perg` and `pergamenum-mcp`,
/// where an `import AppKit` breaks both tool builds (CLAUDE.md, ADR-0001 §D1).
enum ListMarkerRendering {
    /// The character an unordered marker is drawn as, or `nil` when the marker is drawn
    /// verbatim.
    ///
    /// Nil for every ordered marker on purpose: the digits already in the file *are* the
    /// rendered ordinal (ADR-0028 §D4), so there is nothing to substitute and the caller
    /// must leave those characters alone. An `Optional` rather than a sentinel character
    /// so that "draw this instead" and "draw what is written" cannot be confused at a call
    /// site under the length rule, where substituting the wrong number of characters is
    /// the failure mode.
    static func glyph(for kind: MarkdownStyler.Span.ListKind) -> Character? {
        // STUB (ADR-0155, tester owns the interface / coder owns the body): declared here
        // with the tests that call through it, body left to the coder.
        nil
    }

    /// How a list item at `level` is laid out: the indentation its glyph hangs at and the
    /// indentation its wrapped lines align to, both derived from `font` so a list steps in
    /// proportion to the text it is made of rather than by a hardcoded number of points.
    ///
    /// `level` is `MarkdownStyler.Span.listMarker`'s own level - 1 for a top-level item,
    /// capped at 6 - and the step has to be strictly monotonic in it: R-05 is satisfied by
    /// a nested item being *visibly deeper*, not merely different.
    static func paragraphStyle(level: Int, font: NSFont) -> NSParagraphStyle {
        // STUB (ADR-0155, tester owns the interface / coder owns the body).
        NSParagraphStyle()
    }
}
