import SwiftUI

/// The Note view: folder tree on the left, editor in the middle, inspector on the
/// right. This is the M1 screen the Editor mockup described.
struct VaultBrowser: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(Navigation.self) var navigation
    /// The slash menu runs app commands through this rather than re-implementing them
    /// (M8). Injected at app level, where every collaborator it needs exists.
    @Environment(CommandActions.self) var commandActions
    /// Read for the key combinations the slash menu shows beside each app command.
    @Environment(ShortcutStore.self) var shortcuts
    @State private var isShowingInspector = true

    var body: some View {
        HSplitView {
            NoteListPane()
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)
            editor
                .frame(minWidth: 360)
            if isShowingInspector {
                inspector
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)
            }
        }
        .toolbar { toolbar }
        .background(theme.color(.backgroundPrimary))
        .sheet(isPresented: Binding(
            get: { vault.isShowingQuickSwitcher },
            set: { vault.isShowingQuickSwitcher = $0 }
        )) {
            QuickSwitcher(mode: .navigate) { choice in
                vault.isShowingQuickSwitcher = false
                open(choice)
            }
        }
        .sheet(isPresented: Binding(
            get: { vault.isAddingRelatedLink },
            set: { vault.isAddingRelatedLink = $0 }
        )) {
            RelatedLinkSheet()
        }
        .modifier(HistorySheetPresentation())
    }

    /// Acts on what the quick switcher was asked for.
    ///
    /// Here and not in the switcher, which is a picker shared with the task view: only this
    /// screen has the editor a heading jump lands in, and only the controller knows whether
    /// Cmd+T asked for a tab of its own (ADR-0012 D5), which is why `openChosenNote` and not
    /// `openNote`.
    private func open(_ choice: QuickSwitcher.Choice) {
        switch choice {
        case .note(let path):
            vault.openChosenNote(at: path)
        case .dailyNote:
            do { try vault.openDailyNote(for: .today) } catch {
                vault.recordProblem(ConformanceText.creationFailure(error))
            }
        case .createNote(let title):
            do { try vault.createNote(title: title, date: .today) } catch {
                vault.recordProblem(ConformanceText.creationFailure(error))
            }
        case .heading(let path, let range, let ordinal):
            vault.openChosenNote(at: path)
            // One turn later, so the column has the note before the jump reaches it. Sent in
            // the same pass, the jump arrives at a text view still showing the note you came
            // from and puts the caret on whatever is at that offset.
            Task { @MainActor in navigation.jumpToOutlineEntry(range: range, ordinal: ordinal) }
        }
    }

    /// The commands worth a click, in the place macOS puts them.
    ///
    /// Every one of these is also a menu item with a shortcut: the toolbar is the
    /// discoverable copy, not a second implementation. Nothing lives only here.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { vault.beginNewNote() } label: {
                Label("Nuova nota", systemImage: "square.and.pencil")
            }
            .help("Nuova nota")
            .disabled(vault.root == nil)

            Button { vault.isShowingQuickSwitcher = true } label: {
                Label("Vai alla nota", systemImage: "magnifyingglass")
            }
            .help("Vai alla nota")
            .disabled(vault.root == nil)

            Button { vault.isShowingGlobalSearch = true } label: {
                Label("Ricerca globale", systemImage: "text.magnifyingglass")
            }
            .help("Cerca in tutte le note")
            .disabled(vault.root == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: vault.saveOpenNote) {
                Label("Salva", systemImage: "arrow.down.doc")
            }
            .help("Salva la nota")
            .disabled(vault.openNote?.hasUnsavedChanges != true)

            Toggle(isOn: Bindable(vault).isReadingMode) {
                Label("Modalità lettura", systemImage: "book")
            }
            .help("Modalità lettura")
            .disabled(vault.openNote == nil)

            Button {
                isShowingInspector.toggle()
            } label: {
                Label("Ispettore", systemImage: "sidebar.right")
            }
            .help("Backlink, conformità, link non risolti")
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if vault.isComposingNote {
            NewNoteComposer(
                draft: vault.noteDraft ?? .init(),
                onCreated: { _ in vault.endNewNote() },
                onCancel: { vault.endNewNote() }
            )
        } else {
            // One column, or two after «Dividi l'editor» (ADR-0012 D4).
            EditorColumns()
        }
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        // `isOpenNoteVisible` and not just `openNote`: backlinks, conformance and the
        // history of a note the composer is covering describe something nobody is
        // looking at (PG-027).
        if let note = vault.openNote, vault.isOpenNoteVisible {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    star(note)
                    conformance(note)
                    history(note)
                    backlinks(note)
                    LinkedTasksPanel(title: note.title, emptyText: "nessun task linka questa nota")
                    unresolved
                }
                .padding(theme.spacing(.m))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundSecondary))
        } else {
            Color.clear.background(theme.color(.backgroundSecondary))
        }
    }

    /// The star, at the top of the inspector because it is about the note as a whole rather
    /// than about anything inside it (ADR-0012 D6). The sidebar's context menu does the same
    /// thing for a note nobody has open.
    private func star(_ note: VaultController.OpenNote) -> some View {
        let isStarred = vault.isStarred(note.relativePath)
        return Button { vault.toggleStar(note.relativePath) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .themedText(.body, color: isStarred ? .accentPrimary : .textTertiary)
                Text(isStarred ? "Preferita" : "Aggiungi alle preferite")
                    .themedText(.caption, color: .textSecondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Togli dalle preferite" : "Aggiungi alle preferite")
        .accessibilityIdentifier("star-note")
    }

    private func conformance(_ note: VaultController.OpenNote) -> some View {
        let violations = vault.violations(for: note)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("CONFORMITÀ").themedText(.caption, color: .textTertiary)
            if violations.isEmpty {
                Label("Conforme", systemImage: "checkmark.seal")
                    .themedText(.caption, color: .textSecondary)
            } else {
                ForEach(ConformanceText.lines(violations), id: \.self) { line in
                    Text(line).themedText(.caption, color: .taskOverdue)
                }
            }
        }
    }

    private func backlinks(_ note: VaultController.OpenNote) -> some View {
        let records = vault.index.backlinks(toTitle: note.title)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("BACKLINK").themedText(.caption, color: .textTertiary)
            if records.isEmpty {
                Text("nessuno").themedText(.caption, color: .textTertiary)
            } else {
                ForEach(records, id: \.relativePath) { record in
                    Button(record.title) { vault.openNote(at: record.relativePath) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .accentPrimary)
                }
            }
        }
    }

    private var unresolved: some View {
        let links = vault.index.unresolvedLinks().prefix(10)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("LINK NON RISOLTI").themedText(.caption, color: .textTertiary)
            if links.isEmpty {
                Text("nessuno").themedText(.caption, color: .textTertiary)
            } else {
                ForEach(Array(links), id: \.target) { entry in
                    Text("\(entry.target) · \(entry.sources.count)")
                        .themedText(.caption, color: .textSecondary)
                        .help(entry.sources.map(\.title).joined(separator: "\n"))
                }
            }
        }
    }
}

