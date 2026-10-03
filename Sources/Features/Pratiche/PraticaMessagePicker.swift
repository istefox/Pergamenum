import SwiftUI

// ADR-0076 §D8 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 7 - R-11.

/// «Collega a un messaggio…»'s picker: `PraticaLinkPicker`'s shape - title, filter, list,
/// footer, 380×380 - over the pratica's own messages. Which rows it lists, under which filter
/// and which one is current is `PraticaMessagePickerModel.rows`; this view only draws them and
/// hands the chosen Message-ID to `PraticaCommandActions.anchor(_:to:)`, the guarded door.
struct PraticaMessagePicker: View {
    @Environment(\.theme) private var theme

    let request: PraticaAnchorRequest
    /// The timeline the entry sits in, read when the picker opened.
    let messages: [PraticaTimelineEntry]
    let actions: PraticaCommandActions
    let onClose: () -> Void

    @State private var filter = ""

    /// The anchor the entry carries now, orphaned or not, so the picker can mark it.
    private var currentAnchor: String? {
        switch request.entry.placement {
        case .anchored(let messageID), .orphaned(let messageID), .excluded(let messageID): messageID
        default: nil
        }
    }

    private var rows: [PraticaMessagePickerModel.Row] {
        PraticaMessagePickerModel.rows(from: messages, filter: filter, currentAnchor: currentAnchor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 380)
        .background(theme.color(.surfaceCard))
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-message-picker")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Collega a un messaggio").themedText(.title)
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.color(.textTertiary))
                TextField("Filtra", text: $filter)
                    .textFieldStyle(.plain)
                    .themedText(.body)
                    .onSubmit { if let first = rows.first { choose(first) } }
                    .accessibilityIdentifier("pratiche-message-picker-filter")
            }
        }
        .padding(theme.spacing(.m))
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    rowView(row)
                }
                if rows.isEmpty {
                    Text(filter.isEmpty ? "Nessun messaggio in questa pratica" : "Nessun messaggio trovato")
                        .themedText(.body, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, theme.spacing(.l))
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
        .accessibilityIdentifier("pratiche-message-picker-list")
    }

    private func rowView(_ row: PraticaMessagePickerModel.Row) -> some View {
        Button { choose(row) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.subject).themedText(.body).lineLimit(1)
                    Text("\(PraticaRowFormat.spokenDate(row.date)) · \(row.sender)")
                        .themedText(.caption, color: .textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: theme.spacing(.xs))
                if row.isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.color(.accentPrimary))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ([row.subject, PraticaRowFormat.spokenDate(row.date), row.sender]
                + (row.isCurrent ? ["collegata ora"] : [])).joined(separator: ", ")
        )
        .accessibilityIdentifier("pratiche-message-picker-row-\(row.messageID)")
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Chiudi", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(theme.spacing(.m))
    }

    /// Runs the guarded write, then closes - the picker's job ends when the anchor is written
    /// or refused, and a refusal is reported by the door itself.
    private func choose(_ row: PraticaMessagePickerModel.Row) {
        let entry = request.entry
        Task { @MainActor in
            await actions.anchor(entry, to: row.messageID)
            onClose()
        }
    }
}
