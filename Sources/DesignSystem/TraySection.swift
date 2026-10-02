import SwiftUI

/// The shape a dashboard section has: a caption header with an optional count badge, then
/// either one line of empty text or the rows. Written once because the board tray's two
/// sections were identical down to the spacing and the colour token on every piece of text,
/// and a header that drifts from the one under it is the kind of difference nobody decided
/// on. The Pratiche links pane draws its three sections through it too (PG-376): it had
/// reproduced the view because this one was `private` to `BoardTray.swift`.
///
/// The refresh trigger stays at the call site: the sections watch different things (a task
/// generation, the document itself, a pratica's links), and that is the one part of a
/// section that is genuinely its own.
struct TraySection<Rows: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let badge: String?
    let accessibilityLabel: String
    let identifier: String
    let isEmpty: Bool
    let emptyText: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(title).themedText(.caption, color: .textTertiary)
                if let badge {
                    Text(badge).themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("\(identifier)-header")

            if isEmpty {
                Text(emptyText).themedText(.caption, color: .textTertiary)
            } else {
                rows
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
