import Foundation
import Testing
@testable import Pergamenum

// PG-384 (N1 seams), ADR-0080 §D5: `VaultSettings.inboxFolder` and the one resolver every
// reader goes through. Modelled on `PraticheSettingsTests`: the decode with and without the
// key, then the resolver against a temporary root.

// MARK: - The key

// (n1-seams R-16)
@Test func aSettingsFileWithoutTheKeyDecodesToTheDefaultInboxFolder() throws {
    let settings = try JSONDecoder().decode(
        VaultSettings.self, from: Data(#"{"dailyFolder": "Calendar"}"#.utf8)
    )

    #expect(settings.inboxFolder == "00 Inbox")
    #expect(VaultSettings.defaultInboxFolder == "00 Inbox")
    #expect(VaultSettings.default.inboxFolder == VaultSettings.defaultInboxFolder)
}

// (n1-seams R-16)
@Test func aSettingsFileWithTheKeyDecodesToItsValue() throws {
    let settings = try JSONDecoder().decode(
        VaultSettings.self, from: Data(#"{"inboxFolder": "Triage"}"#.utf8)
    )

    #expect(settings.inboxFolder == "Triage")
}

// (n1-seams R-16)
@Test func theMemberwiseInitialiserDefaultsTheInboxFolderAsItsLastParameter() {
    let settings = VaultSettings(
        dailyFolder: "Calendar", copyDroppedFiles: true, boardShowsGrid: true, boardSnapsToGrid: false
    )
    #expect(settings.inboxFolder == VaultSettings.defaultInboxFolder)

    let named = VaultSettings(
        dailyFolder: "Calendar", copyDroppedFiles: true, boardShowsGrid: true, boardSnapsToGrid: false,
        inboxFolder: "Triage"
    )
    #expect(named.inboxFolder == "Triage")
}

// (n1-seams R-16)
@MainActor
@Test func theInboxFolderSurvivesThroughSettingsJSON() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    session.updateSettings { $0.inboxFolder = "Triage" }

    #expect(VaultSession.readSettings(in: vault.root).settings.inboxFolder == "Triage")
}

// MARK: - The resolver

// (n1-seams R-16)
@Test func aPlainFolderNameIsKept() throws {
    let vault = try TemporaryVault()

    #expect(VaultSettings.resolveInboxFolder("Triage", root: vault.root) == "Triage")
}

// (n1-seams R-16)
@Test func surroundingWhitespaceAndEveryEmptyComponentAreDropped() throws {
    let vault = try TemporaryVault()

    #expect(VaultSettings.resolveInboxFolder(" Triage/ ", root: vault.root) == "Triage")
}

// (n1-seams R-16)
@Test(arguments: [
    ("Triage//", "Triage"),
    ("./Triage", "Triage"),
    ("Triage /", "Triage"),
    ("a/./b", "a/b"),
])
func aNonCanonicalSpellingResolvesToTheOneTheScannerGives(stored: String, expected: String) throws {
    let vault = try TemporaryVault()

    #expect(VaultSettings.resolveInboxFolder(stored, root: vault.root) == expected)
    #expect(
        VaultSettings.resolveInboxFolder(stored, boundary: VaultBoundary(root: vault.root)) == expected
    )
}

// (n1-seams R-16)
@Test(arguments: [
    "",
    "   ",
    "/abs",
    "..",
    "../x",
    "a/../b",
    ".",
    "./",
    "/",
    " . ",
    "a/ ../b",
    "//x",
])
func aValueTheRulesRefuseFallsBackToTheDefault(stored: String) throws {
    let vault = try TemporaryVault()

    #expect(
        VaultSettings.resolveInboxFolder(stored, root: vault.root) == "00 Inbox",
        "«\(stored)» doveva tornare alla cartella predefinita"
    )
}
