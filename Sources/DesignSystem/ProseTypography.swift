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
        fatalError("Task 2 coder: implement — theme.nsFont(.prose)")
    }

    /// The prose family's bold face (R-06). Falls back to the regular face — never to a
    /// monospaced substitute, and never to a different family — when the family has no bold.
    static func proseBold(_ theme: Theme) -> NSFont {
        fatalError("Task 2 coder: implement — bold trait of prose(theme)'s family, falling back to prose(theme) itself")
    }

    /// `CardTextAttributes.italicAttributes`'s rule (R-06), moved here so both the note editor
    /// and the Workspace card read one implementation: `.font` with the family's real italic
    /// face where one exists, `[.obliqueness: 0.2]` on the upright face otherwise.
    static func proseItalicAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        fatalError("Task 2 coder: implement — real italic face or [.obliqueness: 0.2] fallback")
    }

    /// A heading level's size (R-03): `max(prose + 1, proseTitle − (level − 1) × 2)`, clamped to
    /// levels 1...6 so an out-of-range level is clamped rather than crashing.
    static func heading(level: Int, _ theme: Theme) -> NSFont {
        fatalError("Task 2 coder: implement — max(prose + 1, proseTitle - (level - 1) * 2), level clamped to 1...6")
    }

    /// The chrome/code face: `theme.nsFont(.mono)`, optionally at a size other than the token's
    /// own — the fold badge and other small mono uses need a size the token does not carry.
    static func mono(_ theme: Theme, size: CGFloat? = nil) -> NSFont {
        fatalError("Task 2 coder: implement — theme.nsFont(.mono), resized to `size` when given")
    }

    /// A paragraph style carrying `font.prose`'s line-height multiple (R-07), composed onto
    /// `basedOn` rather than replacing it — list markers, transclusion `reservedHeight` and card
    /// alignment all build their own style first, and this must not drop their indentation,
    /// alignment or existing `paragraphSpacing`.
    static func paragraphStyle(_ theme: Theme, basedOn: NSParagraphStyle? = nil) -> NSParagraphStyle {
        fatalError("Task 2 coder: implement — mutable copy of `basedOn` (or a fresh style) with lineHeightMultiple set from font.prose's lineHeight, paragraphSpacing left untouched")
    }
}
