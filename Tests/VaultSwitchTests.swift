import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-334: before another vault replaces the session, `switchVault(to:ask:)` reviews the dirty
// tabs of every column with the quit's machinery; «Annulla», a failed save or a conflicted tab
// keeps vault A open and untouched, otherwise the tabs start empty and vault B's own come back.

/// Vault B: its own `Nexion.md`, which a stale write from vault A would overwrite, and a note
/// only B has, remembered as B's open tab.
@MainActor
private func vaultB(_ vault: borrowing TemporaryVault, rememberedIn controller: VaultController) throws {
    try vault.write(quitNote("Nexion di B."), to: "Nexion.md")
    try vault.write(quitNote("Solo di B."), to: "SoloB.md")
    controller.openTabs.remember(
        OpenTabsStore.Session(columns: [
            .init(entries: [.init(path: "SoloB.md", isPreview: false)], activePath: "SoloB.md"),
        ]),
        for: vault.root
    )
}

@MainActor
private func tabPaths(_ controller: VaultController) -> [String] {
    controller.columns.flatMap(\.tabs).map(\.note.relativePath)
}

@MainActor
@Test func annullaKeepsTheOpenVaultAndItsDirtyTab() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }

    #expect(!switched)
    #expect(asked == 1)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    controller.close()
}

@MainActor
@Test func nonSalvareOpensTheOtherVaultWithOnlyItsOwnTabs() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    _ = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    _ = try openDirty("Dopo.md", adding: "\nDi A.\n", inColumn: 1, of: controller)

    let switched = await controller.switchVault(to: rootB) { _ in .discard }

    #expect(switched)
    #expect(controller.root?.vaultKey == rootB.vaultKey)
    #expect(tabPaths(controller) == ["SoloB.md"])
    #expect(controller.columns.count == 1)
    #expect(!controller.columns.flatMap(\.tabs).contains { $0.isFromPreviousVault })
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(quitOnDisk(rootB, "Dopo.md") == nil)
    // A's arrangement was remembered for A, and comes back when A opens again.
    let rememberedA = controller.openTabs.session(for: rootA).columns.flatMap(\.entries).map(\.path)
    #expect(rememberedA.contains("Nexion.md"))

    let back = await controller.switchVault(to: rootA) { _ in
        Issue.record("B has no dirty tab: nothing to ask")
        return .cancel
    }

    #expect(back)
    #expect(tabPaths(controller).contains("Nexion.md"))
    #expect(!tabPaths(controller).contains("SoloB.md"))
    #expect(!controller.columns.flatMap(\.tabs).contains { $0.note.hasUnsavedChanges })
    controller.close()
}

@MainActor
@Test func salvaWritesTheTabIntoItsOwnVaultBeforeTheSwitch() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    _ = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(switched)
    #expect(quitOnDisk(rootA, "Nexion.md")?.contains("Di A.") == true)
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(controller.root?.vaultKey == rootB.vaultKey)
    #expect(tabPaths(controller) == ["SoloB.md"])
    controller.close()
}

@MainActor
@Test func aFailedSaveCancelsTheSwitchAndKeepsTheTab() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Progetti/Sospensione.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    let switched = try await withReadOnlyFolder(rootA, "Progetti") {
        await controller.switchVault(to: rootB) { _ in .save }
    }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.focusedTab?.id == id)
    #expect(controller.problems.contains { $0.contains("annullata") && $0.contains("Sospensione.md") })
    controller.close()
}

@MainActor
@Test func aConflictedTabLeftUnsavedCancelsTheSwitch() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    controller.updateTab(id) { $0.note.externalChangePending = .text(quitNote("Da fuori.")) }

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    controller.close()
}

@MainActor
@Test func reopeningTheSameVaultAsksNothingAndKeepsTheTabs() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    var asked = 0

    let switched = await controller.switchVault(to: rootA) { _ in
        asked += 1
        return .cancel
    }

    #expect(switched)
    #expect(asked == 0)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    controller.close()
}

