import AppKit

// ADR-0095 §D6 and §D7, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 5 (PG-406).
//
// The coordinator's side of the outline store: which store it feeds, the shift, the splice and the
// rebuild that keep it level with the storage, the stamp that says which revision it describes, and the
// two reads the editor makes of it (the caret's entry and the folds). In a file of its own because the
// coordinator's file is at the length SwiftLint allows: the class holds one stored `outlineFeed`.

extension NoteTextView {
    /// Which outline store the coordinator feeds: the column's when the parent hands one in, otherwise
    /// one of its own (Oggi, Diario, a test), so there is one code path. `fed` is the identity of the
    /// store the coordinator last brought level with its storage; any other store is rebuilt from the
    /// storage before it is first read or spliced.
    struct OutlineFeed {
        var own: OutlineStore?
        var fed: ObjectIdentifier?
    }
}

extension NoteTextView.Coordinator {
    /// The store the parent names, or the private one; nil only before either exists.
    private var namedOutlineStore: OutlineStore? {
        parent.outline.store ?? outlineFeed.own
    }

    /// The store this coordinator feeds, brought level with `textView`'s storage first when it is not
    /// the one last fed.
    func outlineStore(for textView: NSTextView) -> OutlineStore {
        let store: OutlineStore
        if let named = namedOutlineStore {
            store = named
        } else {
            store = OutlineStore()
            outlineFeed.own = store
        }
        if outlineFeed.fed != ObjectIdentifier(store) {
            store.rebuild(text: textView.string)
            outlineFeed.fed = ObjectIdentifier(store)
        }
        return store
    }

    /// The store, only when it is the one last fed: what the shift and the snapshot read, neither of
    /// which may rebuild it from a storage mid-edit.
    var fedOutlineStore: OutlineStore? {
        guard let store = namedOutlineStore, outlineFeed.fed == ObjectIdentifier(store) else { return nil }
        return store
    }

    /// The full pass's rebuild (`settleBaseline`), which every `.full` decision and every pass under the
    /// kill switch reaches.
    func rebuildOutline(from text: String) {
        let store = namedOutlineStore ?? OutlineStore()
        if parent.outline.store == nil { outlineFeed.own = store }
        store.rebuild(text: text)
        outlineFeed.fed = ObjectIdentifier(store)
    }

    /// The `.lines` decision's splice, after the scope absorbed the fragment, with the absorbed map's
    /// fences: the regions `NoteOutline.entries(in:)` skips by.
    func spliceOutline(in textView: NSTextView, note: NSString, dirty: NSRange) {
        guard let fences = restyleScope?.map.fences else { return }
        outlineStore(for: textView).splice(note, in: dirty, fences: fences)
    }

    /// Says which revision of the model the store now describes, after a styling pass.
    func stampOutline(in textView: NSTextView) {
        outlineStore(for: textView).stamp(parent.outline.currentRevision?())
    }

    /// The model's folds, kept as heading offsets, as ordinals of the store's map: nothing folded
    /// reads nothing.
    func foldedOrdinals(of offsets: Set<Int>, in textView: NSTextView) -> Set<Int> {
        guard !offsets.isEmpty else { return [] }
        return outlineStore(for: textView).map.ordinals(ofOffsets: offsets)
    }

    /// The entry the caret is in, by binary search over the store's map.
    func outlineEntry(atCaretOf textView: NSTextView) -> Int? {
        outlineStore(for: textView).map.lastEntry(atOrBefore: textView.selectedRange().location)
    }
}
