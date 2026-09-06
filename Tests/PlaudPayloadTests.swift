import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 1 -
// R-03, R-07, R-13.
//
// Fixtures captured verbatim, live, on 2026-09-05:
//   curl -s http://127.0.0.1:3777/recordings?days=14
//   curl -s http://127.0.0.1:3777/proposals/265473800bc50a6cdfc7a602f390d1d3
// Not tidied: the >60-character name keeps its colon, `last_error` keeps all three raw
// strings verbatim (including the escaped inner quotes in the third), and the
// `themes: []` proposal keeps its empty array and its `no_action_items` warning.
//
// `themedProposalJSON` is a hand-assembled subset of a second live capture
// (`/proposals/2dade977e60e3428deaee7bffc75bd9b`, ~17KB of transcript - too large to embed
// whole against this task's own line budget) built only from values measured in that same
// response: the real `recording` object, `recording_kind`, one theme's two real tasks (one
// `due_hint` null, one not), and an unedited prefix of the measured transcript text, cut at
// a sentence boundary rather than reworded.
@Suite struct PlaudPayloadTests {
    // MARK: - Fixtures

    private static let recordingsListJSON = """
    {"recordings":[{"id":"2dade977e60e3428deaee7bffc75bd9b","name":"09-04 Riunione: Preparazione Audit CGM per Ferrari - Diagramma di Flusso Boccole","recorded_at":"2026-09-04T11:48:07","duration_ms":1236000,"device_serial":"8810B30226192074","state":"ready","last_error":null},{"id":"18682e82795a2eddecf9ec94f2a48ab0","name":"2026-09-04 13:44:51","recorded_at":"2026-09-04T11:44:51","duration_ms":36000,"device_serial":"8810B30226192074","state":"failed","last_error":"Plaud MCP tool get_transcript returned non-JSON content: Block \\"transaction\\" not available for this recording. Available blocks: mark_memo."},{"id":"557e5549189f37981d758c6bf0181f59","name":"09-04 Riunione: Sicurezza, Riorganizzazione e Marketing Vibrofer","recorded_at":"2026-09-04T07:27:48","duration_ms":6448000,"device_serial":"8810B30226192074","state":"failed","last_error":"extraction_invalid: themes is not an array"},{"id":"265473800bc50a6cdfc7a602f390d1d3","name":"09-03 Chiamata: Cambio Fornitore Energia e Sconto Tariffa 30","recorded_at":"2026-09-03T11:58:58","duration_ms":75000,"device_serial":"8810B30226192074","state":"ready","last_error":null},{"id":"20b5d4ee05e014412f7f65579c0d07aa","name":"09-03 Riunione: Problema Antivibranti Ferrari e Gestione Magazzino","recorded_at":"2026-09-03T08:54:40","duration_ms":3454000,"device_serial":"8810B30226192074","state":"ready","last_error":null},{"id":"50c2649e7c7e0ec40f8abaf3138f0199","name":"09-03 Riunione: Riorganizzazione del Personale e Gestione Aziendale","recorded_at":"2026-09-03T07:21:00","duration_ms":5063000,"device_serial":"8810B30226192074","state":"failed","last_error":"extraction_invalid: themes is not an array"},{"id":"037deef97fc44996734b37a3fd6f30d9","name":"07-23 Formazione: Tecniche di Comunicazione Efficace e Realizzazione Personale","recorded_at":"2026-07-23T07:56:39","duration_ms":10992000,"device_serial":"8810B30226192074","state":"failed","last_error":"cleanup returned no text for chunk 2"},{"id":"5a6bdfc765cc205f1624b7100314fed1","name":"07-22 Formazione: Affiancamento Raffaele su Gestione Offerte, Ordini e Clienti Vibrofer","recorded_at":"2026-07-22T06:08:20","duration_ms":8571000,"device_serial":"8810B30226192074","state":"failed","last_error":"extraction_invalid: themes is not an array"}]}
    """

