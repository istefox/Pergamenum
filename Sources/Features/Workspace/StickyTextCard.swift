import SwiftUI

/// The `.text` card: Nota (coloured) and Testo (plain), SPEC §6.4 tools 2 and 3.
///
/// Static `Text` when nobody is writing into it, a `TextEditor` bound to
/// `workspace.editingTextDraft` while `workspace.editingTextNodeID == node.id`. The document
/// is mutated once, at `WorkspaceController.endTextEdit(commit:)`, never per keystroke - the
/// same rule the crop editor and the resize grips already follow, so Cmd+Z undoes one edit
/// rather than one character.
struct StickyTextCard: View {
    @Environment(\.theme) private var theme
    let node: CanvasNode
    let workspace: WorkspaceController

    @FocusState private var isFocused: Bool

    private var isEditing: Bool { workspace.editingTextNodeID == node.id }

    private var storedText: String {
        if case .text(let text) = node.kind { text } else { "" }
    }

    private var placeholder: String { node.color != nil ? "Nota" : "Testo" }

    var body: some View {
        Group {
            if let color = node.color {
                content
                    .padding(theme.spacing(.s))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(stickyColor(color))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
                    .themedShadow(.card)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: isFocused) { _, focused in
            // Losing focus (click elsewhere, window resigns key) commits the draft, the
            // same way the crop editor commits on an outside click.
            if isEditing, !focused { workspace.endTextEdit(commit: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            TextEditor(text: Bindable(workspace).editingTextDraft)
                .scrollContentBackground(.hidden)
                .themedText(node.color != nil ? .body : .heading)
                .focused($isFocused)
                .task { isFocused = true }
                // Return is left alone deliberately - a sticky note has to be able to
                // hold a line break - but Esc has to leave editing (SPEC §6.3), and this
                // TextEditor is the board's only first responder while it exists, so
                // nothing above it in the responder chain ever sees the key.
                .onKeyPress(.escape) {
                    isFocused = false
                    workspace.endTextEdit(commit: true)
                    return .handled
                }
        } else {
            Text(storedText.isEmpty ? placeholder : storedText)
                .themedText(
                    node.color != nil ? .body : .heading,
                    color: storedText.isEmpty ? .textTertiary : .textPrimary
                )
        }
    }

    /// Maps the six JSON Canvas presets onto theme tokens so a canvas made in Obsidian keeps
    /// its colour coding here, in this app's palette.
    private func stickyColor(_ color: CanvasColor) -> Color {
        switch color {
        case .hex(let value):
            let rgba = RGBA(hex: value) ?? RGBA(hex: "#E8E5DF")!
            return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        case .preset(let index):
            return switch index {
            case 1: theme.color(.stickyPink)
            case 2: theme.color(.stickyPink)
            case 3: theme.color(.stickyYellow)
            case 4: theme.color(.stickyGreen)
            case 5: theme.color(.stickyBlue)
            default: theme.color(.stickyGrey)
            }
        }
    }
}
