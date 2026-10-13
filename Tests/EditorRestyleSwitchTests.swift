import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D8, plan docs/plans/per-paragraph-restyle.md, Task 3 (R-10).
//
// The kill switch: `-editorFullRestyle YES` on the command line, or the same key in the defaults,
// turns the incremental restyle off. With it on, nothing takes the incremental path and the editor
// is what it was before ADR-0091.
//
// Red until Task 5: the placeholder reads `false` whatever it is given, and the log stays zero.

@MainActor
@Suite struct EditorRestyleSwitchTests {
    /// A defaults domain of its own, removed when the test is done.
    private func scratchDefaults() throws -> (UserDefaults, name: String) {
        let name = "pergamenum.tests.restyle-switch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    // (R-10) The key is the one the ADR names.
    @Test func theKeyIsEditorFullRestyle() {
        #expect(EditorRestyleSwitch.key == "editorFullRestyle")
    }

    // (R-10) The launch argument turns it on.
    @Test func theLaunchArgumentTurnsItOn() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(EditorRestyleSwitch.forcesFullRestyle(arguments: ["-editorFullRestyle", "YES"], defaults: defaults))
        #expect(EditorRestyleSwitch.forcesFullRestyle(
            arguments: ["Pergamenum", "-disableCalendar", "YES", "-editorFullRestyle", "YES"], defaults: defaults
        ))
    }

    // (R-10) The key in the defaults turns it on.
    @Test func theDefaultsKeyTurnsItOn() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: EditorRestyleSwitch.key)

        #expect(EditorRestyleSwitch.forcesFullRestyle(arguments: [], defaults: defaults))
    }

    // (R-10) Neither the argument nor the key: off, and an argument about something else is not it.
    @Test func absentItIsOff() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!EditorRestyleSwitch.forcesFullRestyle(arguments: [], defaults: defaults))
        #expect(!EditorRestyleSwitch.forcesFullRestyle(arguments: ["-disableCalendar", "YES"], defaults: defaults))
    }

    // (R-10) With the switch on, a typed sentence is never restyled by the dirty range, and the
    // editor ends exactly where its twin does.
    @Test func withTheSwitchOnNothingTakesTheIncrementalPath() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let editor = twin.full
        #expect(editor.coordinator.forcesFullRestyle)
        let before = editor.coordinator.restyleLog

        var location = 12
        for character in "Una frase digitata.".map(String.init) {
            twin.type(character, at: location)
            location += 1
        }

        let log = editor.coordinator.restyleLog
        #expect(log.incremental == 0, "the switch is on and a styling took the incremental path: \(log)")
        #expect(log.full > before.full, "a typed sentence was not counted as full restyles: \(before) then \(log)")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        // The twin is the control: it ran the same sentence through the incremental path.
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "the control never took the incremental path")
        #expect(RestyleTwin.emptyFields(of: editor.coordinator.derivedStateSnapshot()).isEmpty)
    }

    // MARK: The layout switch (ADR-0093 §D6, R-09)

    // (R-09) The key is the one the ADR names.
    @Test func theLayoutKeyIsEditorFullLayout() {
        #expect(EditorRestyleSwitch.layoutKey == "editorFullLayout")
    }

    // (R-09) The launch argument turns it on.
    @Test func theLayoutLaunchArgumentTurnsItOn() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(EditorRestyleSwitch.forcesFullLayout(arguments: ["-editorFullLayout", "YES"], defaults: defaults))
        #expect(EditorRestyleSwitch.forcesFullLayout(
            arguments: ["Pergamenum", "-disableCalendar", "YES", "-editorFullLayout", "YES"], defaults: defaults
        ))
    }

    // (R-09) The key in the defaults turns it on.
    @Test func theLayoutDefaultsKeyTurnsItOn() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: EditorRestyleSwitch.layoutKey)

        #expect(EditorRestyleSwitch.forcesFullLayout(arguments: [], defaults: defaults))
    }

    // (R-09) Neither the argument nor the key: off, and an argument about something else is not it.
    @Test func theLayoutSwitchAbsentIsOff() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!EditorRestyleSwitch.forcesFullLayout(arguments: [], defaults: defaults))
        #expect(!EditorRestyleSwitch.forcesFullLayout(arguments: ["-disableCalendar", "YES"], defaults: defaults))
    }

    // (R-09) The two switches are independent: neither argument nor key reads as the other.
    @Test func theTwoSwitchesAreIndependent() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!EditorRestyleSwitch.forcesFullRestyle(arguments: ["-editorFullLayout", "YES"], defaults: defaults))
        #expect(!EditorRestyleSwitch.forcesFullLayout(arguments: ["-editorFullRestyle", "YES"], defaults: defaults))

        defaults.set(true, forKey: EditorRestyleSwitch.key)
        #expect(!EditorRestyleSwitch.forcesFullLayout(arguments: [], defaults: defaults))
        defaults.removeObject(forKey: EditorRestyleSwitch.key)
        defaults.set(true, forKey: EditorRestyleSwitch.layoutKey)
        #expect(!EditorRestyleSwitch.forcesFullRestyle(arguments: [], defaults: defaults))
    }

    // (R-09) The coordinator reads the layout switch at `init`, and the fixture's explicit value wins.
    @Test func theCoordinatorReadsTheLayoutSwitchAtInit() {
        let read = EditorRestyleSwitch.forcesFullLayout(
            arguments: ProcessInfo.processInfo.arguments, defaults: .standard
        )
        let left = ScrolledEditorFixture(text: "Una riga.\n", forcesFullLayout: nil)
        let forced = ScrolledEditorFixture(text: "Una riga.\n", forcesFullLayout: true)
        let off = ScrolledEditorFixture(text: "Una riga.\n")
        defer { [left, forced, off].forEach { $0.window.orderOut(nil) } }

        #expect(left.coordinator.forcesFullLayout == read)
        #expect(forced.coordinator.forcesFullLayout)
        #expect(!off.coordinator.forcesFullLayout)
    }
}
