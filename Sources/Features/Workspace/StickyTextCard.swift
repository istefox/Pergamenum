import SwiftUI

/// The `.text` card: Nota (coloured) and Testo (plain), SPEC §6.4 tools 2 and 3.
///
/// One `CardTextView` in both states (ADR-0027 §D3): bound to the node's stored text when
/// nobody is writing into it, to `workspace.editingTextDraft` while
/// `workspace.editingTextNodeID == node.id`, and `isEditable` is the only property that tells
/// the two apart - so a card cannot look one way at rest and another way while it is edited
/// (R-08). The document is mutated once, at `WorkspaceController.endTextEdit(commit:)`, never
/// per keystroke - the same rule the crop editor and the resize grips already follow, so Cmd+Z
/// undoes one edit rather than one character.
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

    /// One component for both states, `isEditable` the only thing that differs (ADR-0027 §D3,
    /// R-08). Return is left alone deliberately - a sticky note has to be able to hold a line
    /// break - and Esc is handled inside `FormattingTextView`, where the first responder now is:
    /// SwiftUI's `.onKeyPress` never sees a key an `NSTextView` has already taken.
    private var content: some View {
        CardTextView(
            text: isEditing ? Bindable(workspace).editingTextDraft : .constant(storedText),
            theme: theme,
            style: CardTextStyle.read(from: node),
            isEditable: isEditing,
            // The vault setting, off the controller rather than out of the environment
            // (ADR-0028 §D10): `WorkspaceView.applyBoardSettings()` already carries the board's
            // preferences here the same way, and a `@Environment(VaultController.self)` read at
            // this level would crash a card built in a preview or a test.
            hidesMarkup: workspace.hidesMarkup,
            // Which of this card's headings are folded (ADR-0028 §D8), off the controller by node
            // id and along the same route as the setting above. Transient by construction: the
            // table is cleared in `attach`/`detach`, so a reopened board starts unfolded and
            // nothing of this reaches the `.canvas` file.
            foldedEntries: workspace.foldedHeadings[node.id] ?? [],
            // The card is the only thing that knows both its node's id and its live text view,
            // so it is where the two are put together for the board's floating format bar
            // (ADR-0027 §D5). The controller keeps the last one published; whether a bar is
            // drawn for it is `BoardFormatBarGeometry.shouldShowFormatBar`'s answer, not this
            // card's, so nothing here has to be undone when editing moves elsewhere.
            onSelectionChange: { textView in
                workspace.cardTextSelection.update(nodeID: node.id, from: textView)
            },
            // Guarded on this card's own session, exactly as the focus commit above is: when
            // editing moves straight from one card to another, this card's text view resigns
            // *after* `editingTextNodeID` already names the other one, and an unguarded call
            // here would commit and close the session the user just opened over there.
            onEndEditing: { if isEditing { workspace.endTextEdit(commit: true) } },
            // A click on a folded heading's badge, and the same controller call «Ripiega titoli»
            // makes - one fold model reached from two places, never two (ADR-0028 §D8). Unguarded,
            // unlike the two closures above: the click can only arrive from this card's own text
            // view while it is editable, so there is no other card's session to close over.
            onToggleFold: { entry in workspace.toggleFold(entry, forNodeID: node.id) }
        )
        .focused($isFocused)
        // The placeholder is the one thing the text view does not draw: it is not the card's
        // text, and writing it into the storage would make an empty card commit the word
        // "Testo" the first time it lost focus. Inset to match the text view's own container.
        .overlay(alignment: .topLeading) {
            if !isEditing, storedText.isEmpty {
                Text(placeholder)
                    .themedText(.body, color: .textTertiary)
                    .padding(2)
                    .allowsHitTesting(false)
            }
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