/// Renders violations as Italian sentences, kept out of the views so the wording is
/// in one place and testable.
enum ConformanceText {
    static func lines(_ violations: NoteViolations) -> [String] {
        nameLines(violations.name)
            + frontmatterLines(violations.frontmatter)
            + tagLines(violations.tags)
            + relatedLines(violations)
    }

    private static func nameLines(_ violations: [NoteName.Violation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .empty: lines.append("Il titolo è vuoto")
            case .containsForbiddenCharacter(let character): lines.append("Carattere vietato nel titolo: \(character)")
            case .tooLong(let count): lines.append("Titolo di \(count) caratteri, massimo \(NoteName.maximumLength)")
            case .hasVersionSuffix(let suffix): lines.append("Suffisso di versione nel titolo: \(suffix)")
            case .hasLeadingOrTrailingWhitespace: lines.append("Spazi all'inizio o alla fine del titolo")
            case .malformedDailyName(let name): lines.append("Daily note non in formato YYYYMMDD: \(name)")
            }
        }
        return lines
    }

    private static func frontmatterLines(_ violations: [FrontmatterViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .missingBlock: lines.append("Frontmatter assente")
            case .missingDate: lines.append("Manca la chiave date")
            case .missingTags: lines.append("Manca la chiave tags")
            case .foreignKey(let name): lines.append("Chiave fuori schema: \(name)")
            case .inlineTagList: lines.append("tags in forma inline, serve la lista a blocco")
            case .unparsableTag(let raw): lines.append("Tag non conforme: \(raw)")
            case .tooManyAliases(let count): lines.append("\(count) alias, massimo \(Frontmatter.maximumAliases)")
            case .unresolvedRelatedLink(let target): lines.append("related punta a una nota inesistente: \(target)")
            case .relatedOutOfSyncWithSection: lines.append("related e Note correlate non coincidono")
            }
        }
        return lines
    }

    private static func tagLines(_ violations: [TagViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .malformed(let raw): lines.append("Tag malformato: \(raw)")
            case .notInVocabulary(let tag): lines.append("\(tag) non è nel vocabolario chiuso")
            case .vocabularyUnavailable(let namespace): lines.append("Vocabolario \(namespace.rawValue) non importato: non verificabile")
            case .tooMany(let count): lines.append("\(count) tag, massimo \(TagRules.maximumTagsPerNote)")
            case .multipleStatus(let tags): lines.append("Più di uno status: \(tags.map(\.description).joined(separator: ", "))")
            case .dateTag(let tag): lines.append("Tag data non ammesso: \(tag)")
            case .statusNotAllowedOnNote(let tag): lines.append("\(tag) non ammesso su una nota")
            case .missingRequiredTag(let name): lines.append("Manca il tag obbligatorio \(name)")
            }
        }
        return lines
    }

    private static func relatedLines(_ violations: NoteViolations) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: violations.relatedMissingInSection.map {
            "\($0) è in related ma non in Note correlate"
        })
        lines.append(contentsOf: violations.relatedMissingInFrontmatter.map {
            "\($0) è in Note correlate ma non in related"
        })
        return lines
    }
}

extension ConformanceText {
    static func creationFailure(_ error: Error) -> String {
        guard let creation = error as? VaultController.CreationError else { return "\(error)" }
        switch creation {
        case .alreadyExists(let path):
            return "Esiste già una nota in \(path)"
        case .invalidTitle(let violations):
            let named = NoteViolations(
                name: violations, frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            )
            return lines(named).joined(separator: "; ")
        }
    }
}
