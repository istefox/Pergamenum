import SwiftUI

/// Renaming a tag across the vault, as a person sees it (ADR-0012 D7; mockup approved on
/// 2026-08-19).
///
/// **The diff comes before the write, and it is one diff plus a count.** The line that changes
/// is the same line in every note the rename touches, so showing it twelve times says exactly
/// what showing it once says and puts eleven identical blocks between the person and the
/// button. What the count is for is the other half of the question: *how many*.
///
/// Nothing here performs a write. It hands back the new tag and the caller does it, so the
/// journal is armed in one place and this stays a sheet.
struct TagRenameSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let old: Tag
    let onRename: (Tag) -> Void
    let onCancel: () -> Void

    @State private var typed: String

    init(old: Tag, onRename: @escaping (Tag) -> Void, onCancel: @escaping () -> Void) {
        self.old = old
        self.onRename = onRename
        self.onCancel = onCancel
        _typed = State(initialValue: old.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina «\(old.description)» in tutto il vault")
                .themedText(.heading)

            TextField("nuovo tag", text: $typed)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("tag-rename-field")

            if let problem {
                Text(problem).themedText(.caption, color: .taskOverdue)
            } else {
                preview
            }

            HStack(spacing: theme.spacing(.s)) {
                Spacer()
                Button("Annulla", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rinomina") {
                    if let parsed { onRename(parsed) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed == nil || changes.isEmpty)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.backgroundPrimary))
    }

    // MARK: Cosa succederebbe

    @ViewBuilder
    private var preview: some View {
        if changes.isEmpty {
            Text("Nessuna nota porta «\(old.description)».")
                .themedText(.caption, color: .textTertiary)
        } else {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text(changes.count == 1 ? "1 nota toccata" : "\(changes.count) note toccate")
                    .themedText(.caption, color: .textSecondary)
                if let first = changes.first, let diff = diff(of: first) {
                    DiffView(path: first.path, diff: diff)
                }
                if changes.count > 1 {
                    Text("e altre \(changes.count - 1), tutte con la stessa riga")
                        .themedText(.caption, color: .textTertiary)
                }
            }
        }
    }

    private func diff(of change: VaultSession.TagRenameChange) -> String? {
        UnifiedDiff.between(change.before, change.after, path: change.path, context: 1)
    }

    /// The new tag, or nil while what is typed is not one. SPEC §4.4 closes the grammar and a
    /// sheet is not where it is widened: the field refuses rather than writing something the
    /// linter would then report in forty notes.
    private var parsed: Tag? {
        guard let tag = Tag(typed.trimmingCharacters(in: .whitespaces)), tag != old else { return nil }
        return tag
    }

    private var problem: String? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        if trimmed == old.description { return nil }
        guard Tag(trimmed) == nil else { return nil }
        return """
        «\(trimmed)» non è un tag valido: namespace fra client, competitor, project, type, \
        topic, status, area, source, poi un trattino e parole minuscole.
        """
    }

    private var changes: [VaultSession.TagRenameChange] {
        guard let parsed else { return vault.tagRenamePreview(old, to: old) }
        return vault.tagRenamePreview(old, to: parsed)
    }
}

/// A unified diff, coloured by line. Small enough to live here: it is the only place in the app
/// that shows one to a person.
private struct DiffView: View {
    @Environment(\.theme) private var theme
    let path: String
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(path).themedText(.caption, color: .textTertiary)
            ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
                    .themedText(.mono, color: colour(of: line))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private func colour(of line: String) -> ColorToken {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { return .textTertiary }
        if line.hasPrefix("+") { return .codeString }
        if line.hasPrefix("-") { return .taskOverdue }
        return .textSecondary
    }
}
