import SwiftUI

/// The inspector's BACKLINK section, each row saying why it is there (ADR-0084 §D1, mockup
/// «Ispettore: link» approved for N3): the title, the line that links with the link in the
/// accent, a count above one, and «strutturale» when the other note's `related` names this one.
///
/// The row menu is `BacklinkCommand`, rendered as the `.contextMenu` and as the
/// `.accessibilityActions` (ADR-0023 §D1). The inspector is a `ScrollView`, not a `List`, so a
/// SwiftUI menu opens here (ADR-0069 is about `List` rows only).
struct BacklinksSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(CommandActions.self) private var commandActions

    let note: VaultController.OpenNote

    /// The row «Scollega» asks about; the dialog hands it to its button as a parameter.
    @State private var unlinking: BacklinkRow?
    /// Why «Scollega» did nothing, or only half: `vault.problems` shows in Settings alone, so the
    /// sentence is read right after the refusal and kept here (as `NoteListPane`'s `trashRefused`).
    @State private var unlinkRefused: String?

    var body: some View {
        let rows = vault.backlinkRows(toTitle: note.title)
        let header = VaultBrowser.InspectorSection.backlinks(count: rows.count)
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
        // The names are in the message, which receives the row: a title reading `unlinking` would
        // lose the second name while the dialog closes, since the binding nils it on the way out.
        .confirmationDialog(
            "Scollegare il legame strutturale?",
            isPresented: Binding(
                get: { unlinking != nil },
                set: { if !$0 { unlinking = nil } }
            ),
            titleVisibility: .visible,
            presenting: unlinking
        ) { row in
            Button("Scollega", role: .destructive) { unlink(row) }
            Button("Annulla", role: .cancel) { unlinking = nil }
        } message: { row in
            Text("Il legame fra «\(note.title)» e «\(row.title)» e i due motivi spariscono da entrambe le note.")
        }
        .alert(
            "Scollega",
            isPresented: Binding(
                get: { unlinkRefused != nil },
                set: { if !$0 { unlinkRefused = nil } }
            ),
            presenting: unlinkRefused
        ) { _ in
            Button("OK", role: .cancel) { unlinkRefused = nil }
                .accessibilityIdentifier("backlink-unlink-refused-ok")
        } message: { reason in
            Text(reason)
                .accessibilityIdentifier("backlink-unlink-refused")
        }
    }

    private func rowView(_ row: BacklinkRow) -> some View {
        Button { run(.open, on: row) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: theme.spacing(.xs)) {
                    Text(row.title).themedText(.body, color: .accentPrimary).lineLimit(1)
                    if row.isStructural {
                        Text("strutturale")
                            .themedText(.caption, color: .textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.color(.backgroundTertiary)))
                    }
                    Spacer(minLength: 0)
                    if row.count > 1 {
                        Text("\(row.count) link").themedText(.caption, color: .textTertiary)
                    }
                }
                if let line = row.firstLine {
                    Text(context(line))
                        .themedText(.caption, color: .textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(row.path)
        .contextMenu {
            ForEach(BacklinkCommand.available(for: row)) { command in
                if command == .makeStructural || command == .unlink { Divider() }
                Button(command.title) { run(command, on: row) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(row))
        .accessibilityIdentifier("backlink-row-\(row.path)")
        .accessibilityActions {
            ForEach(BacklinkCommand.available(for: row)) { command in
                Button(command.title) { run(command, on: row) }
            }
        }
    }

    /// The line, with every link to this note in the accent, so the eye lands on why the row is
    /// here.
    private func context(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)
        let wanted = note.title.lowercased()
        for link in WikilinkParser.links(in: line) where link.target.lowercased() == wanted {
            guard let lower = AttributedString.Index(link.range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(link.range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].foregroundColor = theme.color(.accentPrimary)
        }
        return attributed
    }

    private func accessibilityText(_ row: BacklinkRow) -> String {
        var parts = [row.title]
        if row.isStructural { parts.append("legame strutturale") }
        if row.count > 1 { parts.append("\(row.count) link") }
        if let line = row.firstLine { parts.append(line) }
        return parts.joined(separator: ", ")
    }

    private func run(_ command: BacklinkCommand, on row: BacklinkRow) {
        switch command {
        case .open: commandActions.open(notePath: row.path, how: .replace)
        case .openInOtherColumn: commandActions.open(notePath: row.path, how: .otherColumn)
        case .makeStructural: vault.beginStructuralLink(preselecting: row.path)
        case .unlink: unlinking = row
        }
    }

    /// The row arrives as the dialog's parameter and is captured before the `Task`: the dialog
    /// nils `unlinking` on its way out (`.claude/rules/swiftui-views.md`).
    private func unlink(_ row: BacklinkRow) {
        let source = note.relativePath
        unlinking = nil
        Task { @MainActor in
            unlinkRefused = await vault.unlinkStructuralLink(from: source, toNoteAt: row.path)
        }
    }
}
