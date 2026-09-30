import AppKit
import Testing
@testable import Pergamenum

// ADR-0073 §D2/§D3, plan Task 4: the alert as built, never run - button order, titles from
// the copy, the key equivalents NSAlert would not assign to Italian titles (F11), and the
// destructive flag.

private let copy = QuitReview.Copy(
    message: "Salvare le modifiche a 2 note prima di uscire?",
    informative: "«A»\n«B»",
    saveLabel: "Salva tutto",
    discardLabel: "Non salvare",
    cancelLabel: "Annulla"
)

@MainActor
@Test func theAlertShowsTheCopyWithSaveAnnullaAndNonSalvareInThatOrder() {
    let alert = QuitReviewAlert.make(copy)

    #expect(alert.messageText == copy.message)
    #expect(alert.informativeText == copy.informative)
    #expect(alert.buttons.map(\.title) == ["Salva tutto", "Annulla", "Non salvare"])
}

@MainActor
@Test func returnSavesEscapeCancelsAndCommandDDoesNotSave() {
    let buttons = QuitReviewAlert.make(copy).buttons

    #expect(buttons[0].keyEquivalent == "\r")
    #expect(buttons[1].keyEquivalent == "\u{1b}")
    #expect(buttons[2].keyEquivalent == "d")
    #expect(buttons[2].keyEquivalentModifierMask == .command)
}

@MainActor
@Test func onlyNonSalvareIsDestructive() {
    let buttons = QuitReviewAlert.make(copy).buttons

    #expect(buttons.map(\.hasDestructiveAction) == [false, false, true])
}

@MainActor
@Test func eachButtonCarriesTheIdentifierAUITestFindsItBy() {
    let buttons = QuitReviewAlert.make(copy).buttons

    // Literal, not `QuitReviewAlert.Identifier`: `QuitReviewUITests` spells the same strings.
    #expect(buttons.map { $0.accessibilityIdentifier() } == [
        "quit-prompt-save", "quit-prompt-cancel", "quit-prompt-discard",
    ])
}

@MainActor
@Test func eachResponseMapsToItsAnswer() {
    #expect(QuitReviewAlert.answer(for: .alertFirstButtonReturn) == .save)
    #expect(QuitReviewAlert.answer(for: .alertSecondButtonReturn) == .cancel)
    #expect(QuitReviewAlert.answer(for: .alertThirdButtonReturn) == .discard)
    #expect(QuitReviewAlert.answer(for: .abort) == .cancel)
}
