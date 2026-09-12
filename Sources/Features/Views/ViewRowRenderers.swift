import SwiftUI

/// The rows of a `render: table` (ADR-0009), drawn as the approved mockup draws them.
///
/// Columns are the block's, in the order it wrote them, and the sorted one says so in its
/// header: `sort:` lives in a block the reader may not have open, and a table that did not
/// show it would look arbitrarily ordered.
///
/// Widths are proportional rather than fixed. A rendered view sits in a reading column whose
/// width is the window's, so a table of five columns in points would be right on one machine
/// and clipped on the next.
struct ViewTableRenderer: View {
    @Environment(\.theme) private var theme

    let block: ViewBlock
    let result: ViewResult
    /// A click target carrying the clicked row's own title (ADR-0033 §D9, R-09). `nil` means
    /// no row is clickable - today's rendering, and what R-10/R-11 (transclusion, export) rely
    /// on staying true without their own edit.
    var onOpenNote: ((String) -> Void)?

    private var columns: [ViewField] { block.effectiveColumns }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: theme.spacing(.s), verticalSpacing: 0) {
            GridRow {
                ForEach(columns, id: \.self) { field in
                    HStack(spacing: 2) {
                        Text(field.label).themedText(.caption, color: .textTertiary)
                        if let key = block.sort.first, key.field == field {
                            Image(systemName: key.descending ? "chevron.down" : "chevron.up")
                                .themedText(.caption, color: .textTertiary)
                        }
                    }
                }
            }
            .padding(.bottom, theme.spacing(.xs))

            ForEach(result.groups.indices, id: \.self) { index in
                group(result.groups[index])
            }
        }
        .accessibilityIdentifier("view-table")
    }

    @ViewBuilder
    private func group(_ group: ViewResult.Group) -> some View {
        // A grouped table keeps its groups: `group:` is one of the seven keys and dropping it
        // for four of the five renderers would make the same block mean different things.
        if result.groups.count > 1 {
            GridRow {
                Text(group.label ?? block.group?.absentLabel ?? "Senza valore")
                    .themedText(.caption, color: .textSecondary)
                    .padding(.top, theme.spacing(.s))
                    .gridCellColumns(columns.count)
            }
        }
        ForEach(group.rows, id: \.path) { row in
            GridRow {
                ForEach(columns, id: \.self) { field in
                    // The first column is the note's own title, drawn in `.accentPrimary`
                    // since PG-012 and clickable only from ADR-0033 on (R-09) - the other
                    // columns carry values, not names, so a click there would open a note the
                    // reader did not point at.
                    ViewCell(field: field, row: row, isFirst: field == columns.first)
                        .opensNote(field == columns.first ? openAction(for: row) : nil)
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
    }

    /// The action a click on `row`'s own title performs (R-09) - `nil` when nothing is
    /// listening, which is a row with no click target at all.
    ///
    /// A function rather than a closure inlined at the call site, so what a click does can be
    /// asserted without a live SwiftUI render (`Tests/ViewBlockQuerySourceTests.swift`): it is
    /// a fact about the renderer, and reading it back out of a rendered `Button` would be an
    /// assertion about SwiftUI instead.
    func openAction(for row: ViewResult.Row) -> (() -> Void)? {
        guard let onOpenNote else { return nil }
        return { onOpenNote(row.title) }
    }
}

/// One cell. Tags are chips wherever they appear, because a tag in a table and a tag in the
/// sidebar are the same thing; everything else is the one string `ViewValueText` gives.
struct ViewCell: View {
    let field: ViewField
    let row: ViewResult.Row
    var isFirst = false

    /// The evaluated value when the block asked for this column, and the record's own
    /// otherwise. Not always the record: `linkedFrom` and `unresolved` are answers only the
    /// whole vault has, and a cell computing them from one note would quietly draw an empty
    /// column (`ViewGraph` says why they are precomputed).
    private var value: ViewValue { row.values[field] ?? field.value(of: row.record) }

    var body: some View {
        if field == .tags, case .list(let tags) = value, !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { ViewTagChip(text: $0) }
            }
        } else if let text = ViewValueText.text(value, of: field) {
            Text(text)
                .themedText(isFirst ? .body : .caption, color: isFirst ? .accentPrimary : .textSecondary)
                .lineLimit(isFirst ? 1 : 2)
        } else {
            // An em dash, never a blank: a blank cell and a cell holding an empty string are
            // the same picture, and the file says different things.
            Text("—").themedText(.caption, color: .textTertiary)
        }
    }
}

/// The list renderer: for a view embedded in a note that is about something else.
///
/// One line each, every column after the first folded into a single caption in the order the
/// block wrote them. A project page carrying its own documents wants a paragraph's worth of
/// rows, not a table with headers.
struct ViewListRenderer: View {
    @Environment(\.theme) private var theme

    let block: ViewBlock
    let result: ViewResult
    /// A click target carrying the clicked line's own title (ADR-0033 §D9, R-09). `nil` means
    /// no line is clickable - today's rendering.
    var onOpenNote: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(result.groups.indices, id: \.self) { index in
                let group = result.groups[index]
                if result.groups.count > 1 {
                    Text(group.label ?? block.group?.absentLabel ?? "Senza valore")
                        .themedText(.caption, color: .textSecondary)
                        .padding(.top, theme.spacing(.xs))
                }
                ForEach(group.rows, id: \.path) { row in
                    line(row)
                }
            }
        }
        .accessibilityIdentifier("view-list")
    }

    private func line(_ row: ViewResult.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: "doc.text").themedText(.caption, color: .textTertiary)
            // The title alone, not the whole line: the detail caption is other columns'
            // values, and a click on those would be a click on something that is not a name.
            Text(row.title).themedText(.body, color: .accentPrimary).lineLimit(1)
                .opensNote(openAction(for: row))
            Text(detail(row)).themedText(.caption, color: .textTertiary).lineLimit(1)
        }
    }

    /// Everything but the first column, joined. A field with no value is left out rather than
    /// drawn as an em dash: in a caption a dash between two separators reads as a mistake,
    /// and a list row has room to say nothing at all.
    private func detail(_ row: ViewResult.Row) -> String {
        block.effectiveColumns
            .dropFirst()
            .compactMap { field in
                ViewValueText.text(row.values[field] ?? field.value(of: row.record), of: field)
            }
            .joined(separator: " · ")
    }

    /// `ViewTableRenderer.openAction(for:)`'s own twin, same reason and same seam (R-09).
    func openAction(for row: ViewResult.Row) -> (() -> Void)? {
        guard let onOpenNote else { return nil }
        return { onOpenNote(row.title) }
    }
}

extension View {
    /// Wraps a row's own title in the click target R-09 gives it, and leaves it untouched
    /// when there is no action - which is every surface that passes no `onOpenNote`, and
    /// therefore today's rendering for the transclusion and export paths (R-10, R-11).
    ///
    /// Declared once for all four renderers rather than four times: the four are one gesture
    /// with four drawings, and a per-renderer copy is four places for the plain button style
    /// or the hit area to drift. A `Button` and not an `onTapGesture`, because a target that
    /// answers the keyboard and reports itself to accessibility is what a row that opens a
    /// note is.
    @ViewBuilder
    func opensNote(_ action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                // The whole rectangle, so a card's gaps and a chip's padding are the target
                // too - without it only the glyphs themselves answer the click.
                contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            self
        }
    }
}

/// A tag, drawn the way the tag browser draws one.
struct ViewTagChip: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .themedText(.caption, color: .textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
