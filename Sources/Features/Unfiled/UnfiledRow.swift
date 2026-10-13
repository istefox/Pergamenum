import SwiftUI

// PG-387 (N4), ADR-0085 §D1/§D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 5 - R-01.

/// One row of «Da classificare»: the title, where the note is, its date, and a mark on a
/// Contenitore scheda, whose form has no folder field.
struct UnfiledRow: View {
    @Environment(\.theme) private var theme
    let row: UnfiledListModel.Row

    var body: some View {
        HStack(spacing: theme.spacing(.m)) {
            Image(systemName: row.isScheda ? "archivebox" : "doc.text")
                .foregroundStyle(theme.color(.textTertiary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).themedText(.body).lineLimit(1)
                Text(subtitle).themedText(.caption, color: .textSecondary).lineLimit(1)
            }
            Spacer(minLength: theme.spacing(.m))
            Text(row.date?.italianForm ?? "").themedText(.caption, color: .textSecondary)
        }
        .padding(.vertical, theme.spacing(.xs))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("unfiled-row")
    }

    private var subtitle: String {
        let place = row.folder.isEmpty ? "(radice)" : row.folder
        return row.isScheda ? "Contenitore · \(place)" : place
    }
}
