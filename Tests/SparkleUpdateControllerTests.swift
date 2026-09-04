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
//
// Defect measured 2026-09-04 (see `Sources/App/SparkleUpdateController.swift`'s header): this
// very suite IS `.claude/test-cmd`'s unit-test host, hosted inside the real `Pergamenum.app`
// launched by xctest without `-disableUpdater`. `isIsolatedReadsFalseWhenTheKeyIsAbsent` pins
// `isTestHost: false` explicitly, because it is asserting the defaults-only branch in isolation
// from the fact that we genuinely are a test host right now. The three tests added below assert
// the opposite: that the default `isTestHost` reads `true` inside this suite (no explicit
// override), and that an explicitly-isolated-by-test-host instance behaves exactly like an
// explicitly-isolated-by-defaults one. All three are RED against today's `init`, which computes
// `isIsolated` from `defaults` only and does not yet OR in `isTestHost` - that fill is the
// coder's, not this file's.
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
        // `isTestHost: false` explicitly: this test asserts the defaults-only branch, in
        // isolation from the fact that this very suite genuinely is a test host.
        let suiteName = "SparkleUpdateControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = SparkleUpdateController(defaults: defaults, isTestHost: false)
        #expect(sut.isIsolated == false)
    }

    @Test @MainActor func startIsANoOpWhenIsolatedAndCanCheckForUpdatesStaysFalse() {
        let defaults = Self.isolatedDefaults(disableUpdater: true)
        let sut = SparkleUpdateController(defaults: defaults)
        sut.start()
        #expect(sut.canCheckForUpdates == false)
    }

    /// RED against today's `init`: this suite genuinely runs as a unit-test host, so the
    /// default `isTestHost` (`VaultState.isRunningUnderTest`) must read `true` here with no
    /// explicit override - and once the coder ORs it into `isIsolated`, an instance built with
    /// only an unset `disableUpdater` default must still come out isolated.
    @Test @MainActor func isIsolatedReadsTrueByDefaultInsideTheUnitTestHost() {
        let suiteName = "SparkleUpdateControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = SparkleUpdateController(defaults: defaults)
        #expect(sut.isTestHost == true)
        #expect(sut.isIsolated == true)
    }

    /// RED against today's `init`: an instance forced isolated via `isTestHost: true` (with
    /// `disableUpdater` unset) must behave exactly like the `disableUpdater`-isolated case
    /// above - `isIsolated == true` and `start()` leaving `canCheckForUpdates` false - which
    /// is the actual fix for the hang: the unit-test host must never reach
    /// `controller.startUpdater()` regardless of what `-disableUpdater` says.
    @Test @MainActor func isIsolatedViaTestHostAloneAlsoKeepsStartANoOp() {
        let suiteName = "SparkleUpdateControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = SparkleUpdateController(defaults: defaults, isTestHost: true)
        #expect(sut.isIsolated == true)
        sut.start()
        #expect(sut.canCheckForUpdates == false)
    }
}
