import SwiftUI

/// Cmd+O: where to go next (ADR-0012, slice 4).
///
/// It began as a fuzzy note finder and stayed one for eight milestones. What it was missing is
/// what you reach for when you do *not* have a name in your head: the note you were just in,
/// the ones you keep to hand, today's daily note, a section inside a long note, and the note
/// that does not exist yet.
///
/// **Two callers, two questions.** The note pane asks "where do I go", and every row below is
/// an answer. `TasksView` asks "which note does this task link to", and only an existing note
/// is one - a heading, a daily note or a note that has still to be written would each mean
/// something the caller cannot use. `Mode` is that difference, and it is the reason this view
/// hands back a `Choice` instead of acting: the switcher knows what was picked, not what the
/// caller meant by asking.
struct QuickSwitcher: View {
    enum Mode {
        /// The note pane: recents, starred, the daily note, headings and «crea la nota».
        case navigate
        /// A picker for something else. Existing notes only.
        case pick
    }

    enum Choice: Equatable {
        case note(String)
        /// A heading inside a note: the range the editor scrolls to and the position in the
        /// index the reading view counts blocks by, exactly as `OutlinePane` hands them over.
        case heading(path: String, range: NSRange, ordinal: Int)
        case createNote(title: String)
        case dailyNote
    }

    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss

    var mode: Mode = .pick
    let onChoose: (Choice) -> Void

