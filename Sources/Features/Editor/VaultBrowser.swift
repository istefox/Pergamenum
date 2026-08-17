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
    /// Held here rather than read straight from `Navigation`, because the insertion has
    /// to be consumed once: read directly it would be re-applied on every view update
    /// until something else changed it.
    @State var pendingInsertion: (text: String, cursorBack: Int)?
    @State private var isShowingInspector = true
    /// Bumped after a note is created, so the editor that replaces the composer opens
    /// with the cursor already in it.
    @State var focusRequest = 0
    /// The embedded file a click asked to see, and the panel that shows it. Empty until
    /// there is one: the Quick Look host takes first responder whenever it has a file,
    /// and taking it before the user has asked for anything would be taking it for
    /// nothing.
    @State var previewURLs: [URL] = []
    @State var isPreviewingEmbed = false

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
        .onChange(of: navigation.pendingInsertion) { _, _ in
            pendingInsertion = navigation.consumeInsertion()
        }
        .background(theme.color(.backgroundPrimary))
        .sheet(isPresented: Binding(
            get: { vault.isShowingQuickSwitcher },
            set: { vault.isShowingQuickSwitcher = $0 }
        )) {
            QuickSwitcher { path in
                vault.openNote(at: path)
                vault.isShowingQuickSwitcher = false
            }
        }
        .sheet(isPresented: Binding(
            get: { vault.isAddingRelatedLink },
            set: { vault.isAddingRelatedLink = $0 }
        )) {
            RelatedLinkSheet()
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

            Toggle(isOn: Bindable(navigation).isReadingMode) {
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
        if let draft = vault.newNote {
            NewNoteComposer(
                draft: draft,
                onCreated: { _ in
                    vault.newNote = nil
                    focusRequest += 1
                },
                onCancel: { vault.newNote = nil }
            )
        } else if let note = vault.openNote {
            VStack(spacing: 0) {
                editorHeader(note)
                if note.externalChangePending != nil { conflictBanner }
                Divider()
                if navigation.isReadingMode {
                    reading(note)
                } else {
                    editing(note)
                }
            }
            .background(theme.color(.backgroundPrimary))
            .quickLook(urls: previewURLs, isPresented: $isPreviewingEmbed)
        } else {
            emptyState
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.color(.taskOverdue))
            Text("La nota è cambiata su disco mentre la stavi modificando.")
                .themedText(.caption)
            Spacer()
            Button("Ricarica da disco", action: vault.acceptExternalChange)
            Button("Tieni la mia versione", action: vault.keepLocalVersion)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.accentMuted))
    }

    /// On the controller since the Diario pane's editor offers the same list.
    var tagSuggestions: [String] { vault.tagSuggestions }

    func follow(title: String) {
        let matches = vault.index.resolve(title: title)
        guard let first = matches.first else { return }
        vault.openNote(at: first)
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing(.s)) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessuna nota aperta").themedText(.body, color: .textSecondary)
            Text("Cmd+O per il quick switcher").themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.backgroundPrimary))
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        if let note = vault.openNote {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    conformance(note)
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

/// Fuzzy note finder (Cmd+O), matching titles and aliases.
struct QuickSwitcher: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    let onOpen: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Vai alla nota…", text: $query)
                .textFieldStyle(.plain)
                .font(theme.font(.title))
                .padding(theme.spacing(.m))
                .onSubmit { open(selection ?? results.first?.relativePath) }
                // `pergamenum://search?q=` parks its query on the controller and this
                // is what picks it up. Without it the route opened the switcher with an
                // empty field: the link worked, visibly, and did the wrong thing.
                .task {
                    if let pending = vault.consumePendingSearch() { query = pending }
                }

            Divider()

            List(results, id: \.relativePath, selection: $selection) { note in
                HStack {
                    Text(note.title).themedText(.body)
                    Spacer()
                    Text(note.folder).themedText(.caption, color: .textTertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { open(note.relativePath) }
                .tag(note.relativePath)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 560, height: 380)
        .background(theme.color(.surfaceCard))
        .onExitCommand { dismiss() }
    }

    private var results: [NoteRecord] {
        vault.index.search(query, limit: 30)
    }

    private func open(_ path: String?) {
        guard let path else { return }
        onOpen(path)
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
