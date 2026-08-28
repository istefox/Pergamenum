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
/// Rules the implementation (coder-owned, this file's bodies are stubs) must satisfy - held to
/// them by `Tests/CardTextViewTests.swift`:
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
        fatalError("not implemented")
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
        fatalError("not implemented")
    }

    /// One span's attributes. Same signature shape as
    /// `MarkdownAttributedText.attributes(for:theme:links:)` for consistency between the two
    /// tables, minus the `links:` parameter - a card's links are never clickable, so there is
    /// no default to override.
    static func attributes(
        for span: MarkdownStyler.Span,
        theme: Theme
    ) -> [NSAttributedString.Key: Any] {
        fatalError("not implemented")
    }
}
