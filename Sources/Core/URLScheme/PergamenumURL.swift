import Foundation

/// The `pergamenum://` routes of SPEC §9.
///
/// Every route is idempotent and opens the app if it is closed, so a link pasted into
/// Obsidian, DEVONthink, Mail or Calendar behaves the same however often it is
/// clicked.
enum PergamenumRoute: Equatable, Sendable {
    /// `pergamenum://note?file=<path>`
    case note(path: String)
    /// `pergamenum://note?id=<uuid>`
    case noteID(String)
    /// `pergamenum://canvas?file=<path>[&node=<id>]`
    case canvas(path: String, nodeID: String?)
    /// `pergamenum://day/YYYYMMDD`
    case day(CalendarDate)
    case today
    /// `pergamenum://search?q=<query>`
    case search(String)
    /// `pergamenum://capture?text=<t>[&dest=<d>][&note=<path>][&schedule=<d>][&deadline=<d>]`,
    /// appended without raising the app.
    ///
    /// `dest` is carried as written and resolved by the connector, which owns the four
    /// destinations of ADR-0008 §D6: this type lives in `Core` and cannot see them.
    case capture(text: String, destination: String?, scheduled: String?, due: String?)
    /// `pergamenum://task?add=<text>`
    case addTask(String)

    /// Parses a URL into a route, or nil when it is not one this app answers.
    ///
    /// Unknown routes return nil rather than a nearest guess: a link that opens the
    /// wrong note is worse than a link that reports it does not work.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == AppInfo.urlScheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // `pergamenum://day/20260811` puts "day" in the host and the date in the path;
        // `pergamenum://today` has no path at all.
        let host = components.host?.lowercased() ?? ""
        let pathComponents = components.path.split(separator: "/").map(String.init)

        func query(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }

        switch host {
        case "note":
            if let file = query("file"), !file.isEmpty {
                self = .note(path: file)
            } else if let id = query("id"), !id.isEmpty {
                self = .noteID(id)
            } else {
                return nil
            }
        case "canvas":
            guard let file = query("file"), !file.isEmpty else { return nil }
            self = .canvas(path: file, nodeID: query("node"))
        case "day":
            guard let first = pathComponents.first, let date = CalendarDate(compact: first) else { return nil }
            self = .day(date)
        case "today":
            self = .today
        case "search":
            guard let q = query("q"), !q.isEmpty else { return nil }
            self = .search(q)
        case "capture":
            guard let text = query("text"), !text.isEmpty else { return nil }
            // `?note=<path>` is the form SPEC §9 published and Shortcuts may already
            // hold, so it keeps working and means what it always meant: append to that
            // note. An explicit `?dest=` wins when both are given.
            let destination = query("dest") ?? query("note").map { "note:\($0)" }
            self = .capture(
                text: text,
                destination: destination,
                scheduled: query("schedule"),
                due: query("deadline")
            )
        case "task":
            guard let add = query("add"), !add.isEmpty else { return nil }
            self = .addTask(add)
        default:
            return nil
        }
    }

    /// Whether handling this route should bring the app to the front.
    ///
    /// `capture` is explicitly excluded by SPEC §9: it appends text without
    /// interrupting whatever the user is doing in another app.
    var raisesApp: Bool {
        if case .capture = self { return false }
        return true
    }

    /// The case name alone, with no associated value (PG-125) - safe to log with
    /// `privacy: .public`, unlike the route itself, which carries capture text, search
    /// queries and note paths.
    var kind: String {
        switch self {
        case .note: "note"
        case .noteID: "noteID"
        case .canvas: "canvas"
        case .day: "day"
        case .today: "today"
        case .search: "search"
        case .capture: "capture"
        case .addTask: "addTask"
        }
    }
}

/// Builds `pergamenum://` links (SPEC §9), in two forms for a note. The stable id form
/// (`note(id:)`) is what «Copia link Pergamenum» copies (ADR-0059 §D8); the path form
/// (`note(path:)`) stays where a path is the point - `perg app open note`, the MCP note
/// resources, reminder notifications - and is the fallback when no id can be minted.
enum PergamenumLink {
    /// Percent-encodes a path so a note whose name contains `&`, `?`, `#` or a space
    /// survives the round-trip through a URL.
    static func note(path: String) -> URL? {
        build(host: "note", queryItems: [URLQueryItem(name: "file", value: path)])
    }

    /// A `pergamenum://note?id=<id>` link (ADR-0059 §D8), the durable form: it survives
    /// every rename and move the app performs.
    static func note(id: String) -> URL? {
        build(host: "note", queryItems: [URLQueryItem(name: "id", value: id)])
    }

    static func canvas(path: String, nodeID: String? = nil) -> URL? {
        var items = [URLQueryItem(name: "file", value: path)]
        if let nodeID { items.append(URLQueryItem(name: "node", value: nodeID)) }
        return build(host: "canvas", queryItems: items)
    }

    static func day(_ date: CalendarDate) -> URL? {
        var components = URLComponents()
        components.scheme = AppInfo.urlScheme
        components.host = "day"
        components.path = "/\(date.compactForm)"
        return components.url
    }

    static func search(_ query: String) -> URL? {
        build(host: "search", queryItems: [URLQueryItem(name: "q", value: query)])
    }

    private static func build(host: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = AppInfo.urlScheme
        components.host = host
        components.queryItems = queryItems
        return components.url
    }
}
