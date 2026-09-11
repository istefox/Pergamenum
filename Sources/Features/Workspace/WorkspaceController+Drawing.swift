import CoreGraphics
import Foundation

/// The Disegno tool of SPEC §6.4, and the SVG it leaves behind (§6.2).
///
/// JSON Canvas has no node type for ink, so a drawing is an SVG file in the board's
/// folder referenced by a `file` node: Obsidian shows it as an image, and Pergamenum
/// can reopen it as strokes.
extension WorkspaceController {
    func beginStroke(at point: CGPoint, color: String, width: CGFloat, opacity: Double) {
        activeDrawing.strokes.append(
            Drawing.Stroke(points: [point], color: color, width: width, opacity: opacity)
        )
    }

    func extendStroke(to point: CGPoint) {
        guard !activeDrawing.strokes.isEmpty else { return }
        activeDrawing.strokes[activeDrawing.strokes.count - 1].points.append(point)
    }

    /// Removes strokes passing near a point, which is what the eraser does.
    func eraseStrokes(near point: CGPoint, radius: CGFloat) {
        activeDrawing.strokes.removeAll { stroke in
            stroke.points.contains { candidate in
                hypot(candidate.x - point.x, candidate.y - point.y) <= radius
            }
        }
    }

    /// Writes the active strokes to an SVG and places or updates its card.
    ///
    /// The node keeps its identity when a drawing is reopened, so editing ink does not
    /// leave the old card behind next to the new one.
    @discardableResult
    func commitDrawing(date: CalendarDate = .today) -> String? {
        guard let store, !activeDrawing.strokes.isEmpty else { return nil }
        let bounds = activeDrawing.bounds

        let relativePath: String
        if let editingID = editingDrawingNodeID,
           let node = document.node(id: editingID),
           case .file(let existing, _) = node.kind {
            relativePath = existing
        } else {
            relativePath = folder.isEmpty
                ? nextDrawingName(date: date, in: store.root)
                : "\(folder)/\(nextDrawingName(date: date, in: store.root.appending(path: folder)))"
        }

        let url = store.root.appending(path: relativePath, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(DrawingSVG.encode(activeDrawing).utf8).write(to: url, options: .atomic)
        } catch {
            recordProblem("salvataggio del disegno: \(error.localizedDescription)")
            return nil
        }

        let id: String
        if let editingID = editingDrawingNodeID {
            mutate { document in
                guard let index = document.nodes.firstIndex(where: { $0.id == editingID }) else { return }
                document.nodes[index].width = max(40, bounds.width)
                document.nodes[index].height = max(30, bounds.height)
            }
            id = editingID
        } else {
            id = addNode(CanvasNode(
                id: CanvasID.generate(),
                kind: .file(path: relativePath, subpath: nil),
                x: bounds.minX, y: bounds.minY,
                width: max(40, bounds.width), height: max(30, bounds.height)
            ), creatingOnDisk: relativePath)
        }

        activeDrawing = .empty
        editingDrawingNodeID = nil
        refreshContents()
        return id
    }

    /// Reopens a drawing card for editing, when its SVG is one this app wrote.
    /// Returns false for an imported illustration, which is an image and not ink.
    @discardableResult
    func editDrawing(nodeID: String) -> Bool {
        guard let store,
              let node = document.node(id: nodeID),
              case .file(let path, _) = node.kind,
              path.lowercased().hasSuffix(".svg"),
              let text = try? String(contentsOf: store.root.appending(path: path), encoding: .utf8),
              let drawing = DrawingSVG.decode(text)
        else { return false }

        activeDrawing = drawing
        editingDrawingNodeID = nodeID
        return true
    }

    /// First free `disegno-YYYYMMDD-NNN.svg` in a folder.
    private func nextDrawingName(date: CalendarDate, in directory: URL) -> String {
        for sequence in 1...999 {
            let name = DrawingSVG.fileName(for: date, sequence: sequence)
            let candidate = directory.appending(path: name, directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return name
            }
        }
        return DrawingSVG.fileName(for: date, sequence: 999)
    }
}
