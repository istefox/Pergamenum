import AppKit
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D8, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-13: typing `/`
// over a selection replaces it, so `CompletingTextView` keeps a one-shot stash (where it was and
// what it said) and puts it back before running a command that takes the selection. The text view
// is driven the way typing drives it, through `insertText(_:replacementRange:)` and
// `setSelectedRange`, with no event sent (`CompletionPanelTests` is the precedent for a bare view).
//
// The names this file reads are the plan's Signatures: `slashSelectionStash`,
// `restoreSlashSelection(replacing:)`. How the slash candidates are filtered is not named there, so
// the candidates are read from the completion panel's items after `refreshCompletion`, which is
// where the user sees them.

private let note = "Uno due tre"
private let due = NSRange(location: 4, length: 3)
private let replacingSelection = NSRange(location: NSNotFound, length: 0)

/// A text view with `note` and "due" selected, the whole catalogue as the slash menu's.
@MainActor
private func selecting() -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = note
    view.editorCommands = EditorCommand.all(canRun: { _ in true })
    view.setSelectedRange(due)
    return view
}

/// Types `text` the way the keyboard does: one `insertText` at the selection.
@MainActor
private func type(_ text: String, into view: CompletingTextView) {
    view.insertText(text, replacementRange: replacingSelection)
}

@MainActor
private func offersExtract(_ view: CompletingTextView) -> Bool {
    view.completionPanel.items.contains { item in
        if case .command(let command) = item { return command.id == "app.extractToNote" }
        return false
    }
}

// MARK: - Stashing

@MainActor
@Test func aSlashTypedOverASelectionStashesIt() {
    let view = selecting()

    type("/", into: view)

    #expect(view.string == "Uno / tre", "the slash replaced the selection, as typing does")
    #expect(view.slashSelectionStash?.text == "due") // R-13
    #expect(view.slashSelectionStash?.location == 4)
}

@MainActor
@Test func aSlashWithNoSelectionStashesNothing() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = note
    view.setSelectedRange(NSRange(location: 3, length: 0))

    type("/", into: view)

    #expect(view.slashSelectionStash == nil) // R-13: nothing was replaced
}

// MARK: - Restoring

@MainActor
@Test func restoringPutsTheTextBackOverTheSlashPrefixAndReselectsIt() {
    let view = selecting()
    type("/", into: view)
    type("e", into: view)
    type("s", into: view)
    #expect(view.string == "Uno /es tre")
    let prefix = NSRange(location: 4, length: 3)

    let restored = view.restoreSlashSelection(replacing: prefix)

    #expect(restored) // R-13
    #expect(view.string == note, "the selection's text is back where `/es` was")
    #expect(view.selectedRange() == due, "and selected again, so the command takes it")
    #expect(view.slashSelectionStash == nil, "the stash is one-shot")
}

@MainActor
@Test func restoringWithNoStashChangesNothingAndSaysSo() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "Uno /es tre"
    view.setSelectedRange(NSRange(location: 7, length: 0))

    let restored = view.restoreSlashSelection(replacing: NSRange(location: 4, length: 3))

    #expect(!restored)
    #expect(view.string == "Uno /es tre")
}

// MARK: - Dropping

@MainActor
@Test func dismissingTheMenuDropsTheStashAndLeavesTheReplacedTextReplaced() throws {
    let view = selecting()
    type("/", into: view)
    try #require(view.slashSelectionStash != nil)

    view.dismissCompletion()

    #expect(view.slashSelectionStash == nil) // SPEC edge case: any other outcome drops it
    #expect(view.string == "Uno / tre", "the replaced text stays replaced, as today (Cmd+Z restores it)")
}

@MainActor
@Test func acceptingAnotherCommandDropsTheStash() throws {
    let view = selecting()
    type("/", into: view)
    type("t", into: view)
    type("a", into: view)
    type("b", into: view)
    view.refreshCompletion(theme: .emergency)
    try #require(view.completionPanel.isVisible, "the menu should be open on /tab")
    try #require(view.slashSelectionStash != nil)

    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

    #expect(view.slashSelectionStash == nil) // R-13
}

// MARK: - Which entries are offered

@MainActor
@Test func extractIsOfferedOnlyWhileAStashExists() {
    let withStash = selecting()
    type("/", into: withStash)
    type("e", into: withStash)
    type("s", into: withStash)
    type("t", into: withStash)
    withStash.refreshCompletion(theme: .emergency)
    #expect(offersExtract(withStash), "«Estrai in una nota» is offered over a stashed selection") // R-13
    withStash.dismissCompletion()

    let without = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    without.string = note
    without.editorCommands = EditorCommand.all(canRun: { _ in true })
    without.setSelectedRange(NSRange(location: 3, length: 0))
    type("/", into: without)
    type("e", into: without)
    type("s", into: without)
    type("t", into: without)
    without.refreshCompletion(theme: .emergency)
    #expect(!offersExtract(without), "without a stash those entries are not offered") // R-13
    without.dismissCompletion()
}

@MainActor
@Test func theSelectionCommandLivesInSelectionEntriesNotInTheCatalogue() {
    // `EditorCommand.all` leaves out every `takesSelection` command (ADR-0085 §D8); the text view
    // adds `EditorCommand.selectionEntries` only while a slash stash exists. `EditorCommandTests`
    // counts `ShortcutCommand.allCases.count - 3` app entries (two + the selection command).
    func appCommands(_ entries: [EditorCommand]) -> [ShortcutCommand] {
        entries.compactMap { entry -> ShortcutCommand? in
            if case .app(let command) = entry.action { return command }
            return nil
        }
    }
    let inCatalogue = appCommands(EditorCommand.all(canRun: { _ in true }))
    #expect(!inCatalogue.contains(.extractToNote))
    #expect(inCatalogue.count == ShortcutCommand.allCases.count - 3)
    #expect(appCommands(EditorCommand.selectionEntries) == [.extractToNote])
}
