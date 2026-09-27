import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 §D16/§D18 (over-threshold attachments stay in Mail's own store, recorded as
// `MessageDocument.StoreReference` rather than copied - R-10), plan
// docs/superpowers/plans/2026-09-09-pratiche.md Task 6 - R-27; ADR-0040 §D8 (R-08, R-09).
//
// A temporary directory stands in for `allegati/` and for Mail's own store - never
// `~/Library/Mail`.
//
// This batch's staleness rewrite (ADR-0040 §D8, plan Task 8): every function moved from a
// `fileExists: (URL) -> Bool` probe to a `state: (URL) -> AttachmentChipModel.FileState`
// probe, so the same 21 assertions below now assert through `.usable`/`.missing` instead of
// `true`/`false` - same outcomes, new vocabulary. New tests cover the third state,
// `.unusable`, and the new `.pending` content case.

@Suite struct AttachmentChipModelTests {
    private static func withTemporaryFile(_ body: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-chip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    /// Stands in for the production probe (`FileManager.fileExists` gated by
    /// `AttachmentIntegrity.verdict(ofFileAt:named:)`): present on disk is `.usable`,
    /// absent is `.missing`. No test in this file exercises `.unusable` through the
    /// real filesystem - the two dedicated tests below inject a constant `.unusable`
    /// probe instead, since provoking a real damaged file is Task 8's coder-side
    /// integration concern, not this pure model's.
    private static func state(_ url: URL) -> AttachmentChipModel.FileState {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? .usable : .missing
    }

    /// Records every URL it is asked about, always answering `.unusable` - used by the
    /// `.pending` test to prove the probe is never consulted at all (R-08).
    private final class RecordingProbe {
        private(set) var calls: [URL] = []
        func state(_ url: URL) -> AttachmentChipModel.FileState {
            calls.append(url)
            return .unusable
        }
    }

    // MARK: - PG-123: executables, bundles, disk images and scripts never open from the chip

    @Test(arguments: ["script.command", "install.sh", "image.dmg", "tool.exe", "setup.pkg", "run.scpt"])
    func aUsableFileOfARefusedTypeRevealsAndCopiesButHasNoOpenTarget(fileName: String) throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: fileName, directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: fileName, url: url))

            #expect(AttachmentChipModel.refusesToOpen(url))
            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == nil, "\(fileName) must never reach NSWorkspace.open")
            #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == url, "the Finder is where it goes instead")
            #expect(AttachmentChipModel.copyItems(for: content, state: Self.state) == [url])
            #expect(AttachmentChipModel.symbol(for: content, state: Self.state) == "paperclip", "the refusal is about opening, not about the file's integrity")
        }
    }

    @Test func anExtensionlessFileWithItsExecuteBitSetIsRefusedByTheTypeTheFilesystemReports() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "payload", directoryHint: .notDirectory)
            try Data("#!/bin/sh\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "payload", url: url))

            #expect(AttachmentChipModel.refusesToOpen(url))
            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == nil)
            #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == url)
        }
    }

    @Test(arguments: ["offerta.pdf", "disegno.dwg", "foto.jpg", "listino.xlsx", "note.txt"])
    func anOrdinaryDocumentStillOpens(fileName: String) throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: fileName, directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: fileName, url: url))

            #expect(!AttachmentChipModel.refusesToOpen(url))
            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == url)
        }
    }

    @Test func aStoreReferenceToARefusedTypeHasNoOpenTargetEither() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "grande.dmg", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.storeReference(
                MessageDocument.StoreReference(name: "grande.dmg", size: 500 * 1024 * 1024, storePath: url.path(percentEncoded: false))
            )

            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == nil)
            #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == url)
        }
    }

    // MARK: - R-27: a copied, usable file present on disk

    @Test func aLocalUsableFileOnDiskGetsThePaperclipSymbolAndPreviewsOpensAndReveals() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))

            #expect(AttachmentChipModel.symbol(for: content, state: Self.state) == "paperclip")
            #expect(AttachmentChipModel.previewURL(for: content, state: Self.state) == url)
            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == url)
            #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == url)
            #expect(AttachmentChipModel.copyItems(for: content, state: Self.state) == [url])
        }
    }

    // MARK: - R-27: a file reference whose copy is not on disk

    @Test func aMissingLocalFileGetsTheQuestionMarkSymbolAndEveryTargetIsNil() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-chip-missing-\(UUID().uuidString)/offerta.pdf")
        let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))

        #expect(AttachmentChipModel.symbol(for: content, state: Self.state) == "questionmark.folder")
        #expect(AttachmentChipModel.previewURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.copyItems(for: content, state: Self.state).isEmpty)
    }

    // MARK: - R-10/R-27: a store reference whose store path still resolves and is usable

    @Test func aStoreReferenceWithAnExistingUsableStorePathGetsTheCloudSlashSymbolButNoPreview() throws {
        try Self.withTemporaryFile { root in
            let storeURL = root.appending(path: "allegato-grande.zip", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: storeURL)
            let reference = MessageDocument.StoreReference(
                name: "allegato-grande.zip", size: 400_000_000, storePath: storeURL.path(percentEncoded: false)
            )
            let content = AttachmentChip.Content.storeReference(reference)

            #expect(AttachmentChipModel.symbol(for: content, state: Self.state) == "icloud.slash")
            // A store reference never previews in place (R-27): it opens from its store
            // path instead, which is a different action from Quick Look.
            #expect(AttachmentChipModel.previewURL(for: content, state: Self.state) == nil)
            #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == storeURL)
            #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == storeURL)
            #expect(AttachmentChipModel.copyItems(for: content, state: Self.state) == [storeURL])
        }
    }

    // MARK: - R-10/R-27: a store reference whose store path is gone

    @Test func aStoreReferenceWithAnAbsentStorePathResolvesToNothing() {
        let storePath = "/Volumes/gone/allegato-grande.zip"
        let reference = MessageDocument.StoreReference(
            name: "allegato-grande.zip", size: 400_000_000, storePath: storePath
        )
        let content = AttachmentChip.Content.storeReference(reference)

        #expect(AttachmentChipModel.symbol(for: content, state: Self.state) == "icloud.slash")
        #expect(AttachmentChipModel.previewURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.openURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, state: Self.state) == nil)
        #expect(AttachmentChipModel.copyItems(for: content, state: Self.state).isEmpty)
    }

    // MARK: - R-27: the context menu's exact wording and order

    @Test func theContextMenuOffersExactlyMostraNelFinderAndCopia() {
        #expect(AttachmentChipModel.contextMenuTitles == ["Mostra nel Finder", "Copia"])
    }

    // MARK: - ADR-0040 §D8, R-09: a copied file `AttachmentIntegrity` rejects

    @Test func aFileWhoseProbeAnswersUnusableGetsTheTriangleSymbolAndEveryTargetIsNilLikeMissing() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))
            let unusable: (URL) -> AttachmentChipModel.FileState = { _ in .unusable }

            #expect(
                AttachmentChipModel.symbol(for: content, state: unusable) == "exclamationmark.triangle",
                "an unusable file must read differently from an absent one (R-09)"
            )
            #expect(AttachmentChipModel.previewURL(for: content, state: unusable) == nil)
            #expect(AttachmentChipModel.openURL(for: content, state: unusable) == nil)
            #expect(AttachmentChipModel.revealURL(for: content, state: unusable) == nil)
            #expect(AttachmentChipModel.copyItems(for: content, state: unusable).isEmpty)
        }
    }

    // MARK: - ADR-0040 §D8, R-07: a store reference whose bytes are unusable

    @Test func aStoreReferenceWhoseProbeAnswersUnusableHasNoOpenOrRevealTarget() {
        let reference = MessageDocument.StoreReference(
            name: "allegato-grande.zip", size: 400_000_000, storePath: "/tmp/allegato-grande.zip"
        )
        let content = AttachmentChip.Content.storeReference(reference)
        let unusable: (URL) -> AttachmentChipModel.FileState = { _ in .unusable }

        #expect(AttachmentChipModel.openURL(for: content, state: unusable) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, state: unusable) == nil)
    }

    // MARK: - ADR-0040 §D8, R-08: an attachment still waiting for its bytes

    @Test func aPendingContentGetsTheClockSymbolEveryTargetIsNilAndTheProbeIsNeverCalled() {
        let content = AttachmentChip.Content.pending(name: "offerta.pdf")
        let probe = RecordingProbe()

        #expect(AttachmentChipModel.symbol(for: content, state: probe.state) == "clock.badge.questionmark")
        #expect(AttachmentChipModel.previewURL(for: content, state: probe.state) == nil)
        #expect(AttachmentChipModel.openURL(for: content, state: probe.state) == nil)
        #expect(AttachmentChipModel.revealURL(for: content, state: probe.state) == nil)
        #expect(AttachmentChipModel.copyItems(for: content, state: probe.state).isEmpty)
        #expect(
            probe.calls.isEmpty,
            "a pending attachment has no file to probe - the state closure must never be invoked (R-08)"
        )
    }

    // MARK: - Item 11 "Apri" half (ADR-0067 §D10, R-17): `openDecision`'s four cases

    /// Already-quarantined file: opens without ever trying to apply anything.
    /// Guard - the stub already maps `openURL` to `.open` regardless of the
    /// quarantine closures, and this case needs neither called.
    @Test func openDecisionForAnAlreadyQuarantinedFileOpensWithoutApplying() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))
            var applyCalls: [URL] = []

            let decision = AttachmentChipModel.openDecision(
                for: content, state: Self.state,
                isQuarantined: { _ in true },
                applyQuarantine: { applyCalls.append($0) }
            )

            #expect(decision == .open(url))
            #expect(applyCalls.isEmpty, "an already-quarantined file must never be re-quarantined")
        }
    }

    /// Not yet quarantined, applying it succeeds: opens, and the quarantine was
    /// actually applied - PG-123's own gap for a file placed before the fix landed.
    /// Red until Task 6 wires `openDecision` to call `applyQuarantine` for a
    /// not-yet-quarantined file: today's stub never calls it at all.
    @Test func openDecisionForAFileNotYetQuarantinedAppliesItThenOpens() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))
            var applyCalls: [URL] = []

            let decision = AttachmentChipModel.openDecision(
                for: content, state: Self.state,
                isQuarantined: { _ in false },
                applyQuarantine: { applyCalls.append($0) }
            )

            #expect(decision == .open(url))
            #expect(
                applyCalls == [url],
                "a not-yet-quarantined file must be quarantined before it opens - red until Task 6 wires this"
            )
        }
    }

    /// Not yet quarantined, applying it fails (the volume refuses the attribute):
    /// refuses with the reveal URL, never opens. Red until Task 6: today's stub
    /// ignores `applyQuarantine` entirely and always opens.
    @Test func openDecisionForAFileWhoseQuarantineCannotBeAppliedRefusesWithTheRevealURL() throws {
        try Self.withTemporaryFile { root in
            let url = root.appending(path: "offerta.pdf", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "offerta.pdf", url: url))
            struct QuarantineFailure: Error {}

            let decision = AttachmentChipModel.openDecision(
                for: content, state: Self.state,
                isQuarantined: { _ in false },
                applyQuarantine: { _ in throw QuarantineFailure() }
            )

            guard case .refuse(_, let reveal) = decision else {
                Issue.record("expected .refuse when applying quarantine fails, got \(decision)")
                return
            }
            #expect(reveal == url)
        }
    }

    /// A store reference is unaffected by quarantine entirely (ADR-0036: never a file
    /// this app wrote itself) - opens exactly as `openURL` says, guard.
    @Test func openDecisionForAStoreReferenceIsUnchangedByQuarantine() throws {
        try Self.withTemporaryFile { root in
            let storeURL = root.appending(path: "allegato-grande.zip", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: storeURL)
            let reference = MessageDocument.StoreReference(
                name: "allegato-grande.zip", size: 400_000_000, storePath: storeURL.path(percentEncoded: false)
            )
            let content = AttachmentChip.Content.storeReference(reference)

            let decision = AttachmentChipModel.openDecision(
                for: content, state: Self.state,
                isQuarantined: { _ in false },
                applyQuarantine: { _ in Issue.record("a store reference must never be quarantined") }
            )

            #expect(decision == .open(storeURL))
        }
    }
}
