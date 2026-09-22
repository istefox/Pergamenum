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
struct PlaudHTTPClient: PlaudService, Sendable {
    /// ADR §D2: the one permitted force-unwrap-shaped construct, one named constant, one
    /// file. `127.0.0.1`, never `localhost` - `lsof` shows the service listening on IPv4
    /// only, and `localhost` resolves to `::1` first on this machine's resolver order.
    /// `Tests/PlaudIsolationTests.swift` guards that this literal is well formed rather than
    /// leaving a bad edit to surface only at the client's first real call.
    static let base = URL(string: "http://127.0.0.1:3777")!

    /// The one session this app owns, holding exactly the five settings ADR §D2 names. Each
    /// of them is a way of not accumulating state about a machine talking to itself, and
    /// `URLSession.shared` is rejected there by name: its cache would make «Aggiorna» a lie.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    let session: URLSession

    init(session: URLSession = PlaudHTTPClient.makeSession()) {
        self.session = session
    }

    func health() async throws -> PlaudHealth {
        try await decoded(PlaudHealth.self, from: get(Self.base.appending(path: "health")))
    }

    func recordings(days: Int) async throws -> [PlaudRecording] {
        let url = try query(
            on: Self.base.appending(path: "recordings"),
            items: [URLQueryItem(name: "days", value: String(days))]
        )
        return try await decoded(PlaudRecordingsResponse.self, from: get(url)).recordings
    }

    func process(id: String, force: Bool) async throws -> PlaudJobHandle {
        let endpoint = try Self.endpoint("recordings", id, "process")
        // `force=1` is appended only when asked: an unconditional force would start real
        // transcription work on a recording that already has a proposal (plan, Risks).
        let url = force
            ? try query(on: endpoint, items: [URLQueryItem(name: "force", value: "1")])
            : endpoint
        return try await decoded(PlaudJobHandle.self, from: post(url))
    }

    func job(id: String) async throws -> PlaudJob {
        try await decoded(PlaudJob.self, from: get(Self.endpoint("jobs", id)))
    }

    func proposal(recordingID: String) async throws -> PlaudProposal {
        try await decoded(PlaudProposal.self, from: get(Self.endpoint("proposals", recordingID)))
    }

    func confirmImported(recordingID: String, taskIDs: [String]) async throws {
        let url = try Self.endpoint("proposals", recordingID, "imported")
        var request = post(url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(ImportedBody(taskIDs: taskIDs))
        } catch {
            // Encoding an array of strings cannot realistically fail, but the error domain
            // above this line is closed to `PlaudError` and stays that way.
            throw PlaudError.decodeFailure("richiesta non serializzabile: \(error)")
        }
        // 204 No Content: the response body is empty and nothing is decoded from it.
        _ = try await responseData(for: request)
    }

    // MARK: - Requests

    private func get(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func post(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// PG-126. The only way to put a service-supplied identifier in a request path - a
    /// caller cannot append one by hand without going around this. `appending(component:)`
    /// percent-encodes a `/`, but a bare `.` or `..` stays a live dot-segment under either
    /// appending call (measured live): RFC 3986 dot-segment removal runs on the finished URL
    /// regardless of how a component was appended, so the charset check below is what
    /// actually stops it, not the encoding.
    private static func endpoint(_ collection: String, _ identifier: String, _ action: String? = nil) throws -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard !identifier.isEmpty,
              identifier != ".", identifier != "..",
              identifier.unicodeScalars.allSatisfy(allowed.contains) else {
            throw PlaudError.invalidIdentifier(identifier)
        }
        var url = Self.base.appending(path: collection).appending(component: identifier)
        if let action {
            url = url.appending(path: action)
        }
        return url
    }

    /// A query string added through `URLComponents` rather than by string concatenation, so
    /// the percent-encoding is the framework's job and not this file's.
    private func query(on url: URL, items: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let built = components?.url else {
            throw PlaudError.transportFailure("URL non costruibile per \(url.path)")
        }
        return built
    }

    /// The one place a transport failure, a non-2xx status and an unreadable body become the
    /// three `PlaudError` cases the pane knows how to show (R-07).
    private func responseData(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlaudError.transportFailure(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PlaudError.transportFailure("risposta non HTTP da \(request.url?.path ?? "-")")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PlaudError.map(status: http.statusCode, body: data)
        }
        return data
    }

    private func decoded<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let data = try await responseData(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlaudError.decodeFailure(String(describing: error))
        }
    }

    /// `POST /proposals/{id}/imported`'s body, the one payload this app sends rather than
    /// reads - snake_case here too, spelled out rather than converted (ADR §D2's contract
    /// lives in another repo).
    private struct ImportedBody: Encodable {
        let taskIDs: [String]

        enum CodingKeys: String, CodingKey {
            case taskIDs = "task_ids"
        }
    }
}
