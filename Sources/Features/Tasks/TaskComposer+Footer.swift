import SwiftUI

/// `TaskComposer`'s footer: the schedule/due chips, their popovers, and clearing a date
/// (PG-035 — pure code motion off `TaskComposer.swift`, which had drifted past
/// `type_body_length`'s warning threshold).
extension TaskComposer {
    var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            chip(
                .scheduled,
                symbol: "calendar",
                title: "Programma",
                value: value(draft.scheduled, draft.scheduledTime)
            )
            chip(
                .due,
                symbol: "flag",
                title: "Scadenza",
                value: value(draft.due, draft.dueTime)
            )
            // The reminder is set inside the Programma panel, where Craft keeps it, so
            // it shows here only once there is one to show.
            if let reminder = draft.reminder {
                Label(
                    String(format: "%02d:%02d", reminder.hour, reminder.minute),
                    systemImage: "alarm"
                )
                .themedText(.caption, color: .textSecondary)
                .accessibilityIdentifier("task-composer-reminder-badge")
            }
            if let recurrence = draft.recurrence {
                Label("\(recurrence.total)×", systemImage: "arrow.triangle.2.circlepath")
                    .themedText(.caption, color: .textSecondary)
                    .accessibilityIdentifier("task-composer-repeat-badge")
            }
            categoryChip

            Spacer()

            // Split button: the click creates, the chevron offers the variant that
            // opens the note the task landed in.
            HStack(spacing: 0) {
                Button(action: create) {
                    Text("Crea")
                        .themedText(.body, color: canCreate ? .textInverted : .textTertiary)
                        .padding(.horizontal, theme.spacing(.m))
                        .padding(.vertical, theme.spacing(.xs))
                }
                .buttonStyle(.plain)
                // Also on Enter from anywhere in the panel, not only from the text
                // field: the date popovers take focus and give it back.
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityIdentifier("task-composer-create")

                Menu {
                    Button("Crea e apri la nota") { create(opening: true) }
                    Button("Crea e continua") { create(keepingOpen: true) }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(theme.color(canCreate ? .textInverted : .textTertiary))
                        .padding(.trailing, theme.spacing(.s))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!canCreate)
                .accessibilityLabel("Altre opzioni di creazione")
            }
            // Muted rather than a faded accent: an accent-coloured button that does
            // nothing when clicked is worse than one that plainly looks unavailable.
            .background(theme.color(canCreate ? .accentPrimary : .surfaceRaised))
            .clipShape(Capsule())
        }
    }

    /// What a chip reads once it has a date: `20/08/2026`, and the hour when there is
    /// one. Italian, like the day view's header - the ISO form belongs in the file.
    func value(_ date: CalendarDate?, _ time: TaskTime?) -> String? {
        guard let date else { return nil }
        return date.italianForm + (time.map { " \($0.text)" } ?? "")
    }

    /// One date chip: label alone when unset, value plus a clear button when set.
    func chip(_ popover: DatePopover, symbol: String, title: String, value: String?) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button {
                open = popover
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                    Text(value ?? title)
                        .themedText(.caption, color: value == nil ? .textTertiary : .textPrimary)
                }
                .foregroundStyle(theme.color(value == nil ? .textTertiary : .accentPrimary))
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityIdentifier("task-composer-\(popover.rawValue)")

            if value != nil {
                Button {
                    clear(popover)
                } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Togli \(title.lowercased())")
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        .background(value == nil ? Color.clear : theme.color(.accentMuted))
        .clipShape(Capsule())
        // One popover per chip, bound to whether this chip is the open one. Bound to
        // the shared value with `.popover(item:)` all three would try to present at
        // once, and the one that won was not the one clicked.
        .popover(
            isPresented: Binding(
                get: { open == popover },
                set: { if !$0, open == popover { open = nil } }
            ),
            arrowEdge: .top
        ) {
            popoverContent(for: popover)
        }
    }

    // MARK: - Category (ADR-0047 §D5, R-03)

    /// The composer's category chip: a menu of registered, non-archived categories
    /// grouped parent → child (`CategoryRegistry.assignableGroups`, the same shape
    /// `CategoryPicker` uses), setting `draft.category` rather than writing anything -
    /// the tag is appended to the drafted line only once `create()` actually captures
    /// it, through Task 3's `TaskParser.line(for:assigningCategory:)`
    /// (`VaultSession+Tasks.swift`'s `captureTask`), never string concatenation here.
    var categoryChip: some View {
        Menu {
            ForEach(vault.categories.assignableGroups, id: \.parent.slug) { group in
                if group.children.isEmpty {
                    categoryMenuButton(group.parent)
                } else {
                    Menu(group.parent.name) {
                        categoryMenuButton(group.parent)
                        ForEach(group.children) { child in categoryMenuButton(child) }
                    }
                }
            }
            if draft.category != nil {
                Divider()
                Button("Togli la categoria") { draft.category = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                Text(categoryName ?? "Categoria")
                    .themedText(.caption, color: draft.category == nil ? .textTertiary : .textPrimary)
            }
            .foregroundStyle(theme.color(draft.category == nil ? .textTertiary : .accentPrimary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("task-composer-category")
    }

    private func categoryMenuButton(_ category: Category) -> some View {
        Button(category.name) { draft.category = category.slug }
    }

    /// The chosen category's display name, or the bare slug when the registry no
    /// longer names it (deleted or archived while the composer was open) - shown
    /// rather than silently dropped, since `create()` still writes whatever slug is
    /// held.
    private var categoryName: String? {
        guard let slug = draft.category else { return nil }
        return vault.categories.entries.first { $0.slug == slug }?.name ?? slug
    }

    @ViewBuilder
    func popoverContent(for popover: DatePopover) -> some View {
        switch popover {
        case .scheduled:
            SchedulePanel(
                date: $draft.scheduled,
                time: $draft.scheduledTime,
                reminder: $draft.reminder,
                recurrence: $draft.recurrence
            ) { open = nil }
        case .due:
            DuePanel(date: $draft.due, time: $draft.dueTime) { open = nil }
        }
    }

    func clear(_ popover: DatePopover) {
        switch popover {
        case .scheduled:
            draft.scheduled = nil
            draft.scheduledTime = nil
            // The reminder hangs off the day the task shows up on; left behind it would
            // fire for a task with no date at all.
            draft.reminder = nil
        case .due:
            draft.due = nil
            draft.dueTime = nil
        }
        // Nothing left to block out: the checkbox is gone from the panel, and leaving
        // it set would plan a day the task no longer has.
        if draft.blockSlot == nil { draft.blocksTheDay = false }
    }
}
