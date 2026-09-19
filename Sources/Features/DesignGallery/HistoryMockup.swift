import SwiftUI

// MARK: - La cronologia di una nota (M9)

/// The surface that lets a person browse and restore the snapshots `NoteHistory` has
/// been writing since ADR-0011 D2 - which today nothing in the app can see.
///
/// **The placement is not the open question here**, unlike the outline's mockup: a
/// version is a whole note's worth of text, and the only chrome in this app with room
/// to read one is a sheet over the window. The inspector is 260 points wide and holds
/// facts *about* a note; a popover is narrower still. So the sheet is assumed below and
/// the two things actually worth looking at are:
///
/// 1. **What the right-hand pane shows** - the old text as it was, or what changed
///    between it and the note as it is now. Storage does not decide this (D3 keeps full
///    text either way); it is purely what a person is asked to read.
/// 2. **How the version gets picked** - the list's own grouping, which is where the
///    thinning rule of D4 becomes visible whether or not anyone explains it: everything
///    from the last 24 hours, then exactly one row per day before that.
///
/// Everything below is literal. Nothing calls `NoteHistory`, and no view here is the
/// one that will ship - this is the thing to look at before that view is written.
struct HistoryMockup: View {
    @Environment(\.theme) private var theme

    /// Sized from `MockupGalleryView.contentWidth` rather than guessed: at the 230 this
    /// first shipped with, the three cells came to 818 points against the sheet's 780
    /// and were quietly clipped at both edges. Nobody caught it until the template
    /// mockup made the same mistake by a wider margin.
    private static let tripleWidth: CGFloat = 208

    var body: some View {
        MockupPage {
            MockupScene(
                "Il foglio, testo pieno: «com'era»",
                HistorySheet(pane: .fullText)
            )
            MockupScene(
                "Lo stesso foglio, differenze: «cosa è cambiato»",
                HistorySheet(pane: .diff)
            )
            entryPoints
            edgeCases
        }
    }

    /// Where the sheet is opened from. Both are cheap; showing them together is the
    /// point, because only one of them makes the feature discoverable by a person who
    /// does not already know it exists.
    private var entryPoints: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Da dove ci si arriva").themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("Sezione nell'ispettore", InspectorEntry())
                labelled("Solo dal menu Nota", MenuEntry())
            }
        }
    }

    /// The four states a list like this gets wrong.
    private var edgeCases: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("I casi che una lista così sbaglia")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("Mai salvata", VersionList(days: [], selected: nil))
                labelled("Una sola versione", VersionList(days: HistoryDay.single, selected: 0))
                labelled("Due salvataggi identici", VersionList(days: HistoryDay.identical, selected: 1))
            }
        }
    }

    private func labelled(_ title: String, _ content: some View) -> some View {
        MockupCell(title, width: Self.tripleWidth) { content }
    }
}

// MARK: - Il foglio

private struct HistorySheet: View {
    enum Pane { case fullText, diff }

    @Environment(\.theme) private var theme
    let pane: Pane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VersionList(days: HistoryDay.sample, selected: 1)
                    .frame(width: 230)
                    .padding(theme.spacing(.s))
                Divider()
                readingPane
            }
            Divider()
            footer
        }
        .frame(height: 420)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .themedShadow(.card)
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Cronologia").themedText(.heading)
            Text("Trasmissibilità del rumore").themedText(.body, color: .textTertiary)
            Spacer()
            Image(systemName: "xmark")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var readingPane: some View {
        switch pane {
        case .fullText: FullTextPane()
        case .diff: DiffPane()
        }
    }

    /// The line that makes the button safe to press, and the reason it is written rather
    /// than left implicit: restoring is itself a write, so by ADR-0011 D2 it snapshots
    /// what it replaced on the way past. Nothing is lost by trying one.
    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "info.circle")
                .themedText(.caption, color: .textTertiary)
            Text("Ripristinare salva anche la versione di adesso: si può sempre tornare indietro.")
                .themedText(.caption, color: .textTertiary)
            Spacer()
            Text("Ripristina")
                .themedText(.caption, color: .textInverted)
                .padding(.horizontal, theme.spacing(.m))
                .padding(.vertical, theme.spacing(.xs))
                .background(theme.color(.accentPrimary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .padding(theme.spacing(.m))
    }
}

// MARK: - L'elenco delle versioni

/// Grouped by day, because that is the shape the store already has: D4 keeps every
/// snapshot from the last 24 hours and exactly one per day before that, so a flat list
/// would hide a rule the grouping states for free.
private struct VersionList: View {
    @Environment(\.theme) private var theme
    let days: [HistoryDay]
    let selected: Int?

