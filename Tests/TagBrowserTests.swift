import Foundation
import Testing
@testable import Pergamenum

// The tag browser of ADR-0012 slice 3: narrowing to the notes that carry every chosen tag, and
// the pins that keep a tag at the top of the list.
//
// The pane itself is not reachable from here - it is rows, a split and a context menu, which is
// the category of thing this project has learned to check on screen. What *is* reachable is the
// filter and the store, and both are here rather than inside the view for that reason.

private func note(tags: [String]) -> String {
    """
    ---
    date: 2026-08-19
    tags:
    \(tags.map { "  - \($0)" }.joined(separator: "\n"))
    ---

    Testo.
    """
}

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note(tags: ["type-note", "client-nexion", "topic-gomma"]), to: "Nexion.md")
    try vault.write(note(tags: ["type-note", "topic-gomma"]), to: "Curva.md")
    try vault.write(note(tags: ["type-note", "client-nexion"]), to: "Offerta.md")
    try vault.write(note(tags: ["type-note", "topic-gomma-metallo"]), to: "Metallo.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

/// Swift Testing has a `Tag` of its own, for labelling tests, so the bare name is ambiguous in
/// this target. Aliased rather than written out at every use: `#require(Pergamenum.Tag(raw))`
/// does not compile - the macro cannot make sense of the module-qualified name.
private typealias VaultTag = Pergamenum.Tag

private func tag(_ raw: String) throws -> VaultTag {
    try #require(VaultTag(raw))
}

// MARK: Narrowing (AND)

@MainActor
@Test func oneTagAnswersEveryNoteCarryingIt() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let notes = session.index.notes(carryingAll: [try tag("topic-gomma")])

    #expect(notes.map(\.title) == ["Curva", "Nexion"])
}

@MainActor
@Test func twoTagsLeaveOnlyTheNotesCarryingBoth() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let notes = session.index.notes(carryingAll: [
        try tag("topic-gomma"), try tag("client-nexion"),
    ])

    // AND and not OR: `Curva` and `Offerta` carry one each and neither survives.
    #expect(notes.map(\.title) == ["Nexion"])
}

@MainActor
@Test func aTagThatIsThePrefixOfAnotherIsNotTheSameTag() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let notes = session.index.notes(carryingAll: [try tag("topic-gomma")])

    // `topic-gomma-metallo` is its own tag, not a longer spelling of this one.
    #expect(!notes.map(\.title).contains("Metallo"))
}

@MainActor
@Test func noTagChosenAnswersNothingRatherThanEverything() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    // The browser with an empty filter is asking a question, not selecting the vault.
    #expect(session.index.notes(carryingAll: []).isEmpty)
}

@MainActor
@Test func theCountsAreTheNotesCarryingEachTag() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let usage = Dictionary(uniqueKeysWithValues: session.index.tagUsage().map { ($0.tag, $0.count) })

    #expect(usage[try tag("topic-gomma")] == 2)
    #expect(usage[try tag("client-nexion")] == 2)
    #expect(usage[try tag("topic-gomma-metallo")] == 1)
    #expect(usage[try tag("type-note")] == 4)
}

// MARK: Pinning

@Test func aVaultWithNoPinsHasNone() throws {
    let vault = try TemporaryVault()

    #expect(PinnedTagsStore.volatile().tags(for: vault.root).isEmpty)
}

@Test func pinsComeBackInTheOrderTheyWerePinned() throws {
    let vault = try TemporaryVault()
    let store = PinnedTagsStore.volatile()

    store.remember([try tag("topic-gomma"), try tag("client-nexion")], for: vault.root)

    #expect(store.tags(for: vault.root).map(\.description) == ["topic-gomma", "client-nexion"])
}

@Test func aStoredStringThatIsNotATagIsSkippedRatherThanFailingTheRest() throws {
    let vault = try TemporaryVault()
    let defaults = try #require(UserDefaults(suiteName: "pergamenum.tests.\(UUID())"))
    defaults.set(["non un tag", "topic-gomma"], forKey: PinnedTagsStore.key(for: vault.root))

    // SPEC §4.4 closes the grammar and this file is not where it is widened.
    #expect(PinnedTagsStore(defaults: defaults).tags(for: vault.root).map(\.description) == ["topic-gomma"])
}

@MainActor
@Test func pinningAndUnpinningThroughTheControllerSurvivesReopening() async throws {
    let vault = try TemporaryVault()
    _ = try await session(vault)
    let store = PinnedTagsStore.volatile()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile(), pinnedTags: store)
    await controller.open(vault.root)

    controller.togglePin(try tag("topic-gomma"))
    controller.togglePin(try tag("client-nexion"))

    #expect(controller.pinnedTags.map(\.description) == ["topic-gomma", "client-nexion"])
    #expect(controller.isPinned(try tag("topic-gomma")))

    controller.togglePin(try tag("topic-gomma"))
    #expect(controller.pinnedTags.map(\.description) == ["client-nexion"])

    // The next launch reads the store, not this controller.
    let reopened = VaultController(recents: .volatile(), openTabs: .volatile(), pinnedTags: store)
    await reopened.open(vault.root)
    #expect(reopened.pinnedTags.map(\.description) == ["client-nexion"])
    reopened.close()
    controller.close()
}

// MARK: - Task 6 (R-07): what `TagBrowserView` reads from the controller

// `FinishedRename`/`TagRenameBanner`/`perform(renameOf:to:)` are private to the view and stay
// unreachable here (`@testable import` widens `internal`, not `private`) - the pane itself is
// UI-test territory (this file's own header), and standing rule 8 adds none in this task. What
// is reachable, and is the view's only source for `refusals`, is `VaultController.renameTag`/
// `undoJournalledWrites`: both are a bare pass-through of `VaultSession.TagRenameOutcome`
// (`Sources/App/VaultController+Files.swift`), never a second construction of it, so this pins
// that the new field survives the controller layer rather than re-testing `VaultSession.renameTag`
// itself (`Tests/TagRenameTests.swift`'s Task 3 tests already own that).
@MainActor
@Test func renameTagThroughTheControllerCarriesRefusalsThroughUnchanged() async throws {
    let vault = try TemporaryVault()
    _ = try await session(vault)
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let outcome = await controller.renameTag(try tag("topic-gomma"), to: try tag("topic-fune"))

    #expect(outcome.changed.sorted() == ["Curva.md", "Nexion.md"])
    #expect(outcome.refusals.isEmpty)

    let undone = await controller.undoJournalledWrites(outcome.journalIDs)

    #expect(undone.changed.count == 2)
    #expect(undone.refusals.isEmpty)

    controller.close()
}