@MainActor
@Test func theSwitchQuestionHasItsOwnWordsAndIdentifiers() {
    var column = EditorColumn()
    column.tabs = [NoteTab(note: VaultController.OpenNote(
        relativePath: "Nexion.md", title: "Nexion", text: "x", savedText: "y"
    ))]
    let copy = QuitReview(columns: [column]).copy(for: .vaultSwitch)

    #expect(copy.message == "Salvare le modifiche a «Nexion» prima di aprire un'altra cartella note?")
    #expect(!copy.informative.contains("Uscendo"))
    // Literal: a UI test would spell the same strings.
    #expect(QuitReviewAlert.make(copy, for: .vaultSwitch).buttons.map { $0.accessibilityIdentifier() } == [
        "vault-switch-prompt-save", "vault-switch-prompt-cancel", "vault-switch-prompt-discard",
    ])
}

// `restoreVersion` refuses a previous vault's tab like `saveTab(_:)` does. Reached below the
// door, through `open(_:)` directly, which still lets a tab survive.

@MainActor
@Test func restoreVersionOnATabOfThePreviousVaultWritesNothing() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Nexion.md")
    let id = try #require(controller.focusedTab?.id)
    await controller.open(rootB)
    controller.revealTab(id)
    #expect(controller.focusedTab?.isFromPreviousVault == true)

    await controller.restoreVersion(quitNote("Versione passata."))

    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(controller.problems.contains { $0.contains("Nexion.md") && $0.contains("aperta prima") })
    controller.close()
}

// Added by the tester: the second column, text typed during the saves, and B's restored tabs.

@MainActor
@Test func theQuestionCoversTheDirtyTabsOfEveryColumnAndSalvaWritesBoth() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    _ = try openDirty("Nexion.md", adding: "\nColonna uno.\n", inColumn: 0, of: controller)
    _ = try openDirty("Dopo.md", adding: "\nColonna due.\n", inColumn: 1, of: controller)
    var shown: [String] = []

    let switched = await controller.switchVault(to: rootB) { review in
        shown = review.entries.map(\.relativePath)
        return .save
    }

    #expect(switched)
    #expect(Set(shown) == ["Nexion.md", "Dopo.md"])
    #expect(quitOnDisk(rootA, "Nexion.md")?.contains("Colonna uno.") == true)
    #expect(quitOnDisk(rootA, "Dopo.md")?.contains("Colonna due.") == true)
    #expect(quitOnDisk(rootB, "Dopo.md") == nil)
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(tabPaths(controller) == ["SoloB.md"])
    controller.close()
}

@MainActor
@Test func aSecondColumnTabAloneStillRaisesTheQuestionAndCancelKeepsIt() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Nexion.md")
    let id = try openDirty("Dopo.md", adding: "\nSolo colonna due.\n", inColumn: 1, of: controller)
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }

    #expect(!switched)
    #expect(asked == 1)
    #expect(controller.columns.count == 2)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(quitOnDisk(rootA, "Dopo.md") == quitNote("Dopo."))
    controller.close()
}

@MainActor
@Test func textTypedDuringTheSavesCancelsTheSwitch() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Nexion.md", adding: "\nPrima.\n", inColumn: 0, of: controller)

    // Scheduled from the question, it runs at the first suspension of the saves, after
    // `saveForQuit` has read the text it writes.
    let switched = await controller.switchVault(to: rootB) { _ in
        Task { @MainActor in
            controller.updateOpenNoteText((controller.openNote?.text ?? "") + "Durante.\n")
        }
        return .save
    }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    let tab = try #require(controller.tab(withID: id))
    #expect(tab.note.hasUnsavedChanges)
    #expect(tab.note.text.contains("Durante."))
    // The interleaving the comment above names really happened: the save took the text as it
    // was before the suspension, and the keystroke typed during it reached no file.
    let onDiskA = quitOnDisk(rootA, "Nexion.md")
    #expect(onDiskA?.contains("Prima.") == true)
    #expect(onDiskA?.contains("Durante.") == false)
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(controller.problems.contains { $0.contains("annullata") && $0.contains("Nexion.md") })
    controller.close()
}

@MainActor
@Test func noPathOfTheLeftVaultSurvivesIntoTheRestoredTabs() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    _ = try openDirty("Dopo.md", adding: "\nx\n", inColumn: 1, of: controller)
    controller.focusColumn(0)

    let switched = await controller.switchVault(to: rootB) { _ in .discard }

    #expect(switched)
    let paths = tabPaths(controller)
    #expect(paths == ["SoloB.md"])
    #expect(!paths.contains("Dopo.md") && !paths.contains("Progetti/Pressa.md"))
    #expect(controller.columns.count == 1)
    #expect(controller.focusedColumnIndex == 0)
    controller.close()
}

