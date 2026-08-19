import AppKit
import SwiftUI

/// The editor's one or two columns, and the divider between them (ADR-0012 D4).
///
/// **Deliberately not an `HSplitView`.** `NSSplitView` keeps the width the pane already had and
/// hands the newcomer whatever is left, so «Dividi l'editor» produced two halves of visibly
/// different size whatever the children were framed with - `maxWidth: .infinity` on both did not
/// change it. The split is a fraction of the available width here: half of it when the second
/// column appears, and the divider is the only thing that moves it.
struct EditorColumns: View {
    @Environment(VaultController.self) private var vault

    var body: some View {
        if vault.columns.count > 1 {
            SplitColumns()
        } else {
            EditorColumnView(columnIndex: 0)
        }
    }
}

/// The two-column case. A view of its own so that its `fraction` is born with it: closing a
/// column and splitting again starts from half, rather than from wherever the divider was left.
private struct SplitColumns: View {
    @Environment(\.theme) private var theme

    /// The share of the width the first column takes.
    @State private var fraction: CGFloat = 0.5
    /// Where the divider was when the drag began - a `DragGesture` reports its translation from
    /// there, not the position of the pointer.
    @State private var fractionAtDragStart: CGFloat?
    @State private var isHoveringDivider = false

    /// Narrower than this and a column shows no text worth reading. It matches the minimum the
    /// single column carried while the split was an `HSplitView`.
    private let minColumnWidth: CGFloat = 280
    private let dividerWidth: CGFloat = 1
    /// The line is a hairline; what the pointer has to hit is a finger wide.
    private let grabWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let available = max(geometry.size.width - dividerWidth, 0)
            HStack(spacing: 0) {
                EditorColumnView(columnIndex: 0)
                    .frame(width: leadingWidth(in: available))
                divider(available: available)
                EditorColumnView(columnIndex: 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The first column's width, clamped so neither half falls under the minimum.
    private func leadingWidth(in available: CGFloat) -> CGFloat {
        guard available > 0 else { return 0 }
        // Under twice the minimum there is no way to honour it on both sides, and half each is
        // the least bad answer. The window's own minimum keeps it out of this in practice.
        guard available >= minColumnWidth * 2 else { return available / 2 }
        return min(max(available * fraction, minColumnWidth), available - minColumnWidth)
    }

    private func divider(available: CGFloat) -> some View {
        Rectangle()
            .fill(theme.color(.borderSubtle))
            .frame(width: dividerWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: grabWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        // Guarded, because a `pop` without its `push` takes the arrow away from
                        // whatever pushed one before.
                        guard hovering != isHoveringDivider else { return }
                        isHoveringDivider = hovering
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(drag(available: available))
            }
    }

    private func drag(available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard available > 0 else { return }
                let start = fractionAtDragStart ?? fraction
                fractionAtDragStart = start
                fraction = min(max(start + value.translation.width / available, 0), 1)
            }
            .onEnded { _ in fractionAtDragStart = nil }
    }
}
