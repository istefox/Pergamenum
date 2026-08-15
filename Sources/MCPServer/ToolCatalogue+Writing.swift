import Foundation
import MCP

/// The tools that change a file, and the two schema helpers only they use.
///
/// In their own file rather than below the reading half: together they are a single
/// enum body of nearly three hundred lines, which is more than anyone reads in one go.
extension ToolCatalogue {
    /// Every one of these takes `dryRun`, and it defaults to **true**. Omitting it gets
    /// a diff and no change; writing takes a second call with `dryRun: false`.
    static let writing: [Tool] = [
        Tool(
            name: "create_note",
            description: """
                Crea una nota con frontmatter conforme già a posto. Rifiuta un titolo che \
                le regole non accettano invece di correggerlo di nascosto. \
                dryRun è true se omesso: torna il diff e non scrive.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "il titolo, che diventa anche il nome del file"],
                    "folder": ["type": "string", "description": "cartella di destinazione, la radice se omessa"],
                    "topic": ["type": "string", "description": "un tag topic-*, es. topic-acustica"],
                    "date": ["type": "string", "description": "YYYY-MM-DD, oggi se omesso"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["title"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "append_to_note",
            description: "Aggiunge testo in fondo a una nota che esiste, dopo una riga vuota.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "text": ["type": "string"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "text"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "add_task",
            description: """
                Aggiunge un task. Senza «note» finisce nell'inbox, che viene creato se \
                manca; con «note» la nota deve già esistere.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "il testo del task, senza «- [ ]»"],
                    "scheduled": ["type": "string", "description": "YYYY-MM-DD, il giorno in cui affiora"],
                    "due": ["type": "string", "description": "YYYY-MM-DD, oltre il quale è in ritardo"],
                    "note": ["type": "string", "description": "percorso della nota che lo ospita"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["text"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "complete_task",
            description: "Segna un task come fatto.",
            inputSchema: taskChangeSchema(),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "reopen_task",
            description: "Riapre un task chiuso.",
            inputSchema: taskChangeSchema(),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "reschedule_task",
            description: "Sposta il giorno in cui un task affiora, oppure lo toglie con «none».",
            inputSchema: taskChangeSchema(extra: [
                "to": ["type": "string", "description": "YYYY-MM-DD, oppure «none» per togliere la data"],
            ], required: ["to"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "add_time_block",
            description: """
                Mette un blocco sulla timeline di un giorno, creando la nota giornaliera \
                se manca. Se l'ora è occupata il blocco scala invece di sovrapporsi, e la \
                risposta lo dice in «note».
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "at": ["type": "string", "description": "ora di inizio, HH:MM"],
                    "minutes": ["type": "integer", "description": "durata; quella di default del vault se omessa"],
                    "day": ["type": "string", "description": "YYYY-MM-DD, oggi se omesso"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["title", "at"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "undo_write",
            description: """
                Rimette un file com'era prima di una scrittura registrata nel journal. \
                Si rifiuta se qualcuno lo ha toccato dopo, e non cancella: annullare una \
                creazione va fatto a mano.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "l'id che dà «journal_log»"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["id"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true)
        ),
    ]

    private static let dryRunProperty: Value = [
        "type": "boolean",
        "description": "true (il valore di default) calcola la scrittura e mostra il diff senza applicarla",
    ]

    /// The three task changes take the same argument: which task, said either as a
    /// phrase or exactly as `percorso:riga`.
    private static func taskChangeSchema(
        extra: [String: Value] = [:], required: [Value] = []
    ) -> Value {
        var properties: [String: Value] = [
            "task": [
                "type": "string",
                "description": "il testo del task, oppure «percorso:riga» per indicarlo esattamente",
            ],
            "dryRun": dryRunProperty,
        ]
        properties.merge(extra) { _, new in new }
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string("task")] + required),
        ]
    }
}
