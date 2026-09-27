import Foundation
import Testing
@testable import Pergamenum

// ADR-0067 §D7/§D19 (Task 3): the fallback walk's own third outcome - `.indeterminate` -
// distinguished from a genuine miss (`.notInStore`) and a drifted rule (`.ruleFailed`).

@Suite struct EMLXLocatorTests {
    private func makeMailTree() throws -> (root: URL, dataDirectory: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "emlx-locator-\(UUID().uuidString)", directoryHint: .isDirectory)
        let dataDirectory = root
            .appending(path: "V10/acct/INBOX.mbox/Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        return (root, dataDirectory)
    }

    private func predictedURL(under dataDirectory: URL) -> URL {
        dataDirectory
            .appending(path: "3/Messages", directoryHint: .isDirectory)
            .appending(path: "4123.emlx", directoryHint: .notDirectory)
    }

    /// R-11: a budget too small to reach the file anywhere in the tree reports the
    /// walk could not answer, never a false "not in Mail".
    @Test func aBudgetTooSmallToCoverTheTreeIsIndeterminate() throws {
        let (_, dataDirectory) = try makeMailTree()
        let messages = dataDirectory.appending(path: "7/Messages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        for index in 0..<10 {
            try Data().write(to: messages.appending(path: "\(index).emlx", directoryHint: .notDirectory))
        }

        let result = EMLXLocator.locate(predictedURL: predictedURL(under: dataDirectory), enumerationBudget: 1)

        #expect(result == .indeterminate(.budgetExhausted))
    }

    /// A subdirectory this process cannot read must not be reported as a genuine
    /// miss either - it is exactly the situation `.notInStore` must never describe.
    @Test func anUnreadableSubdirectoryWithNoHitIsIndeterminate() throws {
        let (_, dataDirectory) = try makeMailTree()
        let locked = dataDirectory.appending(path: "9/Messages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false)
            )
        }

        let result = EMLXLocator.locate(predictedURL: predictedURL(under: dataDirectory))

        #expect(result == .indeterminate(.unreadable))
    }

    /// A complete, readable walk that genuinely finds nothing stays `.notInStore` -
    /// R-16's legitimate «non più in Mail» must not regress into `.indeterminate`.
    @Test func aCompleteReadableMissIsNotInStore() throws {
        let (_, dataDirectory) = try makeMailTree()
        let messages = dataDirectory.appending(path: "3/Messages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)

        let result = EMLXLocator.locate(predictedURL: predictedURL(under: dataDirectory))

        #expect(result == .notInStore)
    }
}
