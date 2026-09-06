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
    var message: String {
        switch self {
        case .invalidDays:
            return "Intervallo di giorni non valido: il servizio accetta da 1 a 3650 giorni."
        case .unknownRecording:
            return "Registrazione sconosciuta: il servizio non la conosce più, aggiorna l'elenco."
        case .unknownJob:
            return "Elaborazione sconosciuta: il servizio ha perso traccia di questo lavoro, riprova."
        case .proposalNotFound:
            return "Nessuna proposta disponibile: elabora la registrazione prima di rivederla."
        case .payloadTooLarge:
            return "Richiesta troppo grande: il servizio ha rifiutato l'elenco delle attività."
        case .serviceDisconnected:
            return "Plaud non è collegato: collega il registratore e riprova."
        case let .transportFailure(detail):
            return "Servizio Plaud non raggiungibile su 127.0.0.1:3777. Dettaglio: \(detail)"
        case let .decodeFailure(detail):
            return "Risposta del servizio non riconosciuta. Dettaglio: \(detail)"
        case let .unrecognised(status, body):
            // R-07's verbatim half: a status this table has never seen is shown labelled
            // rather than dressed up as one of the sentences above.
            return body.isEmpty
                ? "Errore del servizio (HTTP \(status))."
                : "Errore del servizio (HTTP \(status)): \(body)"
        }
    }

    /// Maps an HTTP status and the raw `{"error": "..."}` response body to a case, per the
    /// measured table: 400 `invalid_days`; 404 `recording_not_found` / `job_not_found` /
    /// `proposal_not_found`; 413 `payload_too_large`; 503 by status alone (Plaud
    /// disconnected - the contract documents no informative body for it).
    static func map(status: Int, body: Data?) -> PlaudError {
        let data = body ?? Data()
        let code = (try? JSONDecoder().decode(WireError.self, from: data))?.error
        switch (status, code) {
        case (400, "invalid_days"): return .invalidDays
        case (404, "recording_not_found"): return .unknownRecording
        case (404, "job_not_found"): return .unknownJob
        case (404, "proposal_not_found"): return .proposalNotFound
        case (413, "payload_too_large"): return .payloadTooLarge
        case (503, _): return .serviceDisconnected
        default:
            let text = String(data: data, encoding: .utf8) ?? ""
            return .unrecognised(status: status, body: text)
        }
    }

    /// Maps a job/recording `last_error` string to a readable Italian message, with a
    /// verbatim-including fallback for anything unrecognised (R-07).
    ///
    /// Matched by prefix, not by equality: both coded strings measured live carry a variable
    /// tail (`themes is not an array`, `for chunk 2`), so an equality table would fall
    /// through to the fallback on the next chunk number.
    static func readableLastError(_ raw: String) -> String {
        if raw.hasPrefix("extraction_invalid") {
            return "Il servizio non è riuscito a estrarre le attività dalla trascrizione. Riprova l'elaborazione."
        }
        if raw.hasPrefix("cleanup returned no text") {
            return "La pulizia della trascrizione non ha prodotto testo per una parte della registrazione. Riprova l'elaborazione."
        }
        // Not a coded error at all - one of the three measured strings is a raw MCP tool
        // failure. Labelled and shown as it arrived: honest, and searchable.
        return "Elaborazione fallita: \(raw)"
    }

    /// The `{"error": "..."}` envelope every documented failure body carries.
    private struct WireError: Decodable {
        let error: String
    }
}
