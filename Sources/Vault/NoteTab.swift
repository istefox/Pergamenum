import Foundation

/// One note open in the editor, with everything that belongs to *looking at that note*.
///
/// ADR-0012 D2. The folds, the index entry the caret is in and the Modifica/Lettura choice
/// used to live on `Navigation`, cleared whenever the open note changed - the single-note
/// spelling of what a tab makes structural. With two tabs open, clearing on change stops
/// being a fix and becomes data loss, because the other tab's folds were real.
struct NoteTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var note: VaultController.OpenNote
    /// The index entries whose sections are folded, by ordinal. Not written to the file:
    /// that would mean extending a frontmatter schema SPEC §4.3 closes.
    var foldedEntries: Set<Int> = []
    /// Which index entry the caret is inside, reported by the editor only when it changes.
    /// Nil in reading mode, where there is no caret to be inside anything.
    var currentOutlineEntry: Int?
    /// Whether this note is shown rendered rather than as source (SPEC §10, Cmd+Shift+E).
    var isReadingMode = false
    /// A tab opened by a single click in the list, which the next single click reuses.
    ///
    /// One per column at most. Without it, browsing a list of forty notes means opening forty
    /// tabs, or - worse, and what this app did before them - replacing whatever the person was
    /// reading, forty times. VS Code's rule, and the double click that makes a preview stable
    /// is the same gesture Stefano asked for on 2026-08-19.
    var isPreview = false

    init(note: VaultController.OpenNote, id: UUID = UUID()) {
        self.id = id
        self.note = note
    }

    /// The same tab showing a different note: the identity survives, everything that
    /// described the old note does not.
    ///
    /// This is what `VaultBrowser` used to do with an `onChange` on the open note's path,
    /// and the reason that `onChange` is gone: a reset that belongs to a tab cannot be
    /// written as a reaction to the *window's* one note changing once there is more than
    /// one of them.
    func showing(_ note: VaultController.OpenNote) -> NoteTab {
        var tab = NoteTab(note: note, id: id)
        tab.isPreview = isPreview
        return tab
    }
}

/// A column of the editor: the tabs it holds and which of them is showing.
///
/// One column today. ADR-0012 D4 adds the second in the split-view slice, and the shape is
/// here from the start so that slice moves a boundary rather than inventing one.
struct EditorColumn: Identifiable, Equatable, Sendable {
    let id: UUID
    var tabs: [NoteTab] = []
    var activeID: NoteTab.ID?

    init(id: UUID = UUID()) {
        self.id = id
    }

    var active: NoteTab? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }
}

/// The buffer a tab shows: the note as the editor has it, and as the disk last had it.
///
/// Nested on `VaultController` where it has always been - the name is spoken as
/// `VaultController.OpenNote` in a dozen places - and declared here, beside the tab that
/// holds one.
extension VaultController {
    struct OpenNote: Equatable, Sendable {
        var relativePath: String
        var title: String
        /// The text as the editor has it, which may differ from disk while editing.
        var text: String
        /// The text as last read from or written to disk.
        var savedText: String
        /// An external change arrived while this note had unsaved edits. The editor
        /// must ask rather than merging or discarding either side (ADR-0001 §D3.4).
        var externalChangePending: String?

        var hasUnsavedChanges: Bool { text != savedText }
    }
}
