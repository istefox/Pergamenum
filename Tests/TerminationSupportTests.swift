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
