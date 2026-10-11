import AppKit

/// Every offset-keyed thing the editor holds, as comparable values (ADR-0091 §D6, per-paragraph-restyle
/// plan, Task 3). A test seam: the stores are private to their holders, so each holder answers for
/// itself and this struct gathers the answers. Two editors fed the same edits, one restyled in full
/// and one by the dirty range, must answer equal.
struct DerivedStateSnapshot: Equatable {
    var decorations: DecorationSnapshot
    var unspellable: [NSRange]
    var embedRuns: [NSRange]
    var tablesDrawn: [Int]
    var tableHiddenRows: Set<Int>
    var viewBlocksDrawn: [Int]
    var viewBlockHiddenLines: Set<Int>
    var embedRenditions: [Int]
    var transclusionRenditions: [Int]
    var foldLayout: NoteFolding.Layout
    var revealed: Set<Int>
    var revealedSpans: [Int: [NSRange]]
    var map: StructureMap?
}

extension NoteTextView.Coordinator {
    /// Moves every offset-keyed holder past `edit`, where it lives (ADR-0091 §D6): each holder
    /// shifts its own stores, so a new store is shifted by the holder that adds it.
    func shiftDerivedState(by edit: StorageEdit) {
        decorations.shift(by: edit)
        tables.shift(by: edit)
        viewBlocks.shift(by: edit)
        embeds.shift(by: edit)
        transclusion.shift(by: edit)
        folding.shift(by: edit)
        reveal.shift(by: edit)
        shiftStyledRanges(by: edit)
    }

    /// The state above as values, read from the stores themselves; `map` is nil while no scope is
    /// kept (the kill switch, or before the first full restyle).
    func derivedStateSnapshot() -> DerivedStateSnapshot {
        DerivedStateSnapshot(
            decorations: decorations.offsetKeyedSnapshot(),
            unspellable: unspellableRanges,
            embedRuns: embedRuns,
            tablesDrawn: tables.drawn.keys.sorted(),
            tableHiddenRows: tables.hiddenRows,
            viewBlocksDrawn: viewBlocks.drawn.keys.sorted(),
            viewBlockHiddenLines: viewBlocks.hiddenLines,
            embedRenditions: embeds.renditions.keys.sorted(),
            transclusionRenditions: transclusion.lastRenditions.keys.sorted(),
            foldLayout: folding.lastFoldLayout,
            revealed: reveal.lastRevealed,
            revealedSpans: reveal.lastRevealedSpans,
            map: restyleScope?.map
        )
    }
}
