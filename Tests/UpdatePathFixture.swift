import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0096 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 1 (PG-406, R-01).
//
// The first test fixture to host `EditorColumnView`. A keystroke typed into its text view writes the
// binding, and SwiftUI's update (the diff of the column's inputs, the column's body, `updateNSView`)
// follows; `ScrolledEditorFixture` stops before that, which is how a whole-note compare in the update
// path hid behind a bench that never called `updateNSView`.

/// The real editor column of a vault with one note open, in a window that is never shown.
@MainActor
final class UpdatePathFixture {
    let vault: VaultController
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    /// The pause the vault was built with, so a test fires it by hand (ADR-0096 §D4, plan Task 4).
    let typingPause: any PauseScheduler
    /// The find session the column was built over, so a test reads `updates` and opens the bar.
    let find: FindSession

    /// How `keystroke()` made SwiftUI run its update, counted over every keystroke so far.
    private(set) var forcedByLayout = 0
    private(set) var forcedByRunLoop = 0
    /// Keystrokes after which `restyleLog.skipped` had not advanced by exactly one, so no update ran.
    private(set) var missedUpdates = 0

    private let hosted: HostedView<AnyView>
    private let defaults: UserDefaults
    private let defaultsName: String
    private let temporaryVault: TemporaryVault
    /// Where the next keystroke types, in the note as it is now.
    private(set) var location: Int

    var host: HostedView<AnyView> { hosted }

    /// `typingPause` and `find` are the two things plan Task 4 needs to reach: the pause that settles the
    /// unsaved mark, and the find session whose `updates` the column's handlers move. Their defaults keep
    /// every Task 1 call site as it was.
    init(
        _ c: RestyleBudget.Case,
        typingPause: any PauseScheduler = ManualPauseScheduler(),
        find: FindSession = FindSession()
    ) async throws {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let temporaryVault = try TemporaryVault()
        try temporaryVault.write(note, to: "Nota.md")

        let vault = VaultController(recents: .volatile(), openTabs: .volatile(), typingPause: typingPause)
        await vault.open(temporaryVault.root)
        vault.openNote(at: "Nota.md")

        let navigation = Navigation()
        let calendarStore = EventKitStore()
        let capture = CaptureController()
        let actions = CommandActions(
            navigation: navigation,
            vault: vault,
            day: DayController(store: calendarStore, vault: vault),
            calendar: calendarStore,
            capturePanel: CapturePanel(
                controller: capture,
                session: { vault.session },
                theme: { ThemeEngine().current },
                shortcutCaption: { nil }
            ),
            history: NavigationHistory(),
            pasteboard: .volatile()
        )
        let defaultsName = "UpdatePathFixture-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let shortcuts = ShortcutStore(defaults: defaults, isOverridden: false)

        let hosted = HostedView(
            AnyView(
                EditorColumnView(columnIndex: 0, find: find)
                    .environment(\.theme, .emergency)
                    .environment(vault)
                    .environment(navigation)
                    .environment(actions)
                    .environment(shortcuts)
            ),
            size: CGSize(width: 900, height: 700)
        )
        await hosted.settle()

        let textView = try #require(
            Self.textView(under: hosted.hosting), "no CompletingTextView under the hosted column"
        )
        let coordinator = try #require(textView.delegate as? NoteTextView.Coordinator)

        self.vault = vault
        self.textView = textView
        self.coordinator = coordinator
        self.typingPause = typingPause
        self.find = find
        self.hosted = hosted
        self.defaults = defaults
        self.defaultsName = defaultsName
        self.temporaryVault = temporaryVault
        location = RestyleBudget.insertionPoint(in: note)
    }

    private static func textView(under view: NSView) -> CompletingTextView? {
        if let found = view as? CompletingTextView { return found }
        for subview in view.subviews {
            if let found = textView(under: subview) { return found }
        }
        return nil
    }

    /// One keystroke: an `x` typed at the end of the middle paragraph through `insertText`, then SwiftUI
    /// made to run the update the binding write scheduled, before returning. First by
    /// `layoutSubtreeIfNeeded()` on the hosting view; when that did not run it, by one turn of the main
    /// run loop. The proof is `restyleLog.skipped` advancing by exactly one (`updateNSView`'s passes find
    /// nothing to restyle after the incremental one `textDidChange` ran); a keystroke whose update did not
    /// run is counted in `missedUpdates`, which the tests assert to be zero.
    func keystroke() {
        type("x", at: location)
        location += 1
    }

    /// `string` typed at `position` the way `keystroke()` types its letter (the selection set there, then
    /// `insertText`), and SwiftUI's update made to run before returning, counted the same way. Added for
    /// plan Task 4, whose tests type a fence's third backtick and a heading's `# ` somewhere other than
    /// the middle paragraph. It leaves `location`, where the next `keystroke()` types, alone.
    func type(_ string: String, at position: Int) {
        let before = coordinator.restyleLog.skipped
        textView.setSelectedRange(NSRange(location: position, length: 0))
        textView.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))

        hosted.hosting.layoutSubtreeIfNeeded()
        if coordinator.restyleLog.skipped == before {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
            if coordinator.restyleLog.skipped == before + 1 { forcedByRunLoop += 1 }
        } else {
            forcedByLayout += 1
        }
        if coordinator.restyleLog.skipped != before + 1 { missedUpdates += 1 }
        // The completion panel is a child window ordered front over the hosted one: a keystroke that
        // opens it puts a panel on the person's screen and makes AppKit send the hosted window events
        // it refuses (R-15), which arrive outside the test and are counted against no test.
        #expect(!textView.completionPanel.isVisible, "typing \(string.debugDescription) opened the completion panel")
    }

    func tearDown() {
        // Read inside the test's own task, so a refused call fails this test rather than «unknown» (PG-201).
        #expect(hosted.refusals.isEmpty, "the hosted window refused \(hosted.refusals)")
        hosted.tearDown()
        vault.close()
        defaults.removePersistentDomain(forName: defaultsName)
    }
}
