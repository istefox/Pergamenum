import SwiftUI

/// The approved-mockup surface the design rule of CLAUDE.md needs: every new screen
/// gets a mockup before it is implemented, and a mockup nobody can open approves
/// nothing.
///
/// The four screens of M0 lived in the sidebar and were removed from it once the real
/// panes existed - `DesignAndReadingUITests` still asserts they are not there. The
/// removal was right and this does not undo it: they are reference material, and
/// reference material belongs in Settings beside the token gallery rather than beside
/// the vault.
struct MockupGalleryView: View {
    @Environment(\.theme) private var theme
    @State private var screen: Screen = .capture

    /// The width a mockup may actually paint in.
    ///
    /// The gallery sheet is 780 points wide (`DesignSystemSettings`), and a vertical
    /// `ScrollView` does not scroll sideways: anything wider is centred and clipped at
    /// **both** edges at once, which reads as broken formatting rather than as overflow.
    /// It cost a review round on the template mockup, whose three 260-point cells came
    /// to 908 points and lost 64 from each side - every line then started exactly at the
    /// sheet's border, whatever its own indentation was.
    ///
    /// 780 less the 24-point padding a mockup puts on each side, less a margin for the
    /// scroller. A row of cells is sized from this, never guessed.
    static let contentWidth: CGFloat = 720

    /// What one mockup row actually gets: `contentWidth` less the 24 points of padding
    /// `MockupPage` puts on each side (`spacing(.l)`), applied *before* it clamps to
    /// `contentWidth`, so the content sees 672 and never 720. Two rows in the gallery were
    /// sized against 720 and came out 32 and 16 points too wide.
    static let rowWidth: CGFloat = contentWidth - 48
    /// Two across, with the 16 points (`spacing(.m)`) an `HStack` puts between them: 328.
    static let pairWidth: CGFloat = (rowWidth - 16) / 2
    /// Three across, the same way: 213 rounded down from 213.33, so the row is 671 and fits.
    /// This is the *outer* width of a cell. A `MockupCell` pads 8 points each side after
    /// its frame, so it takes this less 16 as its `width`.
    static let tripleWidth: CGFloat = ((rowWidth - 32) / 3).rounded(.down)

    enum Screen: String, CaseIterable, Identifiable {
        case capture, slash, code, outline, folding, transclusion, embed, find, format,
             history, template, tabs, tagBrowser, mentions, views, week, taskControls,
             editor, workspace, today, tasks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capture: "Cattura"
            case .slash: "Menu /"
            case .code: "Codice"
            case .outline: "Indice"
            case .folding: "Ripiegamento"
            case .transclusion: "Transclusione"
            case .embed: "Immagini e PDF"
            case .find: "Trova"
            case .format: "Formato"
            case .history: "Cronologia"
            case .template: "Template"
            case .tabs: "Tab"
            case .tagBrowser: "Tag e preferiti"
            case .mentions: "Menzioni"
            case .views: "Viste"
            case .week: "Settimana"
            case .taskControls: "Attività e rollover"
            case .editor: "Editor"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .tasks: "Attività"
            }
        }

        /// The milestone each screen belongs to, so a mockup that has been overtaken by
        /// the real thing is recognisable as such rather than mistaken for a proposal.
        var milestone: String {
            switch self {
            case .capture: "M7, realizzato"
            case .slash: "M8, realizzato"
            case .code: "M8, realizzato"
            case .outline: "M8, realizzato"
            case .folding: "M8, realizzato"
            case .transclusion: "M8, da approvare"
            case .embed: "ADR-0018 slice 3, realizzato"
            case .find: "M8, realizzato"
            case .format: "M8, realizzato"
            case .history: "M9, realizzato"
            case .template: "M9, da approvare"
            case .tabs: "M10, da approvare"
            case .tagBrowser: "M10, da approvare"
            case .mentions: "M10, da approvare"
            case .views: "M11, da approvare"
            case .week: "M12, da approvare"
            case .taskControls: "M12, da approvare"
            case .editor: "M1, realizzato"
            case .workspace: "M2 e M3, realizzato"
            case .today: "M5, realizzato"
            case .tasks: "M4, realizzato"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
            current
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private var picker: some View {
        VStack(spacing: theme.spacing(.xs)) {
            // A menu rather than a segmented control: fourteen screens in a
            // 780-point sheet truncated their own labels, and a tab nobody can read
            // is a mockup nobody can open.
            Picker("", selection: $screen) {
                ForEach(Screen.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Text(screen.milestone).themedText(.caption, color: .textTertiary)
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var current: some View {
        switch screen {
        case .capture: CaptureMockup()
        case .slash: SlashMenuMockup()
        case .code: CodeBlockMockup()
        case .outline: OutlineMockup()
        case .folding: FoldingMockup()
        case .transclusion: TransclusionMockup()
        case .embed: EmbedMockup()
        case .find: FindBarMockup()
        case .format: FormatBarMockup()
        case .history: HistoryMockup()
        case .template: TemplateMockup()
        case .tabs: TabBarMockup()
        case .tagBrowser: TagBrowserMockup()
        case .mentions: UnlinkedMentionsMockup()
        case .views: ViewMockup()
        case .week: WeekMockup()
        case .taskControls: TaskControlsMockup()
        case .editor: EditorMockup()
        case .workspace: WorkspaceMockup()
        case .today: TodayMockup()
        case .tasks: TasksMockup()
        }
    }
}
