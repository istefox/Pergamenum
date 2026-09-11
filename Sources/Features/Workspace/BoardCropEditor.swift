import AppKit
import SwiftUI

/// ADR-0020 D5: the crop rectangle editor, shown in place of an image card's own
/// preview while the card is being cropped. Draws the whole picture, scrimmed outside
/// the rectangle, with the outline and eight grips reusing `ResizeHandleView`'s visual
/// language, plus an inside-drag to move the rectangle.
///
/// `beginCrop(nodeID:drawnSize:)` is called by the context menu with a synchronous
/// estimate - the card's own frame - because the *accurate* drawn size is only known
/// once the picture has loaded and this view has been laid out, both of which happen
/// after crop mode is already entered. `primeCropDrawnSize(_:for:)` refines it here,
/// the moment both are known, as long as nothing has been dragged yet.
struct BoardCropEditor: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let node: CanvasNode
    let path: String
    let modifiers: EventModifiers

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let image {
                    let drawnSize = Self.fittedSize(for: image.size, in: proxy.size)
                    let origin = CGPoint(
                        x: (proxy.size.width - drawnSize.width) / 2,
                        y: (proxy.size.height - drawnSize.height) / 2
                    )

                    Image(nsImage: image)
                        .resizable()
                        .frame(width: drawnSize.width, height: drawnSize.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    if let rect = workspace.cropDisplayRect(for: node.id) {
                        let screenRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                        scrim(around: screenRect, in: proxy.size)
                        outline(screenRect)
                        moveOverlay(screenRect)
                        ForEach(BoardGeometry.Handle.allCases, id: \.self) { handle in
                            CropHandleView(
                                workspace: workspace, handle: handle, rect: screenRect,
                                lockAspect: modifiers.contains(.shift)
                            )
                        }
                    }
                }
            }
            .onChange(of: image?.size) { _, _ in refine(in: proxy.size) }
            .onAppear { refine(in: proxy.size) }
        }
        .task(id: "\(path)@\(ThumbnailStore.bucket(for: node.width))") {
            guard let store = workspace.thumbnails else { image = nil; return }
            let task = await store.thumbnail(for: path, width: node.width)
            let rendered = await task.value
            guard !Task.isCancelled else { return }
            image = rendered
            // D8: nothing to aim at is a refusal, not an empty editor.
            if rendered == nil { workspace.endCrop(confirm: false) }
        }
    }

    private func refine(in containerSize: CGSize) {
        guard let image, containerSize.width > 0, containerSize.height > 0 else { return }
        workspace.primeCropDrawnSize(Self.fittedSize(for: image.size, in: containerSize), for: node.id)
    }

    /// The image's own size scaled to fit inside `container` under `contentMode: .fit` -
    /// the same rule the uncropped `ThumbnailImage` draws with (D4).
    private static func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    // MARK: Scrim and outline

    /// The part of the picture being cropped away, dimmed - four bands around the
    /// rectangle rather than a hole punched with an even-odd fill, following
    /// `GroupFrameShape`'s own reasoning: a hole shape has a seam a horizontal ray can
    /// graze, and a click or a fill along it misbehaves.
    private func scrim(around rect: CGRect, in containerSize: CGSize) -> some View {
        let color = theme.color(.canvasBackground).opacity(0.7)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .frame(width: containerSize.width, height: max(0, rect.minY))
            Rectangle()
                .fill(color)
                .frame(width: containerSize.width, height: max(0, containerSize.height - rect.maxY))
                .offset(y: rect.maxY)
            Rectangle()
                .fill(color)
                .frame(width: max(0, rect.minX), height: rect.height)
                .offset(x: 0, y: rect.minY)
            Rectangle()
                .fill(color)
                .frame(width: max(0, containerSize.width - rect.maxX), height: rect.height)
                .offset(x: rect.maxX, y: rect.minY)
        }
        .allowsHitTesting(false)
    }

    private func outline(_ rect: CGRect) -> some View {
        Rectangle()
            .strokeBorder(theme.color(.canvasSelection), lineWidth: 1.5)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// The inside of the rectangle, which moves it without resizing (D5). Below the
    /// grips in z-order, the same way a card's own drag sits below its resize handles.
    private func moveOverlay(_ rect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(moveGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if value.translation == .zero { workspace.beginCropGesture() }
                workspace.moveCrop(translation: CGSize(
                    width: value.translation.width / workspace.zoom,
                    height: value.translation.height / workspace.zoom
                ))
            }
    }
}

/// One of the crop rectangle's eight grips, visually matching `ResizeHandleView` but
/// driving `WorkspaceController`'s crop state instead of its resize state.
private struct CropHandleView: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let handle: BoardGeometry.Handle
    /// The crop rectangle in the editor's own local space, in board units.
    let rect: CGRect
    let lockAspect: Bool

    private var visualSize: CGFloat {
        BoardGeometry.boardUnits(BoardGeometry.handleScreenSize, at: workspace.zoom)
    }

    private var targetSize: CGFloat {
        BoardGeometry.boardUnits(BoardGeometry.handleTargetScreenSize, at: workspace.zoom)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: visualSize / 4, style: .continuous)
            .fill(theme.color(.surfaceCard))
            .overlay(
                RoundedRectangle(cornerRadius: visualSize / 4, style: .continuous)
                    .strokeBorder(theme.color(.canvasSelection), lineWidth: visualSize / 6)
            )
            .frame(width: visualSize, height: visualSize)
            .frame(width: targetSize, height: targetSize)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { handle.resizeCursor.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(gripGesture)
            .position(
                x: rect.minX + handle.unitPoint.x * rect.width,
                y: rect.minY + handle.unitPoint.y * rect.height
            )
    }

    private var gripGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if value.translation == .zero { workspace.beginCropGesture() }
                workspace.updateCrop(
                    handle: handle,
                    translation: CGSize(
                        width: value.translation.width / workspace.zoom,
                        height: value.translation.height / workspace.zoom
                    ),
                    lockAspect: lockAspect
                )
            }
    }
}
