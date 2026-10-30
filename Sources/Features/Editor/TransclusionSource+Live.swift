import Foundation

// ADR-0098 §D4, closing ADR-0082 §D8's named transclusion gap (PG-428): the one place a
// `TransclusionSource` over a vault is built, so the three editor hosts (the Note pane, Oggi and
// Diario) cannot build three different sources, the way `ViewQuerySource+Live.swift` does for
// the query source.

extension TransclusionSource {
    /// Where a `![[nota]]` gets the note it names (ADR-0010 §D1: read fresh, never copied).
    ///
    /// Two lookups, in the order §D2 gives them: a reference ending in `.md` is a path, and
    /// anything else is a title through the index - the same lookup a `[[wikilink]]` uses,
    /// so the two cannot disagree about which note a name means.
    ///
    /// `EditorColumnView.transclusionGeneration(for:)` rides along so a target is redrawn when
    /// the index changes, and only then: the id it feeds changes when a note is written, not
    /// when a key is pressed. The function stays on the view type rather than moving here because
    /// ADR-0098 §D4 keeps it where `IndexGenerationFollowUpTests` reads it.
    @MainActor
    static func live(for vault: VaultController) -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard let session = vault.session else { return nil }
                let paths = reference.lowercased().hasSuffix(".md")
                    ? [reference]
                    : vault.index.resolve(title: reference)
                for path in paths {
                    guard let read = try? session.read(path) else { continue }
                    return TransclusionSource.Resolved(
                        title: read.record.title,
                        relativePath: path,
                        text: read.text
                    )
                }
                return nil
            },
            generation: EditorColumnView.transclusionGeneration(for: vault)
        )
    }
}
