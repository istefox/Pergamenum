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
        switch kind {
        // U+2022, one UTF-16 unit, which is what makes the substitution legal at all: the
        // displayed paragraph keeps the stored one's length only because a `-`, a `*` or a
        // `+` is swapped for exactly one character (ADR-0028 §D4).
        case .bullet: "\u{2022}"
        case .ordered: nil
        }
    }

    /// How a list item at `level` is laid out: the indentation its glyph hangs at and the
    /// indentation its wrapped lines align to, both derived from `font` so a list steps in
    /// proportion to the text it is made of rather than by a hardcoded number of points.
    ///
    /// `level` is `MarkdownStyler.Span.listMarker`'s own level - 1 for a top-level item,
    /// capped at 6 - and the step has to be strictly monotonic in it: R-05 is satisfied by
    /// a nested item being *visibly deeper*, not merely different.
    ///
    /// `basedOn` is composed onto, never replaced by the indentation computed here (ADR-0030
    /// §D6, the same rule `ProseTypography.paragraphStyle(_:basedOn:)` already follows for its
    /// own `lineHeightMultiple`) - a list line's paragraph style is built wholesale today, so a
    /// line-height multiple pushed in through `basedOn` would otherwise be silently dropped the
    /// moment a paragraph is also a list item.
    ///
    /// **Stub (Task 4, tester; ADR-0155 §D1).** `basedOn` is accepted but not yet composed -
    /// the body below is byte-for-byte the pre-Task-4 two-argument implementation, so every
    /// existing caller's behaviour is unchanged until the coder fills this in. This is what
    /// makes `Tests/MarkupHidingTests.swift`'s composition assertion genuinely red: a `basedOn`
    /// style's own `lineHeightMultiple` does not yet survive a call here.
    static func paragraphStyle(level: Int, font: NSFont, basedOn: NSParagraphStyle? = nil) -> NSParagraphStyle {
        let em = max(font.pointSize, 1)
        let depth = CGFloat(min(max(level, 1), 6))
        let style = NSMutableParagraphStyle()
        // A top-level item is already indented - `depth` starts at 1, never at 0 - because
        // the source's own indentation is drawn in `collapsedFont` and this style is the
        // only thing left holding the line off the margin (ADR-0028 §D4, R-05).
        style.firstLineHeadIndent = em * Self.stepInEms * depth
        // One bullet-width further, so a wrapped item aligns under its own text rather
        // than under its glyph (§D4).
        style.headIndent = style.firstLineHeadIndent + em * Self.glyphInEms
        return style
    }

    /// How far one level of nesting steps in, as a multiple of the point size rather than
    /// a number of points: a list drawn at 24pt has to step further than the same list at
    /// 11pt, or a nested item at the larger size reads as a wrapped line of its parent.
    ///
    /// One and a half ems is wider than the two source spaces it replaces (about half an
    /// em in a proportional face) on purpose. R-05 asks for a nested item to be *visibly*
    /// deeper, and the source's own step is at the edge of legibility once the marker
    /// characters themselves are no longer on screen to mark it.
    private static let stepInEms: CGFloat = 1.5

    /// The width the glyph and its trailing space are assumed to take. Three quarters of
    /// an em covers `• ` in every face this app draws with and is deliberately not
    /// measured: a measurement would have to happen at layout time, per paragraph, for a
    /// hanging indent whose only job is to keep a wrapped line clear of the bullet.
    private static let glyphInEms: CGFloat = 0.75
}
