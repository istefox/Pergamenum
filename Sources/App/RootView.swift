import SwiftUI

/// The M0 shell: a sidebar over the design system gallery and the mockups of the
/// screens M1 to M5 will implement for real.
///
/// This is scaffolding with an expiry date. Once M1 lands, the sidebar becomes the
/// vault's note tree and the gallery moves behind a developer-only menu item.
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var engine
    /// Optional, which is the shape a macOS sidebar `List` expects: with a
    /// non-optional binding SwiftUI writes the focused row back over the initial
    /// value, so the window opened on an arbitrary pane.
    @State private var selectedPane: Pane? = .tokens
    private var pane: Pane { selectedPane ?? .tokens }

    /// Named `Pane` rather than `Section` so it does not shadow `SwiftUI.Section`
    /// inside this file's view builders.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case tokens
        case editor
        case workspace
        case today
        case tasks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tokens: "Design system"
            case .editor: "Editor"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .tasks: "Attività"
            }
        }

        var symbol: String {
            switch self {
            case .tokens: "paintpalette"
            case .editor: "doc.text"
            case .workspace: "square.on.square"
            case .today: "calendar"
            case .tasks: "checklist"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color(.backgroundSecondary))
        }
        .frame(minWidth: 1000, minHeight: 680)
    }

    /// Explicit `ForEach` plus `.tag`, rather than the data-driven `List` initialiser:
    /// with `Identifiable` rows the latter binds the selection to the element's `id`,
    /// which silently ignored the initial value.
    private var sidebar: some View {
        List(selection: $selectedPane) {
            ForEach(Pane.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color(.backgroundSecondary))
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        .safeAreaInset(edge: .bottom) { themePicker }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .tokens: DesignGalleryView()
        case .editor: EditorMockup()
        case .workspace: WorkspaceMockup()
        case .today: TodayMockup()
        case .tasks: TasksMockup()
        }
    }

    /// The M0 acceptance criterion is a runtime theme switch, so the control sits in
    /// the window rather than only in Settings, which does not exist yet.
    private var themePicker: some View {
        @Bindable var engine = engine
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("TEMA")
                .themedText(.caption, color: .textTertiary)
            Picker("Tema", selection: $engine.selection) {
                Text("Sistema").tag(ThemeEngine.Selection.followSystem)
                Text("Chiaro").tag(ThemeEngine.Selection.light)
                Text("Scuro").tag(ThemeEngine.Selection.dark)
                ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { custom in
                    Text(custom.name).tag(ThemeEngine.Selection.named(custom.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !engine.problems.isEmpty {
                Label("\(engine.problems.count) problemi nei token", systemImage: "exclamationmark.triangle")
                    .themedText(.caption, color: .taskOverdue)
                    .help(engine.problems.joined(separator: "\n"))
            }
        }
        .padding(theme.spacing(.s))
    }
}
