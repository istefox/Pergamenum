import SwiftUI

/// The capture panel, the mockup approved in PR #39 made live.
///
/// Everything here matches `CaptureMockup` on purpose: the destination bar as a row
/// rather than a popover, the two chips only on the task destination, the shortcut and
/// the button in the footer. Where the two differ, the mockup is what was approved.
struct CapturePanelView: View {
    @Environment(\.theme) private var theme

    let controller: CaptureController
    let session: VaultSession?
    /// What the hot key is actually registered as, for the footer. Nil when it is not.
    let shortcutCaption: String?
    let onClose: () -> Void

    @State private var focusRequest = 0
    @State private var isChoosingNote = false
    @State private var isChoosingFolder = false
    @State private var openPanel: DatePanel?

    private enum DatePanel: Hashable { case scheduled, due }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            targetRow
            field
            if controller.destination.takesDates { dateChips }
            if let outcome = controller.outcome { outcomeRow(outcome) }
            Divider().overlay(theme.color(.borderSubtle))
            destinationIcons
            footer
        }
        .padding(theme.spacing(.m))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .onAppear { focusRequest += 1 }
        // Back to the text whenever a popover closes, for the reason ADR-0003 §D5
        // records: SwiftUI hands focus back to a TextField by selecting all of it.
        .onChange(of: openPanel) { _, now in if now == nil { focusRequest += 1 } }
        .onChange(of: isChoosingNote) { _, now in if !now { focusRequest += 1 } }
        .onChange(of: isChoosingFolder) { _, now in if !now { focusRequest += 1 } }
        .onExitCommand(perform: onClose)
    }

    // MARK: Destinations

    /// Where the capture is actually going, above the text - the destination
    /// dropdown Craft's Quick Entry puts at the top of its own panel, rather than
    /// buried behind a click nobody makes until they wonder where the text went.
    @ViewBuilder
    private var targetRow: some View {
        switch controller.destination {
        case .note: folderPicker
        case .task, .existing: notePicker
        case .today: EmptyView()
        }
    }

    /// The four destinations as a compact icon rail, Craft's mode row moved to the
    /// bottom of the panel. The label and the shortcut digit that used to sit beside
    /// each icon are gone - `targetRow` and `field`'s placeholder already say which
    /// destination is active, so dropping them here is not losing the information,
    /// only where it is said. `.help` keeps the name one hover away.
    private var destinationIcons: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(Array(CaptureController.Destination.allCases.enumerated()), id: \.element) { index, item in
                let isCurrent = item == controller.destination
                Button {
                    controller.destination = item
                    focusRequest += 1
                } label: {
                    Image(systemName: item.symbol)
                        .foregroundStyle(theme.color(isCurrent ? .textPrimary : .textTertiary))
                        .frame(width: 26, height: 26)
                        .background(isCurrent ? theme.color(.accentMuted) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityIdentifier("capture-destination-\(item.rawValue)")
                .help("\(item.title) — ⌘\(index + 1)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Folder (Nota nuova)

    /// A `Button` + popover, not a `Menu`: `Menu`'s `.borderlessButton` style draws its
    /// closed-state label at the system menu font regardless of any `.font`/`themedText`
    /// applied to it - confirmed on screen, "00 Inbox" here read visibly smaller than
    /// `notePicker`'s "Inbox" even though both asked for the same `.caption` token. A
    /// plain button popover is what `notePicker` already uses and already renders
    /// correctly, so this is the same mechanism rather than a second one to keep in sync.
    private var folderPicker: some View {
        Button { isChoosingFolder = true } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "folder")
                Text(controller.folder ?? VaultAPI.CaptureDestination.defaultFolder)
                    .themedText(.caption, color: .textTertiary)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(theme.color(.textTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-folder")
        .popover(isPresented: $isChoosingFolder) {
            CaptureFolderPicker(session: session) { folder in
                controller.folder = folder
                isChoosingFolder = false
            }
        }
    }

    // MARK: Text

    private var field: some View {
        ComposerTextField(
            text: Binding(get: { controller.text }, set: { controller.text = $0 }),
            placeholder: controller.destination.placeholder,
            font: theme.nsFont(.body),
            color: NSColor(theme.color(.textPrimary)),
            focusRequest: focusRequest,
            identifier: "capture-text",
            onSubmit: submit
        )
        .frame(height: theme.spacing(.l))
    }

    // MARK: Dates

    private var dateChips: some View {
        HStack(spacing: theme.spacing(.s)) {
            chip(.scheduled, symbol: "calendar", title: "Programma", date: controller.scheduled)
            chip(.due, symbol: "flag", title: "Scadenza", date: controller.due)
            Spacer(minLength: 0)
        }
    }

    private func chip(
        _ panel: DatePanel, symbol: String, title: String, date: CalendarDate?
    ) -> some View {
        Button { openPanel = panel } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol)
                Text(title).themedText(.caption, color: .textSecondary)
                if let date {
                    Text(date.italianForm).themedText(.caption, color: .accentPrimary)
                }
            }
            .foregroundStyle(theme.color(.textSecondary))
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-\(panel == .scheduled ? "schedule" : "deadline")")
        .popover(isPresented: Binding(
            get: { openPanel == panel },
            set: { if !$0 { openPanel = nil } }
        )) {
            MonthCalendar(selection: Binding(
                get: { panel == .scheduled ? controller.scheduled : controller.due },
                set: {
                    if panel == .scheduled { controller.scheduled = $0 } else { controller.due = $0 }
                    openPanel = nil
                }
            ))
            .padding(theme.spacing(.s))
        }
    }

    // MARK: A note to append to

    private var notePicker: some View {
        Button { isChoosingNote = true } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "doc.text")
                Text(chosenNoteTitle).themedText(.caption, color: .textTertiary)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(theme.color(.textTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-note")
        .popover(isPresented: $isChoosingNote) {
            CaptureNotePicker(session: session) { path in
                controller.notePath = path
                isChoosingNote = false
            }
        }
    }

    /// Nil is not the same absence for the two destinations that share this row: for
    /// `.task` it is the fixed inbox note, a default that already works; for
    /// `.existing` it is a choice not yet made, and `capture()` refuses it.
    private var chosenNoteTitle: String {
        guard let path = controller.notePath else {
            return controller.destination == .task ? "Inbox" : "Scegli una nota…"
        }
        return NoteName.title(fromFileName: (path as NSString).lastPathComponent)
    }

    // MARK: Outcome

    private func outcomeRow(_ outcome: CaptureController.Outcome) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            switch outcome {
            case .wrote(let path):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.color(.taskDone))
                Text(path).themedText(.caption, color: .textSecondary)
            case .refused(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.color(.taskOverdue))
                Text(reason).themedText(.caption, color: .textPrimary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            // What is registered, never what is configured (ADR-0008 §D2).
            Label(
                shortcutCaption ?? "Scorciatoia non attiva",
                systemImage: shortcutCaption == nil ? "keyboard.badge.ellipsis" : "keyboard"
            )
            .themedText(.caption, color: shortcutCaption == nil ? .taskOverdue : .textTertiary)

            Spacer()
            Text("⏎").themedText(.caption, color: .textTertiary)
            Button(action: submit) {
                Text("Cattura")
                    .themedText(.caption, color: .onAccent)
                    .padding(.horizontal, theme.spacing(.m))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(theme.color(controller.isEmpty ? .accentMuted : .accentPrimary))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(controller.isEmpty)
            .accessibilityIdentifier("capture-submit")
        }
    }

    private func submit() {
        // Stays open on a refusal: the text that was refused is the only copy of it. The
        // branch is inside the hop for that reason (ADR-0043 §D2) - closing the panel
        // before the write answered would throw away the one copy on a refusal.
        Task { @MainActor in
            if await controller.capture(into: session) { onClose() }
        }
    }
}

/// The note to append to, chosen by typing. The quick switcher's fuzzy match over the
/// index, which is the same way every other "which note" question in the app is asked.
/// The folder a new note lands in, chosen the same way `CaptureNotePicker` chooses a
/// note: a button opening a popover, not a `Menu` (see `folderPicker`'s own comment).
private struct CaptureFolderPicker: View {
    @Environment(\.theme) private var theme
    let session: VaultSession?
    let onChoose: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onChoose(nil) } label: {
                Text(VaultAPI.CaptureDestination.defaultFolder)
                    .themedText(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            ForEach(session?.folders ?? [], id: \.self) { folder in
                Button { onChoose(folder) } label: {
                    Text(folder)
                        .themedText(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, theme.spacing(.xs))
            }
        }
        .padding(theme.spacing(.s))
        .frame(width: 220)
    }
}

private struct CaptureNotePicker: View {
    @Environment(\.theme) private var theme
    let session: VaultSession?
    let onChoose: (String) -> Void

    @State private var query = ""

    private var results: [NoteRecord] {
        guard let session else { return [] }
        return session.index.search(query, limit: 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            TextField("Cerca una nota", text: $query)
                .textFieldStyle(.plain)
                .themedText(.body)
            Divider()
            ForEach(results, id: \.relativePath) { record in
                Button { onChoose(record.relativePath) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(record.title).themedText(.caption)
                        Text(record.relativePath).themedText(.caption, color: .textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(theme.spacing(.s))
        .frame(width: 320)
    }
}
