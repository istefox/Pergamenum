import AppKit

/// The one place in `Sources/Features/Editor` + `Sources/Features/Workspace` scope allowed to
/// construct an `NSFont` (ADR-0030 §D1). Everything a page draws — the note editor's prose runs,
/// heading fold badges, list line height, and (Task 5) the Workspace `.text` card — reads a face
/// or a paragraph style through this enum rather than naming one of its own.
///
/// Every function takes the resolved `Theme` explicitly: `EditorDecorationDelegate`,
/// `FoldedHeadingFragment` and `TableGridView` are not `@MainActor` and cannot read
/// `Theme` themselves (ADR-0030 §D5), so a caller resolves once and pushes the value in.
///
/// `Tests/ProseTypographyTests.swift` is the red suite this stub exists to satisfy compile-time;
/// the coder fills in each body next (plan `2026-09-04-editor-page-typography-noteplan.md`,
/// Task 2). No file outside `Sources/DesignSystem/` is touched by this declaration.
enum ProseTypography {
    /// The page's body face: `theme.nsFont(.prose)`, unresolved further here — `Theme` already
    /// owns the named-family probe and its system-face fallback (ADR-0030 §D3).
    static func prose(_ theme: Theme) -> NSFont {
        theme.nsFont(.prose)
    }

    /// The prose family's bold face (R-06). Falls back to the regular face — never to a
    /// monospaced substitute, and never to a different family — when the family has no bold.
    static func proseBold(_ theme: Theme) -> NSFont {
        bolded(prose(theme))
    }

    /// `CardTextAttributes.italicAttributes`'s rule (R-06), moved here so both the note editor
    /// and the Workspace card read one implementation: `.font` with the family's real italic
    /// face where one exists, `[.obliqueness: 0.2]` on the upright face otherwise.
    static func proseItalicAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        let base = prose(theme)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        guard let italic = NSFont(descriptor: descriptor, size: base.pointSize),
              italic.fontDescriptor.symbolicTraits.contains(.italic)
        else {
            return [.obliqueness: 0.2]
        }
        return [.font: italic]
    }

    /// A heading level's size (R-03): `max(prose + 1, proseTitle − (level − 1) × 2)`, clamped to
    /// levels 1...6 so an out-of-range level is clamped rather than crashing.
    ///
    /// The *face* is `font.proseTitle`'s, resized: a heading is the title token scaled down
    /// towards the body, not the body face enlarged, so a theme that gives `proseTitle` its own
    /// family or weight is followed at every level rather than only at level 1.
    static func heading(level: Int, _ theme: Theme) -> NSFont {
        let clamped = min(max(level, 1), 6)
        let title = theme.nsFont(.proseTitle)
        let size = max(prose(theme).pointSize + 1, title.pointSize - CGFloat(clamped - 1) * 2)
        return NSFont(descriptor: title.fontDescriptor, size: size) ?? title
    }

    /// The chrome/code face: `theme.nsFont(.mono)`, optionally at a size other than the token's
    /// own — the fold badge and other small mono uses need a size the token does not carry.
    static func mono(_ theme: Theme, size: CGFloat? = nil) -> NSFont {
        let base = theme.nsFont(.mono)
        guard let size, size != base.pointSize else { return base }
        // Through the descriptor rather than `NSFont(name:size:)`: the token's default family
        // resolves to `.AppleSystemUIFontMonospaced-Regular`, a dot-prefixed system face
        // `NSFont(name:)` will not hand back. The last resort keeps the monospacing, which is
        // the one property a caller asking for `mono` is actually asking for.
        return NSFont(descriptor: base.fontDescriptor, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// A paragraph style carrying `font.prose`'s line-height multiple (R-07), composed onto
    /// `basedOn` rather than replacing it — list markers, transclusion `reservedHeight` and card
    /// alignment all build their own style first, and this must not drop their indentation,
    /// alignment or existing `paragraphSpacing`.
    ///
    /// `font` names the actual run this style is being built for. It defaults to `nil`, which
    /// keeps every existing call site (`base(theme:)`, `NoteTextView+Transclusion.swift`, the
    /// three `ProseTypographyTests` call sites above) reading exactly `font.prose`'s own line
    /// height, unchanged. A caller building a style for a *larger* face — a heading run, whose
    /// font is `ProseTypography.heading(level:_:)` rather than `prose(theme)` — passes that font
    /// explicitly so the multiple scales with it instead of silently staying `prose`-sized
    /// (`MarkdownAttributedText.attributes(for: .heading)`'s bug: it set `.font` and
    /// `.foregroundColor` but never `.paragraphStyle`, so a heading run kept `base(theme:)`'s
    /// single body-sized style regardless of level).
    ///
    /// STUB (tester-owns-interface, ADR-0155 §D1): body intentionally left as `fatalError` — the
    /// coder fills in the actual scaling rule. `lineHeightMultipleTests` in
    /// `Tests/ProseTypographyTests.swift` is the red suite this signature exists to satisfy at
    /// compile time.
    static func paragraphStyle(
        _ theme: Theme,
        font: NSFont? = nil,
        basedOn: NSParagraphStyle? = nil
    ) -> NSParagraphStyle {
        guard font == nil else {
            fatalError("ProseTypography.paragraphStyle(_:font:basedOn:) not yet implemented for an explicit font")
        }
        let style = NSMutableParagraphStyle()
        // `setParagraphStyle` copies every property, including the ones this file has no reason
        // to know about — a property added to `NSParagraphStyle` later survives composition
        // without an edit here, which a field-by-field copy would not.
        if let basedOn { style.setParagraphStyle(basedOn) }
        style.lineHeightMultiple = lineHeightMultiple(theme)
        // No `paragraphSpacing` is set: a fresh style already carries 0, and one that came in
        // through `basedOn` keeps whatever its own author asked for (ADR-0030 §D6).
        return style
    }

    // MARK: - Resolution

    /// The bold face of a font's own family, or that font unchanged.
    ///
    /// Both guards are load-bearing and were measured, not assumed: `NSFont(descriptor:size:)`
    /// on a `.bold`-augmented descriptor returns `nil` for a family with no bold face (Papyrus),
    /// and a family that answers with a substitute would answer with one from a *different*
    /// family — the monospaced system face among them, which R-06 exists to rule out. Falling
    /// back to the upright face of the right family is the smaller lie.
    private static func bolded(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.bold)
        guard let bold = NSFont(descriptor: descriptor, size: font.pointSize),
              bold.fontDescriptor.symbolicTraits.contains(.bold),
              bold.familyName == font.familyName
        else {
            return font
        }
        return bold
    }

    /// `font.prose`'s DTCG `lineHeight`, as the multiple `NSParagraphStyle` takes.
    ///
    /// Read back through `Theme.lineSpacing(_:)`, which is the only accessor the theme exposes
    /// for that field (`fonts` is private and this task's budget is this file alone): the
    /// conversion it applies is `size * (lineHeight - 1)`, so dividing by the same size and
    /// adding one returns the token's own value — exactly, verified for the sizes the bundled
    /// themes carry, since both steps are multiplications by a power of two on this stack.
    /// A token declaring a line height below 1 arrives here as 1, because `lineSpacing` clamps
    /// at zero; no theme in the tree does, and a paragraph tighter than its own glyphs is not a
    /// value this helper should be able to produce.
    private static func lineHeightMultiple(_ theme: Theme) -> CGFloat {
        let size = prose(theme).pointSize
        guard size > 0 else { return 1 }
        return 1 + theme.lineSpacing(.prose) / size
    }
}
