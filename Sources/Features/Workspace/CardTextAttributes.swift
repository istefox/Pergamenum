import AppKit
import SwiftUI

/// The Workspace card's own attribute table (ADR-0027 §D1), keyed on the same
/// `MarkdownStyler.Span` the note editor already classifies source into.
///
/// Deliberately **not** `MarkdownAttributedText.attributes(for:theme:)`, and this file must
/// never call into it. The two tables no longer disagree about *faces*: since ADR-0030 §D1 both
/// read every face from `ProseTypography`, and the note editor's own `.bold` arm is
/// `ProseTypography.proseBold(theme)` as well - not the `NSFont.monospacedSystemFont(ofSize: 13,
/// weight: .bold)` source-mode look it carried when ADR-0027 §D1 first split the two tables.
/// What still separates them is everything else: a card's `.linkTarget`/`.embedTarget` are never
/// clickable (below), the two colour tables are free to diverge, and a card takes the prose faces
/// but deliberately **not** the page's line height (ADR-0030 §D10), so `base(theme:)` here sets no
/// `.paragraphStyle` where the note editor's does. This table is the sibling ADR-0027 §D1 names -
/// a card renders through this table only, and the note editor's own styling is never touched by
/// this feature.
///
/// The rules this table satisfies, held to by `Tests/CardTextViewTests.swift`:
///
/// - `.bold` -> a genuinely bold, non-monospaced font: the prose family's own bold face through
///   `ProseTypography.proseBold(_:)`. Never `NSFont.monospacedSystemFont`, whatever the note
///   editor happens to draw its own bold in at the time.
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
    /// The card's base attributes: the page's own prose face, `ProseTypography.prose(theme)` -
    /// `font.prose`, not the `font.body` chrome face this read until ADR-0030 §D1, and never
    /// `.heading`, which is what a plain `.text` card used to be drawn in (a card whose body text
    /// is already heading-sized has no way left to show a real `#` heading, R-05, and one
    /// component drawing both states, R-08, can only have one base).
    ///
    /// No `.paragraphStyle`, unlike `MarkdownAttributedText.base(theme:)`: a card takes the prose
    /// faces but deliberately not the page's line height (ADR-0030 §D10).
    ///
    /// Everything `attributes(for:theme:)` returns layers on top of these via
    /// `NSMutableAttributedString.addAttributes(_:range:)`, the same merge-not-replace rule
    /// `MarkdownAttributedText.attributed(_:theme:)` documents.
    static func base(theme: Theme) -> [NSAttributedString.Key: Any] {
        [
            .font: ProseTypography.prose(theme),
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
            // The whole face, not a size handed to `NSFont.systemFont`: `ProseTypography.heading`
            // resizes `font.proseTitle`'s own descriptor (ADR-0030 §D1), so a theme that gives
            // that token a family or a weight of its own is followed on a card at every level -
            // which rebuilding the font from the system family here would silently discard.
            [
                .font: ProseTypography.heading(level: level, theme),
                .foregroundColor: NSColor(theme.color(.textPrimary)),
            ]
        case .bold:
            // The prose family's real bold face. ADR-0027 §D1's requirement is unchanged - a
            // card's bold is genuinely bold and never the note editor's old monospaced bold -
            // but the family is no longer picked here: `proseBold` falls back to the upright
            // prose face rather than to a substitute from another family, which is what kept a
            // monospaced face out of this arm before and still does.
            [.font: ProseTypography.proseBold(theme)]
        case .italic:
            // `ProseTypography` owns the real-italic-or-`.obliqueness` rule for both surfaces
            // (ADR-0030 §D1); this table no longer carries a second copy of it.
            ProseTypography.proseItalicAttributes(theme)
        case .strikethrough:
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .code:
            // The mono token's face at the *prose* size, passed explicitly: the two tokens carry
            // different point sizes, and code set at the chrome size beside 16pt prose reads as a
            // different paragraph rather than as a run inside one.
            [
                .font: ProseTypography.mono(theme, size: ProseTypography.prose(theme).pointSize),
                .foregroundColor: NSColor(theme.color(.textSecondary)),
            ]
        case .codeBlock:
            // A monospaced face and a background; the colour is left to whatever grammar found
            // something inside, exactly as the note editor's own table leaves it.
            [
                .font: ProseTypography.mono(theme, size: ProseTypography.prose(theme).pointSize),
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
    //
    // There are none left here. `bodyFont`, `headingSize` and `italicAttributes` all lived in
    // this file until ADR-0030 §D1 made `ProseTypography` the only place in
    // `Sources/Features/Workspace` scope allowed to construct an `NSFont`: the heading scale and
    // the real-italic-or-`.obliqueness` rule are both that helper's now, so the card and the page
    // cannot drift apart on either. A face named here again would be exactly that drift.

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
        case .linkSyntax, .headingMarker, .emphasisMarker, .embedRun, .listMarker: .textTertiary
        // The four ADR-0029 constructs (plan `2026-09-02-editor-wysiwyg-unification`, Task 1):
        // Workspace `.text` cards are explicitly out of scope for the concealment mechanism
        // itself (ADR §D17/CardTextView.swift stays untouched), but this table must still be
        // exhaustive, so each gets the same shelf `.embedRun` already occupies above.
        case .strikethroughMarker, .blockquoteMarker, .horizontalRule, .tableRun: .textTertiary
        case .tag, .linkTarget, .embedTarget: .accentPrimary
        case .codeToken(let token): token.colorToken
        case .taskMarker(let state): state == .done ? .taskDone : .taskOpen
        case .scheduled: .taskScheduled
        case .due: .taskOverdue
        }
    }
}
