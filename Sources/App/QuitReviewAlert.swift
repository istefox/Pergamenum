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
    ///
    /// The same alert asks before another notes folder replaces the open one (PG-334); only
    /// the words and the identifiers differ.
    static func make(_ copy: QuitReview.Copy, for occasion: QuitReview.Occasion = .quit) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.message
        alert.informativeText = copy.informative
        let identifiers = Identifier.all(for: occasion)

        let save = alert.addButton(withTitle: copy.saveLabel)
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = []
        save.setAccessibilityIdentifier(identifiers.save)

        let cancel = alert.addButton(withTitle: copy.cancelLabel)
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        cancel.setAccessibilityIdentifier(identifiers.cancel)

        let discard = alert.addButton(withTitle: copy.discardLabel)
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        discard.hasDestructiveAction = true
        discard.setAccessibilityIdentifier(identifiers.discard)
        return alert
    }

    /// The buttons' accessibility identifiers: the contract a UI test finds them by, since
    /// their titles are prose that can change (`CLAUDE.md`, ADR-0073 departure 18).
    enum Identifier {
        static let save = "quit-prompt-save"
        static let cancel = "quit-prompt-cancel"
        static let discard = "quit-prompt-discard"

        /// The vault switch's buttons (PG-334): the same pattern under their own prefix.
        static let vaultSwitchSave = "vault-switch-prompt-save"
        static let vaultSwitchCancel = "vault-switch-prompt-cancel"
        static let vaultSwitchDiscard = "vault-switch-prompt-discard"

        static func all(for occasion: QuitReview.Occasion) -> ButtonIdentifiers {
            switch occasion {
            case .quit: ButtonIdentifiers(save: save, cancel: cancel, discard: discard)
            case .vaultSwitch:
                ButtonIdentifiers(save: vaultSwitchSave, cancel: vaultSwitchCancel, discard: vaultSwitchDiscard)
            }
        }
    }

    /// The three identifiers one alert's buttons carry.
    struct ButtonIdentifiers {
        let save: String
        let cancel: String
        let discard: String
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

    /// Asks, synchronously, before another notes folder replaces the open one (PG-334).
    /// `VaultController.switchVault(to:ask:)`'s default `ask`.
    static func askBeforeVaultSwitch(_ review: QuitReview) -> QuitReview.Answer {
        answer(for: make(review.copy(for: .vaultSwitch), for: .vaultSwitch).runModal())
    }
}
