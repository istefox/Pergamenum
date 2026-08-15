import Foundation

/// `perg app open …` - the one command that needs Pergamenum running (ADR-0007 §D5).
///
/// Everything else here works on the files with the app closed. This is the actuator:
/// the `pergamenum://` routes of SPEC §9 already open a note, jump to a day and run a
/// search, and they launch the app when it is not running, so no new IPC channel had
/// to be invented for the half of the job that is "put this on screen".
///
/// The URLs are built with `PergamenumLink`, the same builder the app's "Copia link"
/// command uses, so a path with a space, an ampersand or a hash survives the trip.
enum AppCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        guard arguments.word(1) == "open" else {
            throw CommandError("«app \(arguments.word(1) ?? "")» non esiste; c'è «app open»", code: .usage)
        }

        let url = try route(arguments)

        // /usr/bin/open rather than NSWorkspace, which would link AppKit into a tool
        // that has no other use for it.
        //
        // Note which copy answers: `open <url>` hands the URL to LaunchServices, which
        // picks the *registered* bundle - normally the one in /Applications - and not
        // whichever copy happens to be running. That is the right default for a person
        // whose app is installed. `--app <percorso>` forces a particular bundle, which
        // is what a development build needs.
        var openArguments: [String] = []
        if let bundle = arguments["app"] {
            openArguments += ["-a", bundle]
        }
        openArguments.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = openArguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError("open ha risposto \(process.terminationStatus) per \(url.absoluteString)")
        }
        if arguments.has("json") {
            struct Payload: Encodable { let opened: String }
            Output.json(Payload(opened: url.absoluteString))
        } else {
            Output.line("aperto  \(url.absoluteString)")
        }
        return .success
    }

    @MainActor
    private static func route(_ arguments: Arguments) throws -> URL {
        switch arguments.word(2) {
        case "today":
            return try link(host: "today")
        case "note":
            let path = try requireWord(arguments, 3, "perg app open note <percorso>")
            guard let url = PergamenumLink.note(path: path) else {
                throw CommandError("percorso non trasformabile in link: \(path)")
            }
            return url
        case "day":
            let raw = try requireWord(arguments, 3, "perg app open day <data>")
            let date = try TaskCommands.resolveDay(raw)
            guard let url = PergamenumLink.day(date) else {
                throw CommandError("data non trasformabile in link: \(raw)")
            }
            return url
        case "search":
            let query = arguments.rest(from: 3)
            guard !query.isEmpty else {
                throw CommandError("uso: perg app open search <query>", code: .usage)
            }
            guard let url = PergamenumLink.search(query) else {
                throw CommandError("query non trasformabile in link: \(query)")
            }
            return url
        case let other:
            throw CommandError(
                "«\(other ?? "")» non è una rotta; ci sono today, note, day, search",
                code: .usage
            )
        }
    }

    private static func link(host: String) throws -> URL {
        var components = URLComponents()
        components.scheme = AppInfo.urlScheme
        components.host = host
        guard let url = components.url else {
            throw CommandError("rotta non costruibile: \(host)")
        }
        return url
    }

    private static func requireWord(_ arguments: Arguments, _ position: Int, _ usage: String) throws -> String {
        let value = arguments.rest(from: position)
        guard !value.isEmpty else { throw CommandError("uso: \(usage)", code: .usage) }
        return value
    }
}
