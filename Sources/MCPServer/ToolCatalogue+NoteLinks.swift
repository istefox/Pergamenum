import Foundation
import MCP

/// «Collega» and «Scollega» as MCP tools (ADR-0084 §D3, §D4: connector parity, mandatory).
///
/// In their own file rather than appended to `ToolCatalogue+Writing.swift`, which is at the
/// edge of SwiftLint's `file_length` warning. Write tools: `VaultHost` lists and dispatches them
/// only under `--allow-write`, and `dryRun` defaults to **true** like every other write.
extension ToolCatalogue {
    static let noteLinks: [Tool] = [
        Tool(
            name: "link_mention",
            description: """
                Trasforma in link la prima menzione non collegata di una nota dentro un'altra: \
                [[Titolo]], o [[Titolo|testo]] quando il testo scritto è diverso dal titolo (un \
                alias, maiuscole, accenti). Un nome dentro il codice non è una menzione. Rifiuta \
                se la nota è cambiata nel frattempo. dryRun è true se omesso: torna il diff e non \
                scrive.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "il percorso della nota da scrivere"],
                    "title": ["type": "string", "description": "il titolo della nota da collegare"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "title"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
        Tool(
            name: "remove_structural_link",
            description: """
                Toglie un legame strutturale da entrambe le note: la voce in related e il punto \
                elenco sotto «Note correlate». Due percorsi, mai un titolo. Una scrittura riuscita \
                a metà torna quella arrivata, con una nota che nomina il lato rifiutato. dryRun è \
                true se omesso: torna i diff e non scrive.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "il percorso di una delle due note"],
                    "target": ["type": "string", "description": "il percorso dell'altra nota"],
                    "dryRun": dryRunProperty,
                ],
                "required": ["path", "target"],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false)
        ),
    ]
}
