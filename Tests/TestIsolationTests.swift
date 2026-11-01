import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

// R-01 (PG-439): the unit suite writes nothing into the person's machine. `ScratchDefaults` keeps
// a `.volatile()` store in memory, and `VaultState.trashItem(at:)` sends a trashed item into the
// test process's own temp base instead of the Finder's Trash. These tests only READ
// `~/Library/Preferences`; none of them writes, moves or deletes anything there or in `~/.Trash`.

private func preferencesPlist(named suite: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Preferences/\(suite).plist", directoryHint: .notDirectory)
}

// MARK: - ScratchDefaults

@Test func aScratchDefaultsSuiteLeavesNoPlistInPreferences() async throws {
    let suite = "pergamenum.tests.\(UUID().uuidString)"
    let defaults = try #require(ScratchDefaults(suiteName: suite))

    defaults.set(["/tmp/a", "/tmp/b"], forKey: "recents")
    defaults.set(Data([1, 2, 3]), forKey: "blob")
    defaults.set(true, forKey: "flag")
    #expect(defaults.stringArray(forKey: "recents") == ["/tmp/a", "/tmp/b"])

    // cfprefsd writes a domain's plist asynchronously: look at once, and again after it had time.
    #expect(!FileManager.default.fileExists(atPath: preferencesPlist(named: suite).path))
    // No wait-until: the plist must never appear, so there is no condition to poll for.
    try await Task.sleep(for: .milliseconds(300))
    #expect(!FileManager.default.fileExists(atPath: preferencesPlist(named: suite).path))
    defaults.removePersistentDomain(forName: suite)
    #expect(!FileManager.default.fileExists(atPath: preferencesPlist(named: suite).path))
}

@Test func aScratchDefaultsReadsBackEveryTypeThroughItsConvenienceGetters() {
    let defaults = ScratchDefaults.make()

    defaults.set(["a", "b"], forKey: "strings")
    defaults.set(Data([9, 8]), forKey: "data")
    defaults.set(true, forKey: "bool")
    defaults.set(42, forKey: "int")
    defaults.set("testo", forKey: "string")

    #expect(defaults.stringArray(forKey: "strings") == ["a", "b"])
    #expect(defaults.data(forKey: "data") == Data([9, 8]))
    #expect(defaults.bool(forKey: "bool"))
    #expect(defaults.integer(forKey: "int") == 42)
    #expect(defaults.string(forKey: "string") == "testo")
    #expect(defaults.object(forKey: "missing") == nil)
    #expect(!defaults.bool(forKey: "missing"))
}

@Test func removingAKeyOrTheWholeDomainEmptiesAScratchDefaults() {
    let defaults = ScratchDefaults.make()
    defaults.set("uno", forKey: "k1")
    defaults.set("due", forKey: "k2")

    defaults.removeObject(forKey: "k1")
    #expect(defaults.string(forKey: "k1") == nil)
    #expect(defaults.string(forKey: "k2") == "due")

    // The same call a test uses to tidy a real suite, which here touches no domain on disk.
    defaults.removePersistentDomain(forName: "whatever")
    #expect(defaults.string(forKey: "k2") == nil)
}

@Test func twoScratchDefaultsNeverShareAKeyNorReachTheStandardDomain() {
    let first = ScratchDefaults.make()
    let second = ScratchDefaults.make()
    let key = "pergamenum.tests.isolation.\(UUID().uuidString)"

    first.set("solo del primo", forKey: key)

    #expect(second.string(forKey: key) == nil)
    #expect(UserDefaults.standard.object(forKey: key) == nil)
}

@Test func theVolatileStoresKeepTheirStateInMemoryAndApartFromEachOther() throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let recents = RecentVaults.volatile()
    let other = RecentVaults.volatile()
    recents.remember(root)
    #expect(recents.mostRecent?.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path)
    #expect(other.paths.isEmpty)

    let pinned = PinnedTagsStore.volatile()
    let tag = try #require(Tag("topic-prove"))
    pinned.remember([tag], for: root)
    #expect(pinned.tags(for: root) == [tag])
    #expect(PinnedTagsStore.volatile().tags(for: root).isEmpty)
}

// MARK: - VaultState.trashItem

@Test func trashingAFileUnderTestNeverLandsInTheRealTrash() throws {
    let vault = try TemporaryVault()
    let url = try vault.write("Corpo.", to: "Nota.md")

    let landed = try #require(try VaultState.trashItem(at: url))
    defer { try? FileManager.default.removeItem(at: landed.deletingLastPathComponent()) }

    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
    #expect(landed.resolvingSymlinksInPath().path.hasPrefix(temporary), "landed at \(landed.path)")
    #expect(!landed.path.contains("/.Trash"))
    #expect(!FileManager.default.fileExists(atPath: url.path), "the item left where it was")
    #expect(try String(contentsOf: landed, encoding: .utf8) == "Corpo.")
}

