import Foundation
import Testing
@testable import Pergamenum

// The version-history half of M9 (ADR-0011): what `NoteHistory` keeps on disk and how
// it thins itself, with no view on it yet - that is the next slice, mockup-first.

@Test func recordingWritesASnapshotThatSnapshotsReadsBack() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)

    history.record("prima versione\n", for: "N.md")

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.text == "prima versione\n")
}

@Test func snapshotsComeBackNewestFirst() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    let now = Date()

    history.record("vecchia\n", for: "N.md", at: now.addingTimeInterval(-10))
    history.record("nuova\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["nuova\n", "vecchia\n"])
}

@Test func aNoteWithNoHistoryReturnsAnEmptyListNotAnError() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)

    #expect(history.snapshots(for: "Mai salvata.md").isEmpty)
}

// MARK: - Thinning (ADR-0011 D4)

@Test func twoSnapshotsWithinADayBothSurviveThinning() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    let now = Date()

    history.record("uno\n", for: "N.md", at: now.addingTimeInterval(-60))
    history.record("due\n", for: "N.md", at: now)

    #expect(history.snapshots(for: "N.md").count == 2)
}

@Test func twoSnapshotsOlderThanADayOnTheSameDayCollapseToOne() throws {
    // Thinning is write-triggered, not a background job: it only re-evaluates "how old
    // is this" against the timestamp of whichever write just happened. Two old snapshots
    // with nothing written since sit exactly as they are - a later write is what makes
    // the comparison happen at all, so this test supplies one.
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    let now = Date()
    // Both well past the 24h cutoff, both on the same calendar day.
    let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        .addingTimeInterval(-172_800)   // two days ago
    let evening = morning.addingTimeInterval(3 * 3_600)

    history.record("mattina\n", for: "N.md", at: morning)
    history.record("sera\n", for: "N.md", at: evening)
    // Nothing to collapse yet: from `evening`'s own vantage point, `morning` is three
    // hours old, well inside the 24h window. Only a write further out re-evaluates them.
    #expect(history.snapshots(for: "N.md").count == 2)

    history.record("oggi\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["oggi\n", "sera\n"])
}

@Test func twoSnapshotsOlderThanADayOnDifferentDaysBothSurvive() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    let now = Date()
    let threeDaysAgo = now.addingTimeInterval(-259_200)
    let twoDaysAgo = now.addingTimeInterval(-172_800)

    // Written in the order real writes happen, oldest first, then a write near real
    // `now` to actually trigger the comparison thinning depends on (see the same-day
    // test above for why an unthinned pair needs a later write to be re-evaluated at
    // all).
    history.record("tre giorni fa\n", for: "N.md", at: threeDaysAgo)
    history.record("l'altro ieri\n", for: "N.md", at: twoDaysAgo)
    history.record("oggi\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["oggi\n", "l'altro ieri\n", "tre giorni fa\n"])
}

@Test func recentAndOldSnapshotsThinIndependently() throws {
    // The boundary itself: one snapshot inside the 24h window and two on the same
    // older day - only the older pair collapses.
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    let now = Date()
    let old1 = now.addingTimeInterval(-172_800)
    let old2 = old1.addingTimeInterval(3_600)

    history.record("vecchia 1\n", for: "N.md", at: old1)
    history.record("vecchia 2\n", for: "N.md", at: old2)
    history.record("recente\n", for: "N.md", at: now.addingTimeInterval(-60))

    #expect(history.snapshots(for: "N.md").count == 2)
}

@Test func aStrayUnparseableFileIsSkippedByBothReadingAndThinning() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(root: vault.root)
    history.record("buona\n", for: "N.md")

    let noteDir = vault.root
        .appending(path: ".pergamenum/history/N.md", directoryHint: .isDirectory)
    try Data("non è un timestamp\n".utf8)
        .write(to: noteDir.appending(path: "non-parseable.md"))

    // The negative control: without the guard, this file would either crash the read
    // or be counted, and the directory holds exactly one recognisable snapshot.
    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.text == "buona\n")
}

// MARK: - The hook into VaultSession.write

@MainActor
@Test func savingANoteThroughTheSessionRecordsAHistorySnapshot() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root)
    await session.rescan()

    try session.write("contenuto\n", to: "N.md")

    #expect(session.history.snapshots(for: "N.md").count == 1)
}

@MainActor
@Test func aNonMarkdownWriteLeavesNoHistoryBehind() async throws {
    // The scope guard (ADR-0011 D2): a canvas write goes through the same
    // `VaultSession.write`, and must not gain a history directory of its own.
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root)
    await session.rescan()

    try session.write("{\"nodes\":[],\"edges\":[]}", to: "Board.canvas")

    #expect(session.history.snapshots(for: "Board.canvas").isEmpty)
}
