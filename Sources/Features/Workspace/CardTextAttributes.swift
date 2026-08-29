import AppKit
import SwiftUI

/// The Workspace card's own attribute table (ADR-0027 §D1), keyed on the same
/// `MarkdownStyler.Span` the note editor already classifies source into.
///
/// Deliberately **not** `MarkdownAttributedText.attributes(for:theme:)`, and this file must
/// never call into it: that table's `.bold` arm returns
/// `NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)` (`MarkdownAttributedText.swift:56`),
/// the note editor's source-mode look, wrong on a canvas card where bold must simply be bold.
/// This table is the sibling ADR-0027 §D1 names - a card renders through this table only, and
/// the note editor's own styling is never touched by this feature.
///
/// The rules this table satisfies, held to by `Tests/CardTextViewTests.swift`:
///
/// - `.bold` -> a genuinely bold, non-monospaced font, e.g.
///   `NSFont.systemFont(ofSize: 13, weight: .bold)`. Never `NSFont.monospacedSystemFont`.
/// - `.italic` -> an oblique/italic font. Also never `.monospacedSystemFont`.
/// - `.strikethrough` -> `.strikethroughStyle`, `NSUnderlineStyle.single`.
/// - Every colour comes from a theme token (`Theme.color(_:)` / `Theme.rawColor(_:)`), never a
///   hardcoded `NSColor` - this table *is* a view choosing a colour, so the design-system rule
///   ("no hardcoded colour in a view") holds here exactly as it does in `MarkdownAttributedText`.
/// - `.linkTarget` / `.embedTarget` are styled (e.g. a distinct colour, optionally underlined)
///   but must **never** carry `.link` as a key and must never be clickable: a canvas card's text
///   view has no note open to route a click to, so there is no navigation surface to offer
///   (ADR §D1). Unlike `MarkdownAttributedText.attributes(for:theme:links:)`, this table takes
///   no `links:` toggle at all - there is nothing to switch, because a card's links are never
///   navigable.
/// - Nothing in this table may look at what precedes or follows a span's own range. A `.bold`
///   span three characters into a line and a `.bold` span three characters into
///   `"- [ ] "`-prefixed line must attribute identically (R-09, "no special-casing that excludes
///   it") - the To Do prefix is a `.taskMarker` span of its own, entirely outside `.bold`'s
///   range, and this table must stay indifferent to it.
enum CardTextAttributes {
    /// The card's base attributes - a genuinely proportional font, unlike the note editor's
    /// monospaced `MarkdownAttributedText.base(theme:)`. Everything `attributes(for:theme:)`
    /// returns layers on top of these via `NSMutableAttributedString.addAttributes(_:range:)`,
    /// the same merge-not-replace rule `MarkdownAttributedText.attributed(_:theme:)` documents.
    static func base(theme: Theme) -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont(theme),
            .foregroundColor: NSColor(theme.color(.textPrimary)),
        ]
    }

    /// A whole card's markdown source, styled through this table. Same shape as
    /// `MarkdownAttributedText.attributed(_:theme:links:)` with the `links:` parameter dropped:
    /// see `attributes(for:theme:)` above for why there is nothing to switch.
    ///
    /// Implemented by walking `MarkdownStyler.spans(in:)` over `text` and layering
    /// `attributes(for:theme:)` on top of `base(theme:)` for each span's range, in the order
    /// `spans(in:)` returns them - the same construction `MarkdownAttributedText.attributed`
    /// uses, so a span that overlaps another (a bold run inside a heading) resolves the same
    /// way on a card as it does in a note.
    static func attributed(_ text: String, theme: Theme) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        apply(to: result, theme: theme)
        return result
    }

    /// The same walk as `attributed(_:theme:)`, applied to storage that already exists.
    ///
    /// `CardTextView`'s coordinator styles the live `NSTextStorage` of a card's text view rather
    /// than building a new string and assigning it: an attribute-only pass leaves the characters
    /// - and therefore the caret and the selection - exactly where they were, which is what makes
    /// restyling on every keystroke invisible. Both entry points go through this one body so the
    /// string the tests read and the storage the card draws cannot drift.
    ///
    /// `base` replaces `base(theme:)` for the run under the spans, which is how a card's own
    /// whole-card text colour and alignment (ADR-0027 §D4, §D7) reach the text: they sit *under*
    /// the spans, so a purple card still draws its links in the accent colour instead of
    /// flattening every span to one colour.
    static func apply(
        to storage: NSMutableAttributedString,
        theme: Theme,
        base overrides: [NSAttributedString.Key: Any]? = nil
    ) {
        let text = storage.string
        let length = (text as NSString).length
        storage.setAttributes(overrides ?? base(theme: theme), range: NSRange(location: 0, length: length))
        for styled in MarkdownStyler.spans(in: text) {
            let range = NSRange(styled.range, in: text)
            guard range.location != NSNotFound, NSMaxRange(range) <= length else { continue }
            storage.addAttributes(attributes(for: styled.span, theme: theme), range: range)
        }
    }

    /// One span's attributes. Same signature shape as
    /// `MarkdownAttributedText.attributes(for:theme:links:)` for consistency between the two
    /// tables, minus the `links:` parameter - a card's links are never clickable, so there is
    /// no default to override.
    static func attributes(
        for span: MarkdownStyler.Span,
        theme: Theme
    ) -> [NSAttributedString.Key: Any] {
        switch span {
        case .heading(let level):
            [
                .font: NSFont.systemFont(ofSize: headingSize(level, theme: theme), weight: .semibold),
                .foregroundColor: NSColor(theme.color(.textPrimary)),
            ]
        case .bold:
            // The system family, chosen here rather than inherited from the `.body` token: ADR-0027
            // §D1 requires a card's bold to be genuinely bold and never the note editor's
            // monospaced bold, and a theme is free to declare `.body` monospaced. Only the size
            // comes from the token.
            [.font: NSFont.systemFont(ofSize: bodyFont(theme).pointSize, weight: .bold)]
        case .italic:
            italicAttributes(theme)
        case .strikethrough:
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .code:
            [
                .font: NSFont.monospacedSystemFont(ofSize: bodyFont(theme).pointSize, weight: .regular),
                .foregroundColor: NSColor(theme.color(.textSecondary)),
            ]
        case .codeBlock:
            // A monospaced face and a background; the colour is left to whatever grammar found
            // something inside, exactly as the note editor's own table leaves it.
            [
                .font: NSFont.monospacedSystemFont(ofSize: bodyFont(theme).pointSize, weight: .regular),
                .backgroundColor: NSColor(theme.color(.surfaceSunken)),
            ]
        case .linkTarget, .embedTarget:
            // Styled, never clickable: a canvas card's text view has no note open to route a click
            // to (ADR-0027 §D1), so the colour and the underline say "this names something" and
            // there is deliberately no `.link` key and no `.cursor` to promise a navigation that
            // does not exist.
            [
                .foregroundColor: NSColor(theme.color(.accentPrimary)),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        case .embedRun:
            // Nothing, for the reason the note editor's table returns nothing: the span covers a
            // whole `![[foto.png]]` line, wider than the marker-sized spans the colour table below
            // is safe for, and a card draws no embed preview at all.
            [:]
        default:
            [.foregroundColor: NSColor(theme.color(colorToken(for: span)))]
        }
    }

    // MARK: Fonts

    /// The card's base face: the `.body` typography token, proportional where the theme says so.
    /// Deliberately not `.heading`, which is what a plain `.text` card used to be drawn in - a
    /// card whose body text is already heading-sized has no way left to show a real `#` heading
    /// (R-05), and one component drawing both states (R-08) can only have one base.
    private static func bodyFont(_ theme: Theme) -> NSFont { theme.nsFont(.body) }

    /// A heading's size, interpolated between the `.title` and `.body` tokens so the six levels
    /// stay inside the theme's own scale instead of naming point sizes of their own.
    private static func headingSize(_ level: Int, theme: Theme) -> CGFloat {
        let title = theme.nsFont(.title).pointSize
        let body = bodyFont(theme).pointSize
        return max(body + 1, title - CGFloat(level - 1) * 2)
    }

    /// A real italic face where the family has one. Where it has none, the upright face is
    /// slanted instead (`.obliqueness`, the note editor's own choice) rather than left looking
    /// identical to the text around it.
    private static func italicAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        let base = bodyFont(theme)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        guard let italic = NSFont(descriptor: descriptor, size: base.pointSize),
              italic.fontDescriptor.symbolicTraits.contains(.italic)
        else {
            return [.obliqueness: 0.2]
        }
        return [.font: italic]
    }

    // MARK: Colours

    /// Every span's colour, as a theme token - the six with an arm of their own above included,
    /// even though they never arrive here. No `default`, on purpose: a span added to
    /// `MarkdownStyler` later lands on this switch and the compiler asks what colour a card
    /// draws it in. The card's own table rather than `MarkdownAttributedText.colorToken(for:)`,
    /// for the reason this file's header gives: the two surfaces are free to look different, and
    /// sharing a table is how they would stop being.
    private static func colorToken(for span: MarkdownStyler.Span) -> ColorToken {
        switch span {
        case .heading, .bold, .italic, .codeBlock: .textPrimary
        // Struck-through text is text the author kept and marked as gone: dimmer than the rest,
        // because the line already says what it is.
        case .strikethrough: .textSecondary
        case .frontmatter, .code, .annotation: .textSecondary
        case .linkSyntax, .headingMarker, .emphasisMarker, .embedRun: .textTertiary
        case .tag, .linkTarget, .embedTarget: .accentPrimary
        case .codeToken(let token): token.colorToken
        case .taskMarker(let done): done ? .taskDone : .taskOpen
        case .scheduled: .taskScheduled
        case .due: .taskOverdue
        // Placeholder arm only, to keep this switch exhaustive (Task 1 owns the
        // declaration, not the styling). The coder assigns `.textTertiary` in Task 1's
        // "Then implement" step (`2026-08-29-wysiwyg-markdown-in-workspace.md`).
        case .listMarker: .textPrimary
        }
    }
}