    var body: some View {
        if days.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                        Text(day.title.uppercased())
                            .themedText(.caption, color: .textTertiary)
                        ForEach(day.versions) { version in
                            row(version)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ version: HistoryVersion) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(version.time).themedText(.body, color: isSelected(version) ? .textInverted : .textPrimary)
            Spacer()
            Text(version.size)
                .themedText(.caption, color: isSelected(version) ? .textInverted : .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(isSelected(version) ? theme.color(.accentPrimary) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private func isSelected(_ version: HistoryVersion) -> Bool {
        guard let selected else { return false }
        return version.id == selected
    }

    /// A note nobody has saved since the feature landed. Says why it is empty rather
    /// than only that it is - the difference between a bug and a fact.
    private var empty: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessuna versione precedente")
                .themedText(.body, color: .textSecondary)
            Text("Le versioni si accumulano a ogni salvataggio.")
                .themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - I due modi di leggere una versione

private struct FullTextPane: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            ForEach(Array(HistoryVersion.oldBody.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .themedText(line.hasPrefix("#") ? .heading : .body,
                                color: line.isEmpty ? .textTertiary : .textPrimary)
            }
            Spacer()
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The same version, rendered as what changed against the note as it is now.
///
/// Worth noticing while looking at it: **the palette has no token for "added" or
/// "removed"**. Everything below borrows `accentPrimary` and `textTertiary`, which reads
/// as emphasis rather than as insertion and deletion, and a red/green pair would mean
/// two new tokens in every theme file (ADR-0001 §D4 checks themes for completeness, so
/// they cannot be added to one theme only). That cost is real and belongs in the
/// comparison - the full-text pane needs no new token at all.
private struct DiffPane: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(Array(HistoryVersion.diffBody.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: theme.spacing(.s)) {
                    Text(line.marker)
                        .themedText(.mono, color: .textTertiary)
                    Text(line.text)
                        .themedText(.body, color: line.removed ? .textTertiary : .textPrimary)
                        .strikethrough(line.removed)
                }
                .padding(.horizontal, theme.spacing(.xs))
                .background(line.added ? theme.color(.accentMuted) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            }
            Spacer()
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - I due punti di ingresso

private struct InspectorEntry: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("CRONOLOGIA").themedText(.caption, color: .textTertiary)
            Text("7 versioni, l'ultima alle 18:42")
                .themedText(.caption, color: .textSecondary)
            Text("Sfoglia…").themedText(.caption, color: .accentPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuEntry: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack {
                Text("Cronologia…").themedText(.caption, color: .textPrimary)
                Spacer()
                Text("⌥⌘H").themedText(.caption, color: .textTertiary)
            }
            Text("Invisibile finché non si apre il menu.")
                .themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - I dati finti

private struct HistoryVersion: Identifiable {
    let id: Int
    let time: String
    let size: String

    static let oldBody = [
        "# Trasmissibilità del rumore",
        "",
        "Il supporto elastico va dimensionato sulla frequenza di eccitazione,",
        "non sul carico statico.",
        "",
        "Vedi [[Vibrazioni forzate]].",
    ]

    static let diffBody: [DiffLine] = [
        DiffLine(marker: " ", text: "# Trasmissibilità del rumore", added: false, removed: false),
        DiffLine(marker: " ", text: "", added: false, removed: false),
        DiffLine(marker: "−", text: "Il supporto elastico va dimensionato sulla frequenza",
                 added: false, removed: true),
        DiffLine(marker: "−", text: "di eccitazione, non sul carico statico.", added: false, removed: true),
        DiffLine(marker: "+", text: "Il supporto va dimensionato sul rapporto fra frequenza",
                 added: true, removed: false),
        DiffLine(marker: "+", text: "di eccitazione e frequenza propria del sistema.", added: true, removed: false),
        DiffLine(marker: " ", text: "", added: false, removed: false),
        DiffLine(marker: " ", text: "Vedi [[Vibrazioni forzate]].", added: false, removed: false),
    ]
}

private struct DiffLine {
    let marker: String
    let text: String
    let added: Bool
    let removed: Bool
}

private struct HistoryDay {
    let title: String
    let versions: [HistoryVersion]

    /// Deliberately shaped like the thinning rule of ADR-0011 D4: today keeps every
    /// save, every day before it keeps exactly one. A person who never reads the ADR
    /// still learns the rule from the list.
    static let sample = [
        HistoryDay(title: "Oggi", versions: [
            HistoryVersion(id: 0, time: "18:42", size: "2,1 kB"),
            HistoryVersion(id: 1, time: "17:05", size: "1,9 kB"),
            HistoryVersion(id: 2, time: "16:58", size: "1,9 kB"),
            HistoryVersion(id: 3, time: "11:20", size: "1,4 kB"),
        ]),
        HistoryDay(title: "Ieri", versions: [
            HistoryVersion(id: 4, time: "19:03", size: "1,2 kB"),
        ]),
        HistoryDay(title: "Sabato 16 agosto", versions: [
            HistoryVersion(id: 5, time: "09:41", size: "820 B"),
        ]),
        HistoryDay(title: "Giovedì 14 agosto", versions: [
            HistoryVersion(id: 6, time: "22:15", size: "310 B"),
        ]),
    ]

    static let single = [
        HistoryDay(title: "Oggi", versions: [HistoryVersion(id: 0, time: "18:42", size: "2,1 kB")]),
    ]

    /// Two saves with nothing typed between them. The store records both - the hook does
    /// not compare texts - so the list has to be honest about it rather than hide one.
    static let identical = [
        HistoryDay(title: "Oggi", versions: [
            HistoryVersion(id: 0, time: "18:42", size: "2,1 kB"),
            HistoryVersion(id: 1, time: "18:41", size: "2,1 kB"),
        ]),
    ]
}
