import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 1 -
// R-03, R-07, R-13.
//
// Wire payload shapes for the Plaud service contract
// (`/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md`, read-only, outside this repo).
// Explicit `CodingKeys` wherever the wire's snake_case differs from this file's camelCase -
// never `.keyDecodingStrategy = .convertFromSnakeCase` anywhere this app decodes the
// contract: it lives in another repo and the mapping should be readable beside it.

/// `GET /health`.
struct PlaudHealth: Decodable, Equatable, Sendable {
    let status: String
    let plaud: String
    let version: String
}

/// Tolerant wrapper for a recording's `state`. Never a bare `RawRepresentable` enum that
/// throws on decode: a service upgrade adding a state must not break the whole
/// `/recordings` list decode.
enum PlaudRecordingState: Decodable, Equatable, Sendable {
    case new
    case processing
    case ready
    case failed
    case imported
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "new": self = .new
        case "processing": self = .processing
        case "ready": self = .ready
        case "failed": self = .failed
        case "imported": self = .imported
        default: self = .unknown(raw)
        }
    }
}

/// Tolerant wrapper for a proposal's `recording_kind`, same shape and same reason as
/// `PlaudRecordingState`.
enum PlaudRecordingKind: Decodable, Equatable, Sendable {
    case meeting
    case lecture
    case update
    case personal
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "meeting": self = .meeting
        case "lecture": self = .lecture
        case "update": self = .update
        case "personal": self = .personal
        default: self = .unknown(raw)
        }
    }
}

/// One row of `GET /recordings`.
struct PlaudRecording: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let recordedAt: String
    let durationMs: Int
    let deviceSerial: String
    let state: PlaudRecordingState
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, name, state
        case recordedAt = "recorded_at"
        case durationMs = "duration_ms"
        case deviceSerial = "device_serial"
        case lastError = "last_error"
    }
}

/// `GET /recordings?days=N`'s envelope.
struct PlaudRecordingsResponse: Decodable, Equatable, Sendable {
    let recordings: [PlaudRecording]
}

/// `POST /recordings/{id}/process` 202 response.
struct PlaudJobHandle: Decodable, Equatable, Sendable {
    let jobId: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case state
        case jobId = "job_id"
    }
}

/// `GET /jobs/{id}` response.
struct PlaudJob: Decodable, Equatable, Sendable {
    let state: String
    let step: String?
    let error: String?
    let proposalId: String?

    enum CodingKeys: String, CodingKey {
        case state, step, error
        case proposalId = "proposal_id"
    }
}

/// One task proposed under a theme.
struct PlaudTask: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let quote: String
    let urgency: Int
    let importance: Int
    let dueHint: String?

    enum CodingKeys: String, CodingKey {
        case id, title, quote, urgency, importance
        case dueHint = "due_hint"
    }
}

/// One theme of a proposal.
struct PlaudTheme: Decodable, Equatable, Sendable {
    let name: String
    let tasks: [PlaudTask]
}

/// The `recording` object nested inside a proposal - a different, smaller shape than
/// `PlaudRecording` (no `device_serial`, no `state`, no `last_error`).
struct PlaudProposalRecording: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let recordedAt: String
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case recordedAt = "recorded_at"
        case durationMs = "duration_ms"
    }
}

/// The transcript block of a proposal.
struct PlaudTranscript: Decodable, Equatable, Sendable {
    let language: String
    let text: String
    let speakers: [String]
}

/// `GET /proposals/{recording_id}` response.
struct PlaudProposal: Decodable, Equatable, Sendable {
    let recording: PlaudProposalRecording
    let recordingKind: PlaudRecordingKind
    let themes: [PlaudTheme]
    let transcript: PlaudTranscript
    let warnings: [String]
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case recording, themes, transcript, warnings
        case recordingKind = "recording_kind"
        case generatedAt = "generated_at"
    }
}
