import SwiftUI

/// Cattura rapida (SPEC §7.4), in the shape Craft gives it: destination on top, the
/// text in the middle, the dates and the create button along the bottom.
///
/// One panel rather than a form, because capture competes with not capturing at all:
/// everything past the text is optional and one click away, and Enter alone files the
/// task in the inbox with no date, which is what quick capture means.
struct TaskComposer: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(Navigation.self) private var navigation

    let onClose: () -> Void

    @State var draft = VaultController.TaskDraft()
    @State private var isChoosingDestination = false
    @State var open: DatePopover?
    /// Bumped to put the caret back in the text after a popover or a menu took focus.
    @State private var focusRequest = 0

    /// Which of the two date chips has its panel open. One at a time, and held as a
    /// value so opening the second closes the first.
    enum DatePopover: String, Identifiable {
        /// `>`: the day the task shows up on, with the quick choices and the reminder.
        case scheduled
        /// `!`: the day past which it is late, a calendar and nothing else.
        case due
        var id: String { rawValue }
    }

    var canCreate: Bool { !draft.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            parentRow
            ComposerTextField(
                text: $draft.text,
                placeholder: draft.parent == nil ? "Nuovo task" : "Nuovo sotto-task",
                font: theme.nsFont(.body),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: "task-composer-text",
                onSubmit: create
            )
            .frame(height: theme.spacing(.l))
            blockRow
            footer
        }
        .padding(theme.spacing(.m))
        .frame(width: 520)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .onAppear {
            // The controller carries the destination the command chose, so "Nuovo task
            // in questa nota" opens the composer already pointed at it.
            if let pending = vault.taskDraft { draft = pending }
            focusRequest += 1
        }
        // Back to the text whenever a popover closes: the caret goes to the end of
        // what was already typed, not over it.
        .onChange(of: open) { _, now in
            if now == nil { focusRequest += 1 }
        }
        .onChange(of: isChoosingDestination) { _, now in
            if !now { focusRequest += 1 }
        }
        .onExitCommand(perform: onClose)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { isChoosingDestination = true } label: {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: destinationSymbol)
                    Text(destinationTitle).themedText(.body)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-composer-destination")
            .help("Scegli la nota in cui scrivere il task")
            // A sub-task has no destination to choose: `^id` is note-local (ADR-0021
            // D2), so it goes in the parent's own note and nowhere else. Shown greyed
            // rather than hidden, so the panel does not change shape between the two
            // ways of reaching it.
            .disabled(draft.parent != nil)
            .popover(isPresented: $isChoosingDestination, arrowEdge: .bottom) {
                DestinationPicker(destination: $draft.destination) { isChoosingDestination = false }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
            .help("Chiudi senza creare")
        }
    }

    private var destinationTitle: String {
        switch draft.destination {
        case .inbox: "Inbox"
        case .note(let path): NoteName.title(fromFileName: (path as NSString).lastPathComponent)
        }
    }

    private var destinationSymbol: String {
        draft.destination == .inbox ? "tray" : "doc.text"
    }

    // MARK: Parent

    /// Which task this one becomes a child of (ADR-0021 D9, A9), drawn only when the
    /// composer was opened by «Aggiungi sotto-task».
    ///
    /// Read-only on purpose: the parent is chosen by selecting a task before running the
    /// command, and a second way to change it here would be a second selection to keep
    /// in step with the list's.
    @ViewBuilder
    private var parentRow: some View {
        if let parent = draft.parent {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(theme.color(.textTertiary))
                Text("Sotto-task di")
                    .themedText(.caption, color: .textTertiary)
                Text(parent.text)
                    .themedText(.caption, color: .textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sotto-task di \(parent.text)")
            .accessibilityIdentifier("task-composer-parent")
        }
    }

    // MARK: Timeline

    /// Asked rather than assumed: a task with an hour can also be a block on that day's
    /// timeline, and whether the day gets planned that way is the user's call. Shown
    /// only once there is an hour, since a block with no time has nowhere to go.
    @ViewBuilder
    private var blockRow: some View {
        if let slot = draft.blockSlot {
            Toggle(isOn: $draft.blocksTheDay) {
                Text("Mettilo anche nell'orario del giorno, alle \(slot.time.text)")
                    .themedText(.caption, color: .textSecondary)
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("task-composer-block")
            .help("Crea un blocco tempo nella nota del \(slot.day.italianForm)")
        }
    }

    // MARK: Creating

    func create() { create(opening: false) }

    func create(opening: Bool = false, keepingOpen: Bool = false) {
        // Everything after the capture stays *inside* the hop, in the same order it had
        // (ADR-0043 §D2): opening the note or clearing the field before the line is
        // written would show the composer's result before there is one.
        Task { @MainActor in
            guard canCreate, await vault.captureTask(draft) else { return }
            if opening {
                // The pane too, or the note opens behind whatever section is showing and
                // "apri la nota" appears to have done nothing.
                navigation.pane = .notes
                vault.openNote(at: draft.destination.relativePath)
            }

            if keepingOpen {
                // Same destination and same dates, empty text: capturing a list of tasks is
                // the case where reopening the composer three times is the friction.
                draft.text = ""
                focusRequest += 1
            } else {
                onClose()
            }
        }
    }
}

/// Picks the note a task is written into, searching by title the way the quick
/// switcher does.
private struct DestinationPicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Binding var destination: VaultController.TaskDestination
    let onPick: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Cerca una nota…", text: $query)
                .textFieldStyle(.plain)
                .padding(theme.spacing(.s))
                .accessibilityIdentifier("task-composer-destination-search")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row(title: "Inbox", subtitle: VaultController.TaskDestination.inboxPath, symbol: "tray") {
                        destination = .inbox
                    }
                    ForEach(results, id: \.relativePath) { note in
                        row(title: note.title, subtitle: note.folder, symbol: "doc.text") {
                            destination = .note(note.relativePath)
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .frame(width: 360)
    }

    private var results: [NoteRecord] {
        vault.index.search(query, limit: 40)
    }

    private func row(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPick()
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol).foregroundStyle(theme.color(.textTertiary))
                Text(title).themedText(.body).lineLimit(1)
                Spacer()
                Text(subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
