import Foundation
import Testing
@testable import Pergamenum

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 3 (R-02, R-03).
//
// **What this file deliberately does not cover.** `SparkleUpdateController.start()`'s real
// work - `controller.startUpdater()` and the `\.canCheckForUpdates` KVO wiring - touches a
// real `SPUStandardUpdaterController`, which `startUpdater()` can put a modal alert on
// screen for. A modal alert in this suite is a hang, and `.claude/test-cmd` runs this suite
// at the end of every turn, so no test here constructs or starts that object. R-02's "the
// menu item triggers Sparkle's standard update-check UI" half is `UITests/UpdateMenuUITests.swift`
// (Task 4) plus a manual hand check (plan Task 10). What *is* asserted here: that
// `isIsolated` reads the injected `UserDefaults` correctly, and that `start()` leaves
// `canCheckForUpdates` at its default (`false`) when isolated - the one behavior
// `-disableUpdater YES` promises that does not require touching Sparkle.
@Suite struct SparkleUpdateControllerTests {
    /// A throwaway suite per test, never `.standard` - a shared domain would make one
    /// test's `disableUpdater` value leak into another's, and `.claude/test-cmd` gives no
    /// guarantee about test ordering.
    private static func isolatedDefaults(disableUpdater: Bool) -> UserDefaults {
        let suiteName = "SparkleUpdateControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(disableUpdater, forKey: "disableUpdater")
        return defaults
    }

    @Test @MainActor func isIsolatedReadsTrueFromTheInjectedDefault() {
        let defaults = Self.isolatedDefaults(disableUpdater: true)
        let sut = SparkleUpdateController(defaults: defaults)
        #expect(sut.isIsolated == true)
    }

    @Test @MainActor func isIsolatedReadsFalseWhenTheKeyIsAbsent() {
        // A fresh suite with nothing set at all - `disableUpdater` must default to `false`,
        // matching `UserDefaults.bool(forKey:)`'s own documented behavior for a missing key.
        let suiteName = "SparkleUpdateControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = SparkleUpdateController(defaults: defaults)
        #expect(sut.isIsolated == false)
    }

    @Test @MainActor func startIsANoOpWhenIsolatedAndCanCheckForUpdatesStaysFalse() {
        let defaults = Self.isolatedDefaults(disableUpdater: true)
        let sut = SparkleUpdateController(defaults: defaults)
        sut.start()
        #expect(sut.canCheckForUpdates == false)
    }
}
