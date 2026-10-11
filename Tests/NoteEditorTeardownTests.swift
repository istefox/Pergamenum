import AppKit
import Testing
@testable import Pergamenum

/// `SidebarMoveUITests.swift`'s own regression,
/// `testUndoAfterTypingInANoteThenMovingABoardDoesNotCrashOnTheSecondUndo_regression`
/// (`a853e8e`): the note editor's typing-undo registers on the *window's* shared
/// `undoManager` (ADR-0026 §D8, deliberate - the sidebar's own move-undo lives on the same
/// stack). The Note/Workspace pane switch is a full SwiftUI rebuild, not a hide
/// (`RootView`'s `switch pane`), so it deallocates the `NSTextView` while a still-registered
/// action keeps targeting it; the next Cmd+Z to reach that action on the pre-fix build
/// invoked a dangling target - `EXC_BAD_ACCESS` in `-[_NSUndoStack popAndInvoke]`,
/// reproduced by hand 2026-08-28 (commit message, `git show a853e8e`).
/// `NoteTextView.dismantleNSView(_:coordinator:)` is what purges it, and is a `static func`
/// callable directly - the same way `Tests/CardConcealmentTests.swift`'s
/// `dismantlingACardPurgesItsUndoActionsAndClearsTheDelegatesTables` drives
/// `CardTextView.dismantleNSView` for the Workspace card's own copy of this rule, and this
/// test follows that one's proven shape rather than a new one.
///
/// A real, titled, never-shown `NSWindow` is required here and that sibling test needs
/// none: `CardTextView.Coordinator` owns a private `UndoManager()` of its own (its
/// `undoManager`, `CardTextView.swift`), but `NoteTextView.Coordinator.undoManager` is captured
/// from `textView.window?.undoManager` (`NoteTextView+Update.swift`'s
/// `pushInputs(to:coordinator:)`, run by `updateNSView`) precisely because it is the
/// *window's* shared stack this bug is about - a windowless text view would exercise a
/// different undo manager than production ever shares with the sidebar.
///
/// **Why this asserts on the undo stack's own bookkeeping and not on real deallocation.**
/// A first attempt dropped every strong reference to the text view and its storage and
/// checked `weak` variables for `nil`, meaning to reproduce the dangling-target crash
/// itself. Measured (`CFGetRetainCount`, not assumed): AppKit still reported dozens of
/// retains on a never-shown, fully torn-down `NSTextView` - autorelease pools, TextKit's own
/// internal registries and the responder chain all hold transient references a unit test
/// does not control and cannot drain synchronously, so "deallocated by the end of this
/// scope" is not a promise AppKit makes here. `removeAllActions(withTarget:)` does not need
/// the target to be dead to remove its actions - it matches by reference, live or not - so
/// this instead proves the fix's actual mechanism directly: after `dismantleNSView` runs,
/// nothing on the undo stack targets the text view or its storage any more, which is
/// precisely the condition that makes it safe for them to be released later, whenever
/// AppKit gets to it.
///
/// **Red-on-revert, done by hand.** Commenting out `dismantleNSView`'s two
/// `removeAllActions(withTarget:)` calls and running this exact test turned the second
/// `#expect(!undoManager.canUndo, ...)` below red - the typing action was still on the
/// stack after the "pane switch", exactly the state that would hand a real second Cmd+Z a
/// dangling target on the production build. Restoring the two calls is what turned it back
/// into the green test below.
@MainActor
@Test func dismantlingTheNoteEditorPurgesItsDanglingUndoActionsFromTheSharedWindowStack() throws {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 800),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    defer { window.orderOut(nil) }
    let undoManager = try #require(window.undoManager)
    // Grouping by event closes a group at the end of a run loop turn, and there is no run
    // loop turning here - `Tests/CardConcealmentTests.swift`'s own reason for the same line.
    undoManager.groupsByEvent = false

    let view = NoteTextView(
        text: .constant("ciao"), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)
    textView.string = "ciao"

    let scrollView = NSScrollView(frame: textView.frame)
    scrollView.documentView = textView
    window.contentView = scrollView
    // The line `updateNSView` runs on every SwiftUI update (`NoteTextView+Update.swift`'s
    // `pushInputs(to:coordinator:)`), taken here once by hand since this harness never calls
    // `updateNSView` itself.
    coordinator.undoManager = textView.window?.undoManager
    let storage = try #require(textView.textStorage)

    // The typing-undo, pushed first (bottom of the stack).
    undoManager.beginUndoGrouping()
    undoManager.registerUndo(withTarget: textView) { _ in }
    undoManager.registerUndo(withTarget: storage) { _ in }
    undoManager.endUndoGrouping()
    // Stands in for the sidebar's own move-undo (ADR-0026 §D8's shared stack): its own
    // group, pushed second, on top of the typing action already there - the two-deep stack
    // the regression's own "second Cmd+Z" is about. Its own group because `groupsByEvent =
    // false` means every `registerUndo` needs one open around it, or AppKit raises
    // `NSInternalInconsistencyException` (confirmed the hard way - measured, not assumed).
    final class Decoy: NSObject { var undone = false }
    let decoy = Decoy()
    undoManager.beginUndoGrouping()
    undoManager.registerUndo(withTarget: decoy) { $0.undone = true }
    undoManager.endUndoGrouping()
    #expect(undoManager.canUndo, "premessa: le azioni sono davvero registrate")

    // The pane switch, `RootView`'s `switch pane`: the real production call.
    NoteTextView.dismantleNSView(scrollView, coordinator: coordinator)

    // First Cmd+Z: the decoy, the only thing left on the stack if the typing action was
    // purged as it should have been.
    undoManager.undo()
    #expect(decoy.undone, "il primo Cmd+Z avrebbe dovuto raggiungere la voce ancora sullo stack")
    // The assertion the regression is actually about: nothing survives to be the second
    // Cmd+Z's target. On the unfixed build the typing action is still here and this is red.
    #expect(
        !undoManager.canUndo,
        "l'azione di battitura non doveva sopravvivere alla vista che ne è il target - il secondo Cmd+Z l'avrebbe raggiunta, un target smontato"
    )
    // Second Cmd+Z, the regression's own count: a safe no-op on the fixed build.
    undoManager.undo()
}

