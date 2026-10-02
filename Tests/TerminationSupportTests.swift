import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D8, plan Task 4 (R-12): the quit review only runs if the system asks the delegate.
// With sudden or automatic termination switched on it may kill the process without asking
// anything, so both stay off, and this pins it. The unit suite is hosted in the app
// (`Project.swift`: the tests target depends on the app target), so `Bundle.main` is the
// app's own `Info.plist` and `ProcessInfo` is the running app's.

@Test func theAppDoesNotOptIntoSuddenOrAutomaticTermination() {
    let info = Bundle.main
    #expect(info.bundleIdentifier?.hasPrefix("it.stefer.pergamenum") == true, "the suite is not hosted in the app")
    #expect(info.object(forInfoDictionaryKey: "NSSupportsSuddenTermination") as? Bool != true)
    #expect(info.object(forInfoDictionaryKey: "NSSupportsAutomaticTermination") as? Bool != true)
}

@Test func automaticTerminationSupportIsOffInTheRunningApp() {
    #expect(ProcessInfo.processInfo.automaticTerminationSupportEnabled == false)
}

// PG-363: a Quit AppleEvent (Quit from the Dock) reaching this host ended a unit run with
// «The test runner exited with code 0 before finishing running tests». The host refuses it.
// The `false` branch is the quit review itself, pinned through `QuitCoordinator` directly
// (`QuitCoordinatorTests`), never through a delegate that would act on the live windows here.

/// Pins the environment seed the refusal depends on: with no override, the default
/// `isTestHost` reads `true` under the runner.
@Test @MainActor func theDelegateKnowsItIsTheUnitTestHost() {
    #expect(AppDelegate().isTestHost == true)
}

@Test @MainActor func theUnitTestHostRefusesTermination() {
    let delegate = AppDelegate()
    delegate.isTestHost = true
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
}
