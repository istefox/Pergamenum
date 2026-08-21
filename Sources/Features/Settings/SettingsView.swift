import SwiftUI

/// The settings window of SPEC §12.
///
/// Settings that belong to a notes folder are written into
/// `.pergamenum/settings.json`, so the same folder opened on another Mac behaves the
/// same. The theme and the keyboard shortcuts are per-user preferences and stay in
/// `UserDefaults`.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ThemeEngine.self) private var engine
    @Environment(EventKitStore.self) private var calendar
    @Environment(ReminderScheduler.self) private var reminders
    @State private var testProblem: String?
    @State private var sampleViews: String?

    var body: some View {
        TabView {
            general.tabItem { Label("Generali", systemImage: "gearshape") }
            ShortcutSettings().tabItem { Label("Scorciatoie", systemImage: "keyboard") }
            DesignSystemSettings().tabItem { Label("Design system", systemImage: "paintpalette") }
            EditorSettings().tabItem { Label("Editor", systemImage: "text.cursor") }
            CanvasSettings().tabItem { Label("Canvas", systemImage: "rectangle.3.group") }
            TaskSettings().tabItem { Label("Attività", systemImage: "checklist") }
            TimelineSettings().tabItem { Label("Giornata", systemImage: "clock") }
            conventions.tabItem { Label("Convenzioni", systemImage: "checkmark.seal") }
            calendarTab.tabItem { Label("Calendario", systemImage: "calendar") }
            advanced.tabItem { Label("Avanzate", systemImage: "wrench.and.screwdriver") }
        }
        // Taller than it was: the design system pane lists every colour token with
        // its well, and at 420 the list showed four rows and a scroll bar.
        .frame(width: 620, height: 560)
    }

    private func installSamples() {
        let outcome = vault.installSampleViews()
        var parts: [String] = []
        if !outcome.created.isEmpty { parts.append("\(outcome.created.count) scritte") }
        if !outcome.alreadyThere.isEmpty { parts.append("\(outcome.alreadyThere.count) c'erano già") }
        parts.append(contentsOf: outcome.failures)
        sampleViews = parts.joined(separator: ", ")
    }

    // MARK: Generali

    private var general: some View {
        @Bindable var engine = engine
        return Form {
            LabeledContent("Cartella note") {
                Text(vault.root?.lastPathComponent ?? "nessuno")
                    .themedText(.body, color: .textSecondary)
            }
            LabeledContent("Percorso") {
                Text(vault.root?.path(percentEncoded: false) ?? "—")
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button("Apri un'altra cartella…") { VaultOpenPanel.chooseVault(into: vault) }

            LabeledContent("Viste di esempio") {
                VStack(alignment: .leading, spacing: 2) {
                    Button("Scrivi in Templates/") { installSamples() }
                        .disabled(vault.root == nil)
                        .accessibilityIdentifier("install-sample-views")
                    if let sampleViews {
                        Text(sampleViews).themedText(.caption, color: .textTertiary)
                    }
                }
            }
            // Said before it is pressed rather than after: five files appearing in a vault is
            // something to agree to, not to find out about.
            Text("Cinque viste pronte, una per renderer. Sono note ordinarie in Templates/, "
                + "scritte solo ora e mai sovrascritte se ci sono già.")
                .themedText(.caption, color: .textTertiary)

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
            TextField("Cartella diario", text: Binding(
                get: { vault.settings.diaryFolder },
                set: { value in
                    vault.updateSettings {
                        $0.diaryFolder = value.trimmingCharacters(in: .whitespaces)
                    }
                }
            ))
            .disabled(vault.root == nil)
            Text("""
                Il diario scrive un file per giorno, con lo stesso nome della daily note: \
                tenerlo in una cartella sua è quello che li distingue.
                """)
                .themedText(.caption, color: .textTertiary)
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
            LabeledContent("Accesso Notifiche") { accessLabel(reminders.access) }

            // `@remind(...)` markers are parsed whatever this says; without the grant
            // nothing is ever scheduled from them (SPEC §7.1).
            if reminders.access == .notDetermined {
                Button("Richiedi accesso alle notifiche") {
                    Task {
                        await reminders.requestAccess()
                        await reminders.reschedule(for: vault.index.allTasks)
                    }
                }
            } else if reminders.access == .denied {
                Text("I promemoria @remind non possono essere mostrati: le notifiche di Pergamenum sono disattivate in Impostazioni di Sistema.")
                    .themedText(.caption, color: .textTertiary)
            } else {
                Text("^[\(reminders.pendingCount) promemoria](inflect: true) @remind in attesa nel sistema.")
                    .themedText(.caption, color: .textTertiary)
                Text(reminders.deliverySummary).themedText(.caption, color: .textTertiary)
                // Authorised and silent is a real state, and it is the one nobody can
                // diagnose: the reminder fires on time and nothing appears.
                if reminders.isSilent {
                    Text("Le notifiche sono autorizzate ma gli avvisi sono disattivati: un @remind viene consegnato e non si vede. Si riattiva da Impostazioni di Sistema › Notifiche › Pergamenum.")
                        .themedText(.caption, color: .taskOverdue)
                }
                Button("Invia una notifica di prova") {
                    Task { testProblem = await reminders.sendTestNotification() }
                }
                if let testProblem {
                    Text(testProblem).themedText(.caption, color: .taskOverdue)
                } else {
                    Text("Arriva dopo qualche secondo: macOS non mostra una notifica mentre la sua app è in primo piano.")
                        .themedText(.caption, color: .textTertiary)
                }
            }

            if let problem = reminders.lastAccessError {
                Text(problem).themedText(.caption, color: .taskOverdue)
            }

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
            Text("La cache vive fuori dal vault e non è mai la fonte di verità: una riga il cui file è cambiato viene scartata.")
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
