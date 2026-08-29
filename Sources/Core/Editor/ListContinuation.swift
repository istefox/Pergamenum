import Foundation

/// Enter-to-continue and ordered-run renumbering for list lines, pure (ADR-0028 §D6, plan
/// `2026-08-29-wysiwyg-markdown-in-workspace`, Task 2, R-07, R-08).
///
/// Sits beside `LineFormat` in `Sources/Core/Editor/` but answers a different question:
/// `LineFormat` rewrites the lines a *selection* touches, with no knowledge of what is above or
/// below them. `newline` and `renumbered` are both questions about the *run* a line belongs to -
/// where it starts, where it ends, what its own first ordinal was - which is why this is a new
/// type rather than an addition to that one (ADR-0028 §A9). The marker-recognition duplication
/// between the two files is accepted and recorded in the ADR's Consequences.
///
/// STUB: both entry points return `nil` unconditionally so the target and the two connectors
/// keep building while `Tests/ListContinuationTests.swift` goes red for the right reason - missing
/// behavior, not a compile error (concept-to-code's compiled-language rule). The coder fills in
/// the real arithmetic.
///
/// Foundation only. This is under `Sources/Core`, which both connectors compile
/// (`Project.swift`'s `sharedSources` glob, `:73`), so an `import AppKit` or `import SwiftUI`
/// here breaks `perg` and `pergamenum-mcp` rather than this file (`InlineFormat.swift`'s own
/// header warning, repeated here on purpose).
enum ListContinuation {
    /// The text and caret after pressing Return inside a list item at `selection`, or `nil` when
    /// the caret is not inside a list item at all - which is how a caller falls through to
    /// AppKit's ordinary Return.
    static func newline(in text: String, at selection: NSRange) -> (text: String, selection: NSRange)? {
        nil
    }

    /// `text` with every ordered run renumbered contiguously from its own first item's ordinal,
    /// or `nil` when no run needs a change.
    static func renumbered(_ text: String) -> String? {
        nil
    }
}
