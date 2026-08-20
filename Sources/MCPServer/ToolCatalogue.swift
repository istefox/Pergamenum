import Foundation
import MCP

/// What the server offers, and what each tool promises about itself.
///
/// Two lists, not one with a flag: the writing tools are never sent to a client that
/// launched the server without `--allow-write`, so a model cannot call what it was
/// never shown (ADR-0007 §D6). The dispatcher checks again anyway - a list is a
/// courtesy, not a lock.
///
/// The descriptions are in Italian, like every other sentence a person reads out of
/// this project. A model reads them too and does not mind.
enum ToolCatalogue {
    static let reading: [Tool] = [
        Tool(
            name: "search_vault",
            description: """
                Cerca nel vault. La query accetta tag:, path:, task:open, "frase esatta" \
                e parole sciolte, tutti in AND (SPEC §12). Restituisce percorso, titolo \
                e un estratto per ogni nota.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": #"es. tag:type-note "curva di taratura""#],
                    "limit": ["type": "integer", "description": "quanti risultati al massimo (200)"],
                ],
                "required": ["query"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "read_note",
            description: """
                Il testo di una nota, frontmatter compreso, esattamente come sta su disco, \
                più i suoi metadati.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "percorso relativo alla radice del vault"],
                ],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "list_notes",
            description: "Le note del vault, eventualmente filtrate per cartella.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "folder": ["type": "string", "description": "prefisso di percorso, es. «02 Progetti»"],
                ],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "note_links",
            description: "I wikilink che una nota porta, separati fra risolti e non risolti.",
            inputSchema: [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "note_backlinks",
            description: """
                Chi punta a un titolo. Si cerca per titolo e non per percorso, perché un \
                backlink è un wikilink e un wikilink nomina un titolo.
                """,
            inputSchema: [
                "type": "object",
                "properties": ["title": ["type": "string"]],
                "required": ["title"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "unresolved_links",
            description: "Ogni wikilink del vault a cui non risponde nessuna nota, con chi lo scrive.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "list_tasks",
            description: """
                I task del vault, che sono righe markdown e nient'altro (SPEC §7). \
                Ogni task torna con percorso e riga: servono per agire su quello giusto.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "view": [
                        "type": "string",
                        "enum": ["inbox", "today", "upcoming", "by-project", "all"],
                        "description": "la vista, «all» se omessa",
                    ],
                    "day": ["type": "string", "description": "giorno di riferimento YYYY-MM-DD, oggi se omesso"],
                    "includeCompleted": ["type": "boolean", "description": "anche i task chiusi (false)"],
                ],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "day_agenda",
            description: """
                Una giornata come il vault la scrive: blocchi della timeline, task in \
                programma e task in scadenza. Non legge Calendario di Apple: EventKit \
                resta all'app (ADR-0007 §D4).
                """,
            inputSchema: [
                "type": "object",
                "properties": ["day": ["type": "string", "description": "YYYY-MM-DD, oggi se omesso"]],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "lint_note",
            description: "Le violazioni di conformità di una nota (SPEC §4.7): nome, frontmatter, tag, related.",
            inputSchema: [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "lint_vault",
            description: """
                La conformità dell'intero vault. Se «warning» è valorizzato mancano i \
                vocabolari dei tag e il responso vale meno di quel che sembra.
                """,
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "list_views",
            description: """
                Le viste salvate nel vault: blocchi «pergamenum-view» dentro note ordinarie \
                (ADR-0009). Per ognuna dice in quale nota sta, in che posizione, come si \
                disegna e - se il blocco non si legge - perché. Legge ogni nota, quindi \
                chiedila quando serve, non a ogni giro.
                """,
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "run_view",
            description: """
                Esegue una vista e restituisce le righe che trova, con gli stessi campi e le \
                stesse celle che l'app disegna. «total» è quante note hanno risposto, prima \
                del limit del blocco.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "la nota che contiene il blocco"],
                    "ordinal": [
                        "type": "integer",
                        "description": "quale blocco, da 0; obbligatorio se la nota ne ha più d'uno",
                    ],
                ],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "vault_stats",
            description: "Quante note, quanti task, quanti link non risolti, quanto è durata la scansione.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "journal_log",
            description: """
                Le scritture fatte dai connettori, dalla più vecchia. Ogni riga ha un id \
                che «undo_write» sa annullare.
                """,
            inputSchema: [
                "type": "object",
                "properties": ["limit": ["type": "integer", "description": "quante righe (20)"]],
            ],
            annotations: .init(readOnlyHint: true)
        ),
    ]
}
