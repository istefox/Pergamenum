import Foundation

/// The notes a Workspace board references, for the "Note referenziate" section of its
/// dashboard (ADR-0021 §D7, §D8; R-06).
///
/// Read from the open board document itself, never from the index: the board is
/// already loaded and already in memory, and asking the index would answer a
/// different question ("which notes mention this board") and would be wrong on a
/// board whose cards were placed and never linked. Pure and in `Core` so it is tested
/// against a `CanvasDocument` built in memory, with no window, no vault and no
/// SwiftUI - the same reason `TaskArrangement` is where it is.
enum WorkspaceReferences {
    /// Every note this board carries: the `.md` Document cards, plus every wikilink
    /// found inside its text nodes. De-duplicated, stable order.
    ///
    /// Signature-only stub as of this commit (plan
    /// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task
    /// 7): returns `[]` unconditionally so the target builds and
    /// `Tests/WorkspaceReferenceTests.swift` fails red on its assertions rather than
    /// failing to compile.
    static func notes(in document: CanvasDocument) -> [String] {
        []
    }
}
