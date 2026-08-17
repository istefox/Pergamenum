import SwiftUI

/// The table half of reading mode.
///
/// In a file of its own so the view stays inside SwiftLint's type body length: a GFM
/// table is a good third of what reading mode draws, and it draws nothing else.
extension MarkdownBlocksView {
    /// A GFM table.
    ///
    /// A `Grid` rather than a horizontally scrolling one: the reading column is capped
    /// at 760 points and every other block wraps inside it, so a table that wraps is
    /// the consistent choice and never leaves content off the side of the page.
    func table(_ table: MarkdownBlock.Table) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: theme.spacing(.m), verticalSpacing: theme.spacing(.xs)) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { index, cell in
                    Text(inline(cell, base: theme.font(.body).weight(.semibold)))
                        .multilineTextAlignment(textAlignment(table.alignments[index]))
                        // Set on the header cell only: a grid column takes its
                        // alignment from the first row that states one.
                        .gridColumnAlignment(alignment(table.alignments[index]))
                }
            }
            Rectangle()
                .fill(theme.color(.borderSubtle))
                .frame(height: 1)
                .gridCellColumns(max(table.header.count, 1))
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        Text(inline(cell))
                            .themedText(.body)
                            .multilineTextAlignment(textAlignment(table.alignments[index]))
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    func alignment(_ column: MarkdownBlock.Table.Column) -> HorizontalAlignment {
        switch column {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    func textAlignment(_ column: MarkdownBlock.Table.Column) -> TextAlignment {
        switch column {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
