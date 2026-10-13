import SwiftUI

// ADR-0083 §D5/§D6 (PG-386, N3 session B), drawn as the approved N3 page draws it
// (`LinkPreviewMockup.choiceFromKeyboard`).

/// The choice a shared or dangling title asks for when there is no click point to anchor a menu
/// at: the keyboard follow, «Apri collegamento», a Workspace card, a task chip, the board tray.
/// One row per note with its folder, or the one «Crea «X»» row; Return confirms the selected row
/// through the same `choose` the click menu calls, Esc cancels.
struct LinkChoiceSheet: View {
    @Environment(\.theme) private var theme
    @Environment(CommandActions.self) private var actions

    let request: LinkChoiceRequest
    let onClose: () -> Void

    @State private var selection: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title)
                .themedText(.heading, color: .textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            rows
            footer
        }
        .padding(theme.spacing(.m))
        .frame(width: 340, alignment: .leading)
        .background(theme.color(.surfaceRaised))
        .onAppear {
            selection = request.choices.first?.id
            isFocused = true
        }
        .onExitCommand(perform: onClose)
        .accessibilityIdentifier("link-choice-sheet")
    }

    private var isCreation: Bool {
        request.choices.allSatisfy { if case .create = $0.action { true } else { false } }
    }

    private var title: String {
        isCreation ? "Nessuna nota si chiama «\(request.title)»" : "Quale «\(request.title)»?"
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(request.choices) { choice in
                row(choice)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
    }

    private func row(_ choice: LinkChoice) -> some View {
        let selected = choice.id == selection
        return Button {
            selection = choice.id
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: choice.symbol)
                    .themedText(.caption, color: selected ? .textPrimary : .textTertiary)
                    .frame(width: 14)
                Text(choice.label)
                    .themedText(.body, color: selected ? .textPrimary : .textSecondary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing(.s))
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(selected ? theme.color(.accentMuted) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice.detail)
        .accessibilityIdentifier("link-choice-row-\(choice.id)")
    }

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Spacer()
            Button("Annulla", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(isCreation ? "Crea" : "Apri", action: confirm)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
                .accessibilityIdentifier("link-choice-confirm")
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let ids = request.choices.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        selection = ids[min(max(current + offset, 0), ids.count - 1)]
        return .handled
    }

    /// Closes first, then follows: the follow may open the composer in the editor pane (ADR-0003),
    /// and this sheet must be gone before it does.
    private func confirm() {
        guard let choice = request.choices.first(where: { $0.id == selection }) else { return }
        onClose()
        actions.choose(choice, how: request.how, from: request.sourcePath)
    }
}
