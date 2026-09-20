import SwiftUI

/// Chooses a category's home note (PG-166, ADR-0047 §D10): the sheet behind «Collega una
/// nota…» / «Cambia nota…» in the category view and in a category row's context menu.
///
/// The write is `VaultController.setCategoryHome`, not `linkCategory`: a category has one
/// home, so choosing a note displaces whichever note held the key before rather than
/// leaving two claimants for the lint to report as `duplicateHome`.
///
/// The list is read live from the index rather than captured in `.task` (`CategoryPicker`'s
/// reason): a note created or renamed while the sheet is open should appear on its own.
struct CategoryNotePicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// What the sheet is choosing a home for - `Identifiable` so `RootView` can host it with
    /// `.sheet(item:)`, `CategoryEditor.Target`'s shape.
    struct Request: Identifiable, Equatable, Sendable {
        let slug: String
        let name: String

        var id: String { slug }
    }

    let request: Request
    let onClose: () -> Void

    @State private var filter = ""

    private var home: NoteRecord? {
        vault.index.homeNote(ofCategory: request.slug)
    }

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
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nota di «\(request.name)»").themedText(.title)
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.color(.textTertiary))
                TextField("Filtra", text: $filter)
                    .textFieldStyle(.plain)
                    .themedText(.body)
                    .accessibilityIdentifier("category-note-picker-filter")
            }
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Rows

    private var list: some View {
        let notes = filtered
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(notes) { note in
                    row(note)
                }
                if notes.isEmpty {
                    Text(vault.index.allNotes.isEmpty ? "Nessuna nota nel vault" : "Nessuna nota trovata")
                        .themedText(.body, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, theme.spacing(.l))
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
        .accessibilityIdentifier("category-note-picker-list")
    }

    private var filtered: [NoteRecord] {
        let notes = vault.index.allNotes
        guard !filter.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    private func row(_ note: NoteRecord) -> some View {
        let isHome = note.relativePath == home?.relativePath
        return Button {
            choose(note)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "doc.text")
                    .foregroundStyle(theme.color(isHome ? .accentPrimary : .textTertiary))
                Text(note.title)
                    .themedText(.body, color: isHome ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text(note.folder)
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nota \(note.title)")
        .accessibilityIdentifier("category-note-picker-row-\(note.relativePath)")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            if let home {
                Button("Togli la nota") { clear(home) }
                    .accessibilityIdentifier("category-note-picker-clear")
            }
            Spacer()
            Button("Chiudi", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Writing

    private func choose(_ note: NoteRecord) {
        // The category may have been deleted or archived while the sheet was open; the
        // registry is the door, so a stale choice writes nothing (`CategoryPicker.assign`).
        guard vault.categories.entries.contains(where: { $0.slug == request.slug }) else { return }
        Task { @MainActor in
            await vault.setCategoryHome(request.slug, toNoteAt: note.relativePath)
            onClose()
        }
    }

    private func clear(_ note: NoteRecord) {
        Task { @MainActor in
            await vault.unlinkCategory(fromNoteAt: note.relativePath)
            onClose()
        }
    }
}
