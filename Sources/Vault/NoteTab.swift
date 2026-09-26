import Foundation

/// One note open in the editor, with everything that belongs to *looking at that note*.
///
/// ADR-0012 D2. The folds and the index entry the caret is in used to live on `Navigation`,
/// cleared whenever the open note changed - the single-note spelling of what a tab makes
/// structural. With two tabs open, clearing on change stops being a fix and becomes data
/// loss, because the other tab's folds were real.
///
/// A third piece of per-tab state, the Modifica/Lettura choice, was here until ADR-0029 §D13:
/// there is one editor now, always editable and always styled, so there is no mode for a tab
/// to remember.
struct NoteTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var note: VaultController.OpenNote
    /// The sections folded in this tab, each keyed by its own heading's UTF-16 character
    /// offset - not by ordinal position in `NoteOutline.entries(in:)`, which an edit above a
    /// fold silently reassigns to a different heading (`FoldStateOrdinalIndexStalenessTests`).
    /// Resolved back to an ordinal at the boundary, fresh against the current text, by
    /// `foldedOrdinals(ofOffsets:in:)` before reaching `NoteFolding`. Not written to the
    /// file: that would mean extending a frontmatter schema SPEC §4.3 closes.
    var foldedEntries: Set<Int> = []
    /// Which index entry the caret is inside, reported by the editor only when it changes.
    /// Nil until the editor has said, which is any note not yet clicked into.
    var currentOutlineEntry: Int?
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
        ///
        /// One value, not two optionals (ADR-0064 §D3): `nil` is no conflict, `.text` the
        /// note changed on disk, `.deleted` the note is gone from disk.
        var externalChangePending: VaultSession.ExternalChange.Content?

        var hasUnsavedChanges: Bool { text != savedText }

        /// What `catchUp(to:)` did with the incoming content (ADR-0064 §D3).
        enum CatchUp: Equatable {
            /// The buffer took the disk's side, or had nothing to take.
            case adopted
            /// The buffer is dirty: the prompt is pending with the incoming content.
            case asked
            /// The buffer is clean and its file is gone: the caller closes the tab.
            case vanished
        }

        /// Catches this buffer up with what the disk now holds: ADR-0001 §D3.4 for one buffer
        /// (ADR-0058 §D1), and says what it did (ADR-0064 §D3).
        ///
        /// - `.asked`: the buffer is dirty, whatever `incoming` is. It is the person's work:
        ///   never merged, never discarded - the prompt becomes pending with `incoming` as the
        ///   other side. Newest wins: a deletion replaces a pending text, and a recreation
        ///   replaces a pending deletion, so the banner describes the disk as of the last call.
        /// - `.adopted`: the buffer is clean and `incoming` is a text. It takes that text, and a
        ///   prompt still pending on it goes too: a buffer undone back to `savedText` after the
        ///   banner appeared now holds the newest text, so the older one has nothing to ask.
        /// - `.vanished`: the buffer is clean and its file is gone. Nothing on the buffer
        ///   changes; closing the tab is the caller's job (`closeTabs(_:ofVanishedNote:)`).
        ///   An in-process write passes `.text` and can never get this answer.
        @discardableResult
        mutating func catchUp(to incoming: VaultSession.ExternalChange.Content) -> CatchUp {
            if hasUnsavedChanges {
                externalChangePending = incoming
                return .asked
            }
            switch incoming {
            case .text(let incomingText):
                text = incomingText
                savedText = incomingText
                externalChangePending = nil
                return .adopted
            case .deleted:
                return .vanished
            }
        }
    }
}
