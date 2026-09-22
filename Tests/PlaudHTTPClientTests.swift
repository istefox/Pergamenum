import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum). Closes PG-098: `PlaudIsolationTests`
// only checks that `PlaudHTTPClient.base` parses, and every controller test goes through
// `FakePlaudService`, so nothing has ever exercised the client's own request construction -
// query-string building, the conditional `force=1`, headers, and `ImportedBody` encoding.
//
// `URLProtocol.registerClass` intercepts the client's real `URLSession` before any socket
// opens; nothing here reaches the network. `URLSession` converts `URLRequest.httpBody` into
// `httpBodyStream` before `URLProtocol` sees the request, so `request.httpBody` is `nil` in
// `startLoading()` - the body is read back from the stream instead.
@Suite(.serialized)
struct PlaudHTTPClientTests {
    @Test func recordingsRequestsCarryTheDaysQueryItem() async throws {
        let capture = RecordingCaptureProtocol.expect(
            responding: Self.with200(json: #"{"recordings":[]}"#)
        )
        let client = PlaudHTTPClient(session: Self.makeSession())

        _ = try await client.recordings(days: 30)

        let request = try #require(capture.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/recordings")
        #expect(Self.queryValue(request.url, "days") == "30")
    }

    @Test func processWithoutForceOmitsTheForceQueryItem() async throws {
        let capture = RecordingCaptureProtocol.expect(
            responding: Self.with200(json: #"{"job_id":"j1","state":"queued"}"#)
        )
        let client = PlaudHTTPClient(session: Self.makeSession())

        _ = try await client.process(id: "r1", force: false)

        let request = try #require(capture.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/recordings/r1/process")
        #expect(request.url?.query == nil)
    }

    @Test func processWithForceAppendsForceEqualsOne() async throws {
        let capture = RecordingCaptureProtocol.expect(
            responding: Self.with200(json: #"{"job_id":"j1","state":"queued"}"#)
        )
        let client = PlaudHTTPClient(session: Self.makeSession())

        _ = try await client.process(id: "r1", force: true)

        let request = try #require(capture.lastRequest)
        #expect(Self.queryValue(request.url, "force") == "1")
    }

    @Test func getRequestsSendAcceptJSONAndNoContentType() async throws {
        let capture = RecordingCaptureProtocol.expect(
            responding: Self.with200(json: #"{"status":"ok","plaud":"connected","version":"0.2.0"}"#)
        )
        let client = PlaudHTTPClient(session: Self.makeSession())

        _ = try await client.health()

        let request = try #require(capture.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func confirmImportedEncodesTaskIDsAsSnakeCaseJSON() async throws {
        let capture = RecordingCaptureProtocol.expect(responding: Self.noContent())
        let client = PlaudHTTPClient(session: Self.makeSession())

        try await client.confirmImported(recordingID: "r1", taskIDs: ["t1", "t2"])

        let request = try #require(capture.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/proposals/r1/imported")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(capture.lastRequestBody)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: bodyData)
        #expect(decoded == ["task_ids": ["t1", "t2"]])
    }

    // MARK: - PG-126: path-safety charset

    @Test func processRejectsAnIDContainingADotSegmentAndSendsNothing() async throws {
        let capture = RecordingCaptureProtocol.expect(responding: Self.with200(json: "{}"))
        let client = PlaudHTTPClient(session: Self.makeSession())

        await #expect(throws: PlaudError.invalidIdentifier("../health")) {
            _ = try await client.process(id: "../health", force: false)
        }
        #expect(capture.lastRequest == nil)
    }

    @Test func jobRejectsABareDotSegment() async throws {
        let capture = RecordingCaptureProtocol.expect(responding: Self.with200(json: "{}"))
        let client = PlaudHTTPClient(session: Self.makeSession())

        await #expect(throws: PlaudError.invalidIdentifier("..")) {
            _ = try await client.job(id: "..")
        }
        #expect(capture.lastRequest == nil)
    }

    @Test func proposalRejectsAnIDContainingASlash() async throws {
        let capture = RecordingCaptureProtocol.expect(responding: Self.with200(json: "{}"))
        let client = PlaudHTTPClient(session: Self.makeSession())

        await #expect(throws: PlaudError.invalidIdentifier("a/b")) {
            _ = try await client.proposal(recordingID: "a/b")
        }
        #expect(capture.lastRequest == nil)
    }

    @Test func confirmImportedRejectsAnIDContainingADotSegment() async throws {
        let capture = RecordingCaptureProtocol.expect(responding: Self.noContent())
        let client = PlaudHTTPClient(session: Self.makeSession())

        await #expect(throws: PlaudError.invalidIdentifier("../x")) {
            try await client.confirmImported(recordingID: "../x", taskIDs: [])
        }
        #expect(capture.lastRequest == nil)
    }

    @Test func aRealWireShapedIDStillReachesTheIntendedPath() async throws {
        let capture = RecordingCaptureProtocol.expect(
            responding: Self.with200(json: #"{"job_id":"j1","state":"queued"}"#)
        )
        let client = PlaudHTTPClient(session: Self.makeSession())

        _ = try await client.process(id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6", force: false)

        let request = try #require(capture.lastRequest)
        #expect(request.url?.path == "/recordings/a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6/process")
    }

    // MARK: - Fixtures

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingCaptureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func with200(json: String) -> (URLRequest) -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    private static func noContent() -> (URLRequest) -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
    }

    private static func queryValue(_ url: URL?, _ name: String) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}

/// Captures the single request `PlaudHTTPClient` issues per test and hands back a
/// pre-scripted response - no socket, no `127.0.0.1:3777` service required.
///
/// Class-scoped state, not per-request: `URLProtocol` instances are created and torn down
/// by `URLSession` per task, so the capture must live on the type itself. `@Suite(.serialized)`
/// above prevents Swift Testing from running these tests concurrently against that shared state.
private final class RecordingCaptureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var capturedRequest: URLRequest?
    nonisolated(unsafe) private static var capturedBody: Data?

    /// Registers a responder for the next request and returns a handle to read back what was
    /// actually sent, once the call under test has completed.
    static func expect(responding responder: @escaping (URLRequest) -> (HTTPURLResponse, Data)) -> Capture {
        lock.lock()
        Self.responder = responder
        Self.capturedRequest = nil
        Self.capturedBody = nil
        lock.unlock()
        return Capture()
    }

    struct Capture {
        var lastRequest: URLRequest? {
            RecordingCaptureProtocol.lock.lock()
            defer { RecordingCaptureProtocol.lock.unlock() }
            return RecordingCaptureProtocol.capturedRequest
        }

        var lastRequestBody: Data? {
            RecordingCaptureProtocol.lock.lock()
            defer { RecordingCaptureProtocol.lock.unlock() }
            return RecordingCaptureProtocol.capturedBody
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `URLSession` moves `httpBody` into `httpBodyStream` before `URLProtocol` ever sees
        // the request - `request.httpBody` is `nil` here even when the caller set it.
        let body = Self.readBody(from: request)
        let responder = Self.lock.withLock { () -> ((URLRequest) -> (HTTPURLResponse, Data))? in
            Self.capturedRequest = self.request
            Self.capturedBody = body
            return Self.responder
        }

        guard let responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