// Added in the review loop: what else of the folder being left the switch clears, and the two
// interleavings the door guards against.

/// Vault C: its own `Nexion.md` and one note only C has, remembered as C's open tab.
@MainActor
private func vaultC(_ vault: borrowing TemporaryVault, rememberedIn controller: VaultController) throws {
    try vault.write(quitNote("Nexion di C."), to: "Nexion.md")
    try vault.write(quitNote("Solo di C."), to: "SoloC.md")
    controller.openTabs.remember(
        OpenTabsStore.Session(columns: [
            .init(entries: [.init(path: "SoloC.md", isPreview: false)], activePath: "SoloC.md"),
        ]),
        for: vault.root
    )
}

@MainActor
private func remembered(_ controller: VaultController, _ root: URL) -> [String] {
    controller.openTabs.session(for: root).columns.flatMap(\.entries).map(\.path)
}

/// What the second switch saw when it started, recorded rather than assumed: each interleaving
/// test below asserts it, so an ordering that did not happen fails the test instead of letting
/// it pass on the sequential path.
@MainActor
private final class SecondSwitch {
    var task: Task<Bool, Never>?
    var rootAtStart: URL?
    var wasOpeningAtStart: Bool?
    var shown: [String] = []
    var asked = 0
}

@MainActor
@Test func aComposingDraftOfTheLeftVaultIsEndedBySwitching() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.beginNewNote(in: "Progetti")
    controller.noteDraft?.title = "Bozza di A"
    #expect(controller.isComposingNote)

    let switched = await controller.switchVault(to: rootB) { _ in
        Issue.record("no dirty tab: nothing to ask")
        return .cancel
    }

    #expect(switched)
    #expect(controller.noteDraft == nil)
    #expect(!controller.isComposingNote)
    #expect(!controller.hasParkedDraft)
    #expect(quitOnDisk(rootB, "Progetti/Bozza di A.md") == nil)
    #expect(quitOnDisk(rootB, "Bozza di A.md") == nil)
    #expect(tabPaths(controller) == ["SoloB.md"])
    controller.close()
}

@MainActor
@Test func closedTabsRecentsAndACloseRequestOfTheLeftVaultDoNotSurvive() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    let pressa = try #require(controller.focusedTab?.id)
    controller.closeTab(pressa)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    controller.requestCloseFocusedTab()
    // Preconditions: each list names A's files before the switch.
    #expect(controller.closedTabPaths.contains("Progetti/Pressa.md"))
    #expect(controller.recentNotePaths.contains("Nexion.md"))
    #expect(controller.recentNotePaths.contains("Progetti/Pressa.md"))
    #expect(controller.closeRequest == id)

    let switched = await controller.switchVault(to: rootB) { _ in .discard }

    #expect(switched)
    // B has a `Nexion.md` of its own: a path kept from A would reopen B's file.
    for path in ["Nexion.md", "Progetti/Pressa.md"] {
        #expect(!controller.closedTabPaths.contains(path))
        #expect(!controller.recentNotePaths.contains(path))
    }
    #expect(controller.closeRequest == nil)
    #expect(tabPaths(controller) == ["SoloB.md"])
    controller.close()
}

// The guard after the saves' `await` (ADR-0043 §D7). The second switch is scheduled from the
// first one's question, so it is on the main actor's queue before the first switch reaches the
// saves' actor hop, its first suspension, and runs there: the save's own continuation can only
// be queued after the write finishes. That is the same executor ordering
// `textTypedDuringTheSavesCancelsTheSwitch` relies on, not a gate at the actor boundary: none
// exists on `saveTab`'s write path, and adding one would be a production seam. `SecondSwitch`
// records what the second switch found, so the interleaving is asserted, not assumed.

