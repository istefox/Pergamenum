import SwiftUI

/// The selection rectangle, drawn in view coordinates over the board (SPEC §6.3).
///
/// Its own view rather than a computed property on `WorkspaceView`, following
/// `BoardContentLayer` and `BoardZoomControls`: everything it needs arrives through
/// the controller, so it neither reads nor widens the board's private state.
struct BoardMarquee: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        if let rect = workspace.marqueeRect {
            // The board scales from its top-left and then offsets, so a board point p
            // lands at p * zoom + pan.
            let origin = CGPoint(
                x: rect.origin.x * workspace.zoom + workspace.pan.width,
                y: rect.origin.y * workspace.zoom + workspace.pan.height
            )
            Rectangle()
                .fill(theme.color(.canvasSelection).opacity(0.12))
                .overlay(Rectangle().strokeBorder(theme.color(.canvasSelection), lineWidth: 1))
                .frame(width: rect.width * workspace.zoom, height: rect.height * workspace.zoom)
                .position(
                    x: origin.x + rect.width * workspace.zoom / 2,
                    y: origin.y + rect.height * workspace.zoom / 2
                )
                .allowsHitTesting(false)
        }
    }
}

/// Alignment guides, shown only while a drag is snapping to something (SPEC §6.3).
struct BoardGuides: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        Canvas { context, size in
            for guide in workspace.activeGuides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    let x = guide.position * workspace.zoom + workspace.pan.width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                case .horizontal:
                    let y = guide.position * workspace.zoom + workspace.pan.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(
                    path, with: .color(theme.color(.accentPrimary)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
        }
        .allowsHitTesting(false)
    }
}
