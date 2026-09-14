import SwiftUI

/// Creates a structural link, asking for the reason in both directions.
///
/// The reason is required by W-04 and the return link by W-05, so both are in the
/// form rather than optional extras: a link without a reason is a citation, and one
/// written in a single direction is the discrepancy the conformance view reports.
struct RelatedLinkSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedTitle: String?
    @State private var reason = ""
    @State private var reverseReason = ""
    @State private var error: String?

    private var sourceTitle: String { vault.openNote?.title ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Nota correlata").themedText(.title)
            Text("Un legame strutturale si scrive su entrambe le note, ciascuna con il suo motivo.")
                .themedText(.caption, color: .textSecondary)

            TextField("Cerca la nota da collegare…", text: $query)
                .textFieldStyle(.roundedBorder)

            List(candidates, id: \.relativePath, selection: $selectedTitle) { note in
                HStack {
                    Text(note.title).themedText(.body)
                    Spacer()
                    Text(note.folder).themedText(.caption, color: .textTertiary)
                }
                .contentShape(Rectangle())
                .tag(note.title)
            }
            .frame(height: 150)
            .scrollContentBackground(.hidden)

            if let selectedTitle {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    Text("Perché «\(sourceTitle)» rimanda a «\(selectedTitle)»")
                        .themedText(.caption, color: .textTertiary)
                    TextField("motivo", text: $reason)
                        .textFieldStyle(.roundedBorder)

                    Text("Perché «\(selectedTitle)» rimanda a «\(sourceTitle)»")
                        .themedText(.caption, color: .textTertiary)
                    TextField("motivo del ritorno", text: $reverseReason)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let error {
                Text(error).themedText(.caption, color: .taskOverdue)
            }

            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Collega", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
    }

    private var candidates: [NoteRecord] {
        let openPath = vault.openNote?.relativePath
        return vault.index.search(query, limit: 20).filter { $0.relativePath != openPath }
    }

    private var isComplete: Bool {
        selectedTitle != nil
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty
            && !reverseReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        guard let selectedTitle, let source = vault.openNote else { return }
        Task { @MainActor in
            let created = await vault.addStructuralLink(
                from: source.relativePath,
                to: selectedTitle,
                reason: reason,
                reverseReason: reverseReason
            )
            if created {
                dismiss()
            } else {
                error = vault.problems.last ?? "il legame non è stato creato"
            }
        }
    }
}
