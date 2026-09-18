import Foundation

/// `perg pratiche` and `perg pratica <titolo|percorso>` - the correspondence of one
/// matter, from a shell (ADR-0036, SPEC "Connectors" - R-36).
///
/// Read-only and Mail-free by construction: everything printed here comes from
/// `VaultAPI.pratiche(_:)`/`.pratica(_:_:)`, which read the vault's own files and the
/// per-vault ledger. Neither this file nor anything it calls opens Mail's store or
/// triggers a sync - TCC would attribute that access to the terminal that launched
/// `perg`, not to Pergamenum.
enum PraticheCommands {
    @MainActor
    static func list(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let pratiche = VaultAPI.pratiche(session)

        if arguments.has("json") {
            Output.json(pratiche)
        } else if pratiche.isEmpty {
            Output.line("nessuna pratica in questo vault")
        } else {
            for pratica in pratiche { print(pratica) }
        }
        return .success
    }

    @MainActor
    static func show(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        guard let reference = arguments.word(1) else {
            throw CommandError("«perg pratica» vuole il titolo o il percorso di una pratica", code: .usage)
        }
        let pratica = try VaultAPI.pratica(session, reference)

        if arguments.has("json") {
            Output.json(pratica)
        } else {
            print(pratica)
        }
        return .success
    }

    /// `pratica links <pratica>` (ADR-0049 §D12, R-01, R-07, R-08) - the general
    /// relations `show` does not carry, each with its own resolution state.
    @MainActor
    static func links(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let reference = try requireReference(arguments, "pratica links <pratica>")
        let links = try VaultAPI.praticaLinks(session, reference)

        if arguments.has("json") {
            Output.json(links)
        } else {
            print(links)
        }
        return .success
    }

    /// The pratica reference of every `pratica <verbo>` subcommand, once the verb
    /// itself has taken word(1) - the same shift `NoteCommands.requirePath` makes for
    /// `note rename`/`note move`.
    static func requireReference(_ arguments: Arguments, _ usage: String) throws -> String {
        guard let reference = arguments.word(2), !reference.isEmpty else {
            throw CommandError("uso: perg \(usage)", code: .usage)
        }
        return reference
    }

    /// The same shift for every `message <verbo>` subcommand, where word(2) is the
    /// message's own relative path rather than a pratica reference.
    static func requireMessagePath(_ arguments: Arguments, _ usage: String) throws -> String {
        guard let path = arguments.word(2), !path.isEmpty else {
            throw CommandError("uso: perg \(usage)", code: .usage)
        }
        return path
    }

    // MARK: - For a person

    /// One line per pratica: where it is, then what it is - client, stato, quanti
    /// messaggi, quante conversazioni aspettano di essere smistate, e quando è stata
    /// toccata l'ultima volta.
    private static func print(_ summary: VaultAPI.PraticaSummary) {
        var parts = [summary.client, summary.status, "\(summary.messageCount) messaggi"]
        if summary.trayCount > 0 { parts.append("\(summary.trayCount) da smistare") }
        parts.append(summary.lastActivity)
        Output.line("\(summary.path)    \(parts.joined(separator: " · "))")
    }

    /// The timeline as a transcript, oldest first - the order the pane draws and the
    /// order a person reads a correspondence in.
    private static func print(_ pratica: VaultAPI.PraticaTimelinePayload) {
        Output.line("\(pratica.title) · \(pratica.path) · \(pratica.entries.count) voci")
        for entry in pratica.entries {
            var header = [entry.date, label(of: entry)]
            if let from = entry.from { header.append(from) }
            Output.line("")
            Output.line("  \(header.joined(separator: "  "))")
            Output.line("  \(entry.subject)")
            if !entry.attachments.isEmpty {
                Output.line("  allegati: \(entry.attachments.joined(separator: ", "))")
            }
            for line in entry.body.components(separatedBy: "\n") where !line.isEmpty {
                Output.line("    \(line)")
            }
        }
    }

    /// The words the pane uses, so the two surfaces name the same row the same way.
    /// `direction` is only ever set on a message (SPEC "Connectors").
    private static func label(of entry: VaultAPI.PraticaTimelinePayload.Entry) -> String {
        switch (entry.kind, entry.direction) {
        case ("message", "sent"): "inviato"
        case ("message", _): "ricevuto"
        case ("call", _): "telefonata"
        default: "nota"
        }
    }

    /// The three general relations, each reference beside where it resolves to - the
    /// same three states `PraticaLinkResolver` produces (R-07, R-08).
    private static func print(_ links: VaultAPI.PraticaLinksPayload) {
        Output.line("collegamenti di \(links.path)")
        printLinkSection("note", links.notes)
        printLinkSection("task", links.tasks)
        printLinkSection("board", links.boards)
    }

    private static func printLinkSection(_ title: String, _ targets: [VaultAPI.PraticaLinkTarget]) {
        guard !targets.isEmpty else { return }
        Output.line("  \(title):")
        for target in targets {
            Output.line("    \(target.reference)  \(target.path ?? label(ofState: target.state))")
        }
    }

    private static func label(ofState state: String) -> String {
        switch state {
        case "ambiguous": "(ambiguo)"
        case "missing": "(non trovato)"
        default: "(\(state))"
        }
    }
}
