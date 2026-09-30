import AppKit

/// The quit question on screen: an `NSAlert` run app-modally, inside
/// `applicationShouldTerminate(_:)`, before anything has replied (ADR-0073 §D3).
///
/// App-modal rather than a sheet because on the red-button path the window is already gone
/// and a sheet has nothing to hang from; and before `.terminateLater` because then no cap is
/// running while the person reads. The alert draws no colour and no font of its own - it is a
/// system alert, as the tab-close dialog is.
@MainActor
enum QuitReviewAlert {
    /// Builds the alert without running it, so a test reads what it would show.
    ///
    /// Buttons in the order save, «Annulla», «Non salvare», which NSAlert lays out from the
    /// trailing edge: the document-close convention. The key equivalents are assigned by hand
    /// because NSAlert's defaults key on English titles (ADR-0073 F11): Return saves, Escape
    /// cancels, Cmd+D does not save.
    static func make(_ copy: QuitReview.Copy) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.message
        alert.informativeText = copy.informative

        let save = alert.addButton(withTitle: copy.saveLabel)
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = []

        let cancel = alert.addButton(withTitle: copy.cancelLabel)
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []

        let discard = alert.addButton(withTitle: copy.discardLabel)
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        discard.hasDestructiveAction = true
        return alert
    }

    /// The answer a response stands for, in `make`'s button order.
    static func answer(for response: NSApplication.ModalResponse) -> QuitReview.Answer {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertThirdButtonReturn: .discard
        default: .cancel
        }
    }

    /// Asks, synchronously (§D3). The coordinator's `ask`.
    static func ask(_ review: QuitReview) -> QuitReview.Answer {
        answer(for: make(review.copy).runModal())
    }
}
