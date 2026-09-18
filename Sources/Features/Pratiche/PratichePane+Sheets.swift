import SwiftUI

// ADR-0045 §D3 (PG-143 structure refactor): the rename and regeneration sheets, split
// out of `PratichePane.swift` for its own struct-body length - moved verbatim,
// `NoteListPane.swift:23-30`'s convention for every member this file widens.

extension PratichePane {
    /// Not `private`, on this property and every other member down to
    /// `regenerationReadySheet` below: `PratichePane.swift`'s `body`, in the main file,
    /// presents each of these directly through `.alert`/`.sheet(item:)`.
    var deletionAlert: Binding<Bool> {
        Binding(
            get: { pratiche.deletionRequest != nil },
            set: { if !$0 { pratiche.deletionRequest = nil } }
        )
    }

    var renameRequest: Binding<PraticaListItem?> {
        Binding(
            get: { pratiche.renameRequest },
            set: { pratiche.renameRequest = $0 }
        )
    }

    var regenerationBinding: Binding<PraticheController.RegenerationState?> {
        Binding(
            get: { pratiche.regeneration },
            set: { pratiche.regeneration = $0 }
        )
    }

    func renameSheet(_ pratica: PraticaListItem) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina la pratica").themedText(.title)
            TextField("Nome", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { actions.confirmRename(of: pratica, to: typedName) }
                .accessibilityIdentifier("pratiche-rename-field")
            HStack {
                Spacer()
                Button("Annulla") { pratiche.renameRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rinomina") { actions.confirmRename(of: pratica, to: typedName) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(typedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pratiche-rename-confirm")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 420)
        .onAppear { typedName = pratica.title }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-rename")
    }

    /// «Rigenera…» (§D6's second exception, §D21): shows the diff *before* anything is
    /// trashed or rewritten. `pratiche.regeneration` drives every state this sheet can
    /// be in - acquiring the replacement (`.preparing`), showing it (`.ready`, with a
    /// diff or, when nothing changed, a plain notice) - so re-reading it here rather
    /// than switching on a captured parameter is what lets the sheet update itself
    /// while it is already on screen (§D21.4).
    @ViewBuilder
    func regenerationSheet() -> some View {
        switch pratiche.regeneration {
        case .preparing(_, let subject, _):
            regenerationPreparingSheet(subject: subject)
        case .ready(let plan):
            regenerationReadySheet(plan)
        case nil:
            EmptyView()
        }
    }

    private func regenerationPreparingSheet(subject: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rigenerare «\(subject)»?").themedText(.title)
            HStack(spacing: theme.spacing(.s)) {
                ProgressView().controlSize(.small)
                Text("Sto leggendo il messaggio da Mail…").themedText(.caption, color: .textSecondary)
            }
            HStack {
                Spacer()
                Button("Annulla") { pratiche.dismissRegeneration() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-regenerate")
    }

    private func regenerationReadySheet(_ plan: PraticaSyncEngine.RegenerationPlan) -> some View {
        let fileName = (plan.notePath as NSString).lastPathComponent
        return VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rigenerare «\(fileName)»?").themedText(.title)
            if let diff = plan.diff {
                Text("Le modifiche fatte a mano in «\(plan.notePath)» vanno perse.")
                    .themedText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DiffView(path: plan.notePath, diff: diff)
            } else {
                Text("Il file è già identico al messaggio in Mail: non c'è nulla da rigenerare.")
                    .themedText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if plan.diff != nil {
                    Button("Annulla") { pratiche.dismissRegeneration() }
                        .keyboardShortcut(.cancelAction)
                    Button("Rigenera") { actions.confirmRegeneration(plan) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("pratiche-regenerate-confirm")
                } else {
                    Button("Chiudi") { pratiche.dismissRegeneration() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-regenerate")
    }
}
