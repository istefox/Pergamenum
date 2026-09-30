import AppKit

/// Remembers where the keyboard was before a quit ended the open edits, so a quit that ends in
/// «Annulla» gives it back (ADR-0073 §D7, departure 14).
///
/// `commitEditing` asks each window to give up its first responder, because a table cell
/// reaches its note only when its field editor ends. Nothing gave the responder back, so after
/// a cancelled quit the note editor was still in the window but no longer took keystrokes.
@MainActor
final class QuitFocus {
    private struct Saved {
        weak var window: NSWindow?
        weak var responder: NSResponder?
    }

    private var saved: [Saved] = []

    /// Records each window's first responder, then resigns it.
    func resign(in windows: [NSWindow]) {
        saved = windows.map { Saved(window: $0, responder: $0.firstResponder) }
        windows.forEach { $0.makeFirstResponder(nil) }
    }

    /// What a cancelled quit does to the keyboard and the tabs, in the one order that works:
    /// the keyboard goes back **first**, then the unresolved tab is revealed.
    ///
    /// Reversed, the reveal moves `focusedColumnIndex` to the tab's column and only *later* does
    /// that column's `onChange` ask for the keyboard; the synchronous restore lands in between,
    /// makes the old column's editor first responder, and `CompletingTextView.becomeFirstResponder`
    /// hands the focus back to that column in the same transaction, so the onChange never fires
    /// and the revealed tab is in front while Cmd+S and «Salva» act on the other column.
    func restore(thenReveal id: NoteTab.ID?, in vault: VaultController?) {
        restore()
        if let id { vault?.revealTab(id) }
    }

    /// Gives each window its first responder back after a cancelled quit.
    ///
    /// Only a **view still in that window** gets it: one that left the window (a tab closed
    /// meanwhile, a field editor detached when its cell ended) is not a place the keyboard can
    /// go. A field editor is never restored, since it is the shared, detached editor and not
    /// the cell. And only a window that is still **without** a first responder is touched: if
    /// something took the focus since, that wins.
    private func restore() {
        defer { saved = [] }
        for entry in saved {
            guard let window = entry.window,
                  window.firstResponder === window,
                  let view = entry.responder as? NSView,
                  view.window === window,
                  (view as? NSText)?.isFieldEditor != true
            else { continue }
            window.makeFirstResponder(view)
        }
    }
}
