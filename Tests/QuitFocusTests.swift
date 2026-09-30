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
