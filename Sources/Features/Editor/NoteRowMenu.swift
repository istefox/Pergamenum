import AppKit
import SwiftUI

// The menu a note row opens and the sheet that renames it.
//
// Split out of `NoteListPane` when the starred section (ADR-0012 D6) took that file past the
// 400 lines SwiftLint warns at. They are self-contained - a record in, an action out - which is
// what makes them the right half to move rather than the section that reads the pane's state.

/// The note context menu of SPEC §10: rename with link updating (W-08), move, delete.
///
/// One type used by both lists, so the tree and the flat list cannot drift apart.
struct NoteRowMenu: View {
    @Environment(VaultController.self) var vault
    let note: NoteRecord
    @Binding var renaming: NoteRecord?
    @Binding var deleting: NoteRecord?

    var body: some View {
        Button("Apri") { vault.openNote(at: note.relativePath) }
        Button("Apri in una nuova tab") { vault.openNoteInNewTab(at: note.relativePath) }
        Button(vault.isStarred(note.relativePath) ? "Togli dalle preferite" : "Aggiungi alle preferite") {
            vault.toggleStar(note.relativePath)
        }
        Button("Rinomina…") { renaming = note }
        Menu("Sposta in") {
            Button("(radice)") { vault.moveNote(at: note.relativePath, toFolder: "") }
            ForEach(vault.folders, id: \.self) { folder in
                Button(folder) { vault.moveNote(at: note.relativePath, toFolder: folder) }
                    .disabled(folder == note.folder)
            }
        }
        Divider()
        Button("Rivela nel Finder") {
            guard let root = vault.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appending(path: note.relativePath, directoryHint: .notDirectory),
            ])
        }
        Divider()
        Button("Elimina…", role: .destructive) { deleting = note }
    }
}

/// Renaming a note, with the title being typed held here and nowhere else.
struct RenameNoteSheet: View {
    @Environment(\.theme) var theme
    let note: NoteRecord
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var title: String

    init(note: NoteRecord, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.note = note
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: note.title)
    }

    private var violations: [NoteName.Violation] { NoteName.validate(title) }
    private var canRename: Bool { violations.isEmpty && title != note.title }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina nota").themedText(.title)
            Text("I wikilink che puntano a «\(note.title)» vengono riscritti (W-08).")
                .themedText(.caption, color: .textSecondary)

            TextField("Titolo", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRename { onConfirm(title) } }

            ForEach(ConformanceText.lines(NoteViolations(
                name: violations, frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            )), id: \.self) { line in
                Text(line).themedText(.caption, color: .taskOverdue)
            }

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rinomina") { onConfirm(title) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }
}
