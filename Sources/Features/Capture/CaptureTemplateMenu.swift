import SwiftUI

// PG-387 (N4), ADR-0086 §D5, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 - R-09.

/// The template a «Nota nuova» capture is composed into, beside the folder under «Nota nuova» only.
///
/// A button and a popover, the `capture-folder` shape (`CapturePanelView.folderPicker` says why not
/// a `Menu`). The choice lives on `CaptureController.template`, which the panel keeps across
/// invocations the way it keeps the destination.
struct CaptureTemplateMenu: View {
    @Environment(\.theme) private var theme
    let controller: CaptureController
    let session: VaultSession?
    /// Called when the popover closes, so the panel hands the keyboard back to the text.
    let onClose: () -> Void

    @State private var isChoosing = false

    private var templates: [NoteRecord] { session?.templates ?? [] }

    private var chosenTitle: String {
        guard let template = controller.template,
              let record = templates.first(where: { $0.relativePath == template })
        else { return "Nessun modello" }
        return record.title
    }

    var body: some View {
        Button { isChoosing = true } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "doc.text")
                Text(chosenTitle).themedText(.caption, color: .textTertiary)
                Image(systemName: "chevron.down").font(theme.font(.iconSmall))
            }
            .foregroundStyle(theme.color(.textTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modello della nota nuova: \(chosenTitle)")
        .accessibilityIdentifier("capture-template")
        .popover(isPresented: $isChoosing) { choices }
        .onChange(of: isChoosing) { _, now in if !now { onClose() } }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            choice("Nessun modello") { controller.template = nil }
            if templates.isEmpty {
                Text("Una nota in \(NoteTemplate.folder)/ diventa un modello")
                    .themedText(.caption, color: .textTertiary)
            }
            ForEach(templates, id: \.relativePath) { record in
                choice(record.title) { controller.template = record.relativePath }
            }
        }
        .padding(theme.spacing(.s))
        .frame(width: 220)
    }

    private func choice(_ title: String, perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            isChoosing = false
        } label: {
            Text(title)
                .themedText(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
