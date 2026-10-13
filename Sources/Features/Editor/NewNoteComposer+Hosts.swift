import SwiftUI

// PG-387 (N4), ADR-0085 §D7, plan docs/plans/pg-387-n4-birth-of-note.md. The composer's header and
// preview, the parts that read differently in each host, in a file of their own so the composer's
// type body stays under SwiftLint's `type_body_length`.

extension NewNoteComposer {
    var header: some View {
        HStack {
            Text(heading).themedText(.caption, color: .textTertiary)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .buttonStyle(.plain)
            .help("Annulla")
            .accessibilityLabel("Annulla la nuova nota")
        }
    }

    var heading: String {
        switch host {
        case .pane: "Nuova nota"
        case .sheet: "Nuovo documento"
        case .extract: "Estrai in una nota"
        }
    }

    func preview(heading: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(heading).themedText(.caption, color: .textTertiary)
            Text(text)
                .themedText(.body, color: .textSecondary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}
