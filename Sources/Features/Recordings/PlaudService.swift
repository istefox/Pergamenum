import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 2 -
// R-01, R-02, R-13, R-15; ADR §D2.
//
// What the app needs from the Plaud service, behind a protocol - the same shape
// `CalendarStore` uses for EventKit (`Sources/Calendar/CalendarService.swift:69-104`): a
// socket cannot run in a test process either, for a different reason (there may be no
// service loaded, or a real one that would be told to do real work), so everything above
// this line is written against the protocol and tested with `FakePlaudService`
// (`Tests/FakePlaudService.swift`). `PlaudHTTPClient` is its only production conformer.
protocol PlaudService: Sendable {
    func health() async throws -> PlaudHealth
    func recordings(days: Int) async throws -> [PlaudRecording]
    func process(id: String, force: Bool) async throws -> PlaudJobHandle
    func job(id: String) async throws -> PlaudJob
    func proposal(recordingID: String) async throws -> PlaudProposal
    func confirmImported(recordingID: String, taskIDs: [String]) async throws
}
