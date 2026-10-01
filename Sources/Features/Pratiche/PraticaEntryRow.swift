import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-23, R-24, R-27, R-39; DESIGN.md "Binding decisions" (manual entries full width, the whole
// readable column for a free entry, `PraticaLaneRowLayout`),
// UX-BLUEPRINT "Timeline column anatomy" §5.
//
// A «Nota» or «Telefonata» written by hand: one `## YYYY-MM-DD HH:MM [±hh:mm] <Kind> ·
// <Controparte>` heading of `pratica.md` and everything under it (PG-356: the offset is the
// zone the digits were written in; a heading without one reads as UTC).
//
// **Read-only, deliberately** (ADR §D13): the blueprint's inline text view bound to a
// range of `pratica.md` is the shape of every text-loss defect this repo has
// documented, so the body renders with `MarkdownBlocksView` and editing goes to the
// inspector. Task 7 owns writing an entry (`PraticaEntry.insert(kind:at:in:)`) and the
// caret hand-off through `Navigation.jumpToLine`.
struct PraticaEntryRow: View {
    @Environment(\.theme) private var theme

    let entry: PraticaTimelineEntry
    /// `nil` while the folder is being re-read: the row still draws its heading, which
    /// is the part that came from the timeline itself.
    let detail: PraticaRowDetail?
    let isExpanded: Bool
    /// `true` when Opt was held, which expands or collapses every visible row (R-24).
    let onToggle: (_ expandsAll: Bool) -> Void
    var vaultRoot: URL?
    /// «Apri la nota della pratica» - the one editing path (ADR §D13).
    var onOpenNote: (() -> Void)?
    /// The pane's command runner, for the entry catalogue's accessibility actions (ADR-0076
    /// §D7). Optional, `PraticaMessageRow.actions`' own reason: `nil` draws no action.
    var actions: PraticaCommandActions?

    private var isAnchored: Bool {
        if case .anchored = entry.placement { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            // ADR-0076 §D3 (R-09): an orphaned entry keeps its date slot and says why it no
            // longer sits under a message, in words as well as by position.
            if let caption = PraticaTimelineModel.orphanCaption(for: entry) {
                Text(caption)
                    .themedText(.caption, color: .textTertiary)
                    .accessibilityIdentifier("pratiche-entry-orphan-\(Self.timestamp(of: entry))")
            }
            if isExpanded {
                expandedBody
            } else if !entry.bodyPreview.isEmpty {
                Text(entry.bodyPreview)
                    .themedText(.body, color: .textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Its own kind's surface, anchored or free: a note's amber, a call's green.
        .background(theme.color(PraticaTimelineModel.surfaceToken(for: entry)))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(Self.identifier(for: entry))
        .accessibilityActions { accessibilityCommands }
    }

    /// The entry catalogue (ADR-0076 §D7) as VoiceOver actions - the same list the row's
    /// context menu iterates, so the two cannot offer different verbs (ADR-0023 §D1).
    @ViewBuilder
    private var accessibilityCommands: some View {
        if let actions {
            ForEach(actions.commands(forEntry: entry), id: \.self) { command in
                Button(command.title) { actions.run(command, on: entry) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Button {
                onToggle(NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .textTertiary)
            .accessibilityLabel(isExpanded ? "Comprimi" : "Espandi")
            .accessibilityIdentifier("pratiche-entry-chevron-\(Self.timestamp(of: entry))")

            // ADR-0076 §D3 (R-05): an anchored entry hangs off the message above it.
            if isAnchored {
                Image(systemName: "arrow.turn.down.right")
                    .themedText(.caption, color: .textTertiary)
                    .accessibilityHidden(true)
            }
            Image(systemName: entry.kind == .call ? "phone" : "square.and.pencil")
                .themedText(.caption, color: .textSecondary)
            Text(PraticaRowFormat.time(entry.date))
                .themedText(.caption, color: .textSecondary)
            Text(entry.subject)
                .themedText(.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        if let detail, !detail.body.isEmpty {
            MarkdownBlocksView(
                blocks: MarkdownBlockParser.blocks(in: detail.body),
                notePath: detail.notePath,
                vaultRoot: vaultRoot,
                expandsTransclusions: false
            )
        } else {
            Text("Nessun testo in questa voce.")
                .themedText(.caption, color: .textTertiary)
        }
        if let onOpenNote {
            Button("Apri la nota della pratica", action: onOpenNote)
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
                .accessibilityIdentifier("pratiche-entry-open-note-\(Self.timestamp(of: entry))")
        }
    }

    /// «Voce, 10 giugno 14:06, Mario Rossi, compressa» - the blueprint's composed
    /// label, with `PraticaTimelineModel.laneLabel` as its first word so the lane is
    /// carried by words as well as by colour (R-25).
    private var accessibilityText: String {
        var parts = [
            PraticaTimelineModel.laneLabel(.entry),
            PraticaRowFormat.spokenDate(entry.date),
            entry.subject,
        ]
        if isAnchored { parts.append("collegata al messaggio") }
        if let caption = PraticaTimelineModel.orphanCaption(for: entry) { parts.append(caption) }
        parts.append(isExpanded ? "espansa" : "compressa")
        return parts.joined(separator: ", ")
    }

    /// `pratiche-entry-<timestamp>` (UX-BLUEPRINT's checklist), the timestamp spelled
    /// by the same formatter that builds the entry's own id.
    static func identifier(for entry: PraticaTimelineEntry) -> String {
        "pratiche-entry-\(timestamp(of: entry))"
    }

    private static func timestamp(of entry: PraticaTimelineEntry) -> String {
        PraticheController.entryIDFormatter.string(from: entry.date)
    }
}
