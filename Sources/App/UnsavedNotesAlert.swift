import AppKit

/// The production presenter for unsaved note tabs: two `NSAlert`s (ADR-0073 §D2).
///
/// The only file that touches AppKit for this. The prompt, the decision and the save are
/// Foundation and unit-tested; what is left here is the window, checked by hand. No colour and
/// no font of its own: `NSAlert` draws in system style, the same as `VaultOpenPanel`'s
/// `NSOpenPanel`.
extension UnsavedNotesPresenter {
    @MainActor static var alert: UnsavedNotesPresenter {
        UnsavedNotesPresenter(ask: askWithAlert, reportUnsaved: reportWithAlert)
    }

    /// «Salva tutto» / «Annulla» / «Non salvare», added in that order: the first is Return,
    /// the second gets an explicit Escape, the third Cmd+D and the destructive style (F11).
    ///
    /// The app comes forward first: a quit from the Dock menu or a logout can arrive while
    /// another app is frontmost, and a question behind it would read as a hang.
    ///
    /// Only the third button discards. Any other response (the second button, or a modal ended
    /// from outside by `stopModal`/`abortModal`) is `.cancel`: on a data-loss dialog an
    /// unrecognised answer must keep the notes, never drop them.
    @MainActor private static func askWithAlert(_ prompt: UnsavedNotesPrompt) -> UnsavedNotesChoice {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.message
        alert.informativeText = prompt.informativeText
        alert.addButton(withTitle: "Salva tutto")
        let cancel = alert.addButton(withTitle: "Annulla")
        cancel.keyEquivalent = "\u{1b}"
        let discard = alert.addButton(withTitle: "Non salvare")
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        discard.hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .saveAll
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Says the gesture did not go ahead because notes are still unsaved, and where the reason
    /// is: the problem each failed path recorded.
    @MainActor private static func reportWithAlert(_ prompt: UnsavedNotesPrompt?) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Alcune note non sono state salvate"
        let what = prompt.map { "Non salvate:\n\($0.listedTitles)" }
            ?? "Il salvataggio delle note non è andato a buon fine."
        alert.informativeText = what
            + "\n\nLe modifiche sono ancora nelle tab. Il motivo è in Impostazioni › Avanzate › Problemi."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