/// ADR-0083 §D7 (PG-386, PG-258): the Cmd+hover preview's local event monitor, tracking area and
/// window-key observation are released when the pane is left, by the same `dismantleNSView` that
/// purges the undo actions. A monitor that outlived its view was PG-258.
@MainActor
@Test func dismantlingTheNoteEditorTearsDownTheLinkPreviewController() throws {
    let view = NoteTextView(
        text: .constant("ciao"), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    coordinator.textView = textView
    let scrollView = NSScrollView(frame: textView.frame)
    scrollView.documentView = textView

    coordinator.linkPreview.attach(to: textView)
    coordinator.linkPreview.pointerEntered()
    #expect(coordinator.linkPreview.hasTrackingArea, "premessa: il tracking area è installato")
    #expect(coordinator.linkPreview.hasEventMonitor, "premessa: il monitor è installato")

    NoteTextView.dismantleNSView(scrollView, coordinator: coordinator)

    #expect(!coordinator.linkPreview.hasEventMonitor, "il monitor non doveva sopravvivere alla vista")
    #expect(!coordinator.linkPreview.hasTrackingArea)
    #expect(!coordinator.linkPreview.isObservingWindowKey)
}

/// A storage delegate that is not the coordinator, standing in for whatever else could hold the slot.
private final class ForeignStorageDelegate: NSObject, NSTextStorageDelegate {}

/// ADR-0093 §D5, plan docs/plans/scoped-layout-followup.md, Task 1 (R-01). The first styling installs
/// the coordinator as the storage's delegate (ADR-0091 §D2), and `dismantleNSView` ran on every pane
/// switch without taking it out again.
@MainActor
@Test func dismantlingTheNoteEditorClearsTheStorageDelegateItInstalled() throws {
    let fixture = ScrolledEditorFixture(text: "Una riga di prosa.\n")
    defer { fixture.window.orderOut(nil) }
    let storage = try #require(fixture.textView.textStorage)
    #expect(storage.delegate === fixture.coordinator, "premessa: la prima formattazione installa il coordinator")

    NoteTextView.dismantleNSView(fixture.scrollView, coordinator: fixture.coordinator)

    #expect(storage.delegate == nil, "il coordinator è rimasto delegate dello storage dopo lo smontaggio")
}

/// The same teardown leaves alone a delegate that is not this coordinator's: it clears its own
/// installation and only that.
@MainActor
@Test func dismantlingTheNoteEditorLeavesAForeignStorageDelegateInPlace() throws {
    let fixture = ScrolledEditorFixture(text: "Una riga di prosa.\n")
    defer { fixture.window.orderOut(nil) }
    let storage = try #require(fixture.textView.textStorage)
    let foreign = ForeignStorageDelegate()
    storage.delegate = foreign

    NoteTextView.dismantleNSView(fixture.scrollView, coordinator: fixture.coordinator)

    #expect(storage.delegate === foreign, "lo smontaggio ha tolto un delegate che non era del coordinator")
}
