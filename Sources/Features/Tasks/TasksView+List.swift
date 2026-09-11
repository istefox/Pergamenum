import SwiftUI

/// `TasksView`'s list rendering: the current view's arrangement, its stored controls,
/// and the "Progetti" grouping row (PG-035 — pure code motion off `TasksView.swift`,
/// which had drifted to `file_length`/`type_body_length` warnings, the second of which
/// crossed into an error).
extension TasksView {
    var list: some View {
        // Both halves computed once here rather than read twice from the body: the rows need
        // to know which of them are rolled over, and asking a second time would be a second
        // pass over every task in the vault on every redraw.
        let rolled = rolledOverGroup
        // The same reason, one layer down: every read of `options` decodes the stored JSON
        // map, and the arrangement is where that answer is actually needed.
        let options = self.options
        let arranged = arrangedGroups(options: options) + rolled
        let rolledIDs = Set(rolled.first?.tasks.map(\.id) ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            TaskListControls(title: view.title, options: optionsBinding)
                .padding(.horizontal, theme.spacing(.l))
                .padding(.top, theme.spacing(.s))

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ForEach(arranged) { group in
                        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                            if case .project(let parent, _) = group.kind {
                                project(group, parent: parent, rolledIDs: rolledIDs)
                            } else {
                                // An ungrouped list has one group with no title, and no
                                // heading is drawn for it: a single "Oggi" above the day's
                                // own view says nothing the sidebar has not already said.
                                if !group.title.isEmpty {
                                    Text(group.title).themedText(.heading)
                                }
                                ForEach(group.tasks) { task in
                                    row(task, isRolledOver: rolledIDs.contains(task.id))
                                }
                            }
                        }
                    }
                    if arranged.isEmpty {
                        Text("Nessun task in questa vista")
                            .themedText(.body, color: .textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, theme.spacing(.xl))
                    }
                }
                .padding(theme.spacing(.l))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The controls of the view showing, read back from the one stored map and written
    /// straight into it. A binding rather than `@State` mirrored onto storage: two copies of
    /// a preference is how one of them ends up stale after a view switch.
    var optionsBinding: Binding<TaskListOptions> {
        Binding(
            get: { options },
            set: { newValue in
                var map = TaskListOptions.map(fromJSON: storedOptions)
                map[view.rawValue] = newValue
                storedOptions = TaskListOptions.json(of: map)
            }
        )
    }

    var options: TaskListOptions {
        TaskListOptions.map(fromJSON: storedOptions)[view.rawValue] ?? view.defaultListOptions
    }

    /// The current view's tasks, arranged the way its controls ask (ADR-0013 §D6).
    ///
    /// The arrangement itself is in `TaskArrangement`, outside SwiftUI, because a sort that is
    /// not stable and a group that swallows the tasks with nothing to group by are defects a
    /// test can hold and a screenshot cannot.
    func arrangedGroups(options: TaskListOptions) -> [TaskGroup] {
        TaskArrangement.groups(
            vault.index.tasks(for: view, on: today),
            options: options,
            // Only *Tutti* floats its starred notes, which is where the roadmap asks for them:
            // in a view already grouped by day or by project, a star would fight the grouping
            // the user chose rather than help it.
            priorityPaths: view == .all ? Set(vault.starredNotes.map(\.relativePath)) : [],
            boards: boards
        )
    }

    /// The unfinished tasks of the days before today, under their own heading and only in
    /// *Oggi* (ADR-0013 §D1).
    ///
    /// A group appended after the arrangement rather than a sixth grouping: what belongs to an
    /// earlier day is not another way of cutting today's list, it is a second list. The
    /// controls of §D6 act on the day's own tasks and leave this one alone, which is why it is
    /// added here and not passed through `TaskArrangement`.
    var rolledOverGroup: [TaskGroup] {
        guard view == .today, vault.settings.rollover else { return [] }
        let tasks = vault.index.rolledOverTasks(
            on: today, daysBack: vault.settings.rolloverDays
        )
        return tasks.isEmpty ? [] : [TaskGroup(title: TasksView.rolledOverTitle, tasks: tasks)]
    }

    /// The key that does the same thing from the Task menu, read from the store rather than
    /// written here: it is user-editable, and it already moved once - `Cmd+0` became
    /// `Opt+Cmd+0` when `Cmd+1…9` went to the tabs (ADR-0012 §D5). A hardcoded glyph in this
    /// row would have been wrong from the day it was typed, and the approved mockup still
    /// carries the old one.
    var moveKey: String { shortcuts.binding(for: .taskToday).displayString }

    private static let rolledOverTitle = "Rimandati"

    /// A "Progetti" group: the parent task on the disclosure header, its `^parent` children
    /// indented beneath it, and how many of them are done beside the header (ADR-0021 D6).
    ///
    /// The header is the **same** `row` every other task is drawn with, so a project is
    /// completable, selectable and right-clickable exactly like the tasks under it - it is
    /// a task, and a heading that only looked like one would be a second row view to keep
    /// in step with this one.
    func project(
        _ group: TaskGroup, parent: TaskItem, rolledIDs: Set<String>
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsedProjects.contains(group.id) },
                set: { expanded in
                    if expanded {
                        collapsedProjects.remove(group.id)
                    } else {
                        collapsedProjects.insert(group.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                ForEach(group.tasks) { task in
                    row(task, isRolledOver: rolledIDs.contains(task.id))
                }
            }
            .padding(.leading, theme.spacing(.m))
            .padding(.top, theme.spacing(.xs))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                row(parent)
                if case .project(_, let progress) = group.kind {
                    Text("\(progress.done)/\(progress.total)")
                        .themedText(.mono, color: .textTertiary)
                        // Read out in words: "1/3" is a date to VoiceOver as often as a date.
                        .accessibilityLabel(
                            "\(progress.done) di \(progress.total) completati"
                        )
                        // On macOS, `.accessibilityIdentifier` applied to an ANCESTOR
                        // propagates onto every descendant AX element in the same view
                        // subtree that has no identifier of its own on THAT element,
                        // *and even overrides one a descendant already set* - confirmed
                        // twice by reading an exported UI-hierarchy attachment: first
                        // with the identifier on the whole DisclosureGroup (it leaked
                        // onto the disclosed child rows below, replacing their own
                        // "task-row"), then with it on this HStack (it still overrode
                        // row(parent)'s own "task-row", one level up). Putting it on
                        // this Text - a leaf with no identifier of its own, and a
                        // sibling of row(parent) rather than a container of it - is
                        // what keeps it from touching anything else. Progress is always
                        // present here because `group.kind` is `.project`, which is why
                        // this branch runs whenever `project(_:parent:rolledIDs:)` does -
                        // the enum makes that a compile-time pairing (ADR-0021 D6),
                        // not a convention `bySubtasks(_:)` merely has to remember.
                        .accessibilityIdentifier("task-project-group")
                }
            }
        }
    }
}
