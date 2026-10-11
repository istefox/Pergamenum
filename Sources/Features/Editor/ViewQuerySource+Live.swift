import Foundation

// ADR-0082 §D8 (PG-385, R-19): the one place a `ViewQuerySource` over a vault is built, so the
// three editor hosts (the Note pane, Oggi and Diario) cannot build three different sources.
// `ViewQuerySource.swift` itself stays vault-free: its header says the renderer has no vault and
// must not grow one.

extension ViewQuerySource {
    /// The source every editor host hands its `NoteTextView` (ADR-0009 §D4).
    ///
    /// The index answers everything but `text()`, which reads the files - the same work the
    /// global search does, and the reason ADR-0009 §D7 states the cost as a rule rather than a
    /// number. `EditorColumnView.viewQueryGeneration(for:)` rides along so a view is re-evaluated
    /// when the index changes and not when a key is pressed.
    ///
    /// The one write a view makes (ADR-0009 §D5), `move`, and its `undo`, are offered here,
    /// where there is a vault and a person looking at it. A note card on the canvas passes no
    /// source at all and its board never invites the drag; the Viste pane calls
    /// `ViewEvaluator.evaluate` directly.
    @MainActor
    static func live(for vault: VaultController) -> ViewQuerySource {
        ViewQuerySource(
            evaluate: { block in
                ViewEvaluator.evaluate(block, over: vault.index) { record in
                    try? vault.session?.read(record.relativePath).text
                }
            },
            generation: EditorColumnView.viewQueryGeneration(for: vault),
            move: { path, old, new in await vault.moveOnBoard(path, from: old, to: new) },
            undo: { id in await vault.undoJournalledWrites([id]).failures.isEmpty }
        )
    }
}