    private static let emptyThemesProposalJSON = """
    {"recording":{"id":"265473800bc50a6cdfc7a602f390d1d3","name":"2026-09-03 13:58:58","recorded_at":"2026-09-03T11:58:58","duration_ms":75000},"recording_kind":"update","themes":[],"transcript":{"language":"it","text":"Speaker 1: Che riceverà le prossime bollette dal produttore di partnership di Chiata Energia e Energia Verde, perché essendo che lei è nato nel 1976, lei rientra nella seconda fascia di tutela regionale per avere la riduzione di tariffa del 30%. Tutto chiaro? Sì, quindi cosa devo fare? Gian Stefano, attenda soltanto un attimo, io le faccio dare il tour di informazione. Attenda un attimo. No, ma guardi, lasci stare.","speakers":["Speaker 1"]},"warnings":["no_action_items"],"generated_at":"2026-09-05T07:55:24.906Z"}
    """

    private static let themedProposalJSON = """
    {"recording":{"id":"2dade977e60e3428deaee7bffc75bd9b","name":"2026-09-04 13:48:07","recorded_at":"2026-09-04T11:48:07","duration_ms":1236000},"recording_kind":"meeting","themes":[{"name":"Preparazione audit CGM/Ferrari","tasks":[{"id":"7cec8849-f9be-4090-983e-9578e9cc6bb8","title":"Organizzare le cassette con numero di fase di lavorazione identificato","quote":"Bisogna mettere in cassette quel numero. Di stadio a cui è il pezzo praticamente","urgency":5,"importance":5,"due_hint":null},{"id":"ded44744-11e8-498c-8f68-2500913c77b1","title":"Valentina: scrivere email lunedì per posticipare audit adducendo malattia di Simone","quote":"aspettiamo lunedì gli scrivo io dicendo che tu mi hai telefonato e che sei a casa in malattia con l'influenza","urgency":5,"importance":4,"due_hint":"2025-01-14"}]}],"transcript":{"language":"it","text":"Speaker 1: Allora, per quanto riguarda una cosa veloce che dobbiamo valutare, ho parlato con mio padre perché lui aveva già avuto un'ispezione dalla CGM e anche dalla Ferrari. Mi diceva che Andrea, e comunque la CGM e Andrea, sono molto molto puntigliosi.","speakers":["Speaker 1","Simone Salvadori","Raffaele Battimiello","Valentina Testi"]},"warnings":[],"generated_at":"2026-09-05T07:54:16.838Z"}
    """

    // MARK: - Decoding /recordings

    @Test func decodesAllEightMeasuredRecordings() throws {
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        #expect(response.recordings.count == 8)
    }

