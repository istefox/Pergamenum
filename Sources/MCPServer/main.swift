import Foundation
import MCP

/// `pergamenum-mcp`, the vault as an MCP server (ADR-0007 §D1).
///
/// A local process speaking JSON-RPC over stdin and stdout, started by whatever client
/// wants it and living exactly as long as that client does. Pergamenum opens no socket
/// and this program opens none either: the network, if there is one, belongs to the
/// client, and principle 2 comes through untouched.
///
/// Writing is off unless `--allow-write` is passed, and even then every writing tool
/// rehearses by default (§D6). Two locks rather than one, because the cost of the second
/// is a boolean and the cost of being wrong is somebody's notes.

let help = """
pergamenum-mcp - il vault di Pergamenum come server MCP (ADR-0007)

USO
  pergamenum-mcp [--vault <cartella>] [--allow-write]

  --vault <cartella>   su quale vault agire
                       altrimenti $PERGAMENUM_VAULT, altrimenti l'ultimo aperto dall'app
  --allow-write        pubblica anche gli strumenti che scrivono. Senza questa opzione
                       il client non li vede nemmeno elencati
  --help               questo testo

Parla JSON-RPC su stdin e stdout: lanciarlo a mano da un terminale non serve a niente,
se non a vedere che parte. Va registrato in un client MCP, per esempio

  claude mcp add pergamenum -- /usr/local/bin/pergamenum-mcp --vault ~/Labs

Ogni strumento che scrive accetta dryRun, e dryRun vale true se non lo si passa: la
prima chiamata torna il diff, la seconda con dryRun false applica. Ogni scrittura
finisce in .pergamenum/ai-journal/ e «undo_write» sa rimetterla a posto.

Non ci sono: rinomina, spostamento ed eliminazione di note, che riscrivono i link in
molte note in una volta e che il journal non copre per intero; e Calendario di Apple,
perché TCC attribuirebbe l'accesso al processo che lancia questo, non a Pergamenum.
"""

/// The four methods this server answers. Kept out of `boot` so that adding a fifth does
/// not push the entry point past what a reader, or SwiftLint, will hold.
func register(_ host: VaultHost, on server: Server) async {
    await server.withMethodHandler(ListTools.self) { _ in
        await ListTools.Result(tools: host.tools)
    }
    await server.withMethodHandler(CallTool.self) { parameters in
        await host.call(parameters)
    }
    await server.withMethodHandler(ListResources.self) { parameters in
        await host.resources(after: parameters.cursor)
    }
    await server.withMethodHandler(ReadResource.self) { parameters in
        try await host.resource(at: parameters.uri)
    }
}

func boot() async -> Int32 {
    let arguments: Arguments
    do {
        arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    } catch {
        Diagnostics.log("\(error)")
        return 1
    }

    if arguments.has("help") {
        // To stderr like everything else: stdout is the transport even when nobody is
        // listening on it yet, and a program with one output channel is easier to trust
        // than one with a rule about when it may use the other.
        Diagnostics.log(help)
        return 0
    }

    let root: URL
    do {
        root = try VaultResolution.root(from: arguments)
    } catch let refusal as ConnectorError {
        Diagnostics.log(refusal.description)
        return 1
    } catch {
        Diagnostics.log("\(error)")
        return 1
    }

    let host = await VaultHost.open(at: root, allowsWriting: arguments.has("allow-write"))
    let server = Server(
        name: "pergamenum",
        version: version,
        instructions: instructions,
        capabilities: .init(resources: .init(subscribe: false, listChanged: false), tools: .init())
    )
    await register(host, on: server)

    do {
        try await server.start(transport: StdioTransport())
    } catch {
        Diagnostics.log("il trasporto non è partito: \(error)")
        return 2
    }
    Diagnostics.log(
        "in ascolto su \(root.path(percentEncoded: false)), "
            + (arguments.has("allow-write") ? "scrittura abilitata" : "sola lettura")
    )
    await server.waitUntilCompleted()
    return 0
}

/// What the server calls itself. Informational: what a client actually negotiates on is
/// the protocol revision, which the SDK owns.
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

/// Handed to the client at connection, and worth the words: a model that knows the two
/// closed schemas up front does not have to be told twice, and one that knows dryRun
/// defaults to true does not wonder why nothing changed.
let instructions = """
Il vault di Pergamenum: note markdown con wikilink, task che sono righe markdown, e una
timeline per giornata. Tutto è un file su disco.

Due schemi sono chiusi e non vanno estesi. Il frontmatter di una nota è esattamente
date, tags, related, aliases (SPEC §4.3). I tag sono stringhe piatte con namespace,
`client-`, `competitor-`, `project-`, `type-`, `topic-`, `status-`, `area-`, `source-`,
senza annidamento con «/» (SPEC §4.4).

Gli strumenti che scrivono, se ci sono, hanno dryRun a true di default: la prima
chiamata mostra il diff e non tocca niente, e serve una seconda chiamata con dryRun a
false per applicare. Ogni scrittura è registrata e annullabile con undo_write.
"""

exit(await boot())
