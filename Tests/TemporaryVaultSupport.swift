import Foundation

/// A throwaway vault on disk, so the file-touching layers are tested against a real
/// file system rather than a mock that cannot reproduce atomic writes or enumeration.
/// Shared with `VaultSessionTests`, which needs the same throwaway vault.
///
/// This is the one throwaway-vault fixture (ADR-0051 §D2, PG-176). A suite that needs more
/// than a directory and `write` holds one and forwards `root`, as `FolderOpsVault` does; a
/// second copy of the directory-and-cleanup half is the duplicate that issue closed.
/// `#expect` cannot capture a `~Copyable` value passed by name, so read `vault.root` into a
/// local and hand helpers that `URL`; member access and method calls on the vault are fine.
///
/// Four throwaway fixtures stay local on purpose, and this is where the reason for one of them
/// lives: `TemporaryDirectory` in `ThemeCustomizationTests.swift` is not a vault, it is the
/// destination `ThemeCustomization.write(_:to:)` is handed, and it builds its path from
/// `NSTemporaryDirectory()` with no `directoryHint`, where this fixture and `CanvasTemporaryRoot`
/// use `FileManager.default.temporaryDirectory` and mark it a directory, so the `URL` it gives the
/// code under test is not the same value. (The reason sits here because that test file is exactly
/// at SwiftLint's 400-line warning threshold and a comment there would add a warning.) The other
/// three, `VaultWalkFixture`, `BoundaryFixture` and `CallSiteFixture`, carry theirs at the declaration.
struct TemporaryVault: ~Copyable {
    let root: URL
    /// Stands in for `VaultState.applicationSupportBase()`, so a `VaultSession` built
    /// against this vault never touches the real Application Support directory
    /// (ADR-0017) - the same failure `RecentVaults.volatile()` exists to prevent, now
    /// with files instead of `UserDefaults`.
    let stateBase: URL

    // Both throwing calls happen against locals, and `self`'s two stored properties
    // are assigned only at the end: a noncopyable struct's initializer cannot always
    // prove definite initialization across two interleaved throw points otherwise.
    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stateBase = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)

        self.root = root
        self.stateBase = stateBase
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: stateBase)
    }

    @discardableResult
    func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }
}
