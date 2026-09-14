import Foundation
import Testing
@testable import Pergamenum

// PG-123 (2026-09-14): an attachment `PraticaSyncEngine` copied into `allegati/` carried no
// `com.apple.quarantine`, so a hostile executable launched from its chip without the
// Gatekeeper prompt the same file gets from Mail. `AttachmentQuarantine` stamps the copy;
// these tests read the attribute back through both Foundation and the raw xattr.
@Suite struct AttachmentQuarantineTests {
    private static func withTemporaryFile(_ body: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-quarantine-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private static func hasRawQuarantineXattr(_ url: URL) -> Bool {
        getxattr(url.path(percentEncoded: false), "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    @Test func aFreshlyWrittenFileHasNoQuarantineUntilApplied() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("%PDF-1.7\n%%EOF".utf8).write(to: url, options: .atomic)

            #expect(!AttachmentQuarantine.isApplied(to: url))
            #expect(!Self.hasRawQuarantineXattr(url))
        }
    }

    @Test func applyStampsTheEmailAttachmentQuarantineWithTheAppAsAgent() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "script.command", directoryHint: .notDirectory)
            try Data("#!/bin/sh\necho hi\n".utf8).write(to: url, options: .atomic)

            try AttachmentQuarantine.apply(to: url, agentBundleIdentifier: "it.stefer.pergamenum")

            #expect(AttachmentQuarantine.isApplied(to: url))
            #expect(Self.hasRawQuarantineXattr(url), "Gatekeeper reads the raw xattr, not Foundation's view of it")
            let properties = try url.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
            #expect(properties?["LSQuarantineAgentBundleIdentifier"] as? String == "it.stefer.pergamenum")
            #expect(properties?["LSQuarantineType"] as? String == "LSQuarantineTypeEmailAttachment")
        }
    }

    @Test func applyingTwiceRewritesRatherThanFails() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "disegno.dwg", directoryHint: .notDirectory)
            try Data("AC1032".utf8).write(to: url, options: .atomic)

            try AttachmentQuarantine.apply(to: url)
            try AttachmentQuarantine.apply(to: url)

            #expect(AttachmentQuarantine.isApplied(to: url))
        }
    }

    @Test func applyToAMissingFileThrowsInsteadOfPretending() {
        Self.withTemporaryFile { root in
            let url = root.appending(path: "assente.pdf", directoryHint: .notDirectory)
            #expect(throws: (any Error).self) { try AttachmentQuarantine.apply(to: url) }
        }
    }
}
