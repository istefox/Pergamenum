import SwiftUI

/// Assigns a task to a category (ADR-0047 §D5, R-03): the sheet behind "Assegna
/// categoria…", reachable the same way `WorkspacePicker` is - the row's context menu, the
/// Attività toolbar and the Task menu, all routed through `TaskCommand.assignCategory`.
///
/// The list reads `vault.categories` live rather than capturing it once the way
/// `WorkspacePicker`'s `.task`-fetched `boards` does: SPEC "Edge cases" requires a
/// category deleted while the picker is open to disappear from the list on its own, which
/// an `@Observable` read straight from the environment gives for free. Rows come from
/// `CategoryRegistry.assignableGroups` (SPEC "UI flows": "grouped parent → child"), the
/// same grouping the composer's category chip uses.
///
/// The write goes through `VaultSession.TaskChange.category` (Task 3), which replaces
/// every existing `#project-*` tag rather than appending a second.
struct CategoryPicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let task: TaskItem
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 380)
        .background(theme.color(.surfaceCard))
        .onExitCommand(perform: onClose)
    }

    // MARK: Header

    private var header: some View {
        Text("Assegna categoria").themedText(.title)
            .padding(theme.spacing(.m))
    }

    // MARK: Rows

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vault.categories.assignableGroups, id: \.parent.slug) { group in
                    row(group.parent)
                    ForEach(group.children) { child in
                        row(child, indented: true)
                    }
                }
                if vault.categories.assignableGroups.isEmpty {
                    Text("Nessuna categoria nel vault")
                        .themedText(.body, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, theme.spacing(.l))
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
        .accessibilityIdentifier("category-picker-list")
    }

    private func row(_ category: Category, indented: Bool = false) -> some View {
        let isAssigned = task.project?.value == category.slug
        return Button {
            assign(category.slug)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: category.symbol ?? "tag")
                    .foregroundStyle(theme.color(isAssigned ? .accentPrimary : .textTertiary))
                Text(category.name)
                    .themedText(.body, color: isAssigned ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
            }
            .padding(.leading, indented ? theme.spacing(.l) : theme.spacing(.m))
            .padding(.trailing, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Categoria \(category.name)")
        .accessibilityIdentifier("category-picker-row-\(category.slug)")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            // Clearing is the other half of "exactly one category" (R-03): without it a
            // tag assigned by mistake could only be removed by editing the note.
            if task.project != nil {
                Button("Togli la categoria") { assign(nil) }
                    .accessibilityIdentifier("category-picker-clear")
            }
            Spacer()
            Button("Chiudi", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Writing

    /// Assigns `slug`, or clears the category when nil. A non-nil choice is checked
    /// against the live registry first and refused silently when it no longer names a
    /// registered, non-archived category (SPEC "Edge cases": "a stale choice is refused,
    /// not applied") - the picker was left open while the category it is about to write
    /// was deleted or archived out from under it.
    private func assign(_ slug: String?) {
        if let slug, !vault.categories.entries.contains(where: { $0.slug == slug && !$0.archived }) {
            return
        }
        Task { @MainActor in
            await vault.apply(.category(slug), to: task)
            onClose()
        }
    }
}
