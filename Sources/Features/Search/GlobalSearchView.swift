import SwiftUI

/// Full-text search across the vault (SPEC §12, Cmd+Shift+F).
///
/// Reads the files rather than an index of their text: the index holds structure, not
/// content, and a search that returned stale text would be worse than a slow one.
struct GlobalSearchView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var raw = ""
    @State private var results: [Hit] = []
    @State private var isSearching = false
    /// The `regex:` patterns of the current query that do not compile. Shown rather than
    /// swallowed: an empty result list reads as "nothing found", and the difference
    /// between that and "your pattern is broken" is the whole value of the message.
    @State private var invalidPatterns: [String] = []

    private struct Hit: Identifiable {
        var id: String { path }
        var path: String
        var title: String
        /// The line the first match fell on, for context.
        var excerpt: String
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            content
            Divider()
            legend
        }
        .frame(width: 720, height: 520)
        .background(theme.color(.surfaceCard))
        .onExitCommand { dismiss() }
        .task(id: raw) { await search() }
    }

    private var field: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
            TextField("Cerca in tutte le note…", text: $raw)
                .textFieldStyle(.plain)
                .font(theme.font(.title))
            if isSearching { ProgressView().controlSize(.small) }
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var content: some View {
        if !invalidPatterns.isEmpty {
            placeholder("Espressione regolare non valida: \(invalidPatterns.joined(separator: ", "))")
        } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            placeholder("Scrivi per cercare nel testo, nei titoli e nei tag.")
        } else if results.isEmpty, !isSearching {
            placeholder("Nessun risultato.")
        } else {
            List(results) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).themedText(.body)
                    Text(hit.path).themedText(.caption, color: .textTertiary)
                    if !hit.excerpt.isEmpty {
                        Text(hit.excerpt)
                            .themedText(.caption, color: .textSecondary)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    vault.openNote(at: hit.path)
                    dismiss()
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Two lines rather than one: the operators no longer fit on a single row of this
    /// sheet, and a legend that truncates teaches nothing.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("tag:type-note · path:\"01 Progetti\" · task:open · \"frase esatta\" · -escludi · regex:^##")
            Text("modified:>2026-08-01 · modified:2026-08-01..2026-08-19 · is:starred · linked:Nota · orphan:")
        }
        .themedText(.caption, color: .textTertiary)
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .themedText(.body, color: .textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() async {
        let query = SearchQuery(raw)
        invalidPatterns = query.invalidPatterns
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        // A short pause so a search does not run on every keystroke of a long query.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        results = vault.search(query).map { result in
            Hit(path: result.path, title: result.title, excerpt: result.excerpt)
        }
    }
}
