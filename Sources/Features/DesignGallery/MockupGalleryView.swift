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

    /// The outer width of one item in a row of three, padding and frame included.
    ///
    /// 720 less 24 of padding a side leaves 672, and 3 × 213 + 2 × 16 of spacing = 671. One
    /// value for every mockup that draws three across: `TabBarMockup` had 213 and
    /// `HistoryMockup`/`TemplateMockup` had 208, which is the same row at two widths. `208`
    /// was a cell's *content* width, so its outer width was 224 and the row 704, wider than
    /// the 672 there is. `MockupCell(_:outerWidth:)` takes this value as is.
    static let tripleWidth: CGFloat = 213

    /// One mockup: what the picker calls it, where it stands, and the view that draws it.
    ///
    /// These three used to be three separate `switch`es over `Screen`, kept in step by hand.
    /// The compiler forces each to be exhaustive, but nothing tied one to the other, so a
    /// case could be given a title and a milestone and still open the wrong view, or
    /// reuse a neighbour's. They are one value now, produced by the single `switch` in
    /// `Screen.page`: adding a screen is one `case` and one line there, and there is
    /// no second place to forget.
    struct Page {
        let title: String
        /// The milestone the screen belongs to, so a mockup that has been overtaken by
        /// the real thing is recognisable as such rather than mistaken for a proposal.
        let milestone: String
        let content: AnyView

        init(_ title: String, _ milestone: String, _ content: some View) {
            self.title = title
            self.milestone = milestone
            self.content = AnyView(content)
        }
    }

    enum Screen: String, CaseIterable, Identifiable {
        case capture, slash, code, outline, folding, transclusion, embed, find, format,
             history, template, tabs, tagBrowser, mentions, views, week, taskControls,
             editor, workspace, today, tasks

        var id: String { rawValue }

        var title: String { page.title }
        var milestone: String { page.milestone }

        /// The only per-screen table. Exhaustive on purpose: a new `case` above does not
        /// compile until it has a title, a milestone and a view here.
        var page: Page {
            switch self {
            case .capture: Page("Cattura", "M7, realizzato", CaptureMockup())
            case .slash: Page("Menu /", "M8, realizzato", SlashMenuMockup())
            case .code: Page("Codice", "M8, realizzato", CodeBlockMockup())
            case .outline: Page("Indice", "M8, realizzato", OutlineMockup())
            case .folding: Page("Ripiegamento", "M8, realizzato", FoldingMockup())
            case .transclusion: Page("Transclusione", "M8, da approvare", TransclusionMockup())
            case .embed: Page("Immagini e PDF", "ADR-0018 slice 3, realizzato", EmbedMockup())
            case .find: Page("Trova", "M8, realizzato", FindBarMockup())
            case .format: Page("Formato", "M8, realizzato", FormatBarMockup())
            case .history: Page("Cronologia", "M9, realizzato", HistoryMockup())
            case .template: Page("Template", "M9, da approvare", TemplateMockup())
            case .tabs: Page("Tab", "M10, da approvare", TabBarMockup())
            case .tagBrowser: Page("Tag e preferiti", "M10, da approvare", TagBrowserMockup())
            case .mentions: Page("Menzioni", "M10, da approvare", UnlinkedMentionsMockup())
            case .views: Page("Viste", "M11, da approvare", ViewMockup())
            case .week: Page("Settimana", "M12, da approvare", WeekMockup())
            case .taskControls: Page("Attività e rollover", "M12, da approvare", TaskControlsMockup())
            case .editor: Page("Editor", "M1, realizzato", EditorMockup())
            case .workspace: Page("Workspace", "M2 e M3, realizzato", WorkspaceMockup())
            case .today: Page("Oggi", "M5, realizzato", TodayMockup())
            case .tasks: Page("Attività", "M4, realizzato", TasksMockup())
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

    private var current: some View {
        screen.page.content
    }
}
