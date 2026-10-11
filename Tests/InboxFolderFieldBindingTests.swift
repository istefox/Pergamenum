import Foundation
import Testing
@testable import Pergamenum

// note-workflow R-10: the inbox folder is a vault setting edited in Impostazioni > Convenzioni.
//
// `InboxFolderField` (SettingsView.swift, private) binds a text field to exactly two things:
// `VaultController.settings.inboxFolder` for the read and `VaultController.updateSettings`
// for the write. This file pins that pair, which is the part of the field a test can reach
// without a window; that the field is drawn in Convenzioni is a hand check.

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async -> VaultController {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func theFieldReadsTheDefaultWhenTheSettingIsAbsent() async throws {
    let vault = try TemporaryVault()
    let controller = await controller(vault)
    defer { controller.close() }

    #expect(controller.settings.inboxFolder == VaultSettings.defaultInboxFolder) // (note-workflow R-10)
    #expect(controller.session?.inboxFolder == "00 Inbox")
}

@MainActor
@Test func aValueTypedInTheFieldIsKeptAsTypedAndReadBackResolved() async throws {
    let vault = try TemporaryVault()
    let controller = await controller(vault)
    defer { controller.close() }

    // A trailing space is what the field holds between two keystrokes: stored untouched,
    // resolved (trimmed) on every read.
    controller.updateSettings { $0.inboxFolder = "Triage " }

    #expect(controller.settings.inboxFolder == "Triage ") // (note-workflow R-10)
    #expect(controller.session?.inboxFolder == "Triage")
}

@MainActor
@Test func theFieldsValueReachesTheNextOpenOfTheVault() async throws {
    let vault = try TemporaryVault()
    let first = await controller(vault)
    first.updateSettings { $0.inboxFolder = "Triage" }
    first.close()

    let second = await controller(vault)
    defer { second.close() }

    #expect(second.settings.inboxFolder == "Triage") // (note-workflow R-10)
    #expect(second.session?.inboxFolder == "Triage")
}

@MainActor
@Test func aValueTheRulesRefuseReadsAsTheDefaultThroughTheSession() async throws {
    let vault = try TemporaryVault()
    let controller = await controller(vault)
    defer { controller.close() }

    controller.updateSettings { $0.inboxFolder = "../Fuori" }

    #expect(controller.session?.inboxFolder == VaultSettings.defaultInboxFolder) // (note-workflow R-10)
}
