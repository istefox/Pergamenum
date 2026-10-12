import SwiftUI

// The pieces `NoteBirthMockup` draws its scenes from (PG-387, N4). Literal data only: no
// controller, no index, no vault.

/// The app sidebar's LAVORO group, «Da classificare» right after «Attività».
struct NoteBirthMockupSidebar: View {
    @Environment(\.theme) private var theme
    var selected = "Da classificare"

    private let rows: [(title: String, symbol: String)] = [
        ("Attività", "checklist"), ("Da classificare", "tray"), ("Contenitore", "archivebox"),
        ("Pratiche", "folder"), ("Registrazioni", "waveform"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("LAVORO").themedText(.caption, color: .textTertiary)
            ForEach(rows, id: \.title) { row in
                HStack(spacing: theme.spacing(.s)) {
                    Image(systemName: row.symbol).foregroundStyle(theme.color(.accentPrimary)).frame(width: 18)
                    Text(row.title).themedText(.body)
                    Spacer()
                }
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, 3)
                .background(
                    row.title == selected ? theme.color(.accentMuted) : .clear,
                    in: RoundedRectangle(cornerRadius: theme.radius(.control))
                )
            }
        }
        .padding(theme.spacing(.m))
        .frame(width: NoteBirthMockup.sidebarWidth, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

/// One row of «Da classificare»: the title, the folder, the date, a document glyph on a scheda.
struct NoteBirthMockupRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let folder: String
    let date: String
    var isScheda = false
    var isSelected = false

    var body: some View {
        HStack(spacing: theme.spacing(.m)) {
            Image(systemName: isScheda ? "archivebox" : "doc.text")
                .foregroundStyle(theme.color(.textTertiary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).themedText(.body).lineLimit(1)
                Text(isScheda ? "Contenitore · \(folder)" : folder)
                    .themedText(.caption, color: .textSecondary).lineLimit(1)
            }
            Spacer()
            Text(date).themedText(.caption, color: .textSecondary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.xs))
        .background(
            isSelected ? theme.color(.accentMuted) : .clear,
            in: RoundedRectangle(cornerRadius: theme.radius(.control))
        )
    }
}

/// A sheet's frame at `NoteBirthMockup.sheetWidth`, the width the real sheets take.
struct NoteBirthMockupSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.heading)
            content
        }
        .padding(theme.spacing(.l))
        .frame(width: NoteBirthMockup.sheetWidth, alignment: .leading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

/// A section heading in a sheet: the caption-case label the Contenitore form already uses.
struct NoteBirthMockupLabel: View {
    let text: String

    var body: some View {
        Text(text).themedText(.caption, color: .textTertiary)
    }
}

/// A tag as a chip; `struck` draws `status-inbox` leaving, `added` a topic arriving.
struct NoteBirthMockupChip: View {
    @Environment(\.theme) private var theme
    let tag: String
    var struck = false
    var added = false

    var body: some View {
        Text(tag)
            .strikethrough(struck)
            .themedText(.caption, color: struck ? .textTertiary : (added ? .accentPrimary : .textSecondary))
            .padding(.horizontal, theme.spacing(.xs))
            .background(theme.color(.surfaceSunken), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
    }
}

/// The buttons at the foot of a sheet; the last is the default.
struct NoteBirthMockupButtons: View {
    @Environment(\.theme) private var theme
    let titles: [String]

    var body: some View {
        HStack(spacing: theme.spacing(.s)) {
            Spacer()
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .themedText(.body, color: index == titles.count - 1 ? .onAccent : .textPrimary)
                    .padding(.horizontal, theme.spacing(.m))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(
                        index == titles.count - 1 ? theme.color(.accentPrimary) : theme.color(.surfaceSunken),
                        in: RoundedRectangle(cornerRadius: theme.radius(.control))
                    )
            }
        }
    }
}

/// «Nota creata · Annulla» at the foot of the editor, one height with or without its refusal.
struct NoteBirthMockupToast: View {
    @Environment(\.theme) private var theme
    var refusal: String?

    var body: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(refusal ?? "Nota creata").themedText(.caption, color: refusal == nil ? .textPrimary : .taskOverdue)
                .lineLimit(1)
            if refusal == nil {
                Text("Annulla").themedText(.caption, color: .accentPrimary)
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .frame(height: NoteBirthMockup.toastHeight)
        .background(theme.color(.surfaceCard), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.color(.borderStrong), lineWidth: 1))
    }
}
