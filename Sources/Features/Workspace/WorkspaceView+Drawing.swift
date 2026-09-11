import SwiftUI

/// The Disegno tool's overlay (SPEC §6.4, tool 10): pen strokes captured over the board
/// and previewed live, before they are written to their SVG.
extension WorkspaceView {
    func drawingLayer(in size: CGSize) -> some View {
        Canvas { context, _ in
            for stroke in workspace.activeDrawing.strokes {
                guard stroke.points.count > 1 else { continue }
                var path = Path()
                path.move(to: viewPoint(stroke.points[0]))
                for point in stroke.points.dropFirst() { path.addLine(to: viewPoint(point)) }

                context.stroke(
                    path,
                    with: .color(Color(hex: stroke.color).opacity(stroke.opacity)),
                    style: StrokeStyle(
                        lineWidth: stroke.width * workspace.zoom, lineCap: .round, lineJoin: .round
                    )
                )
            }
        }
        .contentShape(Rectangle())
        .gesture(penGesture(in: size))
    }

    /// One drag is one stroke, or one pass of the eraser.
    private func penGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = canvasPoint(from: value.location)
                if isErasing {
                    workspace.eraseStrokes(near: point, radius: max(8, penWidth * 3))
                    return
                }
                if value.translation == .zero {
                    workspace.beginStroke(
                        at: point,
                        color: theme.hexValue(penColor),
                        width: penWidth,
                        // A highlighter is a wide, translucent stroke; the pen is
                        // neither (SPEC §6.4, tool 10).
                        opacity: penWidth >= 10 ? 0.4 : 1
                    )
                } else {
                    workspace.extendStroke(to: point)
                }
            }
            .onEnded { _ in }
    }

    /// Board point to view point, the forward direction of `canvasPoint`.
    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * workspace.zoom + workspace.pan.width,
            y: point.y * workspace.zoom + workspace.pan.height
        )
    }
}
