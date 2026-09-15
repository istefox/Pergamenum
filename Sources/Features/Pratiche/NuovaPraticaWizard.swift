import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-20; DESIGN.md screen 1d and its Binding decision ("Wizard uses an eyebrow «PASSO n
// DI 3», a Form layout and footers Annulla/Continua, Indietro/Continua, Indietro/Crea").
//
// The sheet holds one `WizardState` and nothing else: every gate it draws
// (`canContinueFromNameAndClient`, `canAdvance`, `canCreate`) and the `Dossier` «Crea»
// writes (`makeDossier()`) are that value's own, so the sheet cannot disagree with
// what the tests pin.
//
// «Crea» writes `pratica.md` once, through `VaultSession.write` (ADR §D5), and then
// asks for the first sync - which runs in the background with the pane's own progress
// bar, because it is the ordinary per-pratica sync and not a second import path.
struct NuovaPraticaWizard: View {
    /// Not `private`, on this property, `pratiche` and `vault` below: `NuovaPraticaWizard+
    /// Steps.swift`'s `nameAndClient`, `knownClients`, `seed`, `tick` and `footer`, and
    /// `NuovaPraticaWizard+Actions.swift`'s `resolveSeed`, `performLoadProposals` and
    /// `performCreate`, are extensions of this same struct in separate files, and read
    /// one or more of the three below.
    @Environment(\.theme) var theme
    @Environment(PraticheController.self) var pratiche
    @Environment(VaultController.self) var vault

    let onClose: () -> Void

    /// Not `private`, on this property and every other `@State` down to `typedAddress`
    /// below: `NuovaPraticaWizard+Steps.swift`'s four step views, `footer`, `step(by:)`
    /// and their helpers, and `NuovaPraticaWizard+Actions.swift`'s
    /// `seedFromMailSelection`, `resolveSeed`, `adopt`, `loadProposals`,
    /// `performLoadProposals`, `create` and `performCreate`, are extensions of this same
    /// struct in separate files, and read one or more of the six below - `problem` only
    /// from the second, `isShowingSeedPicker` and `typedAddress` only from the first.
    @State var state = WizardState()
    @State var problem: String?
    @State var isLoadingProposals = false
    @State var isShowingSeedPicker = false
    /// The addresses step 2 offers as chips, and which of them are ticked - kept apart
    /// from `state.counterparts` (the ticked ones) so unticking a chip does not lose it
    /// from the list.
    @State var candidateAddresses: [String] = []
    @State var typedAddress = ""

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("PASSO \(state.step.rawValue + 1) DI \(state.newCounterpartCandidates.isEmpty ? 3 : 4)")
                .themedText(.caption, color: .textTertiary)
                .accessibilityIdentifier("pratiche-wizard-step")
            Text(Self.title(of: state.step)).themedText(.title)
            Form {
                switch state.step {
                case .nameAndClient: nameAndClient
                case .seed: seed
                case .proposals: proposals
                case .newCounterparts: newCounterparts
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            if let problem {
                Text(problem)
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("pratiche-wizard-problem")
            }
            footer
        }
        .padding(theme.spacing(.l))
        .frame(width: 560, height: 520)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-wizard")
        .onAppear { state.rootFolder = vault.settings.pratiche.rootFolder }
        .sheet(isPresented: $isShowingSeedPicker) {
            MailSeedPicker(
                windowDays: vault.settings.pratiche.proposalWindowDays,
                onCancel: { isShowingSeedPicker = false },
                onChoose: { address, proposal, messages in
                    isShowingSeedPicker = false
                    if let id = Int(proposal.id) { state.conversationMessages[id] = messages }
                    adopt(seed: .search, address: address, proposal: proposal)
                }
            )
        }
    }
}
