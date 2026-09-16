import SwiftUI

/// The five views of SPEC §7.4, with the count of what is open in each.
///
/// Its own type rather than a property on `TasksView`, which grew past the size SwiftLint
/// stops at when the controls of ADR-0013 §D6 went in: the list of views is a self-contained
/// piece of that pane, exactly as `TaskSettings` is of the settings window.
///
/// The views stay here, in the sidebar, where §7.4 puts them: they are where you are, not
/// something you do - which is why nothing in this file is a toolbar item.
struct TaskViewSidebar: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    @Binding var selection: TaskPaneSelection

    var body: some View {
        // The rollover window is passed in so the badge counts what the list draws: with it on
        // and nothing scheduled for today, *Oggi* shows the days before under «Rimandati».
        let counts = vault.index.taskCounts(
            on: .today, rolloverDays: vault.settings.rollover ? vault.settings.rolloverDays : 0
        )
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("ATTIVITÀ").themedText(.caption, color: .textTertiary)

            ForEach(IndexSnapshot.TaskView.allCases) { item in
                let isSelected = selection.taskView == item
                HStack {
                    Text(item.title)
                        .themedText(.body, color: isSelected ? .textPrimary : .textSecondary)
                    Spacer()
                    if let count = counts[item], count > 0 {
                        Text("\(count)").themedText(.caption, color: .textTertiary)
                    }
                }
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
                .background(isSelected ? theme.color(.accentMuted) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { selection = .view(item) }
            }

            Divider()
            CategorySidebarSection(selection: $selection)

            Spacer()

            Button {
                vault.beginTaskCapture()
            } label: {
                Label("Cattura rapida", systemImage: "plus.circle")
                    .themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(theme.spacing(.s))
        .frame(width: 200, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }
}