@MainActor
@Test func aSwitchLandingDuringTheSavesStopsTheFirstOne() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let c = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let rootC = c.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    try vaultC(c, rememberedIn: controller)
    _ = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let second = SecondSwitch()

    let switched = await controller.switchVault(to: rootB) { _ in
        second.task = Task { @MainActor in
            second.rootAtStart = controller.root
            return await controller.switchVault(to: rootC) { review in
                second.shown = review.entries.map(\.relativePath)
                second.asked += 1
                return .discard
            }
        }
        return .save
    }
    let secondSwitched = await second.task?.value

    // The second switch ran while A was still open and its tab still unsaved: during the saves.
    #expect(second.rootAtStart?.vaultKey == rootA.vaultKey)
    #expect(second.asked == 1)
    #expect(second.shown == ["Nexion.md"])
    // The first one stopped rather than open B over C.
    #expect(!switched)
    #expect(secondSwitched == true)
    #expect(controller.root?.vaultKey == rootC.vaultKey)
    #expect(tabPaths(controller) == ["SoloC.md"])
    #expect(remembered(controller, rootC) == ["SoloC.md"])
    #expect(remembered(controller, rootA).contains("Nexion.md"))
    // The save that was under way landed in its own folder and nowhere else.
    #expect(quitOnDisk(rootA, "Nexion.md")?.contains("Di A.") == true)
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(quitOnDisk(rootC, "Nexion.md") == quitNote("Nexion di C."))
    #expect(!controller.routeState.isOpeningVault)
    controller.close()
}

// The `isOpeningVault` guard. The second switch is scheduled from the first one's question and
// runs at the first one's first suspension, the scan inside `open(_:)`: B's session is in place,
// `columns` is empty and B's tabs are not restored yet. Same ordering argument as above.

@MainActor
@Test func aSwitchWhileAFolderIsOpeningDoesNothingAndKeepsItsTabs() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let c = try TemporaryVault()
    let rootB = b.root
    let rootC = c.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    try vaultC(c, rememberedIn: controller)
    _ = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let second = SecondSwitch()

    let switched = await controller.switchVault(to: rootB) { _ in
        second.task = Task { @MainActor in
            second.rootAtStart = controller.root
            second.wasOpeningAtStart = controller.routeState.isOpeningVault
            return await controller.switchVault(to: rootC) { _ in
                second.asked += 1
                return .discard
            }
        }
        return .discard
    }
    let secondSwitched = await second.task?.value

    // The second switch ran inside B's opening.
    #expect(second.wasOpeningAtStart == true)
    #expect(second.rootAtStart?.vaultKey == rootB.vaultKey)
    // And did nothing: no question, no C, and B's remembered tabs were not overwritten with the
    // empty arrangement of a folder still being opened.
    #expect(secondSwitched == false)
    #expect(second.asked == 0)
    #expect(switched)
    #expect(controller.root?.vaultKey == rootB.vaultKey)
    #expect(tabPaths(controller) == ["SoloB.md"])
    #expect(remembered(controller, rootB) == ["SoloB.md"])
    #expect(remembered(controller, rootC) == ["SoloC.md"])
    #expect(!controller.routeState.isOpeningVault)
    controller.close()
}

// PG-348: a state base that cannot be resolved. It is reached through
// `VaultController.resolveStateBase`, replaced on this controller alone, never through the
// process-wide defaults `VaultState.processDefaultBase()` reads and every other test shares.
//
// `switchVault` resolves it first, right after the `isOpeningVault` guard: when it fails, the
// switch records a problem and returns before asking, saving or clearing anything, so a dirty
// buffer keeps its text and its tab, and the composer's draft, the reopenable closed tabs and the
// quick switcher's recents all survive. `open(_:)` alone records a problem too. Every test counts
// the resolver's calls, so a bail is proved to come from the resolver and from the expected call.
//
// The branch after `open(_:)` (`session === leaving`, then `restoreTabs()`) stays reachable only
// when the base resolves for the preflight and fails inside `open(_:)`; the last test drives it.

private struct UnresolvableStateBase: Error {}

/// Each column's tab paths, in order, and each column's active path.
@MainActor
private func arrangement(_ controller: VaultController) -> (tabs: [[String]], active: [String?]) {
    (
        controller.columns.map { $0.tabs.map(\.note.relativePath) },
        controller.columns.map { $0.active?.note.relativePath }
    )
}

/// How many problems name the state base, from the switch's preflight or from `open(_:)`.
@MainActor
private func stateBaseProblems(_ controller: VaultController, from door: StateBaseDoor) -> Int {
    controller.problems.filter { $0.hasPrefix(door.rawValue) && $0.contains("Application Support") }.count
}

private enum StateBaseDoor: String {
    case switchPreflight = "Apertura di un'altra cartella note annullata"
    case open = "Apertura della cartella note annullata"
}

