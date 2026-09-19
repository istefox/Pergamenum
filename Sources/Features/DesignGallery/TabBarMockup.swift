import SwiftUI

// MARK: - Le tab del pannello Note (M10)

/// The first slice of ADR-0012: more than one note open at a time, in the Note pane.
///
/// The architecture is settled and is not what this mockup is for. A tab lives inside the
/// Note pane and `Navigation.pane` survives (D1); a tab owns the buffer and the fold, index,
/// reading-mode and find state that today sit in `Navigation` (D2); closing a tab with unsaved
/// edits asks (D3); the keys are Cmd+T and Cmd+1…Cmd+9 (D5). None of that is drawn here.
///
/// What is open is visual, and the first question is the one that costs the most to get wrong:
///
/// 1. **Does the bar sit above today's editor header, or replace it?** The header already shows
///    the note's title, its path, the Modifica/Lettura picker and the save state
///    (`VaultBrowser+Editor.swift:131`). A tab bar shows titles too. Keeping both means the
///    title is on screen twice and the editor loses 60 points of height to chrome; replacing
///    the header means finding somewhere for the path, the picker and the save state to live.
/// 2. **Is the bar there when only one note is open?** Hiding it keeps today's layout exactly
///    as it is until a second note arrives - and makes the pane jump when it does.
/// 3. **What happens when the tabs do not fit.** Shrinking keeps every tab reachable and makes
///    every title unreadable; scrolling keeps them readable and puts some off screen.
/// 4. **How the active tab is marked**, which is the smallest question and the one a person
///    reads a hundred times a day.
///
/// **Approved on 2026-08-19, all four:** the bar takes the header's place, with the path on a
/// thin line of its own and Modifica/Lettura and the save state at its right end; it is always
/// there, one note or six, which costs no height precisely because it replaced the header and
/// means nothing moves when the second note arrives; tabs keep a readable minimum width and
/// scroll, since Cmd+1…Cmd+9 reaches the ones off screen anyway; and the active tab is filled,
/// on `surfaceRaised`, which reads from across the room in both themes without leaning on the
/// accent colour.
///
/// Everything is literal: no controller, no real note, nothing that could be mistaken for the
/// feature being half-built.
struct TabBarMockup: View {
    @Environment(\.theme) private var theme

    /// Full width inside `MockupGalleryView.contentWidth`: 720 less 24 of padding a side.
    private static let sceneWidth: CGFloat = 672
    /// Two across: 2 × 328 + 16 of spacing = 672.
    private static let pairWidth: CGFloat = 328
    /// Three across: 3 × 213 + 2 × 16 = 671.
    private static let tripleWidth: CGFloat = 213

    var body: some View {
        MockupPage {
            MockupScene("La barra sopra l'intestazione di oggi: il titolo compare due volte") {
                Column(width: Self.sceneWidth) {
                    TabStrip(tabs: Self.threeTabs, carriesHeaderControls: false)
                    Divider()
                    NoteHeader()
                    Divider()
                    BodyLines(count: 4)
                }
            }
            MockupScene("La barra al posto dell'intestazione: i controlli passano nella barra") {
                Column(width: Self.sceneWidth) {
                    TabStrip(tabs: Self.threeTabs, carriesHeaderControls: true)
                    Divider()
                    PathLine()
                    Divider()
                    BodyLines(count: 5)
                }
            }
            singleNote
            overflow
            activeMarking
        }
    }

    // MARK: Una nota sola

    /// Today's pane is the left one. The question is whether it stays that way until a second
    /// note is opened, or whether the bar is permanent so nothing ever moves.
    private var singleNote: some View {
        MockupScene("Una nota sola: barra nascosta, com'è oggi · barra sempre presente") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                Column(width: Self.pairWidth) {
                    NoteHeader()
                    Divider()
                    BodyLines(count: 4)
                }
                Column(width: Self.pairWidth) {
                    TabStrip(tabs: [Self.threeTabs[0]], carriesHeaderControls: false)
                    Divider()
                    NoteHeader()
                    Divider()
                    BodyLines(count: 3)
                }
            }
        }
    }

    // MARK: Otto tab

    private var overflow: some View {
        MockupScene("Otto tab: restringere fino a stare dentro · scorrere e tenerle leggibili") {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Column(width: Self.sceneWidth) {
                    TabStrip(tabs: Self.eightTabs, carriesHeaderControls: false, isCramped: true)
                }
                Column(width: Self.sceneWidth) {
                    TabStrip(
                        tabs: Array(Self.eightTabs.prefix(4)),
                        carriesHeaderControls: false,
                        showsScrollChevron: true
                    )
                }
            }
        }
    }

    // MARK: L'attiva

    private var activeMarking: some View {
        MockupScene("L'attiva: riempita · sottolineata · solo il peso del testo") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                ForEach(TabChip.Marking.allCases, id: \.self) { marking in
                    Column(width: Self.tripleWidth) {
                        HStack(spacing: 2) {
                            TabChip(tab: Self.threeTabs[0], marking: marking)
                            TabChip(tab: Self.threeTabs[1], marking: marking)
                        }
                        .padding(theme.spacing(.xs))
                    }
                }
            }
        }
    }

    // MARK: Il contenuto finto

    private static let threeTabs: [TabChip.Model] = [
        .init(title: "Curva di trasmissibilità", isActive: true, isDirty: false),
        .init(title: "Nexion", isActive: false, isDirty: true),
        .init(title: "Sospensione motore", isActive: false, isDirty: false),
    ]

    private static let eightTabs: [TabChip.Model] = [
        .init(title: "Curva di trasmissibilità", isActive: true, isDirty: false),
        .init(title: "Nexion", isActive: false, isDirty: true),
        .init(title: "Sospensione motore", isActive: false, isDirty: false),
        .init(title: "Antivibranti serie AV", isActive: false, isDirty: false),
        .init(title: "Riunione kickoff", isActive: false, isDirty: false),
        .init(title: "Capitolato 2026", isActive: false, isDirty: true),
        .init(title: "Distretto ceramico", isActive: false, isDirty: false),
        .init(title: "20260819", isActive: false, isDirty: false),
    ]
}

