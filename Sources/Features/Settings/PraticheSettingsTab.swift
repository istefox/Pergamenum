import AppKit
import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 9 -
// R-35; UX-BLUEPRINT "Settings layout"; screen 1f.
//
// The eleventh Settings tab. Eight rows (UX-BLUEPRINT's own table): six bind
// `VaultSettings.pratiche` directly (a trivial, deterministic `Binding` - the same
// class of "real" mapping `TaskSettings`'s own Picker/Toggle bindings already ship,
// not a stub), and two are UI-only and read something other than the settings file -
// «Accesso completo al disco» reads `FullDiskAccessProbe.state()` (already real,
// Task 5), «Sincronizzazione» triggers a sync the coder wires (this tab has no
// `PraticheController` of its own - Settings can be opened with no pratica pane ever
// having existed this launch).
//
// Own addresses pre-fill (R-35, SPEC "Sent detection and counterpart") calls
// `MailStoreReader.sentSenderAddresses()` behind the same publish-then-open sequence
// `MailSeedPicker.reader(mailRoot:stateDirectory:)` already uses - genuinely off the
// Mail store, which is why this tab (not a connector) is where it belongs (R-36 keeps
// `VaultAPI` from doing the same). That query is itself a RED stub
// (`Sources/Core/Email/MailStoreReader.swift`), so the pre-fill call below is wired
// but returns nothing until the coder fills it in - never crashes, never touches
// `ownAddresses` when the store cannot be read.
struct PraticheSettingsTab: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    @State private var newAddress = ""
    @State private var fullDiskAccessState = FullDiskAccessProbe.state()
    @State private var syncProblem: String?

    var body: some View {
        Form {
            rootFolderRow
            ownAddressesRow
            Toggle("Conserva l'originale .eml", isOn: Binding(
                get: { vault.settings.pratiche.keepOriginalEML },
                set: { value in vault.updateSettings { $0.pratiche.keepOriginalEML = value } }
            ))
            .accessibilityIdentifier("settings-pratiche-keep-eml")

            Stepper(
                "Soglia allegati: \(vault.settings.pratiche.attachmentThresholdMB) MB",
                value: Binding(
                    get: { vault.settings.pratiche.attachmentThresholdMB },
                    set: { value in vault.updateSettings { $0.pratiche.attachmentThresholdMB = value } }
                ),
                in: PraticheSettings.attachmentThresholdRange
            )
            .accessibilityIdentifier("settings-pratiche-attachment-threshold")

            Stepper(
                "Finestra proposte: \(vault.settings.pratiche.proposalWindowDays) giorni",
                value: Binding(
                    get: { vault.settings.pratiche.proposalWindowDays },
                    set: { value in vault.updateSettings { $0.pratiche.proposalWindowDays = value } }
                ),
                in: PraticheSettings.proposalWindowRange
            )
            .accessibilityIdentifier("settings-pratiche-proposal-window")

            Toggle("Scrivi nel diario", isOn: Binding(
                get: { vault.settings.pratiche.mirrorsToDailyNote },
                set: { value in vault.updateSettings { $0.pratiche.mirrorsToDailyNote = value } }
            ))
            .accessibilityIdentifier("settings-pratiche-mirror-daily-note")

            fullDiskAccessRow
            syncRow
        }
        .formStyle(.grouped)
        .task { prefillOwnAddressesIfNeeded() }
    }

    // MARK: - Cartella radice

    private var rootFolderRow: some View {
        LabeledContent("Cartella radice") {
            HStack {
                Text(vault.settings.pratiche.rootFolder)
                    .themedText(.body, color: .textSecondary)
                    .accessibilityIdentifier("settings-pratiche-root-folder-label")
                Button("Scegli…") { chooseRootFolder() }
                    .accessibilityIdentifier("settings-pratiche-root-folder-choose")
            }
        }
    }

    /// `NSOpenPanel` scoped to the open vault: a root folder outside it would name a
    /// folder no `VaultSession.write` can ever reach.
    private func chooseRootFolder() {
        guard let root = vault.root else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let relative = chosen.path(percentEncoded: false)
            .replacingOccurrences(of: root.path(percentEncoded: false) + "/", with: "")
        vault.updateSettings { $0.pratiche.rootFolder = relative }
    }

    // MARK: - I miei indirizzi

    private var ownAddressesRow: some View {
        LabeledContent("I miei indirizzi") {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                ForEach(vault.settings.pratiche.ownAddresses, id: \.self) { address in
                    HStack {
                        Text(address).themedText(.body, color: .textSecondary)
                        Button("Rimuovi") { removeOwnAddress(address) }
                            .accessibilityIdentifier("settings-pratiche-own-address-remove-\(address)")
                    }
                    .accessibilityIdentifier("settings-pratiche-own-address-\(address)")
                }
                HStack {
                    TextField("nuovo indirizzo", text: $newAddress)
                        .accessibilityIdentifier("settings-pratiche-own-address-field")
                    Button("Aggiungi") { addOwnAddress() }
                        .disabled(newAddress.isEmpty)
                        .accessibilityIdentifier("settings-pratiche-own-address-add")
                }
            }
        }
        .accessibilityIdentifier("settings-pratiche-own-addresses")
    }

    private func addOwnAddress() {
        let address = newAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        vault.updateSettings { settings in
            guard !settings.pratiche.ownAddresses.contains(address) else { return }
            settings.pratiche.ownAddresses.append(address)
        }
        newAddress = ""
    }

    private func removeOwnAddress(_ address: String) {
        vault.updateSettings { settings in
            settings.pratiche.ownAddresses.removeAll { $0 == address }
        }
    }

    /// R-35: "own addresses pre-fill from the index and stay editable". Runs once per
    /// appearance of this tab, only while the list is still empty - a person's own
    /// deletions (down to zero) must not be silently repopulated on every visit.
    private func prefillOwnAddressesIfNeeded() {
        guard vault.settings.pratiche.ownAddresses.isEmpty else { return }
        guard fullDiskAccessState == .granted else { return }
        let addresses = PraticheSettingsTab.sentSenderAddresses(
            mailRoot: MailStoreLocation.resolve(),
            stateDirectory: PraticheController.stateDirectory(
                for: vault.session ?? { fatalError("no open vault") }()
            )
        )
        guard !addresses.isEmpty else { return }
        vault.updateSettings { $0.pratiche.ownAddresses = addresses }
    }

    /// Off the main actor's own state on purpose - `MailSeedPicker.reader(mailRoot:
    /// stateDirectory:)`'s own shape, kept `nonisolated` so a slow copy of the
    /// Envelope Index never blocks Settings from redrawing.
    private nonisolated static func sentSenderAddresses(mailRoot: URL, stateDirectory: URL) -> [String] {
        switch MailStoreCopy.publish(from: mailRoot, into: stateDirectory) {
        case .published(let url), .unchanged(let url):
            let indexURL = url.appending(path: "Envelope Index", directoryHint: .notDirectory)
            guard let reader = try? MailStoreReader(storeURL: indexURL) else { return [] }
            return reader.sentSenderAddresses()
        case .mailIsWriting, .storeMissing:
            return []
        }
    }

    // MARK: - Accesso completo al disco

    private var fullDiskAccessRow: some View {
        LabeledContent("Accesso completo al disco") {
            HStack {
                accessLabel
                if fullDiskAccessState == .notGranted {
                    Button("Apri Impostazioni di Sistema") { openFullDiskAccessSettings() }
                        .accessibilityIdentifier("settings-pratiche-fda-open-settings")
                }
            }
        }
        .accessibilityIdentifier("settings-pratiche-fda")
        .task { fullDiskAccessState = FullDiskAccessProbe.state() }
    }

    private var accessLabel: some View {
        switch fullDiskAccessState {
        case .granted:
            Label("concesso", systemImage: "checkmark.circle")
                .themedText(.body, color: .textSecondary)
        case .notGranted:
            Label("negato", systemImage: "xmark.circle")
                .themedText(.body, color: .taskOverdue)
        }
    }

    /// `x-apple.systempreferences:` is the one URL scheme System Settings answers to
    /// for a specific pane - `EventKitStore.openPrivacySettings(for:)`'s own
    /// precedent, not reused directly since Full Disk Access is not one of that
    /// function's two cases.
    private func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Sincronizzazione

    /// «Aggiorna tutte le pratiche ora · ultima: …» (UX-BLUEPRINT). No
    /// `PraticheController` is guaranteed to exist when Settings opens (a person can
    /// reach Impostazioni without ever having opened the Pratiche pane this launch),
    /// so this row is deliberately inert until the coder decides where that trigger
    /// actually lives - a stub, not a real sync, so nothing here can silently touch
    /// the Mail store from Settings.
    private var syncRow: some View {
        LabeledContent("Sincronizzazione") {
            VStack(alignment: .leading) {
                Button("Aggiorna tutte le pratiche ora") {
                    syncProblem = "Apri il pannello Pratiche per sincronizzare."
                }
                .accessibilityIdentifier("settings-pratiche-sync-now")
                if let syncProblem {
                    Text(syncProblem).themedText(.caption, color: .textTertiary)
                }
            }
        }
        .accessibilityIdentifier("settings-pratiche-sync")
    }
}
