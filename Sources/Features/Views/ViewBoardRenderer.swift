import SwiftUI

// The board and the one write a view makes (ADR-0009 §D5), apart from the read-only renderers
// for the reason SwiftLint's file length rule gives and this codebase keeps on: a drag, a drop
// target, a guarded write and its banner do not belong inside the file that draws a gallery.

/// `render: board` (ADR-0009 §D5): the one renderer that writes.
///
/// Dragging a card from one column to another rewrites the tag in that note's frontmatter,
/// through `VaultSession.write`, journalled and undoable from the line under the board.
///
/// The gesture is offered only when the grouping is a tag namespace **and** the surface can
/// write. Grouping by `folder` or `modified` gives a report, because dragging a card into a
/// different modification date is meaningless, and §D5 says a renderer that silently did
/// nothing on drop would be worse than one that never invited the drag.
///
/// *Senza stato* comes first and carries no tag name: it stands for the absence of the tag
/// rather than for one, and dragging out of it **adds** while dragging into it **removes** -
/// which is what makes it the only way to take a tag off a note with a gesture. A note with two
/// matching tags appears in both columns, and a drop then replaces the tag of the column the
/// card was dragged *from*, leaving the others alone: the gesture names its source.
struct ViewBoardRenderer: View {
    @Environment(\.theme) private var theme

    let block: ViewBlock
    let result: ViewResult
    var queries: ViewQuerySource?
    /// Run after a write, so the block that owns the evaluation runs the query again.
    ///
    /// Needed rather than automatic: `VaultSession.write` updates the index in place, but the
    /// view is re-evaluated on `scanGeneration`, which counts *scans*. The app's own write is
    /// deliberately not one (ADR-0001 §D3 has the watcher recognise it by hash and leave the
    /// window alone), so without this the file moved and the card sprang back.
    var onWrite: () -> Void = {}

    @State private var lastDrop: Drop?

    private struct Drop: Equatable {
        var summary: String
        var journalID: String?
        var isRefusal: Bool
    }

