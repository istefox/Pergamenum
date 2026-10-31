import AppKit
import Testing
@testable import Pergamenum

// ADR-0073 §D7, departure 14 (fix loop, 2026-09-29): a cancelled quit gives the keyboard back to
// the view `commitEditing` took it from. Windows are built in the test and never shown.

@MainActor
private func window(with views: NSView...) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: [.titled], backing: .buffered, defer: true
    )
    window.isReleasedWhenClosed = false
    let content = NSView(frame: window.contentLayoutRect)
    for (index, view) in views.enumerated() {
        view.frame = NSRect(x: 0, y: index * 60, width: 200, height: 50)
        content.addSubview(view)
    }
    window.contentView = content
    return window
}

@MainActor
@Test func aCancelledQuitGivesTheEditorItsKeyboardBack() {
    let editor = NSTextView()
    let window = window(with: editor)
    #expect(window.makeFirstResponder(editor))
    let focus = QuitFocus()

    focus.resign(in: [window])
    #expect(window.firstResponder === window)
    focus.restore(thenReveal: nil, in: nil)

    #expect(window.firstResponder === editor)
}

@MainActor
@Test func restoreIsOneShot() {
    let editor = NSTextView()
    let window = window(with: editor)
    _ = window.makeFirstResponder(editor)
    let focus = QuitFocus()
    focus.resign(in: [window])
    focus.restore(thenReveal: nil, in: nil)
    _ = window.makeFirstResponder(nil)

    focus.restore(thenReveal: nil, in: nil)

    #expect(window.firstResponder === window)
}

@MainActor
@Test func aViewThatLeftTheWindowIsNotRestored() {
    let editor = NSTextView()
    let window = window(with: editor)
    _ = window.makeFirstResponder(editor)
    let focus = QuitFocus()
    focus.resign(in: [window])
    editor.removeFromSuperview()

    focus.restore(thenReveal: nil, in: nil)

    #expect(window.firstResponder === window)
}

// The guard in isolation: it says nothing about the reveal, which moves the model and not the
// responder chain (see `aCancelledQuitRevealsTheTabInTheOtherColumnAndFocusesIt`).
@MainActor
@Test func focusThatMovedMeanwhileIsNotOverridden() {
    let editor = NSTextView()
    let revealed = NSTextView()
    let window = window(with: editor, revealed)
    _ = window.makeFirstResponder(editor)
    let focus = QuitFocus()
    focus.resign(in: [window])
    _ = window.makeFirstResponder(revealed)

    focus.restore(thenReveal: nil, in: nil)

    #expect(window.firstResponder === revealed)
}

@MainActor
@Test func aFieldEditorIsNeverRestored() {
    let fieldEditor = NSTextView()
    fieldEditor.isFieldEditor = true
    let window = window(with: fieldEditor)
    _ = window.makeFirstResponder(fieldEditor)
    let focus = QuitFocus()
    focus.resign(in: [window])

    focus.restore(thenReveal: nil, in: nil)

    #expect(window.firstResponder === window)
}

/// The production chain, in process: column A's editor is first responder and, as
/// `CompletingTextView.becomeFirstResponder` does through `onTakeFocus`, moves the model's focus
/// onto column A whenever it takes the keyboard. The unresolved tab is in column B.
@MainActor
@Test func aCancelledQuitRevealsTheTabInTheOtherColumnAndFocusesIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nA.\n", inColumn: 0, of: controller)
    let revealed = try openDirty("Dopo.md", adding: "\nB.\n", inColumn: 1, of: controller)
    controller.focusColumn(0)
    let editorA = CompletingTextView()
    editorA.onTakeFocus = { [weak controller] in controller?.focusColumn(0) }
    let window = window(with: editorA)
    #expect(window.makeFirstResponder(editorA))
    let focus = QuitFocus()
    focus.resign(in: [window])

    focus.restore(thenReveal: revealed, in: controller)

    #expect(window.firstResponder === editorA)
    #expect(controller.focusedColumnIndex == 1)
    #expect(controller.focusedTab?.id == revealed)
    controller.close()
}

/// PG-393, M4 of `docs/plans/pg-336-conflicted-board-diary-at-quit.md` (finding 7): a quit
/// cancelled over a Contenitore scheda gives the keyboard back. The chain is the app's own -
/// `commitEditing` resigning through the delegate's `QuitFocus`, «Annulla» reaching
/// `AppDelegate.revealContenitoreAfterCancelledQuit` - wired as `PergamenumApp.swift`'s `quit`
/// wires it, with the window built here in place of `NSApp`'s. The scheda's description field
/// is a `TextEditor`, an `NSTextView` that is not a field editor, so a plain one stands in for it.
/// A scheda deleted under its unsaved edit is what makes the quit ask (PG-341).
@MainActor
@Test func aQuitCancelledOverASchedaGivesTheKeyboardBackOnTheContenitore() async throws {
    let vault = try TemporaryVault()
    let scheda = try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.contenitore.openEditor(for: scheda)
    try #require(harness.contenitore.editor).draft.description = "Scritta su una scheda che non c'è più"
    try FileManager.default.removeItem(at: vault.root.appending(path: scheda))
    harness.navigation.pane = .notes
    // The delegate holds all three weakly; the harness keeps them alive.
    let delegate = AppDelegate()
    delegate.vault = harness.vault
    delegate.navigation = harness.navigation
    delegate.contenitore = harness.contenitore
    let description = NSTextView()
    let window = window(with: description)
    #expect(window.makeFirstResponder(description))
    var resignedBeforeAsking = false
    let hold = Gate()
    let quit = QuitCoordinator(
        vault: { harness.vault }, diary: { nil }, contenitore: { harness.contenitore },
        commitEditing: { delegate.quitFocus.resign(in: [window]) },
        ask: { review in
            resignedBeforeAsking = window.firstResponder === window
            #expect(review.schede.map(\.path) == [scheda])
            return .cancel
        },
        reply: { _ in },
        reveal: { _ in },
        revealContenitore: { delegate.revealContenitoreAfterCancelledQuit($0) },
        revealBoard: {},
        revealDiary: {},
        sleep: { _ in await hold.wait() }
    )

    #expect(quit.shouldTerminate() == .cancel)

    #expect(resignedBeforeAsking, "commitEditing took the keyboard before the question")
    #expect(window.firstResponder === description, "the keyboard is back where it was")
    #expect(harness.navigation.pane == .contenitore)
    #expect(harness.contenitore.selection == scheda)
    hold.open()
    harness.vault.close()
}
