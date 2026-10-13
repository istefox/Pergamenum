import SwiftUI

/// The inspector's LINK NON RISOLTI, now the open note's own (ADR-0084 §D2): each target this
/// note links and no note answers, with «Crea nota» when the target can be a title and «Vai al
/// link», which puts the caret on the line. The vault-wide list is a sample view now.
struct UnresolvedLinksSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(CommandActions.self) private var commandActions

    /// The open note's path, and not the buffer (ADR-0095 §D5): typing does not change it.
    let relativePath: String

    var body: some View {
        let rows = vault.unresolvedLinkRows(ofNoteAt: relativePath)
        let header = VaultBrowser.InspectorSection.unresolved(count: rows.count)
        TraySection(
            title: header.title,
            badge: rows.isEmpty ? nil : "\(rows.count)",
            accessibilityLabel: header.accessibilityLabel,
            identifier: header.identifier,
            isEmpty: header.isEmpty,
            emptyText: header.emptyText
        ) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: UnresolvedLinkRow) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(row.target).themedText(.body, color: .textPrimary).lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            if row.isCreatable {
                small("Crea nota", identifier: "unresolved-link-create-\(row.target)") { create(row) }
            }
            small("Vai al link", identifier: "unresolved-link-go-\(row.target)") {
                commandActions.goToLink(target: row.target)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unresolved-link-\(row.target)")
    }

    /// ADR-0083 §D6's offer: the composer, in this note's folder, with the target as its title.
    private func create(_ row: UnresolvedLinkRow) {
        guard let choice = LinkChoice.entries(for: .missing(title: row.target, creatable: true)).first else { return }
        commandActions.choose(choice, how: .replace, from: relativePath)
    }

    private func small(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themedText(.caption, color: .accentPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                        .fill(theme.color(.backgroundTertiary))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
