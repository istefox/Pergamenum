import AppKit

/// How many stylings took each path, and the range the last incremental one restyled
/// (ADR-0091 §D8, per-paragraph-restyle plan, Task 3). A test seam and a diagnostic: nothing
/// branches on it.
struct RestyleLog: Equatable, Sendable {
    var full: Int = 0
    var incremental: Int = 0
    var skipped: Int = 0
    var lastDirtyRange: NSRange?
}

/// What a styling read besides the text, as of the last one (ADR-0091 §D8). The incremental and the
/// skipped paths are taken only while these are unchanged: anything else here moving restyles the
/// note in full, as every pass did before ADR-0091.
///
/// The plan's fingerprint (storage, theme, `hidesMarkup`, `revealsInlineSpans`) plus four inputs
/// the passes after the styling read off the whole note: the note path, vault root and thumbnail
/// store an embed resolves through, and the container width a transcluded note is measured at. The
/// store is compared by identity: it is an actor, and a new one is a new cache.
struct StylingInputs: Equatable {
    var storage: ObjectIdentifier
    var theme: Theme
    var hidesMarkup: Bool
    var revealsInlineSpans: Bool
    var notePath: String
    var vaultRoot: URL?
    var thumbnails: ObjectIdentifier?
    var containerWidth: CGFloat

    @MainActor
    init(storage: NSTextStorage, textView: NSTextView, theme: Theme, parent: NoteTextView) {
        self.storage = ObjectIdentifier(storage)
        self.theme = theme
        hidesMarkup = parent.hidesMarkup
        revealsInlineSpans = parent.revealsInlineSpans
        notePath = parent.vault.notePath
        vaultRoot = parent.vault.vaultRoot
        thumbnails = parent.vault.thumbnails.map(ObjectIdentifier.init)
        containerWidth = textView.textContainer?.size.width ?? 0
    }
}

/// The text storage's own report of an edit, recorded for the restyle (ADR-0091 §D2). Installed on
/// the storage by the first full `applyStyling`.
extension NoteTextView.Coordinator: NSTextStorageDelegate {
    /// Character edits only: an attribute edit is a styling's own write. Called on the main thread
    /// by the storage's `processEditing`, so the main actor is entered without a hop; what it does
    /// there reads only the touched lines (`recordStorageEdit(_:in:)`) and changes no attribute.
    ///
    /// `willProcessEditing`, not `didProcessEditing`: between the two the storage fixes attributes,
    /// which widens the reported range to the end of the paragraph (a typed character at 10 arrives
    /// as `{10, 27}` there, `{10, 1}` here), so the old range read from it would be wrong. Pinned by
    /// `IncrementalRestyleHosted.theStorageReportsAKeystrokeAsItsRangeAndDelta`.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let edit = StorageEdit(range: editedRange, delta: delta)
        nonisolated(unsafe) let storage = textStorage
        MainActor.assumeIsolated {
            modelSync.heardEdit()
            recordStorageEdit(edit, in: storage)
        }
    }

    /// The second callback (ADR-0093 §D2): the layout record hears every processed edit, characters or
    /// attributes, in the range attribute fixing has widened (a typed character at 10 arrives as
    /// `{10, 27}`), which is what TextKit re-creates. Pinned by `IncrementalRestyleHosted`'s platform pin.
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        let edit = StorageEdit(range: editedRange, delta: delta)
        nonisolated(unsafe) let storage = textStorage
        MainActor.assumeIsolated {
            layoutDebt.hear(edit, in: storage)
        }
    }
}
