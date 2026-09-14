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

    /// The pane's one command runner, shared with the list column and the top bar so
    /// the row menus here cannot offer a different catalogue (ADR-0023 §D1).
    let actions: PraticaCommandActions
    /// «Nota»/«Telefonata» at the end of the timeline (R-28), through
    /// `PraticaEntryComposer` - this view knows the verbs, never the write.
    let onAddNote: () -> Void
    let onAddCall: () -> Void
    /// Opens `pratica.md` where a manual entry can actually be edited (ADR §D13).
    var onOpenNote: (() -> Void)?
    /// «Inserisci qui» (R-28): the two rows the new entry goes between, and which of
    /// the two kinds it is. The midpoint arithmetic is `PraticaEntry.midpoint`'s.
    var onInsertBetween: ((PraticaTimelineEntry, PraticaTimelineEntry, PraticaEntry.Kind) -> Void)?

    @State private var previewURLs: [URL] = []
    @State private var isPreviewing = false
    /// Which row has key focus, and whether the list holds it at all: Backspace maps to
    /// «Escludi» **only** while the timeline is focused (the plan's own rule), or the
    /// key would delete a message while somebody types in the filter field.
    @FocusState private var isListFocused: Bool

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
        List(selection: selection) {
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
        .focused($isListFocused)
        // Backspace is «Escludi», and only here: the plan pins the key to the timeline
        // having key focus, so the same key still deletes characters in the filter
        // field and rows in every other list of the app.
        .onKeyPress(.delete) {
            guard isListFocused, excludeSelectedRow() else { return .ignored }
            return .handled
        }
    }

    /// The focused row (R-31's subject). A `Binding` over the controller rather than a
    /// `@State` here: the row commands act on it from three surfaces, and a second copy
    /// of "which row" is a second thing to keep in step.
    private var selection: Binding<String?> {
        Binding(
            get: { pratiche.selectedEntryID },
            set: { pratiche.selectedEntryID = $0 }
        )
    }

    /// «Escludi» on whatever row holds focus, or `false` when that row is a manual
    /// entry - a `## …` heading in `pratica.md` is not a message and has no files to
    /// trash (the command is absent from its menu for the same reason).
    private func excludeSelectedRow() -> Bool {
        guard let id = pratiche.selectedEntryID,
              let entry = entries.first(where: { $0.id == id }),
              entry.kind == .message
        else { return false }
        // The `true` answers the *key*, not the exclusion: the command has been accepted
        // and goes through the one asynchronous write door (ADR-0043 §D2), and its own
        // failures were always reported on `pratiche.report` rather than through here.
        Task { @MainActor in await actions.exclude(entry, detail: pratiche.details[entry.id]) }
        return true
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
                    vaultRoot: vault.root,
                    actions: rowActions
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
        .contextMenu { menu(for: entry) }
        .tag(entry.id)
    }

    /// The row's context menu: the message catalogue for a message, and «Inserisci
    /// qui» under both - a manual entry has no `MessageCommand` at all (no files, no
    /// `Message-ID`), which the catalogue says by not being asked for one.
    @ViewBuilder
    private func menu(for entry: PraticaTimelineEntry) -> some View {
        if entry.kind == .message {
            MessageMenuItems.menu(
                for: entry, detail: pratiche.details[entry.id], actions: rowActions
            )
            Divider()
        }
        insertHere(after: entry)
    }

    /// R-28's «Inserisci qui», as a submenu of the row above the gap rather than as a
    /// hover-revealed gap row (screen 1a draws the gap; the menu is the same command on
    /// a surface that survives a `List` culling its rows). Absent on the last row: a
    /// midpoint needs two neighbours, and «at the end» is what the counts bar's own
    /// «Nota»/«Telefonata» already mean.
    @ViewBuilder
    private func insertHere(after entry: PraticaTimelineEntry) -> some View {
        if let onInsertBetween, let next = following(entry) {
            Menu("Inserisci qui") {
                ForEach(PraticaEntry.Kind.allCases, id: \.self) { kind in
                    Button(kind.label) { onInsertBetween(entry, next, kind) }
                        .accessibilityIdentifier("pratiche-insert-here-\(kind.rawValue)")
                }
            }
            .accessibilityIdentifier("pratiche-insert-here")
        }
    }

    private func following(_ entry: PraticaTimelineEntry) -> PraticaTimelineEntry? {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }),
              entries.indices.contains(index + 1)
        else { return nil }
        return entries[index + 1]
    }

    /// The shared runner with this view's own Quick Look host attached, so «Anteprima
    /// allegato» opens the panel a chip click opens rather than a second one.
    private var rowActions: PraticaCommandActions {
        var actions = self.actions
        actions.onQuickLook = preview(_:)
        return actions
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
            Button(action: onAddNote) {
                Label("Nota", systemImage: "square.and.pencil")
            }
            .disabled(pratiche.selection == nil)
            .accessibilityIdentifier("pratiche-add-note")

            Button(action: onAddCall) {
                Label("Telefonata", systemImage: "phone")
            }
            .disabled(pratiche.selection == nil)
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
