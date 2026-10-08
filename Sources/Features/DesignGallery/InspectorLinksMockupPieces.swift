import SwiftUI

// The panel, rows, fields and «Dove compare» states `InspectorLinksMockup` is drawn out of, in a
// file of their own for the reason `TagBrowserMockupPieces.swift` gives. Literal content only.

// MARK: - The inspector column

/// The inspector's background at its real width, `UnlinkedMentionsMockup.inspectorWidth`.
struct InspectorMockupPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) { content }
            .padding(theme.spacing(.m))
            .frame(width: UnlinkedMentionsMockup.inspectorWidth, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

/// A section drawn by the real `TraySection`, so the header, the count and the empty line are the
/// ones the inspector already has rather than a copy of them.
struct InspectorMockupSection<Rows: View>: View {
    let title: String
    var count: String?
    /// What VoiceOver reads for the header; the title when nil. The unresolved section's is the
    /// sentence ADR-0084 §D2 gives `InspectorSection.unresolved(count:)`.
    var spokenLabel: String?
    /// The section's empty line, `TraySection`'s own; nil draws the rows.
    var emptyText: String?
    @ViewBuilder let rows: Rows

    var body: some View {
        TraySection(
            title: title, badge: count, accessibilityLabel: spokenLabel ?? title,
            identifier: "mockup-\(title)", isEmpty: emptyText != nil, emptyText: emptyText ?? ""
        ) { rows }
    }
}

// MARK: - A backlink row

/// One backlink (ADR-0084 §D1): the title in the accent; under it the line that links, the link
/// itself in the accent, one line cut at the tail; a count only above one; the badge when the
/// source's `related` names this note.
struct InspectorMockupBacklink: View {
    @Environment(\.theme) private var theme

    enum Badge { case none, word, glyph }

    let title: String
    let before: String
    var link = "Riunione settimanale"
    let after: String
    var count: Int = 1
    var badge: Badge = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(title).themedText(.body, color: .accentPrimary).lineLimit(1)
                switch badge {
                case .none:
                    EmptyView()
                case .word:
                    Text("strutturale")
                        .themedText(.caption, color: .textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.color(.backgroundTertiary)))
                case .glyph:
                    // The alternative: a glyph whose tooltip says «Legame strutturale».
                    Image(systemName: "arrow.left.arrow.right")
                        .themedText(.caption, color: .textTertiary)
                        .help("Legame strutturale")
                }
                Spacer(minLength: 0)
                if count > 1 {
                    Text("\(count) link").themedText(.caption, color: .textTertiary)
                }
            }
            Text("\(before)\(Text("[[\(link)]]").foregroundStyle(theme.color(.accentPrimary)))\(after)")
                .themedText(.caption, color: .textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - An unresolved row

/// One target this note links to and no note answers (ADR-0084 §D2), with its two small trailing
/// buttons; a target that is not a valid title (`Piano.md`) has «Vai al link» only.
struct InspectorMockupUnresolved: View {
    @Environment(\.theme) private var theme
    let target: String
    var creatable = true

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(target).themedText(.body, color: .textPrimary).lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            if creatable {
                small("Crea nota")
            }
            small("Vai al link")
        }
        .padding(.vertical, 2)
    }

    private func small(_ title: String) -> some View {
        Text(title)
            .themedText(.caption, color: .accentPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
            )
    }
}

// MARK: - The structural sheet's fields

/// A text field drawn rather than live: the label above it, the text in it, a caret where the
/// person is typing. `textColor` is the open question of the reverse field: the field's normal
/// text, or a tenuous colour until it is edited.
struct InspectorMockupField: View {
    @Environment(\.theme) private var theme
    /// The line above the field; nil for the search field, which has none.
    let label: String?
    let text: String
    var textColor: ColorToken = .textPrimary
    var caret = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            if let label {
                Text(label).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            HStack(spacing: 0) {
                Text(text).themedText(.body, color: textColor).lineLimit(1)
                if caret {
                    Rectangle().fill(theme.color(.accentPrimary)).frame(width: 1, height: 15)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .background(theme.color(.backgroundPrimary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
            )
        }
    }
}

// MARK: - «Dove compare»

/// The section of ADR-0084 §D6, in each of its states. Asked for and never automatic, so every
/// state follows the button: none fills the section by itself.
struct InspectorMockupAppearances: View {
    @Environment(\.theme) private var theme

    enum State { case resting, scanning, found, empty }

    let state: State

    var body: some View {
        InspectorMockupSection(title: "DOVE COMPARE", count: state == .found ? "4" : nil) {
            switch state {
            case .resting:
                Text("Cerca questa nota nelle board e nelle pratiche: legge ogni board e ogni messaggio.")
                    .themedText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                button("Cerca dove compare", systemImage: "magnifyingglass")
            case .scanning:
                HStack(spacing: theme.spacing(.xs)) {
                    ProgressView().controlSize(.small)
                    Text("Lettura di board e pratiche…").themedText(.caption, color: .textSecondary)
                }
            case .found:
                results
                Text("1 board non leggibile, saltata.").themedText(.caption, color: .textTertiary)
                button("Cerca di nuovo", systemImage: "arrow.clockwise")
            case .empty:
                Text("non compare in nessuna board né pratica").themedText(.caption, color: .textTertiary)
                button("Cerca di nuovo", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        Text("BOARD").themedText(.caption, color: .textTertiary).padding(.top, 2)
        entry("Banco prove", glyph: "square.grid.2x2")
        entry("Fiera 2026", glyph: "square.grid.2x2")
        Text("PRATICHE").themedText(.caption, color: .textTertiary).padding(.top, 2)
        entry("Nexion, supporti serie 40", glyph: "folder.badge.person.crop")
        // A pratica that does not link the note itself, named only as the place of the message under
        // it that does; the message row opens its pratica.
        entry("Rossi Meccanica, pressa 4", glyph: "folder.badge.person.crop", color: .textSecondary)
        entry("Re: campionario serie 40", glyph: "envelope", indent: true)
    }

    private func entry(
        _ title: String, glyph: String, indent: Bool = false, color: ColorToken = .accentPrimary
    ) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: glyph).themedText(.caption, color: .textTertiary).frame(width: 16)
            Text(title).themedText(.body, color: color).lineLimit(1)
        }
        .padding(.leading, indent ? theme.spacing(.m) : 0)
    }

    private func button(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .themedText(.caption, color: .accentPrimary)
            .padding(.top, 2)
    }
}
