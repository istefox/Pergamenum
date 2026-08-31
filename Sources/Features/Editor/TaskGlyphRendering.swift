import AppKit

/// The one fact every surface drawing a task line's checkbox has to agree on: which glyph
/// stands in for each of the four §7.1 states (PG-086; plan
/// `2026-08-31-pg-074-give-the-to-do-tool-an-interactiv`).
///
/// `ListMarkerRendering`'s sibling in shape and in reasoning: `EditorDecorationDelegate`
/// substitutes the glyph into the *displayed* paragraph, never the stored one, so both
/// surfaces this chain touches (the note editor and a Workspace card) draw the identical
/// checkbox for the identical state.
///
/// AppKit rather than Foundation only, and under `Sources/Features/` rather than
/// `Sources/Core/` for the same reason as `ListMarkerRendering`: `Character` alone would not
/// need it, but living beside its sibling keeps the two facts about task-line rendering in
/// one place rather than splitting them across a shared and an app-only file.
enum TaskGlyphRendering {
    /// The single character drawn in place of a task line's state marker
    /// (`- [ ]`/`- [x]`/`- [>]`/`- [-]`), one UTF-16 unit each - the same length-preserving
    /// requirement `ListMarkerRendering.glyph(for:)` satisfies, since the substitution
    /// replaces exactly one character in the displayed paragraph
    /// (`NSTextContentManager.h:120`).
    static func glyph(for state: TaskItem.State) -> Character {
        switch state {
        case .open: "\u{2610}" // ☐
        case .done: "\u{2611}" // ☑
        case .rescheduled: "\u{21C4}" // ⇄
        case .cancelled: "\u{2612}" // ☒
        }
    }
}
