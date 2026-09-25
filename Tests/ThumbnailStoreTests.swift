import Foundation
import Testing
@testable import Pergamenum

/// PG-131: `forgetAll()` and `clearCacheOnDisk()` had zero callers before `VaultController
/// .clearCache()` was wired to call both. These pin the disk half directly - `forgetAll()`'s
/// body is one line (`tasks.removeAll()`) and is exercised through the wiring test instead.
@Test func clearCacheOnDiskRemovesEveryRenderedThumbnail() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-thumb-root-\(UUID().uuidString)", directoryHint: .isDirectory)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-thumb-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
    // Stands in for a rendered PNG - `clearCacheOnDisk` removes the whole directory
    // without reading it, so a real render is not needed to prove the deletion.
    let renderedFile = cacheDirectory.appending(path: "abc123@320.png", directoryHint: .notDirectory)
    try Data("fake png bytes".utf8).write(to: renderedFile)

    let store = ThumbnailStore(root: root, directory: cacheDirectory)
    try await store.clearCacheOnDisk()

    #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path(percentEncoded: false)))
}

@Test func clearCacheOnDiskIsANoOpWhenNothingWasEverRendered() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-thumb-root-\(UUID().uuidString)", directoryHint: .isDirectory)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-thumb-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ThumbnailStore(root: root, directory: cacheDirectory)

    try await store.clearCacheOnDisk()
}
