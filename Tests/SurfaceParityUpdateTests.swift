import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0096 §D10, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406, R-10).
//
// Oggi and Diario do not host the editor column (`TodayView.swift:215`, `DiaryView.swift:109`): each builds
// a `NoteTextView` of its own, so R-10 asks that they get the same cheap keystroke by their own bindings.
// Oggi binds through `updateOpenNoteText`, so the revision and the mark reach it unchanged; Diario binds
// `prose`, which `editorWrote(_:)` writes without the compare the `didSet` makes for any other writer.
// Counters, as in `UpdatePathCounterTests`. Red until Task 5.

// MARK: - Oggi

/// A `NoteTextView` bound as `TodayView.swift:217-219` binds it, hosted in a window that is never shown.
/// Not the column: no outline store is handed in, so the coordinator keeps its own.
@MainActor
private final class OggiFixture {
    let vault: VaultController
    let pause: ManualPauseScheduler
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    private(set) var missedUpdates = 0

    private let hosted: HostedView<AnyView>
    private let temporaryVault: TemporaryVault
    private var location: Int

    /// `TodayView`'s body for the daily note: re-evaluated when `vault.openNote` changes, with the same
    /// get and set on the binding.
    private struct Today: View {
        @Environment(VaultController.self) var vault

        var body: some View {
            if vault.openNote != nil {
                NoteTextView(
                    text: Binding(
                        get: { vault.openNote?.text ?? "" },
                        set: { vault.updateOpenNoteText($0) }
                    ),
                    theme: .emergency,
                    noteTitles: [],
                    tagSuggestions: [],
                    onFollowLink: { _ in }
                )
                .frame(minHeight: 320)
            }
        }
    }

    init(_ c: RestyleBudget.Case) async throws {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let temporaryVault = try TemporaryVault()
        try temporaryVault.write(note, to: "Nota.md")
        let pause = ManualPauseScheduler()
        let vault = VaultController(recents: .volatile(), openTabs: .volatile(), typingPause: pause)
        await vault.open(temporaryVault.root)
        vault.openNote(at: "Nota.md")

        let hosted = HostedView(
            AnyView(Today().environment(\.theme, .emergency).environment(vault)),
            size: CGSize(width: 900, height: 700)
        )
        await hosted.settle()
        let textView = try #require(Self.textView(under: hosted.hosting), "no CompletingTextView under Oggi's editor")
        let coordinator = try #require(textView.delegate as? NoteTextView.Coordinator)

        self.vault = vault
        self.pause = pause
        self.hosted = hosted
        self.temporaryVault = temporaryVault
        self.textView = textView
        self.coordinator = coordinator
        location = RestyleBudget.insertionPoint(in: note)
    }

    private static func textView(under view: NSView) -> CompletingTextView? {
        if let found = view as? CompletingTextView { return found }
        for subview in view.subviews {
            if let found = textView(under: subview) { return found }
        }
        return nil
    }

    /// One `x` through `insertText`, and SwiftUI's update made to run before returning (the proof being
    /// `restyleLog.skipped` advancing by one, as in `UpdatePathFixture.type(_:at:)`).
    func keystroke() {
        let before = coordinator.restyleLog.skipped
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        location += 1
        hosted.hosting.layoutSubtreeIfNeeded()
        if coordinator.restyleLog.skipped == before {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        if coordinator.restyleLog.skipped != before + 1 { missedUpdates += 1 }
    }

    func tearDown() {
        hosted.tearDown()
        vault.close()
    }
}

@MainActor
@Suite(.serialized) struct OggiKeystroke {
    // (R-10) The same keystroke as in the Note pane: no compare in the update, the outline kept current
    // (the snapshot is the coordinator's store, read through the one test seam it has), the mark on, and no
    // exact check until the pause fires.
    @Test(arguments: RestyleBudget.activeCases)
    func aKeystrokeInOggiComparesNothingAndKeepsTheMarkUntilThePauseFires(_ c: RestyleBudget.Case) async throws {
        let oggi = try await OggiFixture(c)
        defer { oggi.tearDown() }

        oggi.keystroke()
        let comparesBefore = oggi.coordinator.modelSync.compares
        let checksBefore = oggi.vault.unsavedMarkChecks
        let restartsBefore = oggi.pause.restarts
        for _ in 0..<5 { oggi.keystroke() }

        #expect(oggi.missedUpdates == 0, "SwiftUI's update did not run after \(oggi.missedUpdates) keystrokes")
        #expect(oggi.coordinator.modelSync.compares - comparesBefore == 0, "Oggi's update compared the whole text")
        let text = try #require(oggi.vault.openNote?.text)
        #expect(oggi.vault.openNote?.hasUnsavedChanges == true)
        #expect(oggi.vault.unsavedMarkChecks == checksBefore, "an exact check ran while typing")
        #expect(oggi.pause.isPending)
        #expect(oggi.pause.restarts - restartsBefore == 5, "each key restarts the pause")
        #expect(
            oggi.coordinator.derivedStateSnapshot().outline == OutlineOracle.items(text),
            "Oggi's private outline is not the parse of the note"
        )

        oggi.pause.fire()
        #expect(oggi.vault.unsavedMarkChecks == checksBefore + 1, "the pause did not check the tab")
        #expect(oggi.vault.openNote?.hasUnsavedChanges == true, "the text differs from disk, so the mark stays on")
    }
}

// MARK: - Diario

@MainActor
@Suite struct DiaryEditorWrites {
    // (R-10) The editor's own write costs no compare of the whole day and still leaves a save owed.
    @Test func theEditorsWriteCountsNoCompareAndLeavesASavePending() async throws {
        let vault = try TemporaryVault()
        let (diary, controller) = try await makeDiary(vault)
        defer { controller.close() }
        try await waitUntil { diary.isSettled }
        #expect(diary.proseCompares == 0, "loading the day compared it")

        diary.editorWrote(diary.prose + "\nUna riga scritta nell'editor.")
        #expect(diary.proseCompares == 0, "the editor's own write compared the whole day")
        #expect(diary.saveState == .pending, "the editor's write left no save owed")
        #expect(diary.prose.hasSuffix("Una riga scritta nell'editor."))
        #expect(!diary.isSettled)
    }

    @Test func aLoadCountsNoCompare() async throws {
        let vault = try TemporaryVault()
        let (diary, controller) = try await makeDiary(vault)
        defer { controller.close() }
        try await waitUntil { diary.isSettled }
        diary.load()
        try await waitUntil { diary.isSettled }
        #expect(diary.proseCompares == 0, "a load compared the day against its old value")
    }

    @Test func aProseAssignmentFromOutsideTheEditorCountsOneCompare() async throws {
        let vault = try TemporaryVault()
        let (diary, controller) = try await makeDiary(vault)
        defer { controller.close() }
        try await waitUntil { diary.isSettled }

        diary.prose += "\nAggiunta da fuori."
        #expect(diary.proseCompares == 1, "an assignment other than the editor's should compare once")
        #expect(diary.saveState == .pending)

        // An assignment of the same value is still one compare, and it owes nothing more.
        let same = diary.prose
        diary.prose = same
        #expect(diary.proseCompares == 2)
    }
}
