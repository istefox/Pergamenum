import Foundation
import Testing
@testable import Pergamenum

// MARK: - Bindings

@Test func lettersAreStoredLowercasedSoAShortcutComparesEqualToItself() {
    #expect(KeyBinding("N", .command) == KeyBinding("n", .command))
    // A named key keeps its spelling: lowercasing it would turn `pageUp` into a key
    // nothing maps.
    #expect(KeyBinding("pageUp").key == "pageUp")
}

@Test func anOrdinaryCharacterNeedsCommandOrControl() {
    // Otherwise the shortcut fires while the letter is being typed into a note.
    #expect(KeyBinding("n", .shift).problem == .needsCommandOrControl)
    #expect(KeyBinding("n", .option).problem == .needsCommandOrControl)
    #expect(KeyBinding("n", .command).isValid)
    #expect(KeyBinding("n", .control).isValid)
}

@Test func aNamedKeyMayStandAlone() {
    // Anteprima rapida is the bare spacebar (SPEC §6.6), so the rule above cannot
    // apply to keys with no printable character.
    #expect(KeyBinding("space").isValid)
    #expect(KeyBinding("left", .command).isValid)
}

@Test func anEmptyOrUnknownKeyIsNotABinding() {
    #expect(KeyBinding("").problem == .empty)
    #expect(KeyBinding("f13", .command).problem == .unknownKey("f13"))
    #expect(KeyBinding("").keyboardShortcut == nil)
}

@Test func theDisplayStringUsesTheSystemOrderOfModifiers() {
    #expect(KeyBinding("n", [.command, .shift]).displayString == "⇧⌘N")
    #expect(KeyBinding("v", [.command, .shift, .option]).displayString == "⌥⇧⌘V")
    #expect(KeyBinding("space").displayString == "␣")
    #expect(KeyBinding("left", .command).displayString == "⌘←")
}

@Test func aBindingSurvivesTheRoundTripThroughItsStoredForm() throws {
    let binding = KeyBinding("k", [.command, .shift])
    let data = try JSONEncoder().encode(binding)
    // The modifiers are a bare number, not the `{"rawValue": …}` the compiler would
    // synthesise: the stored file is meant to be read by a person.
    #expect(String(bytes: data, encoding: .utf8)?.contains("\"modifiers\":3") == true)
    #expect(try JSONDecoder().decode(KeyBinding.self, from: data) == binding)
}

// MARK: - The catalogue

@Test func noTwoCommandsShipOnTheSameKeys() {
    // The panes and the File menu both used to answer to Cmd+T, and only one of them
    // ever fired. This is the test that would have caught it.
    var seen: [KeyBinding: ShortcutCommand] = [:]
    for command in ShortcutCommand.allCases {
        let binding = command.defaultBinding
        if let other = seen[binding] {
            Issue.record("\(command.rawValue) e \(other.rawValue) hanno entrambi \(binding.displayString)")
        }
        seen[binding] = command
    }
}

@Test func everyShippedDefaultIsUsable() {
    for command in ShortcutCommand.allCases {
        #expect(command.defaultBinding.isValid, "\(command.rawValue) ha una scorciatoia non valida")
        #expect(command.defaultBinding.keyboardShortcut != nil)
    }
}

// MARK: - ADR-0021 (plan 2026-08-24-workspace-tasks-notes-integration), Task 9
//
// "Aggiungi sotto-task": UX blueprint's menu bar map names Cmd+Shift+Return in the
// Task menu. `noTwoCommandsShipOnTheSameKeys` above is the collision guard, and it
// already walks `ShortcutCommand.allCases`, so `.taskAddSubtask` is exercised by it
// with no edit to that test - this one only pins the three facts that test cannot.

@Test func taskAddSubtaskLivesInTheTaskSectionWithTheBlueprintsBinding() {
    #expect(ShortcutCommand.taskAddSubtask.section == .task)
    #expect(ShortcutCommand.taskAddSubtask.defaultBinding == KeyBinding("return", [.command, .shift]))
}

// MARK: - ADR-0032 (plan 2026-09-05-plaud-recording-import-into-pergamenum), Task 8
//
// R-01, R-11, R-15; ADR §D15. `noTwoCommandsShipOnTheSameKeys` and `everyShippedDefaultIsUsable`
// above already walk `ShortcutCommand.allCases`, so both new commands are exercised by them
// with no edit to either test - this pins the two facts those generic checks cannot: which key
// each carries and which section it lives in, per the measurement ADR §D15 records.

@Test func bothNewRecordingsCommandsBindToTheirMeasuredFreeKeysInTheViewSection() {
    #expect(ShortcutCommand.paneRecordings.section == .view)
    #expect(ShortcutCommand.paneRecordings.defaultBinding == KeyBinding("0", [.command, .control]))
    #expect(ShortcutCommand.refreshRecordings.section == .view)
    #expect(ShortcutCommand.refreshRecordings.defaultBinding == KeyBinding("r", .command))
}

// MARK: - The store

/// A throwaway suite, so these never touch the real preferences.
private func makeDefaults() -> (UserDefaults, String) {
    let name = "pergamenum.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

@MainActor
@Test func aCommandNobodyTouchedKeepsItsDefault() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    let store = ShortcutStore(defaults: defaults, isOverridden: false)
    #expect(store.binding(for: .newNote) == ShortcutCommand.newNote.defaultBinding)
    #expect(!store.isCustomised(.newNote))
}