@MainActor
@Test func aSwitchWithAnUnresolvableStateBaseAsksNothingAndKeepsTheDirtyTab() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    controller.addColumn()
    controller.focusColumn(1)
    controller.openNoteInNewTab(at: "Dopo.md")
    let dirty = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let before = arrangement(controller)
    #expect(before.tabs == [["Progetti/Pressa.md", "Nexion.md"], ["Dopo.md"]])
    #expect(before.active == ["Nexion.md", "Dopo.md"])
    #expect(controller.focusedColumnIndex == 0 && !controller.recentNotePaths.isEmpty)
    let recentsBefore = controller.recentNotePaths
    let closedBefore = controller.closedTabPaths
    let rememberedABefore = remembered(controller, rootA)
    let sessionA = try #require(controller.session)
    let watcherA = try #require(controller.watcher)
    var resolved = 0
    controller.resolveStateBase = {
        resolved += 1
        throw UnresolvableStateBase()
    }
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .discard
    }

    #expect(!switched)
    // The preflight bailed before the question, and `open(_:)` was never reached.
    #expect(asked == 0)
    #expect(resolved == 1)
    #expect(stateBaseProblems(controller, from: .switchPreflight) == 1)
    #expect(stateBaseProblems(controller, from: .open) == 0)
    // A is still the open folder: the same session, still watched by the same watcher, still
    // the subscriber's session (ADR-0067 §D4), no opening left half done.
    #expect(controller.session === sessionA)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.watcher === watcherA)
    #expect(sessionA.landedChangeSubscriber != nil)
    #expect(!controller.routeState.isOpeningVault)
    // Nothing was cleared: the same arrangement, and the dirty buffer is the same tab, text kept.
    let after = arrangement(controller)
    #expect(after.tabs == before.tabs)
    #expect(after.active == before.active)
    #expect(controller.focusedColumnIndex == 0)
    #expect(!controller.columns.flatMap(\.tabs).contains { $0.isFromPreviousVault })
    let tab = try #require(controller.tab(withID: dirty))
    #expect(tab.note.hasUnsavedChanges)
    #expect(tab.note.text.contains("Di A."))
    #expect(controller.recentNotePaths == recentsBefore)
    #expect(controller.closedTabPaths == closedBefore)
    // Nothing written anywhere, and neither folder's remembered arrangement touched.
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(remembered(controller, rootB) == ["SoloB.md"])
    #expect(remembered(controller, rootA) == rememberedABefore)
    controller.close()
}

@MainActor
@Test func aSwitchWithAnUnresolvableStateBaseKeepsTheDraftTheClosedTabsAndTheRecents() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    let pressa = try #require(controller.focusedTab?.id)
    controller.closeTab(pressa)
    controller.openNoteInNewTab(at: "Nexion.md")
    controller.beginNewNote(in: "Progetti")
    controller.noteDraft?.title = "Bozza di A"
    // Preconditions: what a switch would clear names A's files before it.
    #expect(controller.isComposingNote)
    #expect(controller.closedTabPaths == ["Progetti/Pressa.md"])
    #expect(controller.recentNotePaths.contains("Nexion.md"))
    let recentsBefore = controller.recentNotePaths
    let tabsBefore = arrangement(controller).tabs
    let sessionA = try #require(controller.session)
    let watcherA = try #require(controller.watcher)
    var resolved = 0
    controller.resolveStateBase = {
        resolved += 1
        throw UnresolvableStateBase()
    }
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }

    #expect(!switched)
    #expect(asked == 0)
    #expect(resolved == 1)
    #expect(stateBaseProblems(controller, from: .switchPreflight) == 1)
    #expect(controller.session === sessionA)
    #expect(controller.watcher === watcherA)
    #expect(arrangement(controller).tabs == tabsBefore)
    // The preflight bailed before the switch cleared anything: the draft is still being
    // composed, the closed tab is still reopenable and the recents are A's own.
    #expect(controller.isComposingNote)
    #expect(controller.noteDraft?.title == "Bozza di A")
    #expect(controller.closedTabPaths == ["Progetti/Pressa.md"])
    #expect(controller.recentNotePaths == recentsBefore)
    #expect(quitOnDisk(rootA, "Progetti/Bozza di A.md") == nil)
    #expect(quitOnDisk(rootB, "Progetti/Bozza di A.md") == nil)
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    controller.close()
}

