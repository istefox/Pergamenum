import Foundation
import Testing
@testable import Pergamenum

// The two halves of the capture panel a test can reach: the translation into what
// Carbon wants, and what the controller decides before it writes.
//
// What is deliberately absent: the hot key firing, the panel appearing over another
// application, the focus going back to it. The XCUI runner drives Pergamenum, and the
// whole point of the feature is that Pergamenum is not in front. Those three are a
// manual check and ADR-0008 says so rather than leaving a gap that looks like coverage.

// MARK: - CarbonKey

@Test func everyKeyTheRecorderCanProduceHasAVirtualKeyCode() {
    // The recorder can only produce a named key or a single character, so this is the
    // whole space a binding can occupy. A key with no code is a shortcut that cannot be
    // registered, and the panel would silently never open.
    for name in KeyBinding.namedKeys {
        #expect(CarbonKey.virtualKeyCode(for: name) != nil, "«\(name)» non ha un codice")
    }
    for letter in "abcdefghijklmnopqrstuvwxyz0123456789" {
        #expect(CarbonKey.virtualKeyCode(for: String(letter)) != nil, "«\(letter)» non ha un codice")
    }
}

@Test func theDefaultBindingOfEveryCommandCanBeTranslated() {
    // Not only the capture one: any of them may be assigned to global capture by the
    // user, and a binding the settings pane offers has to be one the system can take.
    for command in ShortcutCommand.allCases {
        #expect(
            CarbonKey.pair(for: command.defaultBinding) != nil,
            "«\(command.title)» non è traducibile"
        )
    }
}

@Test func aKeyOutsideTheTableHasNoCodeRatherThanAGuessedOne() {
    // A guessed code would register the panel on some other key, which reads as the
    // feature being broken rather than as the shortcut being unusable.
    #expect(CarbonKey.virtualKeyCode(for: "f13") == nil)
    #expect(CarbonKey.virtualKeyCode(for: "€") == nil)
    #expect(CarbonKey.virtualKeyCode(for: "") == nil)
    #expect(CarbonKey.pair(for: KeyBinding("f13", .control)) == nil)
}

@Test func theModifierMaskIsCarbonsAndNotAppKits() {
    // Checked by running them: Carbon says control 4096, command 256, option 2048,
    // shift 512 - none of which are NSEvent's. A mask written from memory produces a
    // shortcut that is not the one the user chose.
    #expect(CarbonKey.modifierMask(for: []) == 0)
    #expect(CarbonKey.modifierMask(for: .control) == 4096)
    #expect(CarbonKey.modifierMask(for: .command) == 256)
    #expect(CarbonKey.modifierMask(for: .option) == 2048)
    #expect(CarbonKey.modifierMask(for: .shift) == 512)
    #expect(CarbonKey.modifierMask(for: [.command, .shift]) == 768)
}

@Test func theDefaultCaptureShortcutIsControlSpace() {
    let binding = ShortcutCommand.globalCapture.defaultBinding
    #expect(binding == KeyBinding("space", .control))
    let pair = try? #require(CarbonKey.pair(for: binding))
    // kVK_Space is 49; the panel opening on the wrong key would be indistinguishable
    // from it not opening at all.
    #expect(pair?.code == 49)
    #expect(pair?.modifiers == 4096)
}

// MARK: - The state the settings pane reads

@Test func onlyARegisteredStateReadsAsWorkingAndTheOthersSayWhy() {
    // ADR-0008 §D2: the pane shows what the system did, not what the user asked for.
    // A row that reads ⌃Space while the registration was refused is the failure this
    // type exists to make impossible.
    let binding = KeyBinding("space", .control)
    #expect(GlobalHotkey.State.registered(binding).isRegistered)
    #expect(GlobalHotkey.State.registered(binding).explanation == nil)

    for state: GlobalHotkey.State in [
        .off,
        .takenByAnotherApp(binding),
        .unusableKey(binding),
        .failed(binding, -9878),
    ] where state != .off {
        #expect(!state.isRegistered)
        #expect(state.explanation != nil, "\(state) non dice perché")
    }
    // `off` is not a failure and must not be explained as one.
    #expect(GlobalHotkey.State.off.explanation == nil)
}

@MainActor
@Test func registeringWithTheSystemReportsWhatTheSystemSaid() {
    let hotkey = GlobalHotkey()

    // A combination nothing sane holds, so this exercises the whole path -
    // `CarbonKey` to `RegisterEventHotKey` to the state - without taking a shortcut
    // away from anything the user might be running.
    let free = KeyBinding("z", [.command, .control, .option, .shift])
    #expect(hotkey.register(free) == .registered(free))
    #expect(hotkey.state.isRegistered)

    // Registering a second one replaces the first rather than stacking: two live
    // registrations would open the panel twice on one press.
    let another = KeyBinding("y", [.command, .control, .option, .shift])
    #expect(hotkey.register(another) == .registered(another))

    hotkey.unregister()
    #expect(hotkey.state == .off)

    // A key with no virtual code never reaches the system at all, and says so.
    let impossible = KeyBinding("f13", .control)
    #expect(hotkey.register(impossible) == .unusableKey(impossible))
    #expect(!hotkey.state.isRegistered)
}

