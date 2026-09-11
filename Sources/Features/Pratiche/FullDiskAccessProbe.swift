import AppKit
import Darwin
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

    /// The path to probe is a parameter, never resolved to `~/Library/Mail` inside
    /// this function, so a test can point it at a fixture file it made unreadable
    /// (`chmod 000`) and never touch the real store - the same boundary
    /// `MailStoreLocation` already draws for R-19.
    ///
    /// `open(2)` and nothing else: TCC denies a read of `~/Library/Mail` silently and
    /// never prompts, so the attempt *is* the answer. `EPERM` is what a TCC denial
    /// returns and `EACCES` is what plain POSIX permissions return (the `chmod 000`
    /// fixture in `Tests/PraticheControllerTests.swift`); both mean "not granted",
    /// and they are the only two errnos that do.
    ///
    /// **Every other failure, `ENOENT` first among them, answers `.granted`** (plan
    /// "Risks": "a probe that mistakes «Mail not installed» for «not granted»"). A
    /// missing store is «Nessun archivio di Mail trovato», a different sentence on a
    /// different surface; showing the Full Disk Access banner for it would send a
    /// person into System Settings to grant an access that was never the problem.
    static func state(probing path: URL) -> State {
        let descriptor = Darwin.open(path.path(percentEncoded: false), O_RDONLY)
        guard descriptor < 0 else {
            Darwin.close(descriptor)
            return .granted
        }
        // Read immediately: any call in between - including a `URL` accessor - can
        // overwrite `errno` with its own result.
        let failure = errno
        return failure == EPERM || failure == EACCES ? .notGranted : .granted
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
    /// `NSWorkspace.open` has no fixture-safe fake, so no unit test calls this; the
    /// banner's button is what reaches it (screen 1c).
    ///
    /// `if let` rather than a force-unwrapped literal: a constant `URL` string still
    /// goes through a failable initialiser, and this repo takes no `!` in production.
    /// A URL that stopped resolving on a future macOS opens nothing, which is the
    /// behaviour a banner can survive - a crash is not.
    static func openSystemSettings() {
        guard let url = URL(string: settingsPaneURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The Settings pane deep link, named once so the banner's help text and this call
    /// cannot drift apart.
    static let settingsPaneURLString =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
}
