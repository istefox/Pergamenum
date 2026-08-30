import SwiftUI

/// One crumb in a `BreadcrumbBar` trail - a name to show and the folder path clicking it
/// should reveal or select. `VaultController.breadcrumb` and `WorkspaceController.breadcrumb`
/// both build a `[BreadcrumbSegment]` the same way (root segment, then split-and-accumulate
/// over a folder path); this is the one place that shape is named (PG-081).
struct BreadcrumbSegment: Equatable, Sendable {
    let title: String
    let folder: String
}

/// The breadcrumb row `VaultTopBar` and `BoardChrome.BoardTopBar` both draw above their
/// pane: an unsaved-state dot, the crumb trail with `›` separators, and whatever trailing
/// content the caller wants (PG-081, ADR-0026 §D2's suggested `BreadcrumbSegment` plus one
/// rendering view for both panes).
///
/// The last segment is never a link (ADR-0024 §D8.2 for Workspace, mirrored for Note): it is
/// where you already are. Every other segment is a plain-style `Button` calling
/// `onSelectAncestor` with that segment's `folder`.
struct BreadcrumbBar<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let segments: [BreadcrumbSegment]
    let isUnsaved: Bool
    /// Applied as `.accessibilityIdentifier("\(identifierPrefix)-\(index)")` per segment when
    /// non-nil. Both callers pass `"breadcrumb-crumb"` (PG-081 folded Workspace's own bar into
    /// this identifier too, which only the Note side carried before).
    let identifierPrefix: String?
    let onSelectAncestor: (String) -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(isUnsaved ? .taskScheduled : .accentPrimary))
                .frame(width: 8, height: 8)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                if index == segments.count - 1 {
                    Text(segment.title).themedText(.body, color: .textPrimary)
                        .accessibilityIdentifier(identifierPrefix.map { "\($0)-\(index)" } ?? "")
                } else {
                    Button(segment.title) { onSelectAncestor(segment.folder) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .textSecondary)
                        .accessibilityIdentifier(identifierPrefix.map { "\($0)-\(index)" } ?? "")
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }
}
