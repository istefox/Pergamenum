import SwiftUI

/// Every saved view in the vault, in one list (ADR-0009).
///
/// A view is a fenced `pergamenum-view` block inside an ordinary note, which is what
/// makes it a file and not a feature of this app - and also what made it invisible:
/// until now the only way to reach one was to already know which note it was written in.
///
/// A row says four things, because a list of links to notes would only repeat the note
/// list: **what the view is called** (the heading it sits under, which is the only name
/// the grammar leaves room for), **what it draws**, **what it filters on**, and **how
/// many notes it finds right now**. That last one is the difference between an index and
/// a catalogue - a view matching nothing is usually a view whose tag was renamed.
///
/// **It costs a full-vault read and then one evaluation per view**, which is why it runs
/// when the pane opens and when the vault is rescanned, and never on a draw. The scan is
/// the same one `VaultAPI.views` does for the connector, and the price §D7 accepts for
/// views living in files rather than in a table.
struct ViewsPane: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(ThemeEngine.self) private var themeEngine

    @State private var entries: [ViewEntry] = []
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                header
                if entries.isEmpty, !isScanning { empty }
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
        .task(id: vault.scanGeneration) { scan() }
        // The counts beside each row are answers, and an answer to «modified >= week-start»
        // is a different one on Monday (ADR-0014 §D4).
        .onDayChange { scan() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("views-pane")
        .toolbar { ToolbarItemGroup(placement: .primaryAction) { themeToggleToolbarItem(themeEngine) } }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Viste").themedText(.title)
            if isScanning {
                ProgressView().controlSize(.small)
            } else {
                Text(entries.count == 1 ? "1 vista" : "\(entries.count) viste")
                    .themedText(.caption, color: .textTertiary)
            }
            Spacer()
        }
        .padding(.bottom, theme.spacing(.xs))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessuna vista nel vault.").themedText(.body, color: .textSecondary)
            Text("""
                Una vista è un blocco \(ViewBlock.language) dentro una nota qualsiasi: una \
                query sull'indice, disegnata come tabella, elenco, galleria, calendario o \
                board. L'intestazione sopra il blocco è il nome che porta in questa lista.
                """)
                .themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One view. A broken one is listed with its error rather than hidden: a query with a
    /// typo in it is exactly the one somebody is looking for.
    private func row(_ entry: ViewEntry) -> some View {
        Button { open(entry) } label: {
            ThemedCard {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: theme.spacing(.xs)) {
                        Image(systemName: symbol(for: entry.block?.render))
                            .foregroundStyle(theme.color(entry.error == nil ? .accentPrimary : .taskOverdue))
                        Text(entry.name).themedText(.body)
                        Spacer()
                        Text(subtitle(entry)).themedText(.caption, color: .textTertiary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                        if let error = entry.error {
                            Text(error).themedText(.caption, color: .taskOverdue)
                        } else {
                            Text(filterText(entry)).themedText(.caption, color: .textSecondary)
                            if let block = entry.block, !block.effectiveColumns.isEmpty {
                                Text(block.effectiveColumns.map(\.rawValue).joined(separator: ", "))
                                    .themedText(.caption, color: .textTertiary)
                            }
                        }
                        Spacer()
                        Text(entry.path).themedText(.caption, color: .textTertiary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .help("Apri \(entry.path)")
        .accessibilityIdentifier("view-row")
    }

    /// `tabella · 4 note`, or the renderer alone when the view cannot run.
    private func subtitle(_ entry: ViewEntry) -> String {
        guard let block = entry.block else { return "non valida" }
        let drawn = ViewCatalogue.rendererName(block.render)
        guard let matches = entry.matches else { return drawn }
        return "\(drawn) · \(matches == 1 ? "1 nota" : "\(matches) note")"
    }

    private func filterText(_ entry: ViewEntry) -> String {
        guard let block = entry.block else { return "" }
        let filter = ViewFilterText.describe(block.filter)
        guard !block.scope.isEmpty else { return filter }
        return "in \(block.scope.joined(separator: ", ")) · \(filter)"
    }

    /// Opens the note **with the caret on the block**, not at the top of the file: a note
    /// holding three views would otherwise answer three rows with the same screen.
    private func open(_ entry: ViewEntry) {
        vault.openChosenNote(at: entry.path)
        // One turn later, so the column has the note before the jump reaches it - the
        // lesson `VaultBrowser` paid for with its heading jump.
        Task { @MainActor in
            navigation.pane = .notes
            guard let text = vault.openNote?.text,
                  let range = NoteJump.lineRange(entry.lineIndex, in: text)
            else { return }
            navigation.jumpToLine(
                range: NSRange(range, in: text),
                ordinal: NoteJump.ordinal(of: range.lowerBound, in: text)
            )
        }
    }

    private func symbol(for render: ViewBlock.Renderer?) -> String {
        switch render {
        case .table: "tablecells"
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        case .calendar: "calendar"
        case .board: "rectangle.split.3x1"
        case nil: "exclamationmark.triangle"
        }
    }

    // MARK: The scan

    /// Reads every note once, parses the views in it, and runs each one for its count.
    ///
    /// Synchronous on the main actor, like the rest of what touches `VaultSession`: the
    /// session is main-actor bound, and hopping off it to read files would mean copying
    /// the index to another isolation for no gain on a vault of this size. If a vault
    /// ever makes this stutter, the fix is the watcher of §D7, not a thread.
    private func scan() {
        guard let session = vault.session else {
            entries = []
            return
        }
        isScanning = true
        defer { isScanning = false }

        entries = session.index.allNotes
            .sorted { $0.relativePath < $1.relativePath }
            .flatMap { record -> [ViewEntry] in
                guard let text = try? session.read(record.relativePath).text else { return [] }
                let locations = ViewCatalogue.locations(in: text)
                let blocks = ViewBlock.blocks(in: NoteDocument.parse(text).body)
                return blocks.enumerated().map { ordinal, parsed in
                    entry(record, ordinal: ordinal, parsed: parsed,
                          location: ordinal < locations.count ? locations[ordinal] : nil,
                          session: session)
                }
            }
    }

    private func entry(
        _ record: NoteRecord,
        ordinal: Int,
        parsed: Result<ViewBlock, ViewBlockError>,
        location: ViewCatalogue.Location?,
        session: VaultSession
    ) -> ViewEntry {
        switch parsed {
        case .success(let block):
            let result = ViewEvaluator.evaluate(block, over: session.index) { candidate in
                try? session.read(candidate.relativePath).text
            }
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: block, error: nil, matches: result.total
            )
        case .failure(let failure):
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: nil, error: failure.description, matches: nil
            )
        }
    }
}

/// A filter, said in the language the interface speaks.
///
/// The grammar is written to be typed, not read aloud: `tag("topic-produzione") and not
/// task(done)` is exact and is not what a list of views should show as the answer to
/// "what does this one collect". Apart from the pane because it is pure, and pure is
/// testable.
enum ViewFilterText {
    static func describe(_ filter: ViewFilter) -> String {
        switch filter {
        case .all: "nessun filtro"
        case .and(let left, let right): "\(describe(left)) e \(describe(right))"
        case .or(let left, let right): "\(describe(left)) oppure \(describe(right))"
        case .not(let inner): "non \(describe(inner))"
        case .path, .tag, .linksTo, .linkedFrom, .task, .has, .text, .comparison: term(filter)
        }
    }

    /// The leaves. Apart from the four above so that neither switch is long enough to
    /// hide an arm, which is the whole content of the complexity rule.
    private static func term(_ filter: ViewFilter) -> String {
        switch filter {
        case .path(let path): "in \(path)"
        case .tag(let glob): glob
        case .linksTo(let title): "collega \(title)"
        case .linkedFrom(let title): "collegata da \(title)"
        case .task(let state): "task \(stateName(state))"
        case .has(let field): "con \(field.rawValue)"
        case .text(let needle): "testo «\(needle)»"
        case .comparison(let field, let comparison, let bound):
            // The bound as it was written, not as it resolves today: this line explains the
            // block to somebody reading it, and «modified >= 17/08/2026» would describe an
            // answer rather than the question the block asks.
            "\(field.rawValue) \(comparison.rawValue) \(boundText(bound))"
        case .all, .and, .or, .not: describe(filter)
        }
    }

    /// A written-out day in the Italian form the interface uses everywhere else; a relative
    /// bound in the words the block carries, because translating «week-start» to a date would
    /// hide the only interesting thing about it.
    private static func boundText(_ bound: ViewDateBound) -> String {
        if case .day(let day) = bound { return day.italianForm }
        return bound.text
    }

    private static func stateName(_ state: TaskItem.State) -> String {
        switch state {
        case .open: "aperti"
        case .done: "completati"
        case .rescheduled: "rimandati"
        case .cancelled: "annullati"
        }
    }
}