@MainActor
@Test func aCombinationSomebodyElseHoldsComesBackAsTakenAndNotAsSuccess() {
    // The negative control for the test above: without this, `.registered` could be
    // what the type returns no matter what the system said, and every assertion about
    // it would pass while the panel never opened. Two holders of the same combination
    // is exactly what `kEventHotKeyExclusive` exists to refuse.
    let first = GlobalHotkey()
    let second = GlobalHotkey()
    let contested = KeyBinding("x", [.command, .control, .option, .shift])

    #expect(first.register(contested) == .registered(contested))
    #expect(second.register(contested) == .takenByAnotherApp(contested))
    #expect(!second.state.isRegistered)
    #expect(second.state.explanation != nil)

    // Given back, the same combination is free again.
    first.unregister()
    #expect(second.register(contested) == .registered(contested))
    second.unregister()
}

// MARK: - CaptureController

@MainActor
@Test func onlyTheTaskDestinationCarriesDates() {
    // The panel hides the chips on the other three, and the controller must agree:
    // `VaultAPI.capture` refuses a date off a task, so sending one would turn a capture
    // into a refusal the user did not ask for.
    #expect(CaptureController.Destination.task.takesDates)
    #expect(!CaptureController.Destination.note.takesDates)
    #expect(!CaptureController.Destination.today.takesDates)
    #expect(!CaptureController.Destination.existing.takesDates)
}

@MainActor
@Test func anUnsentDraftSurvivesAMinuteAndNotTwo() async throws {
    let controller = CaptureController()
    let opened = Date()
    controller.text = "Mescola per il distretto"

    // Dismissed by accident, reopened straight away: what was typed is still there.
    controller.hold(now: opened)
    controller.prepare(now: opened.addingTimeInterval(30))
    #expect(controller.text == "Mescola per il distretto")

    // Left for good: the panel opens empty rather than with a thought from yesterday.
    controller.hold(now: opened)
    controller.prepare(now: opened.addingTimeInterval(CaptureController.draftLifetime + 1))
    #expect(controller.text.isEmpty)
}

@MainActor
@Test func anEmptyPanelHoldsNothingAndSaysItIsEmpty() {
    let controller = CaptureController()
    controller.text = "   \n  "
    #expect(controller.isEmpty)
    // Nothing to keep, so nothing is kept: a whitespace draft would otherwise sit there
    // stopping the placeholder from showing.
    controller.hold()
    controller.prepare()
    #expect(controller.text == "   \n  ")
}

@MainActor
@Test func capturingWithNoVaultOpenIsARefusalAndNotASilentNothing() {
    let controller = CaptureController()
    controller.text = "Appunto"

    #expect(!controller.capture(into: nil))
    #expect(controller.outcome == .refused("nessuna cartella note aperta"))
}

@MainActor
@Test func theExistingNoteDestinationRefusesUntilANoteIsChosen() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-17\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "Nota.md")
    let session = VaultSession(root: vault.root)
    await session.rescan()

    let controller = CaptureController()
    controller.destination = .existing
    controller.text = "Riga"

    // Refused, and the panel stays open holding the text: it is the only copy of it.
    #expect(!controller.capture(into: session))
    #expect(controller.outcome != nil)
    #expect(controller.text == "Riga")

    controller.notePath = "Nota.md"
    #expect(controller.capture(into: session))
    #expect(controller.outcome == .wrote(path: "Nota.md"))
    // Cleared only once it went through.
    #expect(controller.text.isEmpty)
}

@MainActor
@Test func aCaptureWritesThroughTheConnectorsDoorAndNotAroundIt() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root)
    await session.rescan()

    let controller = CaptureController()
    controller.destination = .today
    controller.text = "Deciso il fornitore"

    #expect(controller.capture(into: session))
    let path = session.dailyNotePath(for: .today)
    let onDisk = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(onDisk.contains("Deciso il fornitore"))
    // The conformant frontmatter is there, which is the proof it went through
    // `dailyNote(for:)` rather than through a second path of the panel's own.
    #expect(onDisk.contains("type-note"))
}

@MainActor
@Test func theDatesReachTheTaskLineInTheFormTheParserReadsBack() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root)
    await session.rescan()

    let controller = CaptureController()
    controller.destination = .task
    controller.text = "Richiamare Rossi"
    controller.scheduled = CalendarDate(iso: "2026-08-20")
    controller.due = CalendarDate(iso: "2026-08-25")

    #expect(controller.capture(into: session))
    let onDisk = try String(
        contentsOf: vault.root.appending(path: VaultSession.TaskDestination.inboxPath),
        encoding: .utf8
    )
    #expect(onDisk.contains("- [ ] Richiamare Rossi >2026-08-20 !2026-08-25"))
}
