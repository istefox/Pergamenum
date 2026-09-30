import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11, plan
// docs/plans/contenitore.md, Task 7 - R-09, R-13, R-15, R-22, R-25; mockup 1a, 1c, 1e, 1h.

/// The pane's middle column: what is in scope, the notices, the filters, and the documents as a
/// list or a grid.
struct ContenitoreDocuments: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ContenitoreController.self) private var contenitore
    let rows: [ContenitoreRow]
    let actions: ContenitoreCommandActions

    @State private var previewURLs: [URL] = []

    /// The rows the pane shows now, read from the index and the controller's extraction cache,
    /// never from the store's JSON files on a `body` pass.
    static func rows(vault: VaultController, contenitore: ContenitoreController) -> [ContenitoreRow] {
        guard let session = vault.session else { return [] }
        return ContenitoreListModel.rows(
            index: session.index, root: contenitore.root, filter: contenitore.filter,
            container: contenitore.scope, fileExists: session.exists,
            status: contenitore.extractionStatus(sha256:), text: { contenitore.extraction(sha256: $0)?.text }
        )
    }

    var body: some View {
        @Bindable var contenitore = contenitore
        VStack(spacing: 0) {
            header
            ContenitoreNoticeStrip(actions: actions)
            ContenitoreFilterBar(rows: rows)
            Divider()
            if rows.isEmpty {
                empty
            } else if contenitore.layout == .list {
                ContenitoreList(rows: rows, actions: actions, preview: preview)
            } else {
                ContenitoreGrid(rows: rows, actions: actions, preview: preview)
            }
        }
        .background(theme.color(.backgroundPrimary))
        .quickLook(urls: previewURLs, isPresented: $contenitore.isPreviewing, claimsFocus: false)
    }

    private var header: some View {
        @Bindable var contenitore = contenitore
        return HStack(spacing: theme.spacing(.m)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scopeTitle).themedText(.title)
                Text(countLine)
                    .themedText(.caption, color: .textSecondary)
                    .accessibilityIdentifier("contenitore-count")
            }
            Spacer()
            TextField("Cerca, anche nel testo estratto", text: $contenitore.filter.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("contenitore-search")
            Picker("Vista", selection: $contenitore.layout) {
                Label("Lista", systemImage: "list.bullet").tag(ContenitoreController.Layout.list)
                Label("Griglia", systemImage: "square.grid.2x2").tag(ContenitoreController.Layout.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("contenitore-layout")
        }
        .padding(.horizontal, theme.spacing(.l))
        .padding(.vertical, theme.spacing(.m))
    }

    private var scopeTitle: String {
        switch contenitore.scope {
        case .all: "Tutti"
        case .inbox: "Da classificare"
        case .container(let path): (path as NSString).lastPathComponent
        }
    }

    private var countLine: String {
        let filtered = contenitore.filter.isActive || !contenitore.filter.query.isEmpty
        switch rows.count {
        case 0: return filtered ? "nessun documento · filtrati" : "nessun documento"
        case 1: return filtered ? "1 documento · filtrati" : "1 documento"
        default: return "\(rows.count) documenti" + (filtered ? " · filtrati" : "")
        }
    }

    @ViewBuilder
    private var empty: some View {
        VStack(spacing: theme.spacing(.m)) {
            Image(systemName: "archivebox")
                .font(.system(size: 40))
                .foregroundStyle(theme.color(.textTertiary))
            if contenitore.filter.isActive || !contenitore.filter.query.isEmpty || contenitore.scope != .all {
                Text("Nessun documento qui").themedText(.title)
                Text("Nessun documento corrisponde a questa vista o a questi filtri.")
                    .themedText(.body, color: .textSecondary)
            } else {
                Text("Il Contenitore è vuoto").themedText(.title)
                Text("Metti un file qualsiasi in \(contenitore.dropFolderDisplay). Pergamenum lo sposta nella vault, "
                    + "ne estrae il testo e lo mette in «Da classificare».")
                    .themedText(.body, color: .textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack {
                    Button("Mostra la cartella di raccolta") {
                        if let folder = contenitore.resolvedDropFolder { contenitore.revealFiles([folder]) }
                    }
                    SettingsLink { Text("Impostazioni…") }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("contenitore-empty")
    }

    /// Quick Look on a document's file (the spacebar, and «Apri anteprima»).
    private func preview(_ schedaPath: String) {
        guard let session = vault.session,
              let companion = session.companion(ofScheda: schedaPath),
              let url = try? session.store.url(for: companion)
        else {
            NSSound.beep()
            return
        }
        previewURLs = [url]
        contenitore.isPreviewing = true
    }
}

/// The documents as a list (mockup 1a).
struct ContenitoreList: View {
    @Environment(\.theme) private var theme
    @Environment(ContenitoreController.self) private var contenitore
    let rows: [ContenitoreRow]
    let actions: ContenitoreCommandActions
    let preview: (String) -> Void

    /// ADR-0070 / PG-298: a row click does not give the list the keyboard, so the selection
    /// change does, and Backspace reaches `.onDeleteCommand` only while the list has it.
    @FocusState private var isListFocused: Bool

    var body: some View {
        @Bindable var contenitore = contenitore
        List(selection: $contenitore.selection) {
            ForEach(rows) { row in
                ContenitoreRowView(row: row, progress: row.sha256.flatMap { contenitore.queue?.progress[$0] })
                    .tag(row.schedaPath)
            }
        }
        .scrollContentBackground(.hidden)
        // One catalogue for the row menu (ADR-0023 §D1, R-27). Return and double-click open the
        // document: `primaryAction` is the list's own, so no menu key equivalent competes with
        // the text fields for Return.
        .contextMenu(forSelectionType: String.self) { selection in
            if let path = selection.first {
                ContenitoreMenuItems(commands: ContenitoreCommand.rowMenu, schedaPath: path, actions: actions)
            }
        } primaryAction: { selection in
            if let path = selection.first { actions.run(.open, on: path) }
        }
        .focused($isListFocused)
        .onChange(of: contenitore.selection) { _, selected in
            if selected != nil { isListFocused = true }
        }
        .onDeleteCommand {
            guard let path = contenitore.selection else {
                NSSound.beep()
                return
            }
            actions.run(.trash, on: path)
        }
        .onKeyPress(.space) {
            guard let path = contenitore.selection else { return .ignored }
            preview(path)
            return .handled
        }
        .accessibilityIdentifier("contenitore-list")
    }
}

/// One document in the list: thumbnail, name with its colour dot, where it is, its tags, its
/// date and its text.
struct ContenitoreRowView: View {
    @Environment(\.theme) private var theme
    let row: ContenitoreRow
    let progress: (done: Int, total: Int)?

    var body: some View {
        HStack(spacing: theme.spacing(.m)) {
            ContenitoreThumbnail(row: row, width: 32)
                .frame(width: 32, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: theme.spacing(.xs)) {
                    ContenitoreColourDot(colour: row.colour)
                    Text(row.name).themedText(.body).lineLimit(1)
                }
                HStack(spacing: theme.spacing(.xs)) {
                    Text(subtitle).themedText(.caption, color: .textSecondary).lineLimit(1)
                    if row.isFileMissing {
                        Text("file mancante")
                            .themedText(.caption, color: .taskOverdue)
                            .accessibilityIdentifier("contenitore-row-file-missing")
                    }
                    ContenitoreTagChips(tags: row.tags.filter { $0 != Tag(namespace: .type, value: "note") })
                }
            }
            Spacer(minLength: theme.spacing(.m))
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.date?.italianForm ?? "").themedText(.caption, color: .textSecondary)
                Text(extraction).themedText(.caption, color: .textTertiary)
            }
        }
        .padding(.vertical, theme.spacing(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contenitore-row")
    }

    private var subtitle: String {
        let place = row.isInbox ? "Da classificare" : row.container.split(separator: "/").dropFirst().joined(separator: " › ")
        return [row.kind, place].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var extraction: String {
        guard let progress, progress.total > 0 else { return row.extractionLabel }
        return "OCR · pagina \(progress.done) di \(progress.total)"
    }
}

/// A document's colour: a 10 pt dot in its sticky token, ringed with `border.strong` (G2); no
/// colour, no dot.
struct ContenitoreColourDot: View {
    @Environment(\.theme) private var theme
    let colour: ContenitoreColour?

    var body: some View {
        if let colour {
            Circle()
                .fill(theme.color(colour.token))
                .overlay(Circle().strokeBorder(theme.color(.borderStrong), lineWidth: 1))
                .frame(width: 10, height: 10)
                .accessibilityLabel(colour.displayName)
        }
    }
}

/// Tags as small chips.
struct ContenitoreTagChips: View {
    @Environment(\.theme) private var theme
    let tags: [Tag]

    var body: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag.description)
                .themedText(.caption, color: tag == ContenitoreListModel.inboxTag ? .accentPrimary : .textSecondary)
                .padding(.horizontal, theme.spacing(.xs))
                .background(theme.color(.surfaceSunken), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
        }
    }
}

/// The document's thumbnail through `ThumbnailStore`, or a document symbol while there is none.
struct ContenitoreThumbnail: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let row: ContenitoreRow
    let width: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.radius(.control))
                .fill(theme.color(.surfaceSunken))
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: row.isFileMissing ? "questionmark.folder" : "doc")
                    .foregroundStyle(theme.color(.textTertiary))
            }
        }
        .task(id: row.filePath) {
            guard let path = row.filePath, !row.isFileMissing, let store = vault.thumbnails else { return }
            let task = await store.thumbnail(for: path, width: width)
            let rendered = await task.value
            if !Task.isCancelled { image = rendered }
        }
    }
}
