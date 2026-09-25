import Foundation
import Testing
@testable import Pergamenum

/// `forget(_:)` had zero callers before PG-131 wired it into `RecentVaults`' eviction and
/// "Svuota elenco" - these pin the method itself, isolated from that wiring.
private func makeDefaults() -> (UserDefaults, String) {
    let name = "pergamenum.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

@Test func forgetRemovesASessionRememberedForThatVault() throws {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = OpenTabsStore(defaults: defaults)
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)

    var session = OpenTabsStore.Session()
    session.columns = [.init(entries: [.init(path: "Nota.md", isPreview: false)], activePath: "Nota.md")]
    store.remember(session, for: root)
    #expect(store.session(for: root) == session)

    store.forget(root)

    #expect(store.session(for: root) == OpenTabsStore.Session())
}

@Test func forgetLeavesOtherVaultsSessionsUntouched() throws {
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = OpenTabsStore(defaults: defaults)
    let forgotten = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)
    let kept = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-tabs-\(UUID().uuidString)", directoryHint: .isDirectory)

    var keptSession = OpenTabsStore.Session()
    keptSession.columns = [.init(entries: [.init(path: "Altra.md", isPreview: false)], activePath: "Altra.md")]
    store.remember(OpenTabsStore.Session(), for: forgotten)
    store.remember(keptSession, for: kept)

    store.forget(forgotten)

    #expect(store.session(for: kept) == keptSession)
}
