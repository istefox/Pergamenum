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
//
// Defect measured 2026-09-04 13:02-13:12 (`sample` of the hung unit-test host): `.claude/test-cmd`
// (`-only-testing:PergamenumTests`) hosts the suite inside the real `Pergamenum.app`, launched by
// xctest WITHOUT `-disableUpdater`. `PergamenumApp.armCapture()` still calls
// `SparkleUpdateController.start()`; `isIsolated` reads `false` because `defaults` holds nothing;
// `controller.startUpdater()` runs Sparkle's placeholder-key configuration, which is invalid until
// plan Task 9 installs the real EdDSA key, and its startup block puts `-[NSAlert runModal]` on the
// main thread (`__44-[SPUStandardUpdaterController startUpdater]_block_invoke`,
// `SPUStandardUpdaterController.m:99`). The main thread blocks forever and the next test waiting on
// a main-thread callback hangs at 0% CPU. Two earlier runs passed only because the alert lost the
// race against the suite finishing first.
//
// ADR-0031 §D4 isolates the updater under `-disableUpdater YES`; that rule alone does not cover
// this host, since `.claude/test-cmd` never passes that flag (it cannot - it launches through
// `xcodebuild test`, not this app's own argv). The fix is a second, independent isolation input:
// whether the *process* is a unit-test host at all, using the exact precedent
// `VaultState.isRunningUnderTest` already established (ADR-0017) -
// `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil` - and reused here
// directly rather than re-derived, since `Sources/Vault` and `Sources/App` compile into the same
// module. `init` below only *declares* the new input (tester-first, ADR-0155 §D1): `isIsolated`'s
// computation still ignores it, on purpose, so
// `Tests/SparkleUpdateControllerTests.swift`'s new assertions are RED until the coder ORs
// `isTestHost` into `isIsolated`.
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

    /// Whether this *process* is a unit-test host, independent of `-disableUpdater` (see this
    /// file's header, defect measured 2026-09-04). Defaults to
    /// `VaultState.isRunningUnderTest`'s own `XCTestConfigurationFilePath` check (ADR-0017),
    /// reused rather than re-derived since `Sources/Vault` and `Sources/App` share one module -
    /// so `SparkleUpdateController()` at the production call site (`PergamenumApp.swift`) still
    /// gets exactly today's behavior outside a test host, and a test can override it explicitly.
    ///
    /// Not yet read by `isIsolated` below - that OR is the coder's fill (ADR-0155 §D1), left
    /// undone here so `Tests/SparkleUpdateControllerTests.swift`'s new assertions are RED.
    let isTestHost: Bool

    init(defaults: UserDefaults = .standard, isTestHost: Bool = VaultState.isRunningUnderTest) {
        isIsolated = defaults.bool(forKey: "disableUpdater")
        self.isTestHost = isTestHost
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
