import SwiftUI

// MARK: - The grouping, which is the only part worth testing

/// One past version, carrying the position it had in the note's own list.
///
/// The position is the identity, not the date: two saves inside the same second produce
/// two files whose names differ only in `WriteJournal.makeID`'s random suffix, and both
/// parse back to the same `Date`. Selecting by date would make those two the same row.
struct HistoryEntry: Equatable, Identifiable {
    let id: Int
    let snapshot: NoteHistory.Snapshot
}

/// The versions saved on one calendar day, under the name that day is shown by.
struct HistoryDayGroup: Equatable, Identifiable {
    let title: String
    let entries: [HistoryEntry]

    var id: String { title }
}

/// Turns a note's snapshots into the day-by-day list the sheet shows.
///
/// Kept apart from the view, and internal rather than private, because it is the piece
/// with a rule in it: everything else in this file is layout. The rule it renders is
/// `NoteHistory`'s own thinning (ADR-0011 D4) - every save from the last 24 hours, one
/// per day before that - so a grouped list states that rule without anyone explaining
/// it, where a flat list of timestamps would hide it.
enum HistoryGrouping {
    /// Groups newest-first snapshots into newest-first days.
    ///
    /// `now`, `calendar` and `locale` are arguments for the same reason
    /// `NoteHistory.record` takes a date: "today" and "yesterday" cannot be tested
    /// without control of the clock, and the day names must be Italian whatever the
    /// machine running the test is set to.
    static func groups(
        for snapshots: [NoteHistory.Snapshot],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "it_IT")
    ) -> [HistoryDayGroup] {
        var groups: [HistoryDayGroup] = []
        var currentDay: Date?

        for (index, snapshot) in snapshots.enumerated() {
            let entry = HistoryEntry(id: index, snapshot: snapshot)
            let day = calendar.startOfDay(for: snapshot.date)
            // Adjacency is keyed on the day itself, never on the rendered title: two
            // years apart, the same date renders the same words.
            if day == currentDay, let last = groups.last {
                groups[groups.count - 1] = HistoryDayGroup(
                    title: last.title, entries: last.entries + [entry]
                )
            } else {
                currentDay = day
                groups.append(HistoryDayGroup(
                    title: title(for: day, now: now, calendar: calendar, locale: locale),
                    entries: [entry]
                ))
            }
        }
        return groups
    }

    static func title(
        for day: Date, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "Oggi" }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return "Ieri" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: day)
    }

    /// `18:42`. Fixed rather than locale-derived: the interface is Italian (CLAUDE.md),
    /// which is 24-hour, and a stable string is one less thing for a test to guess at.
    static func time(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - The sheet

/// Browses a note's past versions and puts one back (ADR-0011, M9).
///
/// The mockup this follows is `HistoryMockup` in the design gallery, approved on
/// 2026-08-18 with the diff pane declined: a diff would need an "added" and a "removed"
/// token that no theme file has, and ADR-0001 §D4 checks themes for completeness, so the
/// pair could not be added to one theme alone.
struct NoteHistorySheet: View {
    @Environment(\.theme) private var theme

    let noteTitle: String
    let snapshots: [NoteHistory.Snapshot]
    let onRestore: (String) -> Void
    let onClose: () -> Void

    @State private var selection: Int = 0

    private var groups: [HistoryDayGroup] {
        HistoryGrouping.groups(for: snapshots, now: Date())
    }

    private var selected: NoteHistory.Snapshot? {
        snapshots.indices.contains(selection) ? snapshots[selection] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    HistoryVersionList(groups: groups, selection: $selection)
                        .padding(theme.spacing(.s))
                }
                .frame(width: 240)
                Divider()
                HistoryTextPane(text: selected?.text)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 820, height: 560)
        .background(theme.color(.backgroundPrimary))
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Cronologia").themedText(.heading)
            Text(noteTitle).themedText(.body, color: .textTertiary)
            Spacer()
            Button("Chiudi", action: onClose)
        }
        .padding(theme.spacing(.m))
    }

    /// The line that makes the button safe to press, and it is not reassurance: by
    /// ADR-0011 D2 the restore is itself a write, and `VaultController.restoreVersion`
    /// saves the buffer before it, so the version being replaced is in the list a moment
    /// later whether it had been saved or not.
    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "info.circle").themedText(.caption, color: .textTertiary)
            Text("Ripristinare salva anche la versione di adesso: si può sempre tornare indietro.")
                .themedText(.caption, color: .textTertiary)
            Spacer()
            Button("Ripristina") {
                if let text = selected?.text { onRestore(text) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil)
        }
        .padding(theme.spacing(.m))
    }
}

// MARK: - The list

private struct HistoryVersionList: View {
    @Environment(\.theme) private var theme
    let groups: [HistoryDayGroup]
    @Binding var selection: Int

    var body: some View {
        if groups.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                        Text(group.title.uppercased())
                            .themedText(.caption, color: .textTertiary)
                        ForEach(group.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let isSelected = entry.id == selection
        return Button { selection = entry.id } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Text(HistoryGrouping.time(for: entry.snapshot.date))
                    .themedText(.body, color: isSelected ? .textInverted : .textPrimary)
                Spacer()
                Text(Self.size(of: entry.snapshot.text))
                    .themedText(.caption, color: isSelected ? .textInverted : .textTertiary)
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.color(.accentPrimary) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            // Without this the row is clickable only where a glyph happens to be drawn,
            // which is the defect the format bar's buttons shipped with in M8.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A note that has never been saved since this feature landed. Says why it is empty
    /// rather than only that it is - the difference between a fact and a bug.
    private var empty: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessuna versione precedente").themedText(.body, color: .textSecondary)
            Text("Le versioni si accumulano a ogni salvataggio.")
                .themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func size(of text: String) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }
}

// MARK: - The reading pane

private struct HistoryTextPane: View {
    @Environment(\.theme) private var theme
    let text: String?

    var body: some View {
        ScrollView {
            if let text, !text.isEmpty {
                Text(text)
                    .themedText(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing(.m))
            } else {
                Text(text == nil ? "Nessuna versione selezionata" : "Questa versione è vuota.")
                    .themedText(.body, color: .textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing(.m))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.backgroundSecondary))
    }
}
