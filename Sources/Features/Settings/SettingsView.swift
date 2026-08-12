import SwiftUI

/// The settings window of SPEC §12.
///
/// Vault-level settings are written into `.pergamenum/settings.json`, so the same
/// vault opened on another Mac behaves the same. The theme is a per-user preference
/// and stays in `UserDefaults`.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ThemeEngine.self) private var engine
    @Environment(EventKitStore.self) private var calendar

    var body: some View {
        TabView {
            general.tabItem { Label("Generali", systemImage: "gearshape") }
            canvasTab.tabItem { Label("Canvas", systemImage: "rectangle.3.group") }
            conventions.tabItem { Label("Convenzioni", systemImage: "checkmark.seal") }
            calendarTab.tabItem { Label("Calendario", systemImage: "calendar") }
            advanced.tabItem { Label("Avanzate", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 420)
    }

    // MARK: Generali

    private var general: some View {
        @Bindable var engine = engine
        return Form {
            LabeledContent("Vault") {
                Text(vault.root?.lastPathComponent ?? "nessuno")
                    .themedText(.body, color: .textSecondary)
            }
            LabeledContent("Percorso") {
                Text(vault.root?.path(percentEncoded: false) ?? "—")
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button("Apri un altro vault…") { VaultOpenPanel.chooseVault(into: vault) }

            Picker("Tema", selection: $engine.selection) {
                Text("Sistema").tag(ThemeEngine.Selection.followSystem)
                Text("Chiaro").tag(ThemeEngine.Selection.light)
                Text("Scuro").tag(ThemeEngine.Selection.dark)
                ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { custom in
                    Text(custom.name).tag(ThemeEngine.Selection.named(custom.id))
                }
            }
            if !engine.problems.isEmpty {
                Section("Problemi nei token") {
                    ForEach(engine.problems, id: \.self) { problem in
                        Text(problem).themedText(.caption, color: .taskOverdue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Canvas

    private var canvasTab: some View {
        Form {
            Toggle("Mostra la griglia", isOn: Binding(
                get: { vault.settings.boardShowsGrid },
                set: { value in vault.updateSettings { $0.boardShowsGrid = value } }
            ))
            Toggle("Aggancia alla griglia", isOn: Binding(
                get: { vault.settings.boardSnapsToGrid },
                set: { value in vault.updateSettings { $0.boardSnapsToGrid = value } }
            ))
            Text("Le guide di allineamento con le altre card restano attive comunque: hanno la precedenza sulla griglia.")
                .themedText(.caption, color: .textTertiary)

            Section("Import") {
                Picker("File trascinati", selection: Binding(
                    get: { vault.settings.copyDroppedFiles },
                    set: { value in vault.updateSettings { $0.copyDroppedFiles = value } }
                )) {
                    Text("Copia nel vault").tag(true)
                    Text("Riferimento dove sono").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text("Un riferimento fuori dal vault si rompe il giorno in cui il file viene spostato o il volume non è montato.")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }

    // MARK: Convenzioni

    private var conventions: some View {
        Form {
            TextField("Cartella daily", text: Binding(
                get: { vault.settings.dailyFolder },
                set: { value in
                    vault.updateSettings {
                        $0.dailyFolder = value.trimmingCharacters(in: .whitespaces)
                    }
                }
            ))
            .disabled(vault.root == nil)
            Section("Vocabolari chiusi") {
                LabeledContent("type") { Text("\(vault.vocabulary.type.count) valori") }
                LabeledContent("status") { Text("\(vault.vocabulary.status.count) valori") }
                LabeledContent("area") { Text("\(vault.vocabulary.area.count) valori") }
                LabeledContent("source") { Text("\(vault.vocabulary.source.count) valori") }

                if vault.vocabulary.isEmpty {
                    Text("Nessun vocabolario importato: le famiglie chiuse non sono verificabili.")
                        .themedText(.caption, color: .taskOverdue)
                }
                Button("Importa convenzioni…") {
                    VaultOpenPanel.chooseHarnessRepository(into: vault)
                }
                .disabled(vault.root == nil)
            }
            Text("La repo harness-system resta la fonte di verità: l'app ne tiene una replica dichiarata e non modifica mai i suoi documenti.")
                .themedText(.caption, color: .textTertiary)
        }
        .formStyle(.grouped)
    }

    // MARK: Calendario

    private var calendarTab: some View {
        @Bindable var calendar = calendar
        return Form {
            LabeledContent("Accesso Calendario") { accessLabel(calendar.eventAccess) }
            LabeledContent("Accesso Promemoria") { accessLabel(calendar.reminderAccess) }

            if !calendar.eventAccess.isGranted || !calendar.reminderAccess.isGranted {
                // Asking is only offered while asking can still do something. macOS
                // shows the dialog once; after a refusal the request returns in
                // silence, and a button that silently does nothing is worse than no
                // button at all.
                if calendar.canStillBeAsked {
                    Button("Richiedi accesso") {
                        Task { await calendar.requestAccess() }
                    }
                }
                if calendar.eventAccess == .denied {
                    Button("Apri Impostazioni di Sistema: Calendario") {
                        EventKitStore.openPrivacySettings(for: .event)
                    }
                }
                if calendar.reminderAccess == .denied {
                    Button("Apri Impostazioni di Sistema: Promemoria") {
                        EventKitStore.openPrivacySettings(for: .reminder)
                    }
                }
                Text("macOS chiede il consenso una sola volta. Al ritorno da Impostazioni di Sistema il permesso viene riletto da solo.")
                    .themedText(.caption, color: .textTertiary)
                if let problem = calendar.lastAccessError {
                    Text(problem).themedText(.caption, color: .taskOverdue)
                }
            }

            if calendar.eventAccess.isGranted {
                Picker("Calendario di scrittura", selection: Binding(
                    get: { calendar.writeCalendarTitle ?? "" },
                    set: { calendar.writeCalendarTitle = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Predefinito").tag("")
                    ForEach(calendar.writableCalendarTitles, id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                Text("I time block pubblicati finiscono qui.")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func accessLabel(_ access: CalendarAccess) -> some View {
        switch access {
        case .granted:
            Label("concesso", systemImage: "checkmark.circle")
                .themedText(.body, color: .textSecondary)
        case .denied:
            Label("negato", systemImage: "xmark.circle")
                .themedText(.body, color: .taskOverdue)
        case .notDetermined:
            Label("non richiesto", systemImage: "questionmark.circle")
                .themedText(.body, color: .textTertiary)
        }
    }

    // MARK: Avanzate

    private var advanced: some View {
        Form {
            LabeledContent("Note indicizzate") { Text("\(vault.index.count)") }
            LabeledContent("Ultima scansione") {
                Text(scanDuration).themedText(.body, color: .textSecondary)
            }
            LabeledContent("Riusate dalla cache") {
                Text("\(vault.index.reusedFromCache) su \(vault.index.count)")
                    .themedText(.body, color: .textSecondary)
            }
            Button("Rigenera indice") { Task { await vault.rescan() } }
                .disabled(vault.root == nil)
            Button("Svuota cache e ricostruisci") { Task { await vault.clearCache() } }
                .disabled(vault.root == nil)
            Text("La cache sta in .pergamenum/cache.db e non è mai la fonte di verità: una riga il cui file è cambiato viene scartata.")
                .themedText(.caption, color: .textTertiary)

            if !vault.index.failures.isEmpty {
                Section("File non leggibili") {
                    ForEach(vault.index.failures, id: \.self) { failure in
                        Text(failure).themedText(.caption, color: .taskOverdue)
                    }
                }
            }
            if !vault.problems.isEmpty {
                Section("Problemi") {
                    ForEach(vault.problems.suffix(10), id: \.self) { problem in
                        Text(problem).themedText(.caption, color: .textSecondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scanDuration: String {
        let milliseconds = vault.index.lastScanDuration.components.attoseconds / 1_000_000_000_000_000
        let seconds = vault.index.lastScanDuration.components.seconds
        return seconds > 0 ? "\(seconds),\(milliseconds / 100) s" : "\(milliseconds) ms"
    }
}
