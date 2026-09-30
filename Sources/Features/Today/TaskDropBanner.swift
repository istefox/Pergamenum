import SwiftUI

/// What the last drop or block insertion wrote, and the way back (ADR-0013 §D5,
/// ADR-0075 §D3), drawn by `TodayView` above all three scales.
///
/// Its own view so a test can host it and measure it: its height is a constraint, not a
/// look (below).
struct TaskDropBanner: View {
    @Environment(\.theme) private var theme

    let drop: DayController.Drop
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: drop.isRefusal ? "exclamationmark.triangle" : "checkmark")
                .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textTertiary)
            // The banner sits above the Today view's `HSplitView` and must never change height
            // once it is up: it can appear mid drop-commit, and a taller banner then makes AppKit
            // renegotiate the split's constraints inside that transaction and abort the app
            // (PG-259, ADR-0075 §D3). The hidden two-line text sizes the slot, not the summary:
            // `.lineLimit(2, reservesSpace: true)` reserves two lines without the token's line
            // spacing, so a wrapped summary still grew the banner by it (measured, 26 vs 32pt).
            ZStack(alignment: .leading) {
                Text(verbatim: " \n ").themedText(.caption).hidden()
                Text(drop.summary)
                    .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textSecondary)
                    .lineLimit(2)
                    .help(drop.summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if drop.journalID != nil {
                Button("Annulla", action: onUndo)
                    .accessibilityIdentifier("undo-task-drop")
            }
            Button("Chiudi", action: onClose)
                .buttonStyle(.plain)
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .accessibilityIdentifier("task-drop-banner")
    }
}
