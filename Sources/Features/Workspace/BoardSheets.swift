import SwiftUI

struct NewCanvasItemSheet: View {
    enum Kind { case folder, link, note }

    @Environment(\.theme) private var theme
    let kind: Kind
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var value = ""

    private var title: String {
        switch kind {
        case .folder: "Nuova cartella"
        case .link: "Nuovo link"
        case .note: "Nuovo documento"
        }
    }

    private var prompt: String {
        switch kind {
        case .folder: "Nome della cartella"
        case .link: "URL o URI (https://, obsidian://, message://)"
        case .note: "Titolo della nota"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            TextField(prompt, text: $value)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Crea") { onConfirm(value.trimmingCharacters(in: .whitespaces)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }
}

/// Renders a file's thumbnail, falling back to its type icon while the render runs
/// or when the file has no preview at all.
struct ImportSheet: View {
    @Environment(\.theme) private var theme
    @Binding var proposals: [WorkspaceController.ImportProposal]
    let onCancel: () -> Void
    let onConfirm: ([WorkspaceController.ImportProposal]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(proposals.count == 1 ? "Importa file" : "Importa \(proposals.count) file")
                .themedText(.title)
            Text("Il nome proposto segue le convenzioni harness. Puoi modificarlo.")
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
