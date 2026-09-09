import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-18, §D17.
//
// macOS exposes no API to ask TCC directly whether Full Disk Access is granted
// (SPEC "Full Disk Access"). The only reliable signal is attempting the read itself:
// `open(2)` on the Envelope Index returns `EPERM` when the access has not been
// granted. Probed per trigger, never cached across a launch, so a grant given while
// the app is running is picked up by the very next trigger with no restart (R-18).
//
// App-only: `Sources/Features/Pratiche/**` is not in `sharedSources`
// (`Project.swift`), so neither `perg` nor `pergamenum-mcp` links this file or learns
// the probe exists.
enum FullDiskAccessProbe {
    enum State: Equatable, Sendable {
        case granted
        case notGranted
    }

    /// Tester-declared boundary (ADR-0155 §D1): the coder implements the real
    /// `open(2)`/`errno` check. The path to probe is a parameter, never resolved to
    /// `~/Library/Mail` inside this function, so a test can point it at a fixture
    /// file it made unreadable (`chmod 000`) and never touch the real store - the
    /// same boundary `MailStoreLocation` already draws for R-19.
    ///
    /// Stubbed to always answer `.granted` - a wrong-but-safe default rather than
    /// `fatalError`, so a test that calls this exercises a real (failing) assertion
    /// instead of crashing the whole xctest process (the `Theme.emergency`
    /// force-unwrap lesson, applied here to a probe instead of a token lookup).
    static func state(probing path: URL) -> State {
        .granted
    }

    /// Production call sites' convenience: probes the real Envelope Index under
    /// `MailStoreLocation`'s resolved root. Never called by a test - a unit test
    /// that reached the real store would be a test about somebody's correspondence
    /// (SPEC "Edge cases", the same rule `-disableCalendar` already exists for).
    static func state() -> State {
        state(probing: MailStoreLocation.resolve().appending(
            path: "MailData/Envelope Index", directoryHint: .notDirectory
        ))
    }

    /// Deep link to Privacy & Security › Full Disk Access (SPEC "Full Disk Access").
    /// Coder's body - `NSWorkspace.open` has no fixture-safe fake, so no unit test
    /// calls this.
    static func openSystemSettings() {
    }
}
