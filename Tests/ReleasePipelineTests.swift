import Foundation
import Testing
@testable import Pergamenum

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, tasks 6-8.
//
// Recorded plan deviation (orchestrator, step 5 batch 3): Task 6 carries no unit test of its
// own ("this repo has no shell test harness and inventing one for a 90-line fetcher is the
// wrong trade" - the plan's own words) and Task 8 carries its own `--self-test`, so without
// this file R-06 and R-07 would have no mechanical coverage running every turn through
// `.claude/test-cmd`. This is that one guard file. Every test below is red right now because
// none of `scripts/appcast.py`, `scripts/fetch-sparkle-tools.sh`, or the Task 7 insertions
// into `scripts/release.sh` exist yet - that is the correct state for this dispatch.
//
// R-06: scripts/release.sh, run end-to-end, re-packages the stapled bundle (not the
// pre-staple notarization zip) into the artifact that gets signed and published.
// R-07: scripts/release.sh, run end-to-end, publishes a GitHub Release with the signed zip
// attached and regenerates appcast.xml with a correct <item>.
@Suite struct ReleasePipelineTests {

    // MARK: - R-07: scripts/appcast.py --self-test (ADR-0031 §D10)

    @Test func appcastSelfTestExitsZeroWithOutput() async throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/appcast.py")
        try #require(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "scripts/appcast.py does not exist yet (Task 8, R-07)"
        )

        let result = try await Self.run(
            executable: "/usr/bin/env",
            arguments: ["python3", "scripts/appcast.py", "--self-test"],
            currentDirectory: repoRoot
        )

        #expect(
            result.exitCode == 0,
            "appcast.py --self-test exited \(result.exitCode); stderr: \(result.stderr)"
        )
        #expect(
            !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "appcast.py --self-test produced no stdout, expected a report of what it checked"
        )
    }

    // MARK: - R-06: scripts/release.sh distributable + preflight (ADR-0031 §D8, §D11, §D12)

    @Test func releaseScriptPassesBashSyntaxCheck() async throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let result = try await Self.run(
            executable: "/bin/bash",
            arguments: ["-n", "scripts/release.sh"],
            currentDirectory: repoRoot
        )
        #expect(result.exitCode == 0, "bash -n scripts/release.sh failed: \(result.stderr)")
    }

    @Test func releaseScriptCutsDistributableFromStapledBundleAfterStaple() throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/release.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        let lines = contents.components(separatedBy: "\n")

        let stapleIndex = lines.firstIndex { $0.contains(#"xcrun stapler staple "$BUNDLE""#) }
        let distDittoIndex = lines.firstIndex {
            $0.contains(#"ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST""#)
        }
        let zipDittoIndex = lines.firstIndex {
            $0.contains(#"ditto -c -k --keepParent "$BUNDLE" "$zip""#)
        }

        let staple = try #require(
            stapleIndex,
            #"no `xcrun stapler staple "$BUNDLE"` line found in scripts/release.sh"#
        )
        let distDitto = try #require(
            distDittoIndex,
            #"no `ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST"` line found in scripts/release.sh (Task 7, ADR-0031 §D8)"#
        )
        let zipDitto = try #require(
            zipDittoIndex,
            #"pre-existing `ditto -c -k --keepParent "$BUNDLE" "$zip"` line missing or changed in scripts/release.sh - it must stay exactly where it is (ADR-0031 §D8)"#
        )

        #expect(
            distDitto > staple,
            "the $DIST ditto line must appear after the `xcrun stapler staple` line (ADR-0031 §D8: cut from the already-stapled bundle)"
        )
        #expect(
            zipDitto < staple,
            "the pre-existing $zip ditto line must remain before the staple line, untouched (ADR-0031 §D8: $zip is notarytool's evidence, never reused)"
        )
    }

    @Test func releaseScriptDefinesSparkleToolResolver() throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/release.sh")
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(
            contents.contains("sparkle_tool()") || contents.contains("sparkle_tool ()"),
            "scripts/release.sh does not define a sparkle_tool() function (ADR-0031 §D11/§D12 preflight resolution order)"
        )
    }

    // MARK: - Task 6 / R-06 support: scripts/fetch-sparkle-tools.sh (ADR-0031 §D11)

    @Test func fetchSparkleToolsScriptExistsAndPassesSyntaxCheck() async throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/fetch-sparkle-tools.sh")
        try #require(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "scripts/fetch-sparkle-tools.sh does not exist yet (Task 6, R-06)"
        )

        let result = try await Self.run(
            executable: "/bin/bash",
            arguments: ["-n", "scripts/fetch-sparkle-tools.sh"],
            currentDirectory: repoRoot
        )
        #expect(result.exitCode == 0, "bash -n scripts/fetch-sparkle-tools.sh failed: \(result.stderr)")
    }

    @Test func fetchSparkleToolsScriptIsStrictPinnedAndNeverForceRemoves() throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let scriptURL = repoRoot.appendingPathComponent("scripts/fetch-sparkle-tools.sh")
        try #require(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "scripts/fetch-sparkle-tools.sh does not exist yet (Task 6, R-06)"
        )
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(
            contents.contains("set -euo pipefail"),
            "scripts/fetch-sparkle-tools.sh must `set -euo pipefail` (bash 3.2 discipline, CLAUDE.md)"
        )
        #expect(
            contents.contains("8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"),
            "scripts/fetch-sparkle-tools.sh must pin Sparkle's own SHA-256 from its Package.swift (ADR-0031 §D11)"
        )
        #expect(
            !contents.contains("rm -rf"),
            "scripts/fetch-sparkle-tools.sh must never rm -rf - fails loud on mismatch, deletes nothing (ADR-0031 §D11, plan Task 6)"
        )
    }

    // MARK: - R-08: the watchdog itself survives the continuation-based rewrite (ADR-0041 Task 9)

    /// `run`'s `DispatchSemaphore` + `finished.wait(timeout:)` (ADR-0041 §D9) is due to become
    /// a continuation-based wait, still bounded by the same timeout. Nothing here exercised the
    /// timeout path itself before this test: every other case above runs a command that finishes
    /// well inside 60s, so a rewrite that quietly dropped the watchdog - turning it into an
    /// unbounded wait on a hung `xcodebuild` subprocess - would have nothing here to catch it.
    ///
    /// A short timeout against a command that deliberately outlives it, asserting the specific
    /// `ProcessTimeoutError` rather than merely "throws something": this must stay green across
    /// the rewrite, not go red once and get quietly relaxed to pass either way.
    @Test func aProcessThatOutlivesItsTimeoutIsReportedRatherThanAwaitedForever() async throws {
        await #expect(throws: ProcessTimeoutError.self) {
            _ = try await Self.run(
                executable: "/bin/sleep",
                arguments: ["5"],
                currentDirectory: FileManager.default.temporaryDirectory,
                timeout: 0.2
            )
        }
    }

    // MARK: - Shared plumbing

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Signals exactly one waiter with the first outcome to arrive, whichever of
    /// `terminationHandler` or the timeout `Task` fires first. Guards against the race where
    /// the outcome lands before `withCheckedContinuation`'s body has installed the
    /// continuation (a process that exits in well under a millisecond is not hypothetical here
    /// - `bash -n` routinely does): `resume(finished:)` records the outcome even with no
    /// continuation yet registered, and `wait(startingTimeoutWith:)` replays it immediately
    /// if it finds one already recorded. Either way only the first outcome is ever delivered.
    private final class ProcessOutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedOutcome: Bool?
        private var continuation: CheckedContinuation<Bool, Never>?

        func resume(finished: Bool) {
            lock.lock()
            guard recordedOutcome == nil else {
                lock.unlock()
                return
            }
            recordedOutcome = finished
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: finished)
        }

        func wait(startingTimeoutWith startTimeout: () -> Void) async -> Bool {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                lock.lock()
                if let outcome = recordedOutcome {
                    lock.unlock()
                    continuation.resume(returning: outcome)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                startTimeout()
            }
        }
    }

    /// Runs `executable arguments…` with `currentDirectory` as cwd, bounded by a 60s watchdog
    /// that terminates the process and throws loudly rather than hanging the suite. Output is
    /// read only after the process has exited, which is fine for the short, small-output
    /// commands this file runs (a bash -n check, appcast.py's in-process self-test).
    ///
    /// Continuation-based rather than a blocking `DispatchSemaphore` wait (ADR-0041 Task 9):
    /// `terminationHandler` and a timeout `Task.sleep` race to resolve the same
    /// `ProcessOutcomeBox` first, so this suspends the calling task instead of parking a thread.
    /// `terminationHandler` is still driven by the process's own dispatch source, not a manually
    /// queued block waiting on `process.waitUntilExit()` — that queued-block shape previously
    /// starved under the full suite's concurrent load (a captured priority-inversion warning:
    /// "Thread running at User-initiated quality-of-service class waiting on a lower QoS thread
    /// running at Utility quality-of-service class") and let the 60s watchdog fire even though
    /// the child process exited in milliseconds. → PG-110
    private static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        timeout: TimeInterval = 60
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outcome = ProcessOutcomeBox()
        process.terminationHandler = { _ in outcome.resume(finished: true) }

        try process.run()

        var timeoutTask: Task<Void, Never>?
        let didFinish = await outcome.wait {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                outcome.resume(finished: false)
            }
        }
        timeoutTask?.cancel()

        if !didFinish {
            process.terminate()
            throw ProcessTimeoutError(executable: executable, arguments: arguments, timeout: timeout)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// One `deletingLastPathComponent()` off this file's own directory (`Tests/`) gives the
    /// repository root - the exact resolution `Tests/SharedSourcesPurityTests.swift` uses. If
    /// the candidate does not contain a `Sources` directory, this throws naming the path
    /// tried - it never skips silently.
    private static func resolvedRepoRoot() throws -> URL {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoot = thisFileURL
            .deletingLastPathComponent() // ReleasePipelineTests.swift -> Tests/
            .deletingLastPathComponent() // Tests/ -> repository root
        guard FileManager.default.fileExists(atPath: candidateRoot.appendingPathComponent("Sources").path) else {
            throw RepoRootResolutionError.notFound(candidate: candidateRoot.path)
        }
        return candidateRoot
    }
}

private struct ProcessTimeoutError: Error, CustomStringConvertible {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval

    var description: String {
        "\(executable) \(arguments.joined(separator: " ")) did not finish within \(timeout)s"
    }
}

private enum RepoRootResolutionError: Error, CustomStringConvertible {
    case notFound(candidate: String)

    var description: String {
        switch self {
        case let .notFound(candidate):
            return "Could not resolve the repository root from #filePath. Candidate tried: \(candidate)"
        }
    }
}