    @Test func preservesTheOverlongHumanTitleWithItsColon() throws {
        // Measured: seven of eight rows are human titles, not timestamps - this one is 80
        // characters and contains ":", both of which disqualify it as a note title
        // (`NoteName.maximumLength` 60, `:` in `NoteName.forbiddenCharacters`) - D5's whole
        // reason for deriving the note name rather than taking it from the recording.
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        let first = response.recordings[0]
        #expect(
            first.name
                == "09-04 Riunione: Preparazione Audit CGM per Ferrari - Diagramma di Flusso Boccole"
        )
        #expect(first.name.count > 60)
        #expect(first.name.contains(":"))
    }

    @Test func preservesTheOldTimestampStyleNameSideBySideWithHumanTitles() throws {
        // Both shapes are in the wild at once (ADR M1): this row still carries the old
        // `name` form, unlike its seven siblings.
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        #expect(response.recordings[1].name == "2026-09-04 13:44:51")
    }

    @Test func decodesTheTwoMeasuredKnownStates() throws {
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        #expect(response.recordings[0].state == .ready)
        #expect(response.recordings[1].state == .failed)
    }

    @Test func decodesAnUnrecognisedStateAsUnknownRatherThanThrowing() throws {
        // A service upgrade adding a state must not break the whole list decode - the whole
        // reason `PlaudRecordingState` is a tolerant wrapper and not a throwing
        // `RawRepresentable` enum. No live row carries an unrecognised state today, so this
        // one case is a synthetic minimal row, not a live capture.
        let json = """
        {"recordings":[{"id":"x","name":"n","recorded_at":"2026-01-01T00:00:00",\
        "duration_ms":1,"device_serial":"s","state":"archived_by_a_future_service",\
        "last_error":null}]}
        """
        let response = try JSONDecoder().decode(PlaudRecordingsResponse.self, from: Data(json.utf8))
        #expect(response.recordings[0].state == .unknown("archived_by_a_future_service"))
    }

    @Test func nullLastErrorDecodesAsNilOnAReadyRecording() throws {
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        #expect(response.recordings[0].lastError == nil)
    }

    @Test func preservesAllThreeMeasuredLastErrorStringsVerbatim() throws {
        // Five of eight recordings are `failed` (ADR M5) - R-07's readable-error mapping is
        // the common path, not a corner, and needs a table plus a fallback because the
        // third string here is not a coded error at all.
        let response = try JSONDecoder().decode(
            PlaudRecordingsResponse.self, from: Data(Self.recordingsListJSON.utf8)
        )
        let lastErrors = response.recordings.compactMap(\.lastError)
        #expect(lastErrors.contains("extraction_invalid: themes is not an array"))
        #expect(lastErrors.contains("cleanup returned no text for chunk 2"))
        #expect(
            lastErrors.contains(
                #"Plaud MCP tool get_transcript returned non-JSON content: Block "transaction" not available for this recording. Available blocks: mark_memo."#
            )
        )
    }

    // MARK: - Decoding /proposals/{recording_id}

    @Test func decodesAZeroThemeProposalWithItsWarning() throws {
        // A live proposal has `themes: []` with `warnings: ["no_action_items"]` right now
        // (ADR, measured) - the SPEC's zero-theme edge case is not hypothetical.
        let proposal = try JSONDecoder().decode(
            PlaudProposal.self, from: Data(Self.emptyThemesProposalJSON.utf8)
        )
        #expect(proposal.themes.isEmpty)
        #expect(proposal.warnings == ["no_action_items"])
        #expect(proposal.recordingKind == .update)
    }

    @Test func decodesAnUnrecognisedRecordingKindAsUnknownRatherThanThrowing() throws {
        let json = """
        {"recording":{"id":"x","name":"n","recorded_at":"2026-01-01T00:00:00",\
        "duration_ms":1},"recording_kind":"symposium","themes":[],\
        "transcript":{"language":"it","text":"","speakers":[]},"warnings":[],\
        "generated_at":"2026-01-01T00:00:00.000Z"}
        """
        let proposal = try JSONDecoder().decode(PlaudProposal.self, from: Data(json.utf8))
        #expect(proposal.recordingKind == .unknown("symposium"))
    }

    @Test func decodesTasksWithAndWithoutADueHint() throws {
        // `due_hint` was null on every task sampled, 25 of 25 (ADR, measured) - the `>date`
        // marker is the exception, not the rule.
        let proposal = try JSONDecoder().decode(
            PlaudProposal.self, from: Data(Self.themedProposalJSON.utf8)
        )
        let tasks = proposal.themes[0].tasks
        let withHint = tasks.first { $0.dueHint != nil }
        let withoutHint = tasks.first { $0.dueHint == nil }
        #expect(withHint?.dueHint == "2025-01-14")
        #expect(withoutHint?.dueHint == nil)
    }

    @Test func decodesGeneratedAtWithFractionalSecondsAndZoneVerbatim() throws {
        let proposal = try JSONDecoder().decode(
            PlaudProposal.self, from: Data(Self.themedProposalJSON.utf8)
        )
        #expect(proposal.generatedAt == "2026-09-05T07:54:16.838Z")
    }

    // MARK: - PlaudError: HTTP status + body mapping (measured live and from the contract)

    @Test func mapsFourHundredInvalidDays() {
        let body = Data(#"{"error":"invalid_days"}"#.utf8)
        #expect(PlaudError.map(status: 400, body: body) == .invalidDays)
    }

    @Test func mapsFourOhFourAcrossItsThreeMeasuredShapes() {
        #expect(
            PlaudError.map(status: 404, body: Data(#"{"error":"recording_not_found"}"#.utf8))
                == .unknownRecording
        )
        #expect(
            PlaudError.map(status: 404, body: Data(#"{"error":"job_not_found"}"#.utf8)) == .unknownJob
        )
        #expect(
            PlaudError.map(status: 404, body: Data(#"{"error":"proposal_not_found"}"#.utf8))
                == .proposalNotFound
        )
    }

    @Test func mapsFourHundredOnTheImportedRouteAcrossItsTwoSubCodes() {
        // PG-097: `POST /proposals/{id}/imported` documents two distinct 400 bodies, both of
        // which used to fall through to the generic `.unrecognised`.
        #expect(
            PlaudError.map(status: 400, body: Data(#"{"error":"invalid_json"}"#.utf8))
                == .invalidImportBody
        )
        #expect(
            PlaudError.map(status: 400, body: Data(#"{"error":"invalid_task_ids"}"#.utf8))
                == .invalidTaskIDs
        )
    }

    @Test func mapsFourHundredThirteenPayloadTooLarge() {
        // Not reproduced live (it needs a >64KiB confirm body); the exact wire shape is
        // documented in `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md`, read-only,
        // never copied into this repo.
        #expect(
            PlaudError.map(status: 413, body: Data(#"{"error":"payload_too_large"}"#.utf8))
                == .payloadTooLarge
        )
    }

    @Test func mapsFiveOhThreeAsServiceDisconnectedByStatusAlone() {
        // Not reproduced live (Plaud is connected on this machine); the contract documents
        // 503 for `/recordings` and `/recordings/{id}/process` "when Plaud is disconnected"
        // with no informative body shape given, so the status code alone must be enough.
        #expect(PlaudError.map(status: 503, body: nil) == .serviceDisconnected)
    }

    @Test func everyMappedCaseProducesANonEmptyReadableMessage() {
        // R-07: "readable, not raw" - a mapped case must produce something a person can
        // read, and it must not be the wire's own error token verbatim.
        let cases: [PlaudError] = [
            .invalidDays, .unknownRecording, .unknownJob, .proposalNotFound,
            .payloadTooLarge, .serviceDisconnected, .invalidImportBody, .invalidTaskIDs,
        ]
        for error in cases {
            #expect(!error.message.isEmpty, "\(error) has no readable message")
        }
        #expect(PlaudError.invalidDays.message != "invalid_days")
    }

    @Test func transportFailureProducesAReadableMessage() {
        // The socket never got a response at all - "service down", not a coded wire error.
        #expect(!PlaudError.transportFailure("Could not connect to the server.").message.isEmpty)
    }

    @Test func decodeFailureProducesAReadableMessage() {
        // A 200 response whose body did not match the expected shape.
        #expect(!PlaudError.decodeFailure("keyNotFound(CodingKeys.state)").message.isEmpty)
    }

    // MARK: - PlaudError: last_error string mapping (measured, all three raw strings)

    @Test func mapsExtractionInvalidToAReadableMessage() {
        let message = PlaudError.readableLastError("extraction_invalid: themes is not an array")
        #expect(message != "extraction_invalid: themes is not an array")
        #expect(!message.isEmpty)
    }

    @Test func mapsCleanupReturnedNoTextToAReadableMessage() {
        let message = PlaudError.readableLastError("cleanup returned no text for chunk 2")
        #expect(message != "cleanup returned no text for chunk 2")
    }

    @Test func fallsBackVerbatimForAnUncodedFailureString() {
        // Measured: not a coded error at all, and the wire's own truncation ("Bl…") stays
        // exactly as captured - tidying it would test a string nobody's service ever sent.
        let raw = #"Plaud MCP tool get_transcript returned non-JSON content: Block "transaction" not available for this recording. Available blocks: mark_memo."#
        #expect(PlaudError.readableLastError(raw).contains(raw))
    }
}