// MARK: - I pezzi disegnati

/// A framed column standing in for the editor pane, so a strip is judged against the thing it
/// would sit on rather than against the sheet's background.
private struct Column<Content: View>: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: width, alignment: .leading)
            .background(theme.color(.backgroundPrimary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
            )
    }
}

private struct TabStrip: View {
    @Environment(\.theme) private var theme
    let tabs: [TabChip.Model]
    let carriesHeaderControls: Bool
    var isCramped = false
    var showsScrollChevron = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabChip(tab: tab, marking: .filled, isCramped: isCramped)
            }
            if showsScrollChevron {
                Image(systemName: "chevron.right")
                    .themedText(.caption, color: .textTertiary)
                    .padding(.horizontal, theme.spacing(.xs))
            }
            Image(systemName: "plus")
                .themedText(.caption, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.xs))
            Spacer(minLength: 0)
            if carriesHeaderControls {
                Text("Modifica / Lettura").themedText(.caption, color: .textSecondary)
                Label("Salvato", systemImage: "checkmark.circle")
                    .themedText(.caption, color: .textSecondary)
            }
        }
        .padding(theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
    }
}

private struct TabChip: View {
    @Environment(\.theme) private var theme

    struct Model: Identifiable {
        var title: String
        var isActive: Bool
        /// Unsaved edits. Every tab can have them at once now, which is the whole reason
        /// ADR-0012 D3 makes closing one ask.
        var isDirty: Bool
        var id: String { title }
    }

    /// How the active tab is told apart from the rest.
    enum Marking: CaseIterable {
        case filled, underlined, weight
    }

    let tab: Model
    let marking: Marking
    var isCramped = false

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            if tab.isDirty {
                Circle()
                    .fill(theme.color(.accentPrimary))
                    .frame(width: 6, height: 6)
            }
            Text(tab.title)
                .themedText(.caption, color: tab.isActive ? .textPrimary : .textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "xmark")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: isCramped ? 76 : 168, alignment: .leading)
        .background(background)
        .overlay(alignment: .bottom) {
            if marking == .underlined, tab.isActive {
                Rectangle().fill(theme.color(.accentPrimary)).frame(height: 2)
            }
        }
        .fontWeight(marking == .weight && tab.isActive ? .semibold : .regular)
    }

    @ViewBuilder
    private var background: some View {
        if marking == .filled, tab.isActive {
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(.surfaceRaised))
        }
    }
}

/// Today's header, drawn literally: title, path, the Modifica/Lettura picker and the save state.
private struct NoteHeader: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Curva di trasmissibilità").themedText(.heading)
                Text("Progetti/Curva di trasmissibilità.md")
                    .themedText(.caption, color: .textTertiary)
            }
            Spacer()
            Text("Modifica / Lettura").themedText(.caption, color: .textSecondary)
            Label("Salvato", systemImage: "checkmark.circle")
                .themedText(.caption, color: .textSecondary)
        }
        .padding(theme.spacing(.s))
    }
}

/// What is left of the header when the tab bar takes its place: the path alone, which is the one
/// thing a tab title cannot carry.
private struct PathLine: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Progetti/Curva di trasmissibilità.md")
            .themedText(.caption, color: .textTertiary)
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Grey bars standing in for the note's text, so the chrome above them is judged against
/// something the eye reads as a document.
private struct BodyLines: View {
    @Environment(\.theme) private var theme
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(.surfaceSunken))
                    .frame(height: 8)
                    .frame(maxWidth: index == count - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .padding(theme.spacing(.s))
    }
}
