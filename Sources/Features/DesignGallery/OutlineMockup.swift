import SwiftUI

// MARK: - L'indice della nota (M8)

/// The outline, in the two places it could live, before it lives in either.
///
/// The colours and the row are the easy part. The decision this mockup exists for is
/// **where it goes**, and the two candidates are not equivalent: the inspector already
/// holds things *about* the note (conformance, backlinks, tasks that point here), while
/// the left pane holds things you *navigate to*. An index is arguably both, which is
/// exactly why it should be looked at rather than argued about.
///
/// Everything below is literal. Nothing calls `NoteOutline`, which does not exist yet.
struct OutlineMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                scene(
                    "A destra, nell'ispettore, sopra Backlink",
                    InspectorPlacement()
                )
                scene(
                    "A sinistra, sotto l'elenco delle note",
                    SidebarPlacement()
                )
                edgeCases
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
            content
        }
    }

    /// The three states a list of this kind gets wrong, side by side.
    private var edgeCases: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("I casi che una lista così sbaglia")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("Titolo lungo", OutlineList(entries: OutlineEntry.longTitles, current: 1))
                labelled("Nessun titolo", OutlineList(entries: [], current: nil))
                labelled("Solo embed", OutlineList(entries: OutlineEntry.embedsOnly, current: 0))
            }
        }
    }

    private func labelled(_ title: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textSecondary)
            content
                .frame(width: 230)
                .padding(theme.spacing(.s))
                .background(theme.color(.backgroundSecondary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }
}

// MARK: - The two placements

private struct InspectorPlacement: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            NotePlaceholder()
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                OutlineList(entries: OutlineEntry.sample, current: 3)
                section("CONFORMITÀ") {
                    Label("Conforme", systemImage: "checkmark.seal")
                        .themedText(.caption, color: .textSecondary)
                }
                section("BACKLINK") {
                    Text("Mescole per il forno").themedText(.body, color: .accentPrimary)
                    Text("Fornitori 2026").themedText(.body, color: .accentPrimary)
                }
            }
            .padding(theme.spacing(.m))
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.color(.backgroundSecondary))
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textTertiary)
            content()
        }
    }
}

private struct SidebarPlacement: View {
    @Environment(\.theme) private var theme

    static let notes = ["Curva di trasmissibilità", "Fornitori 2026", "Mescole per il forno"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    Text("NOTE").themedText(.caption, color: .textTertiary)
                    ForEach(Self.notes, id: \.self) { title in
                        Text(title)
                            .themedText(.body, color: title == Self.notes[0] ? .textPrimary : .textSecondary)
                            .lineLimit(1)
                    }
                }
                Divider()
                OutlineList(entries: OutlineEntry.sample, current: 3)
                Spacer(minLength: 0)
            }
            .padding(theme.spacing(.m))
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.color(.backgroundSecondary))
            NotePlaceholder()
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

// MARK: - The list itself

private struct OutlineList: View {
    @Environment(\.theme) private var theme

    let entries: [OutlineEntry]
    let current: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("INDICE").themedText(.caption, color: .textTertiary)
            if entries.isEmpty {
                // Says what is missing rather than showing an empty box, the same refusal
                // the slash menu makes when nothing matches.
                Text("nessun titolo in questa nota")
                    .themedText(.caption, color: .textTertiary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    row(entry, isCurrent: index == current)
                }
            }
        }
    }

    private func row(_ entry: OutlineEntry, isCurrent: Bool) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            // Only the embeds carry a symbol. A bullet on every row would be a column of
            // noise; a symbol where the kind changes is information.
            if entry.isEmbed {
                Image(systemName: "doc.richtext")
                    .themedText(.caption, color: .textTertiary)
            }
            Text(entry.title)
                .themedText(.body, color: isCurrent ? .textPrimary : .textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(entry.level - 1) * theme.spacing(.m))
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(isCurrent ? theme.color(.accentMuted) : .clear)
        )
    }
}

// MARK: - What the scenes show

private struct OutlineEntry {
    let title: String
    let level: Int
    var isEmbed = false

    static let sample: [OutlineEntry] = [
        OutlineEntry(title: "Curva di trasmissibilità", level: 1),
        OutlineEntry(title: "Prove in laboratorio", level: 2),
        OutlineEntry(title: "Campione A, 60 shore", level: 3),
        OutlineEntry(title: "Campione B, 70 shore", level: 3),
        OutlineEntry(title: "Mescole per il forno", level: 2, isEmbed: true),
        OutlineEntry(title: "Conclusioni", level: 2),
        OutlineEntry(title: "Da rivedere con il fornitore", level: 1),
    ]

    static let longTitles: [OutlineEntry] = [
        OutlineEntry(title: "Prove", level: 1),
        OutlineEntry(
            title: "Confronto fra la curva misurata in laboratorio e quella dichiarata dal fornitore",
            level: 2
        ),
        OutlineEntry(title: "Note", level: 1),
    ]

    static let embedsOnly: [OutlineEntry] = [
        OutlineEntry(title: "Fornitori 2026", level: 1, isEmbed: true),
        OutlineEntry(title: "schema-forno.pdf", level: 1, isEmbed: true),
    ]
}

/// A stand-in for the note beside the pane, so each placement is judged where it lives
/// rather than on a blank background.
private struct NotePlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Curva di trasmissibilità").themedText(.title)
            Text("Prove in laboratorio").themedText(.heading, color: .textSecondary)
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(.borderSubtle))
                    .frame(height: 6)
                    .frame(maxWidth: index % 3 == 2 ? 220 : .infinity)
            }
            Text("Campione B, 70 shore").themedText(.heading, color: .textPrimary)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(.borderSubtle))
                    .frame(height: 6)
                    .frame(maxWidth: index % 2 == 1 ? 300 : .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.l))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
    }
}