@Test func twoItemsWithOneNameTrashedUnderTestDoNotCollide() throws {
    let vault = try TemporaryVault()
    let first = try vault.write("Primo.", to: "Una/Nota.md")
    let second = try vault.write("Secondo.", to: "Altra/Nota.md")

    let landedFirst = try #require(try VaultState.trashItem(at: first))
    let landedSecond = try #require(try VaultState.trashItem(at: second))
    defer {
        try? FileManager.default.removeItem(at: landedFirst.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: landedSecond.deletingLastPathComponent())
    }

    #expect(landedFirst != landedSecond)
    #expect(try String(contentsOf: landedFirst, encoding: .utf8) == "Primo.")
    #expect(try String(contentsOf: landedSecond, encoding: .utf8) == "Secondo.")
}

@Test func anItemTrashedUnderTestCanBeRestoredFromTheReturnedURL() throws {
    let vault = try TemporaryVault()
    let url = try vault.write("Da riavere.", to: "Cartella/Nota.md")

    let landed = try #require(try VaultState.trashItem(at: url))
    defer { try? FileManager.default.removeItem(at: landed.deletingLastPathComponent()) }
    try FileManager.default.moveItem(at: landed, to: url)

    #expect(try String(contentsOf: url, encoding: .utf8) == "Da riavere.")
}

@Test func trashingAFolderUnderTestMovesTheWholeTree() throws {
    let vault = try TemporaryVault()
    try vault.write("Uno.", to: "Cartella/Uno.md")
    try vault.write("Due.", to: "Cartella/Sotto/Due.md")
    let folder = vault.root.appending(path: "Cartella", directoryHint: .isDirectory)

    let landed = try #require(try VaultState.trashItem(at: folder))
    defer { try? FileManager.default.removeItem(at: landed.deletingLastPathComponent()) }

    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(try String(contentsOf: landed.appending(path: "Sotto/Due.md"), encoding: .utf8) == "Due.")
}

@Test func trashingAMissingItemThrowsRatherThanReportingALandingPlace() throws {
    let vault = try TemporaryVault()
    let missing = vault.root.appending(path: "Non c'è.md", directoryHint: .notDirectory)

    #expect(throws: (any Error).self) { try VaultState.trashItem(at: missing) }
}

// MARK: - NeverKeyWindow (PG-434)

/// A hover built the way AppKit's tracking areas build one, aimed at a hosted window.
@MainActor
private func hoverEvent(_ type: NSEvent.EventType, to window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, trackingNumber: 0, userData: nil
    ))
}

/// AppKit's tracking areas deliver `.mouseEntered`/`.mouseExited` to a hosted editor's window
/// after the test that built it has torn it down; the window drops those without an issue. The
/// cause (that test's tracking area outliving its body) is not pinned here, only what the window
/// does when it happens - with no `withKnownIssue`, so a recorded issue fails this test.
@MainActor
@Test func theHarnessWindowDropsTheHoverAppKitDeliversAfterTearDown() async throws {
    let host = HostedView(
        Text("PG-434").environment(\.theme, .emergency), size: CGSize(width: 120, height: 40)
    )
    await host.settle()
    host.tearDown()

    for type in [NSEvent.EventType.mouseEntered, .mouseExited] {
        host.window.sendEvent(try hoverEvent(type, to: host.window))
    }

    #expect(host.refusals.isEmpty)
    #expect(host.neverShown)
}

/// Before `tearDown` a hover is a test's own doing, and it is refused like any other event: the
/// late-delivery drop above does not turn a test that sends one into a silent no-op.
@MainActor
@Test func aHoverSentBeforeTearDownIsRefused() async throws {
    let host = HostedView(
        Text("PG-434").environment(\.theme, .emergency), size: CGSize(width: 120, height: 40)
    )
    defer { host.tearDown() }
    await host.settle()

    for type in [NSEvent.EventType.mouseEntered, .mouseExited] {
        let event = try hoverEvent(type, to: host.window)
        withKnownIssue {
            host.window.sendEvent(event)
        } matching: { issue in
            let text = "\(issue)"
            return text.contains("event type \(type.rawValue)")
                && text.contains("window built by aHoverSentBeforeTearDownIsRefused")
        }
    }
    #expect(host.refusals == ["sendEvent", "sendEvent"])
    #expect(host.neverShown)
}

/// An event a test really sent is still refused, and the message now names the event type and
/// the test that built the window - the two things the PG-434 hunt lacked.
@MainActor
@Test func aRefusedEventNamesItsTypeAndTheTestThatBuiltTheWindow() async throws {
    let host = HostedView(
        Text("PG-434").environment(\.theme, .emergency), size: CGSize(width: 120, height: 40)
    )
    defer { host.tearDown() }
    await host.settle()
    let event = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber,
        context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
    ))

    withKnownIssue {
        host.window.sendEvent(event)
    } matching: { issue in
        let text = "\(issue)"
        return text.contains("event type \(NSEvent.EventType.keyDown.rawValue)")
            && text.contains("window built by aRefusedEventNamesItsTypeAndTheTestThatBuiltTheWindow")
    }
    #expect(host.refusals == ["sendEvent"])
}