@MainActor
@Test func openAloneWithAnUnresolvableStateBaseLeavesTheOpenVaultUntouched() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let sessionA = try #require(controller.session)
    let watcherA = try #require(controller.watcher)
    let generation = controller.indexGeneration
    var resolved = 0
    controller.resolveStateBase = {
        resolved += 1
        throw UnresolvableStateBase()
    }

    await controller.open(rootB)

    #expect(resolved == 1)
    // With a session open, the bail tells the person why nothing changed.
    #expect(stateBaseProblems(controller, from: .open) == 1)
    #expect(controller.session === sessionA)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.watcher === watcherA)
    #expect(sessionA.landedChangeSubscriber != nil)
    #expect(controller.indexGeneration == generation)
    #expect(!controller.routeState.isOpeningVault)
    // `open(_:)` keeps `columns` by design; on a bail it does not even mark the tab foreign.
    let tab = try #require(controller.tab(withID: id))
    #expect(tab.note.hasUnsavedChanges)
    #expect(!tab.isFromPreviousVault)
    #expect(arrangement(controller).tabs == [["Nexion.md"]])
    #expect(remembered(controller, rootB) == ["SoloB.md"])
    controller.close()
}

@MainActor
@Test func aSwitchWithAnUnresolvableStateBaseSavesNothingEvenBeforeSalva() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let sessionA = try #require(controller.session)
    var resolved = 0
    controller.resolveStateBase = {
        resolved += 1
        throw UnresolvableStateBase()
    }
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .save
    }

    #expect(!switched)
    #expect(asked == 0)
    #expect(resolved == 1)
    #expect(stateBaseProblems(controller, from: .switchPreflight) == 1)
    // No «Salva» was ever answered: A's file is unchanged and nothing reached B.
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(remembered(controller, rootB) == ["SoloB.md"])
    // A stays the open folder, and the same tab still holds the unsaved edit.
    #expect(controller.session === sessionA)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(arrangement(controller).tabs == [["Nexion.md"]])
    let tab = try #require(controller.tab(withID: id))
    #expect(tab.note.hasUnsavedChanges)
    #expect(tab.note.text.contains("Di A."))
    controller.close()
}

// The base resolves for the preflight and fails inside `open(_:)`: the only way left to the
// branch after `open(_:)`. A's arrangement comes back through `restoreTabs()`, re-read from disk.

@MainActor
@Test func aStateBaseLostAfterThePreflightRestoresTheLeftVaultsTabs() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    try vaultB(b, rememberedIn: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    controller.addColumn()
    controller.focusColumn(1)
    controller.openNoteInNewTab(at: "Dopo.md")
    _ = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let before = arrangement(controller)
    #expect(before.tabs == [["Progetti/Pressa.md", "Nexion.md"], ["Dopo.md"]])
    let sessionA = try #require(controller.session)
    let watcherA = try #require(controller.watcher)
    var resolved = 0
    controller.resolveStateBase = {
        resolved += 1
        if resolved == 1 { return try VaultState.processDefaultBase() }
        throw UnresolvableStateBase()
    }
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .discard
    }

    #expect(!switched)
    #expect(asked == 1)
    // Once by the preflight, once by `open(_:)`, which is where it bailed.
    #expect(resolved == 2)
    #expect(stateBaseProblems(controller, from: .switchPreflight) == 0)
    #expect(stateBaseProblems(controller, from: .open) == 1)
    #expect(controller.session === sessionA)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.watcher === watcherA)
    #expect(sessionA.landedChangeSubscriber != nil)
    #expect(!controller.routeState.isOpeningVault)
    // A's arrangement is back, column by column, in order, with the same tabs in front.
    let after = arrangement(controller)
    #expect(after.tabs == before.tabs)
    #expect(after.active == before.active)
    #expect(controller.focusedColumnIndex == 0)
    #expect(!controller.columns.flatMap(\.tabs).contains { $0.isFromPreviousVault })
    // «Non salvare» covered the buffer: the restored tab shows A's file as it is on disk.
    #expect(controller.openNote?.text == quitNote("Nexion."))
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    #expect(quitOnDisk(rootB, "Nexion.md") == quitNote("Nexion di B."))
    #expect(remembered(controller, rootB) == ["SoloB.md"])
    controller.close()
}