    @State private var query = ""
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            list
            if mode == .navigate {
                Divider()
                legend
            }
        }
        .frame(width: 560, height: 380)
        .background(theme.color(.surfaceCard))
        .onExitCommand { dismiss() }
    }

    private var field: some View {
        TextField(mode == .navigate ? "Vai alla nota, o a una sezione con #…" : "Vai alla nota…",
                  text: $query)
            .textFieldStyle(.plain)
            .font(theme.font(.title))
            .padding(theme.spacing(.m))
            .onSubmit { choose(selection) }
            // `pergamenum://search?q=` parks its query on the controller and this is what
            // picks it up. Without it the route opened the switcher with an empty field: the
            // link worked, visibly, and did the wrong thing.
            .task {
                if let pending = vault.consumePendingSearch() { query = pending }
            }
    }

    /// Says what is missing rather than showing an empty box under a heading that promises
    /// rows - the same refusal the slash menu and the outline pane make.
    @ViewBuilder
    private var list: some View {
        if groups.allSatisfy(\.rows.isEmpty) {
            Text(headingQuery == nil ? "Nessuna nota." : "Nessuna sezione con questo nome.")
                .themedText(.body, color: .textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            rows
        }
    }

    private var rows: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        rowView(row).tag(row.id)
                    }
                } header: {
                    if let header = group.header {
                        Text(header).themedText(.caption, color: .textTertiary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: row.icon)
                .themedText(.caption, color: .textTertiary)
                .frame(width: 14)
            Text(row.title).themedText(.body)
            Spacer(minLength: theme.spacing(.s))
            Text(row.detail).themedText(.caption, color: .textTertiary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onChoose(row.choice) }
    }

    private var legend: some View {
        Text("Invio apre · # per una sezione · un nome che non esiste diventa una nota nuova")
            .themedText(.caption, color: .textTertiary)
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ id: String?) {
        let rows = groups.flatMap(\.rows)
        guard let row = rows.first(where: { $0.id == id }) ?? rows.first else { return }
        onChoose(row.choice)
    }

    // MARK: What is on offer

    private struct Row: Identifiable {
        var id: String
        var icon: String
        var title: String
        var detail: String
        var choice: Choice
    }

    private struct Group: Identifiable {
        var id: String
        var header: String?
        var rows: [Row]
    }

    private var groups: [Group] {
        if let heading = headingQuery { return headingGroups(heading) }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty, mode == .navigate { return startingPoints }

        var groups = [Group(id: "notes", header: nil, rows: noteRows(matching: trimmed))]
        if let creation = creationRow(for: trimmed) {
            groups.append(Group(id: "create", header: nil, rows: [creation]))
        }
        return groups.filter { !$0.rows.isEmpty }
    }

    /// With nothing typed, the switcher is not a list of the vault in alphabetical order -
    /// which is what it used to be, and which answers a question nobody asks. It is the three
    /// places you actually go back to.
    private var startingPoints: [Group] {
        let recents = vault.recentNotePaths.compactMap { vault.index.note(at: $0) }
        let groups = [
            Group(id: "today", header: nil, rows: [
                Row(id: "daily", icon: "calendar", title: "Nota di oggi",
                    detail: CalendarDate.today.italianForm, choice: .dailyNote),
            ]),
            Group(id: "recent", header: "RECENTI", rows: recents.map(row(for:))),
            Group(id: "starred", header: "PREFERITE", rows: vault.starredNotes.map(row(for:))),
        ].filter { !$0.rows.isEmpty }

        // A window opened a minute ago has neither recents nor stars, and three empty
        // headings are worse than the list they replaced.
        guard groups.count > 1 else {
            return groups + [Group(id: "all", header: "TUTTE LE NOTE",
                                   rows: noteRows(matching: ""))]
        }
        return groups
    }

    private func noteRows(matching query: String) -> [Row] {
        vault.index.search(query, limit: 30).map(row(for:))
    }

    private func row(for note: NoteRecord) -> Row {
        Row(id: note.relativePath, icon: "doc.text", title: note.title,
            detail: note.folder, choice: .note(note.relativePath))
    }

    /// The row that writes the note you were looking for and did not find.
    ///
    /// Offered on the exact title and not on the fuzzy match: `vibr` finding nothing is a
    /// search that has not narrowed yet, and proposing to create a note called `vibr` there
    /// would be proposing a typo.
    private func creationRow(for title: String) -> Row? {
        guard mode == .navigate, !title.isEmpty, !title.contains("#"),
              vault.index.resolve(title: title).isEmpty
        else { return nil }
        return Row(id: "create:\(title)", icon: "plus", title: "Crea la nota «\(title)»",
                   detail: "", choice: .createNote(title: title))
    }

    // MARK: Headings

    /// `Nota#sez` splits into the note and the section. `#sez` on its own means the note that
    /// is open, which is how you jump inside a long one without naming it again.
    private var headingQuery: (path: String, needle: String)? {
        guard mode == .navigate, let hash = query.firstIndex(of: "#") else { return nil }
        let notePart = String(query[query.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
        let needle = String(query[query.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
        let path = notePart.isEmpty
            ? vault.openNote?.relativePath
            : vault.index.search(notePart, limit: 1).first?.relativePath
        return path.map { ($0, needle) }
    }

    private func headingGroups(_ heading: (path: String, needle: String)) -> [Group] {
        guard let text = vault.noteText(at: heading.path) else { return [] }
        let title = vault.index.note(at: heading.path)?.title ?? heading.path

        // The ordinal is the entry's place in the whole index, embeds included: it is what
        // the reading view counts blocks by, and renumbering the filtered list would send it
        // to a different section than the editor.
        let rows = NoteOutline.entries(in: text).enumerated().compactMap { ordinal, entry -> Row? in
            guard case .heading = entry.kind else { return nil }
            guard heading.needle.isEmpty
                    || FuzzyMatch.score(query: heading.needle, candidate: entry.title) != nil
            else { return nil }
            // No detail: the section header above already names the note, and repeating it
            // on every row is a column that says the same thing as many times as there are
            // headings.
            return Row(
                id: "heading:\(ordinal)", icon: "number", title: entry.title, detail: "",
                choice: .heading(path: heading.path, range: NSRange(entry.range, in: text),
                                 ordinal: ordinal)
            )
        }
        return [Group(id: "headings", header: title.uppercased(), rows: rows)]
    }
}
