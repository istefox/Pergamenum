import SwiftUI

/// The header of a task list: the view's name, and the two menus that decide how it reads
/// (ADR-0013 §D6).
///
/// **Two menus and not a row of segments.** Three controls across a pane that is 320 points at
/// its narrowest would leave no room for the tasks they act on, and each menu's label already
/// says the state it is in - so the current grouping is readable without opening anything. The
/// mockup approved on 2026-08-20 (`TaskControlsMockup`) is this.
///
/// Sorting shares the first menu rather than taking a third label: it is the same question as
/// grouping asked at one level down, and a person who has just chosen "per nota" is standing
/// in the right menu to say what happens inside each note.
struct TaskListControls: View {
    @Environment(\.theme) private var theme

    let title: String
    @Binding var options: TaskListOptions

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(title.uppercased()).themedText(.caption, color: .textTertiary)
            Spacer()

            Menu {
                Picker("Raggruppa", selection: $options.grouping) {
                    ForEach(TaskGrouping.allCases) { grouping in
                        Label(grouping.title, systemImage: grouping.systemImage).tag(grouping)
                    }
                }
                .pickerStyle(.inline)

                Picker("Ordina", selection: $options.sorting) {
                    ForEach(TaskSorting.allCases) { sorting in
                        Text(sorting.title).tag(sorting)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                label(options.grouping.title, systemImage: options.grouping.systemImage)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("task-grouping-menu")
            .help("Raggruppamento e ordinamento di questa vista")

            Menu {
                Picker("Densità", selection: $options.density) {
                    ForEach(TaskDensity.allCases) { density in
                        Label(density.title, systemImage: density.systemImage).tag(density)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                label(options.density.title, systemImage: options.density.systemImage)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("task-density-menu")
            .help("Quanto di ogni riga viene disegnato")
        }
    }

    /// The label both menus wear: the icon, the current value, and the chevron pair that says
    /// it opens. Built here rather than left to `Menu`'s own label so the two are identical -
    /// the state is the thing being read, and two shapes of the same control read as two
    /// controls.
    private func label(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).themedText(.caption, color: .textTertiary)
            Text(text).themedText(.caption, color: .textSecondary)
            Image(systemName: "chevron.up.chevron.down")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
