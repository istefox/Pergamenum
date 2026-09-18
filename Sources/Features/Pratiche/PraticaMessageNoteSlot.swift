import SwiftUI

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 6 - R-05, R-08; ADR §D8, §D9.

/// The timeline's aligned column (§D8): one message row's own linked note, read-only,
/// drawn at the row's own height inside the same `HStack` `PraticaTimelineView.row(_:)`
/// builds - there is no second scroll view, so this never has to sync itself against
/// one. Empty when the message carries no link at all; marked broken rather than
/// hidden when the reference no longer resolves (R-08, SPEC's Edge cases).
///
/// Opens the note the same two calls `PratichePane+Inspector.swift`'s
/// `openPraticaNote` already makes (§D9) - no text view is bound to the note here,
/// which is that section's whole argument applied to a second surface.
struct PraticaMessageNoteSlot: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    /// `PraticaRowDetail.linkedNote` - the raw `[[Titolo]]` reference, or `nil` when
    /// this message has none.
    let reference: String?
    /// `PraticaMessageRow.hash(of:)`'s own value, so this slot's identifier and the
    /// row's indicator identify the same message the same way.
    let hash: String

    private enum SlotState: Equatable {
        case empty
        case broken(title: String)
        case resolved(path: String, title: String, openingLines: String)
    }

    @State private var state: SlotState = .empty

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 1, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pratiche-message-note-\(hash)")
            .task(id: reference) { load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .empty:
            Color.clear
        case .broken(let title):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "questionmark.square.dashed")
                        .foregroundStyle(theme.color(.textTertiary))
                    Text(title).themedText(.caption, color: .textTertiary).lineLimit(1)
                }
                Text("nota non trovata nel vault").themedText(.caption, color: .textTertiary)
            }
            .padding(theme.spacing(.xs))
            .accessibilityLabel("Nota collegata non trovata: \(title)")
        case .resolved(let path, let title, let openingLines):
            Button {
                vault.openChosenNote(at: path)
                navigation.pane = .notes
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).themedText(.caption, color: .accentPrimary).lineLimit(1)
                    if !openingLines.isEmpty {
                        Text(openingLines).themedText(.caption, color: .textSecondary).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(theme.spacing(.xs))
            .accessibilityLabel("Nota collegata: \(title)")
        }
    }

    /// One index lookup and, only on a unique resolution, one file read - one slot,
    /// one message, never the whole timeline's worth per draw.
    private func load() {
        guard let reference, case let .wikilink(title)? = PraticaLinkReference(parsing: reference) else {
            state = .empty
            return
        }
        guard let root = vault.root else {
            state = .broken(title: title)
            return
        }
        switch PraticaLinkResolver.note(candidates: vault.index.resolve(title: title)) {
        case .unique(let path):
            let url = root.appending(path: path, directoryHint: .notDirectory)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = Self.openingLines(of: NoteDocument.parse(text).body)
            state = .resolved(path: path, title: title, openingLines: lines)
        case .ambiguous, .missing:
            state = .broken(title: title)
        }
    }

    private static func openingLines(of body: String, limit: Int = 3) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(limit)
            .joined(separator: "\n")
    }
}
