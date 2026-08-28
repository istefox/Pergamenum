import Foundation

/// Bullet, numbered and heading prefixes on the lines a selection touches (ADR-0027 §D6, plan
/// `2026-08-28-unificare-nota-e-testo-in-un-solo-strume`, Task 2, R-05).
///
/// `InlineFormat` wraps a *selection* in a pair of markers; a list or a heading is a *line*
/// operation instead - it does not surround characters, it rewrites the start of every line the
/// selection touches, and it must do that whether the selection is a whole paragraph, a single
/// word inside one line, or a bare caret. The two pure engines sit side by side on purpose
/// (`FormattingTextView` in a later task wires both through the same one-edit-per-press path),
/// but they do not share an implementation: markers-around-a-range and prefix-on-every-line are
/// different arithmetic.
///
/// Foundation only. This is under `Sources/Core`, which both connectors compile
/// (`Project.swift`'s `sharedSources` glob, `:73`), so an `import AppKit` or `import SwiftUI`
/// here breaks `perg` and `pergamenum-mcp` rather than this file.
enum LineFormat: Equatable, Sendable {
    case bullet
    case numbered
    /// 1...3, per SPEC scope (`MarkdownStyler`'s existing heading spans go no deeper).
    case heading(level: Int)

    /// Whether every line `range` touches already carries this format, which is what lights the
    /// card's format-bar button and what `toggled` inverts. A *mixed* selection - one line
    /// already prefixed, one not - reads as not-applied, so the next press adds the format to
    /// every touched line rather than stripping the one that already has it (plan Task 2, "one
    /// press makes the whole selection consistent").
    static func isApplied(_ format: Self, in text: String, over range: NSRange) -> Bool {
        fatalError("LineFormat.isApplied not implemented - stub for Task 2, body is Task 5's job")
    }

    /// The text after toggling `format` over every line `range` touches, and where the
    /// selection ends up afterwards.
    ///
    /// - A bare caret (`range.length == 0`) still touches exactly one line, its own, and is not
    ///   a no-op - unlike `InlineFormat.toggled`'s empty-selection rule, which exists to avoid
    ///   leaving a stray marker pair around nothing. There is no equivalent trap here: the
    ///   caret's line is real text (or a real empty line) either way.
    /// - `.numbered` renumbers the touched run from 1 regardless of the lines' position in the
    ///   rest of the document.
    /// - `.heading(level:)` over a line already at a *different* level replaces that line's
    ///   marker rather than stacking a third `#` onto it.
    /// - The returned selection covers the same words it did before, the same contract
    ///   `InlineFormat.toggled` keeps, so pressing the same button twice acts on what the first
    ///   press acted on.
    static func toggled(
        _ format: Self, in text: String, over range: NSRange
    ) -> (text: String, selection: NSRange) {
        fatalError("LineFormat.toggled not implemented - stub for Task 2, body is Task 5's job")
    }
}
