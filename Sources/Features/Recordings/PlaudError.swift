import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 1 -
// R-07, R-13.
//
// Maps the wire's HTTP status + `{"error": "..."}` body, and a job/recording's `last_error`
// string, to something readable in Italian - never the raw wire text, except inside
// `.unrecognised`'s and `readableLastError`'s verbatim fallback, which R-07 asks for by
// name: a labelled raw string is more honest than a generic sentence for a failure this app
// has never seen before.
enum PlaudError: Error, Equatable, Sendable {
    case invalidDays
    case unknownRecording
    case unknownJob
    case proposalNotFound
    case payloadTooLarge
    case serviceDisconnected
    case transportFailure(String)
    case decodeFailure(String)
    /// Any HTTP status/body combination the mapping table below does not name.
    case unrecognised(status: Int, body: String)

    /// The readable Italian message shown to the person (banner or row, per the caller).
    ///
    /// STUB (RED baseline, not yet implemented): always `""`. The coder fills in one line
    /// per case, per Task 1's mapping table (400 `invalid_days`, 404 in its three measured
    /// shapes, 413, 503, transport failure, decode failure, and `.unrecognised`'s
    /// verbatim-including fallback).
    var message: String {
        ""
    }

    /// Maps an HTTP status and the raw `{"error": "..."}` response body to a case.
    ///
    /// STUB (RED baseline, not yet implemented): ignores both arguments and always returns
    /// `.unrecognised(status: -1, body: "")`, so every test naming a specific status/body
    /// pair is red. The coder reads `body`'s `error` field and switches on `(status, error)`
    /// per the measured table: 400 `invalid_days`; 404 `recording_not_found` /
    /// `job_not_found` / `proposal_not_found`; 413 `payload_too_large`; 503 (Plaud
    /// disconnected, no informative body documented).
    static func map(status: Int, body: Data?) -> PlaudError {
        .unrecognised(status: -1, body: "")
    }

    /// Maps a job/recording `last_error` string to a readable Italian message, with a
    /// verbatim-including fallback for anything unrecognised (R-07).
    ///
    /// STUB (RED baseline, not yet implemented): echoes `raw` unchanged. The two measured,
    /// coded strings' tests are red; the fallback's own test happens to pass against this
    /// stub already (echoing is already "contains raw") and will keep passing once the real
    /// body lands - it exists to pin the fallback shape, not to prove red on its own.
    static func readableLastError(_ raw: String) -> String {
        raw
    }
}
