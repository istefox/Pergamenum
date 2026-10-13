import SwiftUI
import Testing
@testable import Pergamenum

// PG-409: `navigation.classifying` names a path of the open notes folder. Nothing disables
// «Apri cartella note…» or «Cartelle recenti» while the «Classifica…» sheet is up, so either can
// switch folders under it, and the sheet's confirm would then classify that relative path against
// the next session. `vaultScopedNavigation()` is hosted for real in a window that is never shown
// (`Tests/HostedViewSupport.swift`) and the real `switchVault(to:ask:)` and `close()` move
// `vault.root` under it. These tests pin the modifier, not its wiring: the one line in
// `Sources/App/RootView.swift` that applies `.vaultScopedNavigation()` is not exercised
// in-process, and removing it would leave this file green. That line is covered by hand only.

private let sharedPath = "00 Inbox/Idea.md"

@MainActor
@Test func aSwitchToAnotherFolderClosesTheClassificaSheetAndTheTreeSelection() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try a.write(captureNote("Di A."), to: sharedPath)
    // B has a capture at the same relative path: a sheet kept open would classify B's file.
    try b.write(captureNote("Di B."), to: sharedPath)
    let app = try await NoteBirthApp.make(a)
    let host = app.hosted(Color.clear.vaultScopedNavigation(), size: CGSize(width: 200, height: 100))
    defer { host.tearDown() }
    await host.settle()
    app.navigation.classifying = .note(sharedPath)
    app.navigation.noteTreeSelection = [sharedPath]

    let switched = await app.vault.switchVault(to: b.root) { _ in
        Issue.record("no dirty tab: nothing to ask")
        return .cancel
    }
    try #require(switched)
    await host.settle()

    #expect(app.navigation.classifying == nil, "the sheet named a path of the folder left")
    #expect(app.navigation.noteTreeSelection.isEmpty, "n1-seams R-11")
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
    app.vault.close()
}

@MainActor
@Test func closingTheFolderClosesTheClassificaSheet() async throws {
    let a = try TemporaryVault()
    try a.write(captureNote("Di A."), to: sharedPath)
    let app = try await NoteBirthApp.make(a)
    let host = app.hosted(Color.clear.vaultScopedNavigation(), size: CGSize(width: 200, height: 100))
    defer { host.tearDown() }
    await host.settle()
    app.navigation.classifying = .note(sharedPath)

    app.vault.close()
    await host.settle()

    #expect(app.navigation.classifying == nil)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func reopeningTheSameFolderKeepsTheClassificaSheet() async throws {
    let a = try TemporaryVault()
    try a.write(captureNote("Di A."), to: sharedPath)
    let app = try await NoteBirthApp.make(a)
    let host = app.hosted(Color.clear.vaultScopedNavigation(), size: CGSize(width: 200, height: 100))
    defer { host.tearDown() }
    await host.settle()
    app.navigation.classifying = .note(sharedPath)

    let switched = await app.vault.switchVault(to: a.root) { _ in
        Issue.record("the same folder: nothing to ask")
        return .cancel
    }
    try #require(switched)
    await host.settle()

    #expect(app.navigation.classifying == .note(sharedPath), "the path still names this folder's note")
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
    app.vault.close()
}

@MainActor
@Test func reopeningTheSameFolderThroughAnotherSpellingKeepsTheClassificaSheet() async throws {
    let a = try TemporaryVault()
    try a.write(captureNote("Di A."), to: sharedPath)
    // A link to the same folder: `switchVault` compares by `vaultKey` and finds the folder open,
    // but the session it opens keeps the spelling it was given, so `vault.root` itself moves.
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a.root)
    defer { try? FileManager.default.removeItem(at: link) }
    let app = try await NoteBirthApp.make(a)
    let host = app.hosted(Color.clear.vaultScopedNavigation(), size: CGSize(width: 200, height: 100))
    defer { host.tearDown() }
    await host.settle()
    let before = try #require(app.vault.root)
    app.navigation.classifying = .note(sharedPath)
    app.navigation.unfiledSelection = sharedPath

    let switched = await app.vault.switchVault(to: link) { _ in
        Issue.record("the same folder: nothing to ask")
        return .cancel
    }
    try #require(switched)
    await host.settle()

    let after = try #require(app.vault.root)
    #expect(after != before, "the test must reopen under another spelling of the URL")
    #expect(after.vaultKey == before.vaultKey)
    #expect(app.navigation.classifying == .note(sharedPath), "the same folder: the sheet is still valid")
    #expect(app.navigation.unfiledSelection == sharedPath)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
    app.vault.close()
}

@MainActor
@Test func aSwitchToAnotherFolderForgetsEveryRequestASheetHolds() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try a.write(captureNote("Di A."), to: sharedPath)
    let app = try await NoteBirthApp.make(a)
    let host = app.hosted(Color.clear.vaultScopedNavigation(), size: CGSize(width: 200, height: 100))
    defer { host.tearDown() }
    await host.settle()
    let task = try #require(TaskParser.tasks(in: "- [ ] Una cosa\n", sourcePath: sharedPath).first)
    let navigation = app.navigation
    navigation.unfiledSelection = sharedPath
    navigation.taskPickingBoard = task
    navigation.taskPickingCategory = task
    navigation.praticaLinkRequest = PraticaLinkRequest(
        kind: .note, scope: .pratica(path: "Pratiche/Rossi/pratica.md"), contextTitle: "Rossi", contextTags: []
    )
    navigation.linkChoice = LinkChoiceRequest(
        id: UUID(), title: "Idea",
        choices: [
            LinkChoice(id: "open:\(sharedPath)", label: "Inbox", detail: sharedPath, action: .open(path: sharedPath))
        ],
        how: .replace, sourcePath: sharedPath
    )
    navigation.categoryEditorTarget = .editing(Category(slug: "rossi", name: "Rossi", color: "rosso"))
    navigation.categoryLinkingNote = .init(slug: "rossi", name: "Rossi")

    let switched = await app.vault.switchVault(to: b.root) { _ in
        Issue.record("no dirty tab: nothing to ask")
        return .cancel
    }
    try #require(switched)
    await host.settle()

    #expect(navigation.unfiledSelection == nil)
    #expect(navigation.taskPickingBoard == nil)
    #expect(navigation.taskPickingCategory == nil)
    #expect(navigation.praticaLinkRequest == nil)
    #expect(navigation.linkChoice == nil)
    #expect(navigation.categoryEditorTarget == nil)
    #expect(navigation.categoryLinkingNote == nil)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
    app.vault.close()
}
