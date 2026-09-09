import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-23, R-24, R-25, R-27, R-32, R-39; DESIGN.md screens 1a/1b, UX-BLUEPRINT
// "Timeline column anatomy" §5-§6.
//
// The chronological middle column: one `List` of day sections, oldest first, with
// messages in two lanes and manual entries full width. The `List` scrolls to its end
// on open, which is where the newest row is (`PraticaTimelineModel.ordered` is
// ascending).
//
// One Quick Look host for the whole column and not one per chip: the panel is a
// single responder, and `QuickLookPresenter`'s target re-asserts first responder for
// whatever it is given (`Sources/Features/QuickLook/QuickLookPresenter.swift`).
struct PraticaTimelineView: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault

    /// Task 7's «Nota»/«Telefonata» (`PraticaEntry.insert(kind:at:in:)`). Absent here,
    /// so the two buttons carry their identifiers and are disabled rather than
    /// pretending to write a heading nothing has implemented yet.
    var onAddNote: (() -> Void)?
    var onAddCall: (() -> Void)?
    /// Opens `pratica.md` where a manual entry can actually be edited (ADR §D13).
    var onOpenNote: (() -> Void)?

    @State private var previewURLs: [URL] = []
    @State private var isPreviewing = false

    private var entries: [PraticaTimelineEntry] { pratiche.filteredTimeline }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                empty
            } else {
                list
            }
            Divider()
            countsBar
        }
        .background(theme.color(.backgroundPrimary))
        .quickLook(urls: previewURLs, isPresented: $isPreviewing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-timeline")
    }

    private var list: some View {
        List {
            ForEach(sections, id: \.day) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(entry)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(PraticaRowFormat.day(section.day))
                        .themedText(.caption, color: .textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        // Ascending order plus a bottom anchor is "opens on the newest" with no
        // scroll-to-id dance and no `ScrollViewReader` (SPEC "Timeline model").
        .defaultScrollAnchor(.bottom)
    }

    @ViewBuilder
    private func row(_ entry: PraticaTimelineEntry) -> some View {
        let lane = PraticaTimelineModel.lane(for: entry)
        Group {
            if entry.kind == .message {
                PraticaMessageRow(
                    entry: entry,
                    detail: pratiche.details[entry.id],
                    isExpanded: pratiche.expansion.isExpanded(entry.id),
                    onToggle: { expandsAll in toggle(entry, expandsAll: expandsAll) },
                    onQuickLook: preview(_:),
                    vaultRoot: vault.root
                )
            } else {
                PraticaEntryRow(
                    entry: entry,
                    detail: pratiche.details[entry.id],
                    isExpanded: pratiche.expansion.isExpanded(entry.id),
                    onToggle: { expandsAll in toggle(entry, expandsAll: expandsAll) },
                    vaultRoot: vault.root,
                    onOpenNote: onOpenNote
                )
            }
        }
        // DESIGN.md "Binding decisions": ~70 % width, leading for received and
        // trailing for sent; a manual entry is full width. The width is the third
        // carrier of direction, beside the glyph and the lane's own token (R-25).
        .containerRelativeFrame(.horizontal, alignment: alignment(of: lane)) { width, _ in
            lane == .entry ? width : width * 0.7
        }
    }

    private func alignment(of lane: PraticaLane) -> Alignment {
        switch lane {
        case .received: .leading
        case .sent: .trailing
        case .entry: .center
        }
    }

    private var empty: some View {
        VStack(spacing: theme.spacing(.s)) {
            Text(pratiche.selection == nil
                ? "Scegli una pratica o creane una nuova"
                : "Nessun messaggio in questa pratica")
                .themedText(.body, color: .textSecondary)
            if pratiche.selection != nil, pratiche.filter != .none {
                Text("I filtri attivi nascondono tutte le righe.")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// «80 messaggi · 3 voci · 14 allegati», with the timeline's two create verbs
    /// beside it (UX-BLUEPRINT §6).
    private var countsBar: some View {
        HStack(spacing: theme.spacing(.s)) {
            Button {
                onAddNote?()
            } label: {
                Label("Nota", systemImage: "square.and.pencil")
            }
            .disabled(onAddNote == nil)
            .accessibilityIdentifier("pratiche-add-note")

            Button {
                onAddCall?()
            } label: {
                Label("Telefonata", systemImage: "phone")
            }
            .disabled(onAddCall == nil)
            .accessibilityIdentifier("pratiche-add-call")

            Spacer()
            Text(countsText).themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }

    /// Counted over the whole timeline and not over the filtered one: the bar says
    /// what the pratica holds, and a filter narrowing the view does not remove a
    /// message from the folder.
    private var countsText: String {
        let all = pratiche.timeline
        let messages = all.filter { $0.kind == .message }.count
        let manual = all.count - messages
        let attachments = all.reduce(into: 0) { total, entry in
            let detail = pratiche.details[entry.id]
            total += (detail?.attachments.count ?? 0) + (detail?.storeReferences.count ?? 0)
        }
        return [
            messages == 1 ? "1 messaggio" : "\(messages) messaggi",
            manual == 1 ? "1 voce" : "\(manual) voci",
            attachments == 1 ? "1 allegato" : "\(attachments) allegati",
        ].joined(separator: " · ")
    }

    // MARK: - Behaviour

    /// Opt+click reaches every row the person can currently see - the filtered
    /// timeline, not the whole one (R-24: "expands or collapses all").
    private func toggle(_ entry: PraticaTimelineEntry, expandsAll: Bool) {
        if expandsAll {
            pratiche.expansion.toggleAll(entries.map(\.id))
        } else {
            pratiche.expansion.toggle(entry.id)
        }
    }

    /// One panel, re-pointed at whatever chip was clicked.
    private func preview(_ url: URL) {
        previewURLs = [url]
        isPreviewing = true
    }

    /// Day sections in the timeline's own ascending order (R-23). Built by walking the
    /// already-ordered array rather than by grouping into a dictionary and sorting it
    /// again: the order is `PraticaTimelineModel.ordered`'s and must not be re-derived.
    private var sections: [DaySection] {
        var sections: [DaySection] = []
        let calendar = Calendar.current
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if sections.last?.day == day {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(DaySection(day: day, entries: [entry]))
            }
        }
        return sections
    }

    private struct DaySection {
        var day: Date
        var entries: [PraticaTimelineEntry]
    }
}
