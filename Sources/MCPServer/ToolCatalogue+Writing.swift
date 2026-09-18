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
            name: "rename_note",
            description: """
                Rinomina una nota e riscrive ogni link e ogni card di board che punta al \
                vecchio titolo. dryRun è true se omesso: torna cosa cambierebbe senza \
                scrivere niente.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "title": ["type": "string", "description": "il nuovo titolo"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "title"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "move_note",
            description: """
                Sposta una nota in un'altra cartella e ripunta le card di board che la \
                mostrano. Nessun link da riscrivere: un wikilink nomina una nota per \
                titolo, non per percorso. dryRun è true se omesso.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "folder": ["type": "string", "description": "cartella di destinazione, la radice se omessa"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "trash_note",
            description: """
                Manda una nota al cestino di Finder e segnala chi resta con un link a \
                nulla. Il journal registra il testo intero: «undo_write» la rimette al \
                suo posto finché il cestino non è stato svuotato. dryRun è true se omesso.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false)
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
            name: "capture",
            description: """
                Cattura una riga dove dice la destinazione: «note» una nota nuova il cui \
                titolo è la prima riga, «task» una riga di task nell'inbox, «today» in \
                fondo alla nota di oggi che viene creata se manca, «note:PERCORSO» in \
                fondo a una nota che esiste. Le date valgono solo per «task». \
                dryRun è true se omesso.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "il testo da catturare"],
                    "destination": [
                        "type": "string",
                        "description": "note, task, today oppure note:PERCORSO; note se omessa",
                    ],
                    "folder": [
                        "type": "string",
                        "description": "solo con «note»: la cartella, «00 Inbox» se omessa",
                    ],
                    "scheduled": ["type": "string", "description": "solo con «task»: YYYY-MM-DD"],
                    "due": ["type": "string", "description": "solo con «task»: YYYY-MM-DD"],
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
            name: "pratica_link_note",
            description: """
                Collega una nota che già esiste a una pratica (ADR-0049, relazione \
                molti-a-molti). Se il riferimento c'è già non lo duplica. \
                dryRun è true se omesso.
                """,
            inputSchema: praticaLinkSchema("title", "il titolo della nota"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_unlink_note",
            description: "Scollega una nota da una pratica, senza toccare la nota. dryRun è true se omesso.",
            inputSchema: praticaLinkSchema("title", "il titolo della nota"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_link_board",
            description: "Collega una board che già esiste a una pratica. dryRun è true se omesso.",
            inputSchema: praticaLinkSchema("board", "il nome del file .canvas"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_unlink_board",
            description: "Scollega una board da una pratica, senza toccarla. dryRun è true se omesso.",
            inputSchema: praticaLinkSchema("board", "il nome del file .canvas"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_link_task",
            description: """
                Collega un task che già esiste a una pratica. Se il task non ha ancora \
                un ^id gliene assegna uno prima di collegarlo. dryRun è true se omesso.
                """,
            inputSchema: praticaLinkSchema("task", "il testo del task, oppure «percorso:riga»"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_unlink_task",
            description: """
                Scollega un task da una pratica, senza toccare il task. Un task senza \
                ^id non è collegato a niente: la risposta lo dice, non è un errore.
                """,
            inputSchema: praticaLinkSchema("task", "il testo del task, oppure «percorso:riga»"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "pratica_create_note",
            description: """
                Crea una nota nuova con i tag di contesto della pratica (topic-pratica, \
                client-*) e la collega subito - prima crea, poi collega. \
                dryRun è true se omesso.
                """,
            inputSchema: praticaCreateSchema("title", "il titolo della nuova nota"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "pratica_create_task",
            description: """
                Cattura un task nuovo nell'inbox, gli assegna un ^id e lo collega alla \
                pratica. dryRun è true se omesso.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "pratica": [
                        "type": "string",
                        "description": "il titolo della pratica, oppure il percorso della sua cartella",
                    ],
                    "text": ["type": "string", "description": "il testo del task, senza «- [ ]»"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["pratica", "text"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "pratica_create_board",
            description: """
                Crea una board vuota (ADR-0022) e la collega subito alla pratica. \
                dryRun è true se omesso.
                """,
            inputSchema: praticaCreateSchema("name", "il nome della nuova board"),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "message_link_note",
            description: """
                Collega una nota che già esiste a un singolo messaggio (relazione 0/1, \
                ADR-0049 §D6): collegarne una seconda sostituisce la prima invece di \
                aggiungersi. dryRun è true se omesso.
                """,
            inputSchema: messageLinkSchema(),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "message_unlink_note",
            description: "Scollega la nota di un messaggio, senza toccare la nota. dryRun è true se omesso.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "il percorso del messaggio"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["message"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "message_create_note",
            description: """
                Crea una nota nuova con i tag di contesto della pratica del messaggio e \
                la collega subito a quel messaggio. dryRun è true se omesso.
                """,
            inputSchema: messageLinkSchema(),
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

    /// Every pratica link/unlink pair takes the pratica plus one target field, named
    /// for what it actually is (`title`, `board`, `task`) rather than a generic
    /// `target` a caller would have to guess the meaning of.
    private static func praticaLinkSchema(_ key: String, _ description: String) -> Value {
        var properties: [String: Value] = [
            "pratica": [
                "type": "string",
                "description": "il titolo della pratica, oppure il percorso della sua cartella",
            ],
            "dryRun": dryRunProperty,
        ]
        properties[key] = ["type": "string", "description": .string(description)]
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string("pratica"), .string(key)]),
        ]
    }

    /// `pratica_create_note`/`pratica_create_board`: the same shape plus an optional
    /// destination folder, which `pratica_create_task` has no use for and does not share.
    private static func praticaCreateSchema(_ key: String, _ description: String) -> Value {
        var properties: [String: Value] = [
            "pratica": [
                "type": "string",
                "description": "il titolo della pratica, oppure il percorso della sua cartella",
            ],
            "folder": ["type": "string", "description": "cartella di destinazione, la radice se omessa"],
            "dryRun": dryRunProperty,
        ]
        properties[key] = ["type": "string", "description": .string(description)]
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string("pratica"), .string(key)]),
        ]
    }

    /// `message_link_note`/`message_create_note`: the message plus the note's title,
    /// both required, no dynamic key needed since neither tool varies the shape.
    private static func messageLinkSchema() -> Value {
        [
            "type": "object",
            "properties": [
                "message": ["type": "string", "description": "il percorso del messaggio"],
                "title": ["type": "string", "description": "il titolo della nota"],
                "dryRun": dryRunProperty,
            ],
            "required": ["message", "title"],
        ]
    }
}
