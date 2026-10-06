import SwiftUI

/// File → "Importa file…" (SPEC §10, rename-assisted per §4.2). The vault-wide
/// counterpart of `Sources/Features/Workspace/BoardSheets.swift`'s `ImportSheet`,
/// which does the same job for a board's drag-and-drop import: same shape, bound to
/// `FileImportProposal` instead of a board-scoped `WorkspaceController.ImportProposal`.
struct FileImportSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Binding var proposals: [FileImportProposal]
    let onCancel: () -> Void
    let onConfirm: ([FileImportProposal]) -> Void

    /// The folder `commitImport` copies into: the vault's inbox folder (ADR-0080 §D5).
    private var inboxFolder: String {
        vault.session?.inboxFolder ?? VaultSettings.defaultInboxFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(proposals.count == 1 ? "Importa file" : "Importa \(proposals.count) file")
                .themedText(.title)
            Text("""
                I file vengono copiati in \(inboxFolder). Il nome proposto segue le convenzioni harness, \
                puoi modificarlo.
                """)
                .themedText(.caption, color: .textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    ForEach($proposals) { $proposal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.originalName)
                                .themedText(.caption, color: .textTertiary)
                            TextField("Nome file", text: $proposal.proposedName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Importa") { onConfirm(proposals) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
    }
}
