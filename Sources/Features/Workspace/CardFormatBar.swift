import SwiftUI

/// The pill that floats over a `.text` card's own selection (ADR-0027 §D6, plan
/// `2026-08-28-unificare-nota-e-testo-in-un-solo-strume` Task 6, R-03/R-05).
///
/// Same visual language as the note editor's own `Sources/Features/Editor/FormatBar.swift` -
/// theme tokens, `Capsule`, `.themedShadow(.raised)`, and the `.contentShape(Rectangle())` fix
/// for hit-testing a `.clear` background (`FormatBar.swift:90-95`, found by someone having to
/// aim at the glyph) - but its own file and its own catalogue. `FormatBar` itself is neither
/// reused nor edited (ADR §D6): it carries a deliberate, reasoned "no headings and no lists"
/// decision for the note editor that this card does not share, so the two pills are free to
/// drift rather than forcing one bar to serve two surfaces with different rules.
///
/// Six buttons, not four: bold/italic/strikethrough (`InlineFormat`, wraps a selection) plus
/// bullet/numbered/heading (`LineFormat`, rewrites the lines a selection touches). No colour and
/// no alignment button - those are whole-card `CardCommand`s, Task 7's job (ADR §D7), reachable
/// with no selection at all, unlike everything on this bar.
///
/// Wiring is closures rather than a `FormattingTextView` reference: this view has no idea which
/// text view it is floating over, only what is currently applied and what to do when a button is
/// pressed. `BoardFormatBar` (this task) and the coder's later placement wiring supply both.
struct CardFormatBar: View {
    @Environment(\.theme) private var theme

    /// Whether `format` is applied over the current selection - `InlineFormat.isApplied`, read
    /// by the caller and handed in rather than computed here, so this view stays free of any
    /// text-view or string dependency of its own.
    let isInlineApplied: (InlineFormat) -> Bool
    /// Whether `format` is applied to every line the current selection touches -
    /// `LineFormat.isApplied`, same shape as `isInlineApplied`.
    let isLineApplied: (LineFormat) -> Bool
    /// Toggles `format` over the current selection - `FormattingTextView.toggleInlineFormat(_:)`.
    let onToggleInline: (InlineFormat) -> Void
    /// Toggles `format` on the lines the current selection touches -
    /// `FormattingTextView.toggleLineFormat(_:)`.
    let onToggleLine: (LineFormat) -> Void

    /// One button, named rather than a tuple - `FormatBar.Entry`'s own reasoning
    /// (`FormatBar.swift:28-29`): `entry.2` says nothing about what it holds.
    private struct Entry: Identifiable {
        var id: String
        var symbol: String
        var help: String
        var isOn: Bool
        var action: () -> Void
    }

    /// Heading always toggles level 1 from this bar. Cycling through levels 1...3 is not part of
    /// R-05's scope for a single selection-bar button; `LineFormat.heading(level:)` supports the
    /// range, this bar exposes the one a person reaches for first.
    private static let headingLevel = 1

    private var entries: [Entry] {
        [
            Entry(id: "bold", symbol: "bold", help: "Grassetto", isOn: isInlineApplied(.bold)) {
                onToggleInline(.bold)
            },
            Entry(id: "italic", symbol: "italic", help: "Corsivo", isOn: isInlineApplied(.italic)) {
                onToggleInline(.italic)
            },
            Entry(
                id: "strikethrough", symbol: "strikethrough", help: "Barrato",
                isOn: isInlineApplied(.strikethrough)
            ) {
                onToggleInline(.strikethrough)
            },
            Entry(
                id: "bullet", symbol: "list.bullet", help: "Elenco puntato",
                isOn: isLineApplied(.bullet)
            ) {
                onToggleLine(.bullet)
            },
            Entry(
                id: "numbered", symbol: "list.number", help: "Elenco numerato",
                isOn: isLineApplied(.numbered)
            ) {
                onToggleLine(.numbered)
            },
            Entry(
                id: "heading", symbol: "textformat.size", help: "Titolo",
                isOn: isLineApplied(.heading(level: Self.headingLevel))
            ) {
                onToggleLine(.heading(level: Self.headingLevel))
            },
        ]
    }

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(entries) { entry in
                button(entry)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 4)
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        // No stroke, matching FormatBar's own reasoning (FormatBar.swift:69-73): the raised
        // shadow is what separates the pill from the card underneath, not a border drawn on it.
        .themedShadow(.raised)
        .accessibilityIdentifier("card-format-bar")
    }

    private func button(_ entry: Entry) -> some View {
        Button(action: entry.action) {
            Image(systemName: entry.symbol)
                .frame(width: 26, height: 22)
                .foregroundStyle(theme.color(entry.isOn ? .onAccent : .textSecondary))
                .background(entry.isOn ? theme.color(.accentPrimary) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                // Copied from FormatBar.swift:90-95: a `.clear` background otherwise hit-tests
                // only the glyph's own opaque pixels, and this names the whole 26x22 frame as
                // the target instead.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.help)
        .accessibilityLabel(entry.help)
        .accessibilityAddTraits(entry.isOn ? [.isSelected] : [])
        .accessibilityIdentifier("card-format-\(entry.id)")
    }
}
