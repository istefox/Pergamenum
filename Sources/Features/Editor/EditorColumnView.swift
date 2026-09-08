import SwiftUI

/// One column of the editor: its tab bar, its note, and everything that belongs to looking at
/// *that* note rather than to the window (ADR-0012 D4).
///
/// **This exists because the state had to become two of everything.** `VaultBrowser` held one
/// find session, one focus request, one pending jump, one pending insertion - fine while a
/// window showed one note, and wrong the moment two are side by side: a search opened on the
/// right would move the caret on the left. Splitting the editor is not a layout change with a
/// second copy of the same view; it is this state moving down one level, to the thing it
/// describes.
///
/// Reads come from `vault.columns[columnIndex].active`, never from the `openNote` facade, which
/// answers for the focused column and would make both halves show the same note. Writes go
/// through the facade as they always did, after taking the focus - so there is still one way
/// into the buffer, and no per-column mirror of the controller's API.
struct EditorColumnView: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(Navigation.self) var navigation
    /// The slash menu runs app commands through this rather than re-implementing them (M8).
    @Environment(CommandActions.self) var commandActions
    /// Read for the key combinations the slash menu shows beside each app command.
    @Environment(ShortcutStore.self) var shortcuts

    let columnIndex: Int

    /// Held here rather than read straight from `Navigation`, because the insertion has to be
    /// consumed once: read directly it would be re-applied on every view update.
    @State var pendingInsertion: Navigation.Insertion?
    /// Bumped after a note is created, so the editor that replaces the composer opens with the
    /// cursor already in it.
    @State var focusRequest = 0
    /// The embedded file a click asked to see, and the panel that shows it. Empty until there
    /// is one: the Quick Look host takes first responder whenever it has a file.
    @State var previewURLs: [URL] = []
    @State var isPreviewingEmbed = false
    /// The jump the index asked for, consumed once, for the same reason as `pendingInsertion`.
    @State var pendingJump: Navigation.OutlineJump?
    /// Trova e sostituisci inside this column's note (SPEC §10, M8). One per column: a search
    /// belongs to the note being looked at, and with two columns there are two of those.
    @State var find = FindSession()
    /// The replacements the bar asked for, consumed once.
    @State var pendingReplacements: [(range: NSRange, text: String)]?
    /// Whether the pending replacements above are an Outline section move rather than a
    /// find/replace-all — the two share the same buffer mechanism, but only the move saves
    /// immediately afterward (R-08). Consumed alongside `pendingReplacements`, in
    /// `onReplacementsApplied` (`EditorColumn+Text.swift`), the one place that already knows
    /// the coordinator just finished applying them.
    @State var pendingReplacementsIsMove = false
    /// The tab whose close button was pressed while it had unsaved changes.
    @State var closing: NoteTab?
    /// The fence a "Modifica query" click asked to edit (ADR-0034 §D2), and the sheet it
    /// presents. Cleared on a successful commit and on cancel; a plain automatic dismissal
    /// (swipe, Esc) drives the same binding through `.sheet(item:)` and needs no separate
    /// handling.
    @State var editingViewQuery: ViewQueryEditRequest?

    var body: some View {
        VStack(spacing: 0) {
            // Outside the `if`: the bar is there with one note open and with none, so nothing
            // moves when a second arrives (ADR-0012 D1, mockup of 2026-08-19).
            NoteTabBar(columnIndex: columnIndex, onCloseRequested: requestClose)
            if let note = tab?.note {
                if note.externalChangePending != nil { conflictBanner }
                Divider()
                if find.isOpen {
                    findBar(note)
                    Divider()
                }
                // One editor, unconditionally (ADR-0029 §D13). A `if tab?.isReadingMode`
                // branch drew `reading(note)` here until the mode itself was removed.
                editing(note)
            } else {
                emptyState
            }
        }
        .background(theme.color(.backgroundPrimary))
        // Anywhere in the column, not only on the tab bar: clicking into a note is how a person
        // says which half they are working in, and the panes around the editor follow it.
        .contentShape(Rectangle())
        .onTapGesture { vault.focusColumn(columnIndex) }
        .quickLook(urls: previewURLs, isPresented: $isPreviewingEmbed)
        .modifier(UnsavedTabDialog(closing: $closing, column: self))
        // ADR-0034 §D2: the sheet is handed `viewQuerySource`, the same source the drawn fence
        // itself renders through, so the count in the sheet and the count in the header cannot
        // disagree. `onCommit` clears the request only on a successful write - a refused
        // commit (the fence moved on under the sheet) leaves it open to report so.
        .sheet(item: $editingViewQuery) { request in
            ViewQueryBuilderSheet(
                source: request.source,
                queries: viewQuerySource,
                onCommit: { body in
                    let committed = request.commit(body)
                    if committed { editingViewQuery = nil }
                    return committed
                },
                onCancel: { editingViewQuery = nil }
            )
        }
        // The menu's requests are answered by the focused column only. Without this both
        // columns would consume the same insertion and the same jump, and the one that lost
        // the race would apply it to the wrong note.
        .onChange(of: navigation.pendingInsertion) { _, _ in
            guard isFocused else { return }
            pendingInsertion = navigation.consumeInsertion()
        }
        .onChange(of: navigation.outlineJump) { _, jump in
            guard isFocused else { return }
            pendingJump = jump
        }
        // Same focused-column guard as the jump above: without it both columns would apply
        // the same move to whichever note they each have open (EditorColumn+Text.swift's
        // documented reason for the identical guard on `pendingInsertion`/`pendingJump`).
        .onChange(of: navigation.outlineMove) { _, move in
            guard isFocused, let move else { return }
            pendingReplacementsIsMove = true
            pendingReplacements = move.replacements.map { ($0.range, $0.text) }
        }
        // **The second half of the focus contract (ADR-0012 D4).** A click in the text moves the
        // model onto this column, through `CompletingTextView.becomeFirstResponder`; this is the
        // other direction - the model moving onto this column takes the keyboard with it. Without
        // it, clicking a tab on the right left the caret in the note on the left, and the first
        // key pressed came back through *that* column's binding, which focuses as it writes: the
        // focus snapped back on its own and the letter landed in the other note.
        //
        // It converges. `focusColumn` is a no-op when the index does not change, and
        // `makeFirstResponder` on the view that already is one does not send `become` again.
        .onChange(of: vault.focusedColumnIndex) { _, now in
            guard now == columnIndex else { return }
            focusRequest += 1
        }
        // The composer has just handed the editor back after creating a note, so the caret
        // belongs in it. The bump used to live on `VaultBrowser`, which owned the one focus
        // request there was; it belongs to the column that is about to show the new note.
        .onChange(of: vault.isComposingNote) { wasComposing, isComposing in
            guard wasComposing, !isComposing, isFocused else { return }
            focusRequest += 1
        }
    }

    // MARK: What this column is showing

    /// This column's tab, which carries the note and everything that describes looking at it.
    var tab: NoteTab? {
        vault.columns.indices.contains(columnIndex) ? vault.columns[columnIndex].active : nil
    }

    var isFocused: Bool { vault.focusedColumnIndex == columnIndex }

    /// Takes the focus, then does the thing.
    ///
    /// **Every write in this file goes through here, and the order is the whole point.** The
    /// controller's writes land in the focused column; a keystroke in the column that does not
    /// have the focus would otherwise be typed into the other note.
    func focused(_ change: () -> Void) {
        vault.focusColumn(columnIndex)
        change()
    }

    /// On the controller since the Diario pane's editor offers the same list.
    var tagSuggestions: [String] { vault.tagSuggestions }

    func follow(title: String) {
        let matches = vault.index.resolve(title: title)
        guard let first = matches.first else { return }
        focused { vault.openNote(at: first) }
    }
}
