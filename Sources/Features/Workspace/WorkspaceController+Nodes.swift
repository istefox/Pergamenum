import CoreGraphics
import Foundation

/// Creating, connecting, deleting and mutating individual canvas nodes (SPEC §6.4/§6.5):
/// resize, colour and text-colour/alignment, the `.text`/`.link` content writers, task-line
/// toggling, and the tool-driven node factories (sticky note, free text, link, folder, file).
/// Split out of `WorkspaceController.swift` to keep its `type_body_length` under the
/// configured error threshold (PG-056) - every method here goes through `mutate`, the same
/// single write path the primary file's own editing methods use, so this is a location split
/// only, not a behavioural one.
extension WorkspaceController {
    func resize(nodeID: String, to size: CGSize) {
        // A node with zero or negative extent cannot be grabbed again, so the minimum
        // is a floor rather than a preference.
        let width = max(40, size.width)
        let height = max(30, size.height)
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            document.nodes[index].width = width
            document.nodes[index].height = height
        }
    }

    func setColor(_ color: CanvasColor?, forNodeIDs ids: Set<String>) {
        mutate { document in
            for index in document.nodes.indices where ids.contains(document.nodes[index].id) {
                document.nodes[index].color = color
            }
        }
    }

    /// «Colore testo» (ADR-0027 §D4, §D7): mirrors `setColor(_:forNodeIDs:)` exactly, one
    /// `mutate` call writing at most `CardTextStyle.colorKey`, removing it - never writing a
    /// default - when `color` is `nil`, the same non-destructive rule `endCrop`/`removeCrop`
    /// already follow (`WorkspaceController+Crop.swift:119-126`).
    ///
    /// The `.text` guard is `setText`'s own below: the two commands are already offered
    /// only on a `.text` node, and a text colour written onto a `.file` or `.group` node would
    /// be a key nothing reads. Every other key on `unknown` is left exactly as it was, so a
    /// node also carrying `pergamenum-crop` keeps it.
    func setTextColor(_ color: CanvasColor?, forNodeIDs ids: Set<String>) {
        mutate { document in
            for index in document.nodes.indices where ids.contains(document.nodes[index].id) {
                guard case .text = document.nodes[index].kind else { continue }
                if let color {
                    document.nodes[index].unknown[CardTextStyle.colorKey] = .string(color.rawValue)
                } else {
                    document.nodes[index].unknown.removeValue(forKey: CardTextStyle.colorKey)
                }
            }
        }
    }

    /// «Allineamento» (ADR-0027 §D4, §D7): same shape as `setTextColor(_:forNodeIDs:)` above,
    /// writing or removing `CardTextStyle.alignKey`.
    func setTextAlignment(_ alignment: CardTextStyle.Alignment?, forNodeIDs ids: Set<String>) {
        mutate { document in
            for index in document.nodes.indices where ids.contains(document.nodes[index].id) {
                guard case .text = document.nodes[index].kind else { continue }
                if let alignment {
                    document.nodes[index].unknown[CardTextStyle.alignKey] = .string(alignment.rawValue)
                } else {
                    document.nodes[index].unknown.removeValue(forKey: CardTextStyle.alignKey)
                }
            }
        }
    }

    func setText(_ text: String, forNodeID id: String) {
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == id }) else { return }
            if case .text = document.nodes[index].kind {
                document.nodes[index].kind = .text(text)
            }
        }
    }

    /// «Rinomina» (PG-073, SPEC §6.4 row 7 / §6.5): the `.link` card's title, same non-destructive
    /// shape as `setTextColor(_:forNodeIDs:)` above - an empty title removes the key rather than
    /// storing `""`, so the card falls back to displaying its URL exactly as an unset title does.
    func setTitle(_ title: String, forNodeID id: String) {
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == id }) else { return }
            guard case .link = document.nodes[index].kind else { return }
            if title.isEmpty {
                document.nodes[index].unknown.removeValue(forKey: LinkCardTitle.key)
            } else {
                document.nodes[index].unknown[LinkCardTitle.key] = .string(title)
            }
        }
    }

    /// A click on a task line's checkbox glyph (PG-074, plan Section 3): toggles that one
    /// line between open and done, `@done(...)` stamp and clear included via `TaskParser.line
    /// (for:settingState:today:)` - the same rewrite `VaultSession.apply(_:to:)` performs for a
    /// note-sourced task, reused here rather than duplicated.
    ///
    /// Two write paths, because the card has two states (plan decision 1). While `id` is being
    /// edited, the draft is mutated and committed through the existing `endTextEdit(commit:)`,
    /// so the toggle is one entry on the card's own undo stack rather than a competing document
    /// write; at rest, `setText(_:forNodeID:)` writes straight through `mutate`, the same call
    /// `endTextEdit(commit:)` itself makes.
    func toggleTask(atLineIndex lineIndex: Int, forNodeID id: String) {
        let isEditingThisCard = editingTextNodeID == id
        let text: String
        if isEditingThisCard {
            text = editingTextDraft
        } else if case .text(let stored) = document.node(id: id)?.kind {
            text = stored
        } else {
            return
        }

        let lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex),
              let task = TaskParser.parse(line: lines[lineIndex], sourcePath: id, lineIndex: lineIndex)
        else { return }

        let newState: TaskItem.State = task.state == .done ? .open : .done
        let newLine = TaskParser.line(for: task, settingState: newState, today: .today)
        guard let updated = TaskParser.rewrite(
            text, at: lineIndex, expecting: lines[lineIndex], with: newLine
        ) else { return }

        if isEditingThisCard {
            editingTextDraft = updated
            endTextEdit(commit: true)
        } else {
            setText(updated, forNodeID: id)
        }
    }

    func delete(nodeIDs: Set<String>) {
        mutate { document in
            document.nodes.removeAll { nodeIDs.contains($0.id) }
            // An edge to a node that no longer exists is unrenderable and would be
            // rejected by a strict reader.
            document.edges.removeAll { nodeIDs.contains($0.fromNode) || nodeIDs.contains($0.toNode) }
        }
        selection.subtract(nodeIDs)
        refreshContents()
    }

    @discardableResult
    func addNode(_ node: CanvasNode, creatingOnDisk created: String? = nil) -> String {
        mutate(creatingOnDisk: created) { $0.nodes.append(node) }
        refreshContents()
        return node.id
    }

    @discardableResult
    func connect(from: String, to: String) -> String? {
        guard from != to, document.node(id: from) != nil, document.node(id: to) != nil else { return nil }
        let edge = CanvasEdge(id: CanvasID.generate(), fromNode: from, toNode: to, toEnd: .arrow)
        mutate { $0.edges.append(edge) }
        return edge.id
    }

    /// Places an existing vault file on the board, which is how an item leaves the
    /// "Nuovi elementi" tray.
    @discardableResult
    func placeFile(
        _ relativePath: String,
        at point: CGPoint,
        creatingOnDisk created: String? = nil
    ) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .file(path: relativePath, subpath: nil),
            x: point.x, y: point.y,
            width: 260, height: 180
        ), creatingOnDisk: created)
    }

    func addStickyNote(_ text: String, at point: CGPoint, color: CanvasColor? = .preset(3)) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .text(text),
            x: point.x, y: point.y,
            width: 220, height: 120,
            color: color
        ))
    }

    func addFreeText(_ text: String, at point: CGPoint) -> String {
        // No colour: SPEC §6.4 tool 3 is text without a background.
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .text(text),
            x: point.x, y: point.y,
            width: 220, height: 60
        ))
    }

    func addLink(_ url: String, at point: CGPoint) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .link(url: url),
            x: point.x, y: point.y,
            width: 260, height: 90
        ))
    }

    /// Creates a real directory and puts its card on the board (SPEC §6.4, tool 4).
    @discardableResult
    func createFolder(named name: String, at point: CGPoint) throws -> String {
        guard let store else { throw CanvasStore.StoreError.alreadyExists("nessuna cartella note aperta") }
        let relativePath = try FolderFileOperations(store: NoteStore(root: store.root))
            .createFolder(named: name, in: folder)
        // No second `refreshContents()` here. The directory exists before `placeFile` runs,
        // and `placeFile` -> `addNode` already refreshed against this same document and this
        // same disk, so a call on the way out enumerated the folder twice for one new card
        // and could only ever recompute the value already in `contents`.
        return placeFile(relativePath, at: point, creatingOnDisk: relativePath)
    }
}
