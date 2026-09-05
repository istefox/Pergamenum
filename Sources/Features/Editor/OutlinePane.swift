import SwiftUI

/// The note's index, under the note list in the sidebar (M8).
///
/// In the sidebar rather than in the inspector, chosen from the mockup: the inspector
/// holds things *about* the note - conformance, backlinks, tasks that point here - and
/// the sidebar holds things you navigate to. An index is the second kind.
///
/// It reads `NoteOutline`, which both this and the reading view use, so a click here and
/// what appears there cannot disagree about what the sections are.
struct OutlinePane: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let entries: [NoteOutline.Entry]
    /// Called with the entry's line and its position in the index. Two numbers because
    /// the editor scrolls by character and the reading view by block.
    let onSelect: (NSRange, Int) -> Void
    /// The whole note, needed only to turn a `String.Index` range into the `NSRange` the
    /// text view speaks. Converted here, once per click, rather than kept as two ranges.
    let text: String
    /// The open note's own path (PG-019): tags the drag payload, so a drop checks the
    /// section it is being asked to move still belongs to the note it is shown for.
    let notePath: String
    /// A valid drop's two replacements, ready for `Navigation.moveOutlineSection(_:)`.
    let onMove: ([(range: NSRange, text: String)]) -> Void

    /// Which entry is being dragged, recorded at drag start (`beginDrag(_:)`) - a
    /// `.dropDestination`'s `isTargeted` closure never sees the payload it is hovering
    /// (ADR-0026 §D5), so this is the only place a gap can ask "would this move work".
    @State private var draggingEntry: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("INDICE").themedText(.caption, color: .textTertiary)
            if entries.isEmpty {
                // Says what is missing rather than showing an empty box, the same refusal
                // the slash menu makes when nothing matches its query.
                Text("nessun titolo in questa nota")
                    .themedText(.caption, color: .textTertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            if !hiddenByFold.contains(index) {
                                gap(toPrecede: index)
                                row(entry, at: index)
                            }
                        }
                        gap(toPrecede: nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("outlinePane")
    }

    private func row(_ entry: NoteOutline.Entry, at index: Int) -> some View {
        let isCurrent = vault.currentOutlineEntry == index
        return HStack(spacing: 0) {
            chevron(for: entry, at: index)
            button(entry, at: index, isCurrent: isCurrent)
        }
        .padding(.leading, CGFloat(entry.level - 1) * theme.spacing(.m))
        .modifier(HeadingDraggable(entry: entry, index: index, beginDrag: beginDrag))
        .modifier(HeadingNestDropTarget(
            entry: entry,
            isValidDrag: draggingEntry.map {
                OutlineMove.replacements(in: text, moving: $0, nestingUnder: index) != nil
            } ?? false,
            perform: { drag in
                defer { draggingEntry = nil }
                guard drag.notePath == notePath,
                      let replacements = OutlineMove.replacements(in: text, moving: drag.entry, nestingUnder: index)
                else { return false }
                onMove(replacements)
                return true
            },
            theme: theme
        ))
    }

    /// The insertion zone before `destination` - or, for `nil`, at the end of the note.
    ///
    /// A line and not a stroke: every existing drop affordance in this app
    /// (`TaskDropTarget`, `NoteTreeRow`, `WorkspaceRow+Move`) is a rounded outline around a
    /// row, because those drops mean "into this container" - a reorder drop means "between
    /// these two", which an outline around a gap cannot say.
    private func gap(toPrecede destination: Int?) -> some View {
        OutlineGap(
            level: gapLevel(toPrecede: destination),
            isValidDrag: draggingEntry.map {
                OutlineMove.replacements(in: text, moving: $0, toPrecede: destination) != nil
            } ?? false,
            perform: { drag in
                defer { draggingEntry = nil }
                guard drag.notePath == notePath,
                      let replacements = OutlineMove.replacements(in: text, moving: drag.entry, toPrecede: destination)
                else { return false }
                onMove(replacements)
                return true
            },
            theme: theme
        )
    }

    /// The level the moved section would take if dropped here - a heading's own level, or
    /// (an embed, or the end of the note) the nearest enclosing heading's, level 1 when
    /// there is none. Display only: `OutlineMove.replacements` computes the real answer at
    /// drop time, this only has to agree with it.
    private func gapLevel(toPrecede destination: Int?) -> Int {
        if let destination, entries.indices.contains(destination) {
            if case .heading(let level) = entries[destination].kind { return level }
            for candidate in entries[..<destination].reversed() {
                if case .heading(let level) = candidate.kind { return level }
            }
            return 1
        }
        for candidate in entries.reversed() {
            if case .heading(let level) = candidate.kind { return level }
        }
        return 1
    }

    /// Records which entry is dragging and returns its payload - called by `.draggable`'s
    /// autoclosure only when a drag actually begins, never on every body evaluation (the
    /// same trap `WorkspaceRow.beginDrag()` documents).
    private func beginDrag(_ index: Int) -> OutlineSectionDrag {
        draggingEntry = index
        return OutlineSectionDrag(notePath: notePath, entry: index)
    }

    /// The fold control, and only where there is something to fold: an embed has no
    /// section, and a heading with nothing under it would fold to nothing.
    @ViewBuilder
    private func chevron(for entry: NoteOutline.Entry, at index: Int) -> some View {
        if case .heading = entry.kind, foldable.contains(index) {
            // `vault.foldedEntries` is offsets (`NoteTab.foldedEntries`); this row's own
            // `entry` already carries its heading's live offset, so no `NoteOutline` re-scan
            // is needed to ask or to toggle - only `hiddenByFold` below needs the full
            // translation, because it has to compare a folded *ancestor* against every entry.
            let offset = text.utf16.distance(from: text.startIndex, to: entry.range.lowerBound)
            Button {
                vault.toggleFold(offset)
            } label: {
                Image(systemName: vault.foldedEntries.contains(offset) ? "chevron.right" : "chevron.down")
                    .themedText(.caption, color: .textTertiary)
                    .frame(width: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(vault.foldedEntries.contains(offset) ? "Espandi la sezione" : "Ripiega la sezione")
        } else {
            Color.clear.frame(width: 12)
        }
    }

    /// The heading's own UTF-16 offset, when this entry can be folded - nil for anything else
    /// (an embed, or a heading with nothing under it), which is what makes it safe to call from
    /// both the chevron and the row's own double-click without duplicating the `foldable` guard.
    ///
    /// STUB (RED baseline, not yet implemented): always returns nil. The real body is
    /// `chevron(for:at:)`'s own guard and offset computation above (`foldable.contains(index)`
    /// then `text.utf16.distance(...)`), moved here unchanged. Internal, not `private`, so
    /// `@testable import Pergamenum` can call it directly
    /// (`Tests/OutlinePaneFoldableOffsetTests.swift`).
    func foldableOffset(for entry: NoteOutline.Entry, at index: Int) -> Int? {
        nil
    }

    /// The entries that have at least one line under them. Computed once per rebuild rather
    /// than per row, because each answer costs a pass over the note.
    private var foldable: Set<Int> {
        Set(entries.indices.filter { index in
            !NoteFolding.hiddenParagraphs(in: text, foldedEntries: [index]).isEmpty
        })
    }

    /// The entries a folded ancestor hides from the index itself (PG-090), so folding `##
    /// A.1` also takes its `### A.1.1` out of INDICE, not just out of the editor. The same
    /// "next heading of the same or a higher level ends the section" rule
    /// `NoteFolding.sectionEnd` applies to lines, applied here directly to entries instead:
    /// there is no text offset to look up, only which entry follows which. An `.embed` never
    /// ends a section (it has no level of its own), so it stays hidden along with the
    /// section it sits inside.
    ///
    /// `vault.foldedEntries` is translated to ordinals here, fresh against this view's own
    /// `text`, before the ordinal walk below runs - the one place in this file that needs
    /// every folded ancestor's ordinal at once rather than one row's own.
    private var hiddenByFold: Set<Int> {
        let folded = foldedOrdinals(ofOffsets: vault.foldedEntries, in: text)
        guard !folded.isEmpty else { return [] }
        var hidden: Set<Int> = []
        for index in folded {
            guard entries.indices.contains(index), case .heading(let level) = entries[index].kind
            else { continue }
            for next in entries.indices where next > index {
                if case .heading(let nextLevel) = entries[next].kind, nextLevel <= level { break }
                hidden.insert(next)
            }
        }
        return hidden
    }

    private func button(_ entry: NoteOutline.Entry, at index: Int, isCurrent: Bool) -> some View {
        Button {
            onSelect(NSRange(entry.range, in: text), index)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                // Only the embeds carry a symbol. A bullet on every row would be a column
                // of noise; a symbol where the kind changes is information.
                if entry.kind == .embed {
                    Image(systemName: "doc.richtext")
                        .themedText(.caption, color: .textTertiary)
                }
                Text(entry.title)
                    .themedText(.body, color: isCurrent ? .textPrimary : .textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(isCurrent ? theme.color(.accentMuted) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(entry.title)
    }
}

/// A heading row is a drag source; an embed row is never one (PG-019) - it moves only as
/// part of the section it sits under, which is what `OutlineMove.replacements` already
/// enforces by refusing a non-heading `entry`. A separate modifier rather than an inline
/// `if` in `row(_:at:)`, so `.draggable`'s autoclosure - which must wrap the call, not its
/// result (the `WorkspaceRow.beginDrag()` trap) - stays next to the condition that gates it.
private struct HeadingDraggable: ViewModifier {
    let entry: NoteOutline.Entry
    let index: Int
    let beginDrag: (Int) -> OutlineSectionDrag

    func body(content: Content) -> some View {
        if case .heading = entry.kind {
            content.draggable(beginDrag(index))
        } else {
            content
        }
    }
}

/// The "nest as a child" drop target on a heading row itself (PG-093), distinct from
/// `OutlineGap`'s between-rows line by the same convention every other container drop in this
/// app already uses (`TaskDropTarget`, `NoteTreeRow`, `WorkspaceRow+Move`): a rounded outline
/// AROUND the row means "into this", where a line between rows means "next to this". An embed
/// row is never a nesting target - only a heading has a level to nest under.
private struct HeadingNestDropTarget: ViewModifier {
    let entry: NoteOutline.Entry
    let isValidDrag: Bool
    let perform: (OutlineSectionDrag) -> Bool
    let theme: Theme

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if case .heading = entry.kind {
            content
                .background(
                    RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                        .strokeBorder(theme.color(.accentPrimary), lineWidth: 2)
                        .opacity(isTargeted && isValidDrag ? 1 : 0)
                )
                .dropDestination(for: OutlineSectionDrag.self) { drops, _ in
                    guard let drag = drops.first else { return false }
                    return perform(drag)
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

/// The insertion-line indicator between two Outline rows (PG-019).
///
/// `isValidDrag` comes from the source side (`OutlinePane.draggingEntry`), never from this
/// drop target's own `isTargeted`: `.dropDestination`'s `isTargeted` closure only reports
/// that a payload of this type is hovering, never which entry it is (ADR-0026 §D5) - so
/// whether THIS gap's move would actually work has to be asked of the whole note's text,
/// which only the parent that holds it can do.
private struct OutlineGap: View {
    let level: Int
    let isValidDrag: Bool
    let perform: (OutlineSectionDrag) -> Bool
    let theme: Theme

    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted && isValidDrag ? theme.color(.accentPrimary) : .clear)
            .frame(height: 2)
            .padding(.leading, CGFloat(level - 1) * theme.spacing(.m))
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .frame(minHeight: 6)
            .dropDestination(for: OutlineSectionDrag.self) { drops, _ in
                guard let drag = drops.first else { return false }
                return perform(drag)
            } isTargeted: { isTargeted = $0 }
    }
}
