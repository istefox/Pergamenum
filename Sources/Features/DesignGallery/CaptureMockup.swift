import SwiftUI

// MARK: - Cattura globale (M7)

/// The capture panel of ADR-0008, before it exists.
///
/// Four scenes rather than one, because what has to be judged here is not a single
/// screen: it is whether the four destinations read as one gesture, whether a task
/// with dates still fits in the same box, and whether a refused shortcut says so.
/// Every scene draws the panel over a stand-in for another application - the panel
/// does not activate Pergamenum (ADR-0008 §D3), and a mockup on a plain background
/// would quietly hide the one thing that makes this screen different from the
/// `TaskComposer` it borrows from.
struct CaptureMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene(
                "Nota nuova, il pannello appena aperto",
                CapturePanelMock(destination: .note, state: .empty)
            )
            scene(
                "Task, con Programma e Scadenza",
                CapturePanelMock(destination: .task, state: .task)
            )
            scene(
                "Aggiunta alla nota di oggi",
                CapturePanelMock(destination: .today, state: .today)
            )
            scene(
                "La scorciatoia che il sistema ha rifiutato",
                CapturePanelMock(destination: .note, state: .shortcutRefused)
            )
        }
    }

    private func scene(_ caption: String, _ panel: CapturePanelMock) -> some View {
        MockupScene(caption) {
            ZStack {
                HostAppBackdrop()
                panel
            }
        }
    }
}

// MARK: - The panel

/// One state of the panel. A value per scene rather than `@State`, so the gallery
/// shows four situations at once instead of one that has to be clicked through.
private struct CapturePanelMock: View {
    @Environment(\.theme) private var theme

    enum Destination: String, CaseIterable {
        case note, task, today, existing

        var title: String {
            switch self {
            case .note: "Nota nuova"
            case .task: "Task"
            case .today: "Oggi"
            case .existing: "In una nota"
            }
        }

        var symbol: String {
            switch self {
            case .note: "doc.badge.plus"
            case .task: "tray"
            case .today: "calendar"
            case .existing: "doc.text"
            }
        }

        /// The placeholder says where the text is going, which is the only thing the
        /// four destinations do not already say in the bar above.
        var placeholder: String {
            switch self {
            case .note: "Titolo della nota, poi il testo"
            case .task: "Che cosa c'è da fare"
            case .today: "Aggiungi alla nota di oggi"
            case .existing: "Aggiungi alla nota scelta"
            }
        }
    }

    enum State {
        case empty, task, today, shortcutRefused
    }