@MainActor
@Test func aChangedShortcutIsReadBackByTheNextLaunch() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    ShortcutStore(defaults: defaults, isOverridden: false)
        .set(KeyBinding("j", [.command, .option]), for: .newNote)

    let reopened = ShortcutStore(defaults: defaults, isOverridden: false)
    #expect(reopened.binding(for: .newNote) == KeyBinding("j", [.command, .option]))
    #expect(reopened.isCustomised(.newNote))
    // Everything else is untouched: one changed binding must not rewrite the rest.
    #expect(reopened.binding(for: .save) == ShortcutCommand.save.defaultBinding)
}

@MainActor
@Test func settingACommandBackToItsDefaultStopsBeingAnOverride() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    let store = ShortcutStore(defaults: defaults, isOverridden: false)
    store.set(KeyBinding("j", .command), for: .newNote)
    store.set(ShortcutCommand.newNote.defaultBinding, for: .newNote)

    // Not recorded as a choice, so a later change of default reaches this user rather
    // than being shadowed by a value identical to yesterday's.
    #expect(store.overrides.isEmpty)
}

@MainActor
@Test func aClearedCommandHasNoShortcutAtAllAndDoesNotFallBack() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    let store = ShortcutStore(defaults: defaults, isOverridden: false)
    store.clear(.quickLook)

    #expect(store.shortcut(for: .quickLook) == nil)
    // Stored as an empty binding rather than as a missing entry: a missing entry is
    // what "never changed" looks like, and the default would come straight back.
    #expect(ShortcutStore(defaults: defaults, isOverridden: false).shortcut(for: .quickLook) == nil)
}

@MainActor
@Test func resettingPutsTheDefaultBack() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    let store = ShortcutStore(defaults: defaults, isOverridden: false)
    store.set(KeyBinding("j", .command), for: .newNote)
    store.clear(.save)
    store.resetAll()

    #expect(store.binding(for: .newNote) == ShortcutCommand.newNote.defaultBinding)
    #expect(store.shortcut(for: .save) != nil)
    #expect(store.overrides.isEmpty)
}

@MainActor
@Test func twoCommandsOnTheSameKeysAreReportedToBothOfThem() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    let store = ShortcutStore(defaults: defaults, isOverridden: false)
    store.set(ShortcutCommand.save.defaultBinding, for: .newNote)

    #expect(store.conflicts(with: .newNote) == [.save])
    #expect(store.conflicts(with: .save) == [.newNote])
    #expect(store.hasConflicts)
    // A cleared command collides with nothing, however many others are also cleared.
    store.clear(.newNote)
    store.clear(.dailyNote)
    #expect(store.conflicts(with: .newNote).isEmpty)
}

@MainActor
@Test func theShippedCatalogueHasNoConflicts() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    #expect(!ShortcutStore(defaults: defaults, isOverridden: false).hasConflicts)
}

@MainActor
@Test func aMapHandedInOnTheCommandLineIsNeverPersisted() {
    // Same guard as `RecentVaults`: the argument domain outranks the persistent one,
    // so a UI test that opened the settings pane would otherwise leave its throwaway
    // bindings in the real preferences, where the app reads them every launch after.
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    ShortcutStore(defaults: defaults, isOverridden: true)
        .set(KeyBinding("j", .command), for: .newNote)

    #expect(defaults.object(forKey: ShortcutStore.defaultsKey) == nil)
}

@MainActor
@Test func aMapArrivingAsAParsedDictionaryIsStillRead() {
    // The argument domain runs every value through the property list reader first, so
    // what the app finds under the key is not always the string it wrote.
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["newNote": ["key": "j", "modifiers": 1]], forKey: ShortcutStore.defaultsKey)

    let store = ShortcutStore(defaults: defaults, isOverridden: true)
    #expect(store.binding(for: .newNote) == KeyBinding("j", .command))
}

@MainActor
@Test func modifiersWrittenAsDigitsAreStillModifiers() {
    // An old-style property list has no number type, so every value the argument
    // domain hands back is a string. Read as JSON that fails, and the shortcut a UI
    // test asked for would silently stay at its default - which is a test that passes
    // by testing nothing.
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["newNote": ["key": "j", "modifiers": "3"]], forKey: ShortcutStore.defaultsKey)

    let store = ShortcutStore(defaults: defaults, isOverridden: true)
    #expect(store.binding(for: .newNote) == KeyBinding("j", [.command, .shift]))
}

@MainActor
@Test func anEntryForACommandThatNoLongerExistsCostsNothingElse() {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(
        #"{"aCommandRemovedInAnEarlierVersion":{"key":"j","modifiers":1},"save":{"key":"y","modifiers":1}}"#,
        forKey: ShortcutStore.defaultsKey
    )

    let store = ShortcutStore(defaults: defaults, isOverridden: true)
    // The stale entry is dropped and the rest of the file still arrives.
    #expect(store.binding(for: .save) == KeyBinding("y", .command))
    #expect(store.overrides.count == 1)
}
