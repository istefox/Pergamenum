import SwiftUI

/// Full-text search across the vault (SPEC §12, Cmd+Shift+F).
///
/// Reads the files rather than an index of their text: the index holds structure, not
/// content, and a search that returned stale text would be worse than a slow one. The reads
/// stay on the main actor (ADR-0041 §D12) and are cooperative (PG-260): the search runs in
/// chunks with a pause between them, so the spinner draws and typing is accepted while it
/// runs, and a keystroke cancels the search it supersedes. The ordering of spinner, results
/// and validation lives in `GlobalSearchState`.
struct GlobalSearchView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var raw = ""
    @State private var search = GlobalSearchState()

    /// The legend, one string per line. Two lines rather than one: the operators no longer
    /// fit on a single row of this sheet, and a legend that truncates teaches nothing.
    /// `tag:client-*` is there because `tag:` is exact since PG-260, and without it the
    /// family search would be invisible.
    static let legendLines: [String] = [
        "tag:type-note · tag:client-* · path:\"01 Progetti\" · task:open · \"frase esatta\" · -escludi · regex:^##",
        "modified:>2026-08-01 · modified:2026-08-01..2026-08-19 · is:starred · linked:Nota · orphan:",
    ]

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
        .task(id: raw) {
            await search.run(
                raw,
                sleep: { try? await Task.sleep(for: $0) },
                search: { try await vault.searchCooperatively($0) }
            )
        }
    }

    private var field: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
            TextField("Cerca in tutte le note…", text: $raw)
                .textFieldStyle(.plain)
                .font(theme.font(.title))
                .accessibilityIdentifier("search-field")
            if search.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("search-progress")
            }
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var content: some View {
        if !search.invalidPatterns.isEmpty {
            placeholder("Espressione regolare non valida: \(search.invalidPatterns.joined(separator: ", "))")
        } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            placeholder("Scrivi per cercare nel testo, nei titoli e nei tag.")
        } else if !search.results.isEmpty {
            List(search.results) { hit in
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
                .accessibilityIdentifier("search-result-\(hit.path)")
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("search-results")
        } else if search.answeredRaw == raw, !search.isSearching {
            // Only for the text actually answered: the spinner starts after the debounce
            // now, and without this check the placeholder would flash during every one.
            placeholder("Nessun risultato.")
        } else {
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.legendLines, id: \.self) { line in
                Text(line)
            }
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
}
