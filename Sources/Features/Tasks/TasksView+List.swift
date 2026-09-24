import SwiftUI

/// `TasksView`'s list rendering: the current view's arrangement, its stored controls,
/// and the "Progetti" grouping row (PG-035 — pure code motion off `TasksView.swift`,
/// which had drifted to `file_length`/`type_body_length` warnings, the second of which
/// crossed into an error).
extension TasksView {
    /// Branches on the pane's one selection (ADR-0047 §D6): one of the five views, drawn
    /// exactly as before, or a category - `CategoryView`, fed this same `row` so a
    /// category's tasks behave exactly like every other task in the pane.
    ///
    /// The task -> pratica lookup is built here, once per render and never per row (SPEC
    /// R-03), and handed down to every `row`.
    @ViewBuilder
    var list: some View {
        let praticaLookup = taskPraticaLookup()
        switch selection {
        case .view(let taskView):
            taskViewList(taskView, praticaLookup: praticaLookup)
        case .category(let slug):
            categoryList(slug, praticaLookup: praticaLookup)
        }
    }

    private func taskViewList(
        _ taskView: IndexSnapshot.TaskView, praticaLookup: TaskPraticaLookup
    ) -> some View {
        // Both halves computed once here rather than read twice from the body: the rows need
        // to know which of them are rolled over, and asking a second time would be a second
        // pass over every task in the vault on every redraw.
        let rolled = rolledOverGroup(for: taskView)
        // The same reason, one layer down: every read of `options(for:)` decodes the stored
        // JSON map, and the arrangement is where that answer is actually needed.
        let currentOptions = options(for: .view(taskView))
        let arranged = arrangedGroups(for: taskView, options: currentOptions) + rolled
        let rolledIDs = Set(rolled.first?.tasks.map(\.id) ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            TaskListControls(title: taskView.title, options: optionsBinding(for: .view(taskView)))
                .padding(.horizontal, theme.spacing(.l))
                .padding(.top, theme.spacing(.s))

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ForEach(arranged) { group in
                        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                            if case .project(let parent, _) = group.kind {
                                project(
                                    group, parent: parent, rolledIDs: rolledIDs, praticaLookup: praticaLookup
                                )
                            } else {
                                // An ungrouped list has one group with no title, and no
                                // heading is drawn for it: a single "Oggi" above the day's
                                // own view says nothing the sidebar has not already said.
                                if !group.title.isEmpty {
                                    Text(group.title).themedText(.heading)
                                }
                                ForEach(group.tasks) { task in
                                    row(
                                        task, isRolledOver: rolledIDs.contains(task.id),
                                        praticaLookup: praticaLookup
                                    )
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

    /// A category's pane (SPEC "UI flows — Category view", R-05): a real registry entry
    /// for a registered slug, or a synthesized stand-in for an implicit one - the same
    /// fallback `CategorySidebarSection`'s "Registra" affordance implies exists, so
    /// clicking either kind of row always opens something rather than nothing.
    private func categoryList(_ slug: String, praticaLookup: TaskPraticaLookup) -> some View {
        let category = vault.categories.entries.first { $0.slug == slug }
            ?? Category(slug: slug, name: slug, color: CategoryColor.grigio.rawValue)
        return VStack(alignment: .leading, spacing: 0) {
            TaskListControls(title: category.name, options: optionsBinding(for: .category(slug)))
                .padding(.horizontal, theme.spacing(.l))
                .padding(.top, theme.spacing(.s))
            CategoryView(
                category: category,
                isRegistered: vault.categories.entries.contains { $0.slug == slug },
                options: options(for: .category(slug))
            ) { task in
                row(task, praticaLookup: praticaLookup)
            }
        }
    }

    /// The `@AppStorage("taskListOptions")` map's key for one selection: a view's own
    /// `rawValue`, unchanged from before this type existed, or `category:<slug>` for a
    /// category row - its own namespace inside the same map (ADR-0013 §D6), never a
    /// second store, so a five-view key and a category key can never collide.
    private func optionsKey(for selection: TaskPaneSelection) -> String {
        switch selection {
        case .view(let taskView): taskView.rawValue
        case .category(let slug): "category:\(slug)"
        }
    }

    /// The default controls for a selection with nothing stored yet: a view's own
    /// (ADR-0013 §D6), or a plain ungrouped, schedule-sorted list for a category - there
    /// is no sixth `TaskView.defaultListOptions` to borrow, and a category's own grouping
    /// (direct tasks, then one section per child) is already what the "Per progetto"
    /// grouping would otherwise ask the list to do a second time.
    private func defaultOptions(for selection: TaskPaneSelection) -> TaskListOptions {
        switch selection {
        case .view(let taskView): taskView.defaultListOptions
        case .category: TaskListOptions(grouping: .none, sorting: .schedule)
        }
    }

    /// The controls of the selection showing, read back from the one stored map and
    /// written straight into it. A binding rather than `@State` mirrored onto storage:
    /// two copies of a preference is how one of them ends up stale after a switch.
    private func optionsBinding(for selection: TaskPaneSelection) -> Binding<TaskListOptions> {
        Binding(
            get: { options(for: selection) },
            set: { newValue in
                var map = TaskListOptions.map(fromJSON: storedOptions)
                map[optionsKey(for: selection)] = newValue
                storedOptions = TaskListOptions.json(of: map)
            }
        )
    }

    private func options(for selection: TaskPaneSelection) -> TaskListOptions {
        TaskListOptions.map(fromJSON: storedOptions)[optionsKey(for: selection)]
            ?? defaultOptions(for: selection)
    }

    /// The controls of whatever is showing right now - not `private`, since
    /// `TasksView+Row.swift`'s `row(_:isRolledOver:praticaLookup:)` reads `options.density` to decide
    /// whether to draw a task's second line, and a row is only ever drawn while the
    /// selection it belongs to is the one showing.
    var options: TaskListOptions { options(for: selection) }

    /// One view's tasks, arranged the way its controls ask (ADR-0013 §D6).
    ///
    /// The arrangement itself is in `TaskArrangement`, outside SwiftUI, because a sort that is
    /// not stable and a group that swallows the tasks with nothing to group by are defects a
    /// test can hold and a screenshot cannot.
    func arrangedGroups(for taskView: IndexSnapshot.TaskView, options: TaskListOptions) -> [TaskGroup] {
        TaskArrangement.groups(
            vault.index.tasks(for: taskView, on: today),
            options: options,
            // Only *Tutti* floats its starred notes, which is where the roadmap asks for them:
            // in a view already grouped by day or by project, a star would fight the grouping
            // the user chose rather than help it.
            priorityPaths: taskView == .all ? Set(vault.starredNotes.map(\.relativePath)) : [],
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
    func rolledOverGroup(for taskView: IndexSnapshot.TaskView) -> [TaskGroup] {
        guard taskView == .today, vault.settings.rollover else { return [] }
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
        _ group: TaskGroup, parent: TaskItem, rolledIDs: Set<String>, praticaLookup: TaskPraticaLookup
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
                    row(task, isRolledOver: rolledIDs.contains(task.id), praticaLookup: praticaLookup)
                }
            }
            .padding(.leading, theme.spacing(.m))
            .padding(.top, theme.spacing(.xs))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                row(parent, praticaLookup: praticaLookup)
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
                        // this branch runs whenever `project(_:parent:rolledIDs:praticaLookup:)` does -
                        // the enum makes that a compile-time pairing (ADR-0021 D6),
                        // not a convention `bySubtasks(_:)` merely has to remember.
                        .accessibilityIdentifier("task-project-group")
                }
            }
        }
    }
}
