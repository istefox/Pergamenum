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

    enum Screen: String, CaseIterable, Identifiable {
        case capture, editor, workspace, today, tasks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capture: "Cattura"
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
            case .capture: "M7, da approvare"
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
            Picker("", selection: $screen) {
                ForEach(Screen.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(screen.milestone).themedText(.caption, color: .textTertiary)
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var current: some View {
        switch screen {
        case .capture: CaptureMockup()
        case .editor: EditorMockup()
        case .workspace: WorkspaceMockup()
        case .today: TodayMockup()
        case .tasks: TasksMockup()
        }
    }
}
