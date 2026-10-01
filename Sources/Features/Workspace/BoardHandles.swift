import AppKit
import SwiftUI

/// One of the eight resize grips of SPEC §6.3.
///
/// The hover cursor and the state that pops what it pushed belong to `BoardGripView`;
/// this view holds no state of its own. It exists for the resize gesture and for a hit
/// target (`targetSize`) larger than the square the grip draws.
struct ResizeHandleView: View {
    let workspace: WorkspaceController
    let node: CanvasNode
    let handle: BoardGeometry.Handle
    /// The frame the grips are laid out on, in board units. The frame of the resize
    /// in flight when there is one, so the grips follow the card as it is stretched.
    let frame: CGRect
    /// Shift, for the proportional resize of SPEC §6.3.
    let modifiers: EventModifiers

    private var targetSize: CGFloat {
        BoardGeometry.boardUnits(BoardGeometry.handleTargetScreenSize, at: workspace.zoom)
    }

    var body: some View {
        BoardGripView(handle: handle, zoom: workspace.zoom)
            // High priority, so the grip wins against the card's own drag underneath
            // it instead of racing it.
            .highPriorityGesture(resizeGesture)
            // Gesture before `.position`, as everywhere on this board: `.position`
            // expands its result to fill the parent, and a gesture added after it
            // listens across the whole card rather than over the grip.
            .position(
                x: targetSize / 2 + handle.unitPoint.x * frame.width,
                y: targetSize / 2 + handle.unitPoint.y * frame.height
            )
    }

    private var resizeGesture: some Gesture {
        // `.global` for the same reason the card drag uses it: the local space sits
        // inside the board's `scaleEffect`, so a 100-point move would be reported in
        // board units and then divided by the zoom a second time.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if workspace.resizingNodeID != node.id {
                    workspace.beginResize(nodeID: node.id, handle: handle)
                }
                workspace.updateResize(
                    translation: CGSize(
                        width: value.translation.width / workspace.zoom,
                        height: value.translation.height / workspace.zoom
                    ),
                    lockAspect: modifiers.contains(.shift)
                )
            }
            .onEnded { _ in workspace.endResize() }
    }
}

/// What a board grip looks like and what the pointer shows over it: the eight resize grips of
/// `ResizeHandleView` and the eight crop grips of `BoardCropEditor` draw through this one view,
/// which is ADR-0020's "the crop grips reuse the resize grip's visual language" made literal.
///
/// The look and the cursor only. Each caller adds its own gesture and its own `.position`,
/// because those are what differ between a resize and a crop.
struct BoardGripView: View {
    @Environment(\.theme) private var theme
    let handle: BoardGeometry.Handle
    let zoom: CGFloat

    @State private var isHovering = false

    private var visualSize: CGFloat {
        BoardGeometry.boardUnits(BoardGeometry.handleScreenSize, at: zoom)
    }

    private var targetSize: CGFloat {
        BoardGeometry.boardUnits(BoardGeometry.handleTargetScreenSize, at: zoom)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: visualSize / 4, style: .continuous)
            .fill(theme.color(.surfaceCard))
            .overlay(
                RoundedRectangle(cornerRadius: visualSize / 4, style: .continuous)
                    .strokeBorder(theme.color(.canvasSelection), lineWidth: visualSize / 6)
            )
            .frame(width: visualSize, height: visualSize)
            // The target is more than twice what is drawn. The extra is transparent,
            // so this costs nothing visually and is the whole reason a corner can be
            // grabbed at all.
            .frame(width: targetSize, height: targetSize)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering { handle.resizeCursor.push() } else { NSCursor.pop() }
            }
            // Popped here too, and this is not belt and braces: deselecting the card
            // while the pointer sits on a grip takes the view away without ever
            // calling `onHover` again, and the resize cursor would stay on the board
            // for the rest of the session.
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

extension BoardGeometry.Handle {
    /// The system's own frame-resize cursor for this grip, so the pointer says what
    /// the grip will do before it is pressed.
    var resizeCursor: NSCursor {
        NSCursor.frameResize(position: cursorPosition, directions: .all)
    }

    private var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }
}

/// The pointer region of a group: its frame only, hollow in the middle (SPEC §6.5).
///
/// A group is a container drawn as a rectangle around other cards, and with a solid
/// hit region it swallowed every click inside itself: the cards it held could not be
/// selected, and dragging one of them dragged the whole group instead.
///
/// Four overlapping bands rather than a rounded rectangle with a hole punched by
/// `eoFill`, and the difference is not stylistic. The hole version reversed itself
/// along one scanline: `Path(roundedRect:)` starts at the middle of the right edge,
/// and an even-odd test whose ray runs through that start vertex miscounts the
/// crossings, so a click at exactly half the group's height hit the middle and
/// missed the frame. Four rectangles under the default winding rule have no vertex a
/// horizontal ray can graze.
struct GroupFrameShape: Shape {
    /// How thick the band is, in the same units as the rectangle.
    var band: CGFloat

    func path(in rect: CGRect) -> Path {
        // A group no wider than two bands is all frame. Insetting it anyway would
        // leave a negative middle, and the group would answer nowhere at all.
        guard band > 0, rect.width > band * 2, rect.height > band * 2 else {
            return Path(rect)
        }
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: band))
        path.addRect(CGRect(x: rect.minX, y: rect.maxY - band, width: rect.width, height: band))
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: band, height: rect.height))
        path.addRect(CGRect(x: rect.maxX - band, y: rect.minY, width: band, height: rect.height))
        return path
    }
}
