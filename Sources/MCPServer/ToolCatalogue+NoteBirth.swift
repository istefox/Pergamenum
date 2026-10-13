import Foundation
import MCP

/// «Classifica» and «Estrai in una nota» as MCP tools (ADR-0085 §D10: connector parity), and the
/// `template` property `create_note` and `capture` share (ADR-0086 §D6).
///
/// In their own file rather than appended to `ToolCatalogue+Writing.swift`, which is at the edge
/// of SwiftLint's `file_length` warning. Write tools: `VaultHost` lists and dispatches them only
/// under `--allow-write`, and `dryRun` defaults to **true** like every other write.
extension ToolCatalogue {
    static let noteBirth: [Tool] = [
        Tool(
            name: "classify_note",
            description: """
                Classifica una nota: toglie status-inbox, tiene o aggiunge type-note, aggiunge i \
                topic, al massimo sette tag; poi, se c'è folder, la sposta. Prima scrive, poi \
                sposta: uno spostamento non riuscito lascia la nota classificata dov'era e lo \
                dice in note. Una scheda del Contenitore si classifica senza folder. dryRun è \
                true se omesso: torna il diff e non scrive.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "il percorso della nota da classificare"],
                    "topics": ["type": "string", "description":
                        "i topic separati da virgola, con o senza prefisso: materiali, topic-acustica"],
                    "folder": ["type": "string", "description": "la cartella in cui spostarla dopo, se serve"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "topics"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "extract_to_note",
            description: """
                Estrae delle righe in una nota nuova: le righe da fromLine a toLine (da 1, \
                incluse, contate sull'intero file, frontmatter compreso) diventano il corpo della \
                nota e al loro posto resta [[title]]. Rifiuta un intervallo che tocca il \
                frontmatter. Se la seconda scrittura è rifiutata la nota nuova resta e \
                sourceRefused dice perché. dryRun è true se omesso: torna i due diff e non scrive.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "il percorso della nota da cui estrarre"],
                    "fromLine": ["type": "integer", "description": "la prima riga, da 1"],
                    "toLine": ["type": "integer", "description": "l'ultima riga, inclusa"],
                    "title": ["type": "string", "description": "il titolo della nota nuova"],
                    "folder": ["type": "string", "description": "la cartella della nota nuova, quella della fonte se omessa"],
                    "topics": ["type": "string", "description": "i topic della nota nuova, separati da virgola"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "fromLine", "toLine", "title"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
    ]

    /// `create_note`'s and `capture`'s template, by path or by title (ADR-0086 §D6).
    static let templateProperty: Value = [
        "type": "string",
        "description": """
            una nota di Templates/, per percorso o titolo; {{cursor}} viene tolto. Con capture vale \
            solo per la destinazione «note»: il testo va al {{cursor}} o dopo il corpo
            """,
    ]
}
