import AppKit
import SwiftUI

/// The drag handle between the board list and the tool column, and the clamp that
/// keeps the list from collapsing its own header or swallowing the board.
///
/// Modelled on `SplitColumns.divider(available:)` in `Sources/Features/Editor/
/// EditorColumns.swift`, the only other draggable divider in this repo - but that one
/// moves a *fraction* of the space two columns share, while this one moves an
/// *absolute* width the board list keeps and the board gives up. Sharing the two would
/// have meant bending one of them to fit the other's shape.
struct WorkspacePaneDivider: View {
    @Environment(\.theme) private var theme
    @Binding var width: CGFloat

    /// Below this the "WORKSPACE" caption and the Filtra field in
    /// `WorkspaceBrowser.swift` wrap onto a second line.
    static let minWidth: CGFloat = 160
    /// Above this the list has stopped being a sidebar.
    static let maxWidth: CGFloat = 420

    /// Where the drag began, so a `DragGesture`'s translation - reported from the start
    /// of the gesture, not the last frame - is added to a fixed base instead of
    /// compounding on itself every frame.
    @State private var widthAtDragStart: CGFloat?
    @State private var isHovering = false

    private let dividerWidth: CGFloat = 1
    /// The line is a hairline; what the pointer has to hit is a finger wide.
    private let grabWidth: CGFloat = 10

    static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    var body: some View {
        Rectangle()
            .fill(theme.color(.borderSubtle))
            .frame(width: dividerWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: grabWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        // Guarded, because a `pop` without its `push` takes the arrow
                        // away from whatever pushed one before.
                        guard hovering != isHovering else { return }
                        isHovering = hovering
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(drag)
            }
            .accessibilityIdentifier("workspace-browser-divider")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                width = Self.clamp(start + value.translation.width)
            }
            .onEnded { _ in widthAtDragStart = nil }
    }
}
