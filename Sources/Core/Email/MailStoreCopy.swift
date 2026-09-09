import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02.
//
// The published-copy protocol, ADR §D2: `Envelope Index` (+ `-wal`, never `-shm`) is
// copied into a staging directory, opened read-write with no `SQLITE_OPEN_CREATE` so
// SQLite recovers the WAL into the copy, `PRAGMA quick_check`ed, then published with
// one atomic directory rename - never opening Mail's live file, never three separate
// renames a crash could interleave.
enum MailStoreCopy {
    /// The four outcomes ADR §D2 designs for. `SQLITE_OPEN_CREATE` is never passed
    /// (`Sources/Core/Email/MailStoreConnection.swift`), which is what makes a missing
    /// store answer `.storeMissing` rather than silently becoming an empty database.
    enum PublishResult: Equatable, Sendable {
        /// A fresh copy was made and published at this generation's directory.
        case published(URL)
        /// The source's modification date matches the already-published generation;
        /// nothing was copied. The URL is that existing, still-valid generation.
        case unchanged(URL)
        /// The copy was torn (Mail wrote between the two file copies) even after the
        /// one retry ADR §D2 step 3 allows.
        case mailIsWriting
        /// `source` holds no `Envelope Index` to copy.
        case storeMissing
    }

    /// Copies `Envelope Index` (+ `-wal`) found under `source` (a directory shaped
    /// like `~/Library/Mail/V10`, i.e. what `MailStoreLocation.resolve()` returns)
    /// into a fresh generation under `stateDirectory`, skipping the copy when the
    /// source's modification date matches the last published generation.
    ///
    /// Stub: tester-declared boundary (ADR-0155). Always answers `.published` at a
    /// placeholder URL with no file ever written, whatever `source` and
    /// `stateDirectory` hold - every behavioural test in
    /// `Tests/MailStoreReaderTests.swift` (skip-when-unchanged, republish-when-changed,
    /// truncated-source retry, missing-store) stays red until the coder implements
    /// ADR §D2's staging/quick_check/rename sequence for real.
    static func publish(from source: URL, into stateDirectory: URL) -> PublishResult {
        .published(stateDirectory.appending(path: "unimplemented-generation", directoryHint: .isDirectory))
    }
}
