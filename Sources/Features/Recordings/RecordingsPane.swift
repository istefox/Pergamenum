import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-02; ADR §D2.
//
// Pure presentation for the health banner (R-02): replaces the whole list while
// `RecordingsController.health` is `.unavailable`, and carries the one command the person can
// copy - selectable text plus a copy button, per the blueprint. The app never executes it: no
// `Process`, no `NSTask`, anywhere in this chain (SPEC, ADR §D2). `RecordingsPane`'s `View`
// body is not yet written - Task 7's coder builds it on top of this type.
struct HealthBannerPresentation: Equatable, Sendable {
    var message: String
    var copyableCommand: String

    /// The exact command the SPEC and the blueprint name, verbatim - a named constant so the
    /// pane and `Tests/RecordingsViewModelTests.swift` read the same string rather than two
    /// copies that can drift apart.
    static let launchctlCommand = "launchctl load ~/Library/LaunchAgents/it.stefer.plaud-service.plist"

    /// Tester-declared stub (ADR-0155): `copyableCommand` deliberately does not yet return
    /// `launchctlCommand`, so the assertion pinning it is red until Task 7's coder wires this.
    static func make(message: String) -> HealthBannerPresentation {
        HealthBannerPresentation(message: message, copyableCommand: "")
    }
}