    private static let columns = [GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .top)]

    /// §D5: only a tag namespace can be dragged, and only where there is something to write to.
    private var isWritable: Bool {
        block.group?.isWritable == true && queries?.move != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: theme.spacing(.s)) {
                ForEach(result.groups.indices, id: \.self) { index in
                    column(result.groups[index])
                }
            }
            if let lastDrop { banner(lastDrop) }
        }
        .accessibilityIdentifier("view-board")
    }

    private func column(_ group: ViewResult.Group) -> some View {
        ColumnDropTarget(isEnabled: isWritable, onDrop: { payload in drop(payload, into: group.label) }, content: {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                HStack(spacing: theme.spacing(.xs)) {
                    if let label = group.label {
                        ViewTagChip(text: label)
                    } else {
                        Text(block.group?.absentLabel ?? "Senza valore")
                            .themedText(.caption, color: .textTertiary)
                    }
                    Spacer()
                    Text("\(group.rows.count)").themedText(.caption, color: .textTertiary)
                }
                ForEach(group.rows, id: \.path) { row in
                    card(row, in: group.label)
                }
                Spacer(minLength: 0)
            }
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.backgroundPrimary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        })
    }

    @ViewBuilder
    private func card(_ row: ViewResult.Row, in column: String?) -> some View {
        let body = VStack(alignment: .leading, spacing: 4) {
            Text(row.title).themedText(.body).lineLimit(2)
            let tags = row.record.frontmatter.tags.map(\.description)
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags.prefix(2), id: \.self) { ViewTagChip(text: $0) }
                }
            }
            let open = row.record.tasks.count { $0.state.isOpen }
            if open > 0 {
                Text(open == 1 ? "1 aperto" : "\(open) aperti")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))

        if isWritable {
            // The payload names the column the card is leaving, not only the note: a note in two
            // columns is dragged out of one of them in particular.
            body.draggable(BoardDragPayload(path: row.path, column: column).text)
        } else {
            body
        }
    }

    // MARK: Il drop

    /// **Answers `true` before the write has landed, on purpose** (ADR-0043 §D2). A SwiftUI
    /// drop handler is synchronous and the write is not any more, so the only two honest
    /// options were this or refusing a drop while a write is in flight - which ADR-0043
    /// rejects by name, «the second caller is usually the user pressing Cmd+S». Every
    /// refusal still reaches the person: it arrives on the banner below, which is the
    /// channel the drop already reported through, a moment later than it used to.
    private func drop(_ payload: String, into destination: String?) -> Bool {
        guard let move = queries?.move, let parsed = BoardDragPayload(text: payload) else { return false }
        guard parsed.column != destination else { return false }

        Task { @MainActor in
            let outcome = await move(
                parsed.path, parsed.column.flatMap(Tag.init), destination.flatMap(Tag.init)
            )
            if let problem = outcome.problem {
                lastDrop = Drop(summary: problem, journalID: nil, isRefusal: true)
                return
            }
            if !outcome.introduced.isEmpty {
                let reasons = ConformanceText.lines(
                    NoteViolations(
                        name: [], frontmatter: [], tags: outcome.introduced,
                        relatedMissingInSection: [], relatedMissingInFrontmatter: []
                    )
                )
                lastDrop = Drop(
                    summary: "Non scritto: \(reasons.joined(separator: ", "))",
                    journalID: nil,
                    isRefusal: true
                )
                return
            }
            guard outcome.didWrite else { return }
            lastDrop = Drop(
                summary: "\(parsed.column ?? "—") → \(destination ?? "—")",
                journalID: outcome.journalID,
                isRefusal: false
            )
            onWrite()
        }
        return true
    }

    /// What the drop left behind, and the way back. The same shape the tag rename's banner has,
    /// for the same reason: a write nobody asked to confirm needs to say what it did.
    private func banner(_ drop: Drop) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: drop.isRefusal ? "exclamationmark.triangle" : "checkmark")
                .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textTertiary)
            Text(drop.summary)
                .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let id = drop.journalID, let undo = queries?.undo {
                Button("Annulla") {
                    Task { @MainActor in
                        _ = await undo(id)
                        lastDrop = nil
                        onWrite()
                    }
                }
                .accessibilityIdentifier("undo-board-drop")
            }
            Button("Chiudi") { lastDrop = nil }
                .buttonStyle(.plain)
                .themedText(.caption, color: .textTertiary)
        }
    }
}

/// The note a card carries and the column it is leaving, as one string.
///
/// A string rather than a `Transferable` type of its own: a drag inside one view does not need
/// a declared uniform type, and one would have to be registered in the app's Info.plist to be
/// worth anything outside it.
struct BoardDragPayload {
    let path: String
    /// Nil for a card in *Senza stato*.
    let column: String?

    private static let separator: Character = "\u{1}"

    var text: String { "\(path)\(Self.separator)\(column ?? "")" }

    init(path: String, column: String?) {
        self.path = path
        self.column = column
    }

    init?(text: String) {
        let parts = text.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: false)
        guard let path = parts.first, !path.isEmpty else { return nil }
        self.path = String(path)
        let column = parts.count > 1 ? String(parts[1]) : ""
        self.column = column.isEmpty ? nil : column
    }
}

/// A column that takes a card, and says so while the card is over it.
///
/// Wrapped rather than applied inline because `dropDestination` has to be attached to the
/// column's whole frame, and the accent border it draws while targeted is the only thing on a
/// board that tells you the drop will land.
private struct ColumnDropTarget<Content: View>: View {
    @Environment(\.theme) private var theme

    let isEnabled: Bool
    let onDrop: (String) -> Bool
    @ViewBuilder let content: Content

    @State private var isTargeted = false

    var body: some View {
        if isEnabled {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                        .stroke(isTargeted ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
                )
                .dropDestination(for: String.self) { payloads, _ in
                    payloads.first.map(onDrop) ?? false
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
