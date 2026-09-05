import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 2 -
// R-01, R-02, R-13, R-15; ADR §D2, §D14.
//
// The one file in the repository permitted to say `URLSession` (ADR §D1, §D14).
// `Tests/PlaudIsolationTests.swift` walks `Sources/` from `#filePath` and asserts it appears
// in exactly this one file - the mechanical half of R-15 and the enforcement of D14's "the
// exception does not travel".
//
// STUB for this batch (ADR-0155, tester owns the interface / coder owns the body): every
// method below throws a placeholder `PlaudError` without making a request. Building the
// actual `URLRequest`s, decoding responses through `PlaudError.map(status:body:)`, and the
// one-time loopback probe (`GET /health`, reported rather than automated into the suite)
// are the coder's next task - explicitly **not** this batch's job per the dispatch brief.
struct PlaudHTTPClient: PlaudService, Sendable {
    /// ADR §D2: the one permitted force-unwrap-shaped construct, one named constant, one
    /// file. `127.0.0.1`, never `localhost` - `lsof` shows the service listening on IPv4
    /// only, and `localhost` resolves to `::1` first on this machine's resolver order.
    /// `Tests/PlaudIsolationTests.swift` guards that this literal is well formed rather than
    /// leaving a bad edit to surface only at the client's first real call.
    static let base = URL(string: "http://127.0.0.1:3777")!

    /// `.ephemeral`, `timeoutIntervalForRequest = 10`, `waitsForConnectivity = false`,
    /// `httpCookieStorage = nil`, `urlCache = nil`, `httpShouldSetCookies = false` (ADR §D2) -
    /// built by the coder. The stub only reserves the stored property, so the type holds
    /// exactly one `URLSession` and stays `Sendable`.
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func health() async throws -> PlaudHealth {
        throw PlaudError.decodeFailure("PlaudHTTPClient.health: not yet implemented")
    }

    func recordings(days: Int) async throws -> [PlaudRecording] {
        throw PlaudError.decodeFailure("PlaudHTTPClient.recordings: not yet implemented")
    }

    func process(id: String, force: Bool) async throws -> PlaudJobHandle {
        throw PlaudError.decodeFailure("PlaudHTTPClient.process: not yet implemented")
    }

    func job(id: String) async throws -> PlaudJob {
        throw PlaudError.decodeFailure("PlaudHTTPClient.job: not yet implemented")
    }

    func proposal(recordingID: String) async throws -> PlaudProposal {
        throw PlaudError.decodeFailure("PlaudHTTPClient.proposal: not yet implemented")
    }

    func confirmImported(recordingID: String, taskIDs: [String]) async throws {
        throw PlaudError.decodeFailure("PlaudHTTPClient.confirmImported: not yet implemented")
    }
}
