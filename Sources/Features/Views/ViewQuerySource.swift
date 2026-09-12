/// Where a `pergamenum-view` block gets its rows (ADR-0009 §D4).
///
/// The same shape `TransclusionSource` has, and for the same reason: the block is drawn by
/// `MarkdownBlocksView`, which has no vault behind it and must not grow one. A closure and a
/// generation are all a renderer needs, and a view drawn without a source says so rather than
/// drawing an empty table - an empty result and no vault at all are different facts.
///
/// `generation` is `VaultController.scanGeneration`, so a view is re-evaluated when the vault
/// is rescanned and not when a key is pressed (§D7: on open, on an explicit refresh, on a
/// debounced watcher change - never per keystroke).
struct ViewQuerySource {
    var evaluate: @MainActor (ViewBlock) -> ViewResult
    var generation: Int = 0
    /// How a card dropped between two columns of a board is written (§D5): the note, the tag of
    /// the column it came from, the tag of the one it landed in. Either may be nil, which is a
    /// drag out of or into *Senza stato*.
    ///
    /// Nil where the surface cannot write, and then the board does not offer the gesture at
    /// all - §D5 is explicit that a renderer which quietly did nothing on drop would be worse
    /// than one that never invited the drag.
    var move: (@MainActor (String, Tag?, Tag?) -> VaultSession.BoardDropOutcome)?
    /// Puts one journalled write back, by its id.
    var undo: (@MainActor (String) -> Bool)?
}
