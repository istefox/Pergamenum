import SwiftUI

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
}

/// Turning a `ViewValue` into the string a cell shows.
///
/// One place, because a table, a list and a calendar all draw the same fields and three
/// spellings of a date is what makes a person doubt the one they are reading.
enum ViewValueText {
    /// The text for a value, or nil when the field has none - which is what a renderer draws
    /// an em dash for. A blank cell and a cell holding an empty string are the same picture,
    /// and the file says different things.
    static func text(_ value: ViewValue, of field: ViewField) -> String? {
        switch value {
        case .absent:
            nil
        case .text(let text):
            text.isEmpty ? nil : text
        case .list(let items):
            items.isEmpty ? nil : items.joined(separator: ", ")
        // An `if` rather than a ternary: SwiftLint reads a call in a ternary as a Void one,
        // and this codebase keeps that rule on rather than silencing it (`CommandActions.run`
        // records why there is no suppression comment anywhere in here).
        case .number(let count):
            if field == .size { bytes().string(fromByteCount: Int64(count)) } else { String(count) }
        // The one date format the interface uses (`CalendarDate.italianForm`). The mockup
        // drew `18/08` to keep its columns narrow; the app writes the year, because a view
        // spanning two of them would otherwise be ambiguous in the one place it matters.
        case .day(let day):
            day.italianForm
        }
    }

    /// Built per call rather than held: `ByteCountFormatter` is not `Sendable`, and a stored
    /// one is a compile error under strict concurrency. Only `size` reaches it, and only for
    /// the rows on screen.
    private static func bytes() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }
}
