import Foundation
import Observation
import Sparkle

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 3 (R-02, R-03).
//
// Declaration only (tester-first, ADR-0155 §D1). The coder fills:
// - `start()`: return immediately when `isIsolated`; otherwise `controller.startUpdater()`
//   and install the KVO observation on `\.canCheckForUpdates`, storing the returned token
//   (`Tests/SparkleUpdateControllerTests.swift` cannot cover this half - see that file's
//   header for why).
// - `checkForUpdates()`: `controller.updater.checkForUpdates()`.
//
// Deviation from the ADR §D3 code sample, recorded here as instructed:
// - `isIsolated` there is `private let isIsolated = UserDefaults.standard.bool(forKey:
//   "disableUpdater")` — not injectable, so a test cannot set the flag in isolation from
//   whatever `UserDefaults.standard` happens to hold in the process running the suite.
//   This declares `init(defaults: UserDefaults = .standard)` instead: production call
//   sites (`SparkleUpdateController()`) get the exact behavior the ADR specifies, and a
//   test can pass a `UserDefaults(suiteName:)` instance to pin the value deterministically.
//   `isIsolated` itself has no access modifier (not `private`) for the same reason - a
//   `private` member is invisible to `Tests/SparkleUpdateControllerTests.swift` even
//   through `@testable import`, since `private` is file-scoped in Swift.
// - `controller` is `lazy`, matching this file's own D3 comment on why `SPUStandardUpdaterController`
//   is never touched by `init`: a lazy property is not constructed until first accessed, so
//   `SparkleUpdateController(defaults:)` in a unit test never builds the real Sparkle object -
//   `start()`'s stub body below does not read `controller`, and a test never calls `start()`
//   on a non-isolated instance, so the property statically exists (the class builds) without
//   ever instantiating `SPUStandardUpdaterController` in-process during `.claude/test-cmd`.
@MainActor
@Observable
final class SparkleUpdateController {
    /// `startingUpdater: false` per ADR §D3: `startUpdater()` can put a modal alert on
    /// screen, and that must never happen before the app has finished coming up (or inside
    /// the unit-test host, which is why this is `lazy` - see the file header).
    ///
    /// `@ObservationIgnored`: the `@Observable` macro rewrites a plain stored property into
    /// an init-accessor-backed computed one, and `lazy` cannot be applied to a computed
    /// property (`init accessor cannot refer to property '_controller'`, measured). Nothing
    /// reads `controller` from a view, so it never needed observation tracking anyway.
    @ObservationIgnored
    lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    /// KVO token for `\.canCheckForUpdates` (ADR §D5). Stored because KVO stops the instant
    /// the token is discarded, silently.
    private var observation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    /// Whether this launch keeps Sparkle out entirely: `-disableUpdater YES` (ADR §D4),
    /// the exact shape of `EventKitStore.isIsolated` (`CalendarService.swift:151`).
    let isIsolated: Bool

    init(defaults: UserDefaults = .standard) {
        isIsolated = defaults.bool(forKey: "disableUpdater")
    }

    /// Called once, from `armCapture()` (ADR §D3) - never from `init`.
    ///
    /// The `isIsolated` return comes before any mention of `controller`, so the lazy
    /// `SPUStandardUpdaterController` is never built under `-disableUpdater YES` - which is
    /// what keeps a modal update alert off the screen in the UI suite (ADR §D4) and out of
    /// the unit-test host entirely.
    func start() {
        guard !isIsolated else { return }
        controller.startUpdater()
        // `MainActor.assumeIsolated` and not `Task { @MainActor in … }`: Sparkle posts this
        // change on the main thread already, and a hop would make the menu item lag its own
        // state by a runloop turn (ADR §D5). `.initial` so the first value arrives without
        // waiting for a change - the menu is built before the updater settles.
        observation = controller.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