    let destination: Destination
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            if state == .shortcutRefused { refusedBanner }
            targetRow
            field
            if destination == .task { dateChips }
            Divider().overlay(theme.color(.borderSubtle))
            destinationIcons
            footer
        }
        .padding(theme.spacing(.m))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.raised)
    }

    // MARK: Destinations

    /// Where the capture is actually going, above the text - matches
    /// `CapturePanelView.targetRow`: a folder for a new note, a note for a task or an
    /// existing note, nothing for today.
    @ViewBuilder
    private var targetRow: some View {
        switch destination {
        case .note: targetChip(symbol: "folder", label: "00 Inbox")
        case .task: targetChip(symbol: "doc.text", label: "Inbox")
        case .existing: targetChip(symbol: "doc.text", label: "Scegli una nota…")
        case .today: EmptyView()
        }
    }

    private func targetChip(symbol: String, label: String) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: symbol)
            Text(label).themedText(.caption, color: .textTertiary)
        }
        .foregroundStyle(theme.color(.textTertiary))
    }

    /// The four destinations as a compact icon rail, matching
    /// `CapturePanelView.destinationIcons` - Craft's mode row moved to the bottom of
    /// the panel, the name said by `targetRow`/`field` instead of printed here.
    private var destinationIcons: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, item in
                let isCurrent = item == destination
                Image(systemName: item.symbol)
                    .foregroundStyle(theme.color(isCurrent ? .textPrimary : .textTertiary))
                    .frame(width: 26, height: 26)
                    .background(isCurrent ? theme.color(.accentMuted) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .help("\(item.title) — ⌘\(index + 1)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Text

    /// A drawn field rather than a `ComposerTextField`: the real one needs the focus
    /// machinery of ADR-0003 §D5, and a mockup that carried it would be the feature
    /// with the wrong parts missing rather than a picture of it.
    private var field: some View {
        HStack(spacing: 2) {
            if let typed = typedText {
                Text(typed).themedText(.body)
            } else {
                Text(destination.placeholder).themedText(.body, color: .textTertiary)
            }
            Rectangle()
                .fill(theme.color(.accentPrimary))
                .frame(width: 1.5, height: 17)
            Spacer(minLength: 0)
        }
        .frame(height: theme.spacing(.l))
    }

    private var typedText: String? {
        switch state {
        case .empty, .shortcutRefused: nil
        case .task: "Richiamare Rossi Impianti sulla curva"
        case .today: "Riunione tecnica, decisa la mescola"
        }
    }

    // MARK: Dates

    /// The same two chips as `TaskComposer`, deliberately unchanged: the lexicon was
    /// approved in ADR-0003 and a second vocabulary for the same two dates would be a
    /// cost with no buyer.
    private var dateChips: some View {
        HStack(spacing: theme.spacing(.s)) {
            chip("calendar", "Programma", "domani")
            chip("flag", "Scadenza", "20/08")
            Spacer(minLength: 0)
        }
    }

    private func chip(_ symbol: String, _ title: String, _ value: String?) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: symbol)
            Text(title).themedText(.caption, color: .textSecondary)
            if let value {
                Text(value).themedText(.caption, color: .accentPrimary)
            }
        }
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Label(shortcutCaption, systemImage: state == .shortcutRefused ? "keyboard.badge.ellipsis" : "keyboard")
                .themedText(.caption, color: state == .shortcutRefused ? .taskOverdue : .textTertiary)
            Spacer()
            Text("⏎").themedText(.caption, color: .textTertiary)
            Text("Cattura")
                .themedText(.caption, color: .onAccent)
                .padding(.horizontal, theme.spacing(.m))
                .padding(.vertical, theme.spacing(.xs))
                .background(theme.color(.accentPrimary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
    }

    private var shortcutCaption: String {
        state == .shortcutRefused ? "Scorciatoia non attiva" : "⌃Spazio da qualsiasi app"
    }

    // MARK: Refusal

    /// `RegisterEventHotKey` returns `eventHotKeyExistsErr` when another process holds
    /// the combination (ADR-0008 §D2). Drawn here because the alternative is a settings
    /// pane showing an intention while nothing happens - which is how `@remind` shipped
    /// wired to nothing, under five green tests.
    private var refusedBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.color(.taskOverdue))
            VStack(alignment: .leading, spacing: 2) {
                Text("⌃Spazio è già di un'altra applicazione")
                    .themedText(.caption, color: .textPrimary)
                Text("Il pannello si apre dal menu, oppure scegli un'altra combinazione")
                    .themedText(.caption, color: .textSecondary)
            }
            Spacer(minLength: 0)
            Text("Cambia…").themedText(.caption, color: .accentPrimary)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.backgroundTertiary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

// MARK: - What the panel floats over

/// A stand-in for whatever application the user was in. Deliberately dull and
/// unreadable: it is here to be behind something, and anything legible would compete
/// with the panel for the eye that is supposed to be judging the panel.
private struct HostAppBackdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(theme.color(.borderSubtle)).frame(width: 9, height: 9)
                }
                Spacer()
            }
            ForEach(0..<6, id: \.self) { row in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.color(.borderSubtle))
                    .frame(height: 9)
                    .frame(maxWidth: row.isMultiple(of: 3) ? 260 : .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.m))
        .frame(height: 300)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .opacity(0.55)
    }
}
