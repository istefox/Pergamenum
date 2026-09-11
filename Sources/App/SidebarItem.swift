import Foundation

/// A row of the sidebar.
///
/// Not the same thing as a pane, and that is the point. Seven panes were seven rows for
/// five milestones; what has been built since - the week and the month (ADR-0013 §D4),
/// the starred notes (ADR-0012 §D6), the saved views (ADR-0009) - is reachable only from
/// inside a pane, which is a place you have to already be to find out it exists.
///
/// Three kinds of row, and they behave differently on purpose:
///
/// - a **pane** is a destination, as it always was.
/// - a **scale** is the day pane with its scale set. Not a pane of its own: ADR-0013 §D4
///   says the three scales share one anchor, and two panes would be two anchors telling
///   two stories about which day you are looking at.
/// - **the day's note** is a row that opens a file, and it is still a destination: it
///   goes to the day scale, on today, with the note open in its column. It lights while
///   that is what you are looking at and goes out as soon as you move.
///
/// Nothing here is an action that lands somewhere else and leaves the highlight on a row
/// nobody chose - «Preferite» was one for an evening, and read as a click that had done
/// nothing.
enum SidebarItem: Hashable, Identifiable, Sendable {
    case pane(Navigation.Pane)
    case scale(DayScale)
    case dailyNote

    var id: String {
        switch self {
        case .pane(let pane): "pane-\(pane.rawValue)"
        case .scale(let scale): "scale-\(scale.rawValue)"
        case .dailyNote: "daily-note"
        }
    }

    var title: String {
        switch self {
        case .pane(let pane): pane.title
        case .scale(let scale): scale.title
        case .dailyNote: "Nota di oggi"
        }
    }

    var symbol: String {
        switch self {
        case .pane(let pane): pane.symbol
        case .scale(.day): "calendar.day.timeline.left"
        case .scale(.week): "calendar.badge.clock"
        case .scale(.month): "calendar"
        case .dailyNote: "doc.badge.clock"
        }
    }

    /// The three headings the rows sit under.
    ///
    /// Eleven rows in one flat list read as a list of commands rather than as the places
    /// of an app. Grouped, the sidebar says what kind of thing each row is before it says
    /// which one.
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case vault
        case day
        case work

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vault: "VAULT"
            case .day: "GIORNATA"
            case .work: "LAVORO"
            }
        }

        var items: [SidebarItem] {
            switch self {
            case .vault:
                [.pane(.notes), .pane(.workspace), .pane(.tags), .pane(.starred), .pane(.views)]
            case .day:
                [.pane(.today), .scale(.week), .scale(.month), .dailyNote, .pane(.diary)]
            case .work:
                // «Registrazioni» last (ADR-0032 §D15): the blueprint asks for the new row
                // at the end of the sidebar, and LAVORO is the group it belongs to - an
                // import is work done on the vault, not a place inside it.
                //
                // «Pratiche» immediately before it (ADR-0036, R-33, UX-BLUEPRINT
                // "Navigation structure"): a pratica is a place inside the vault you come
                // back to, so it sits above the import row rather than after it. The app
                // sidebar stays flat - the pratiche tree lives in the pane's own list
                // column, as the notes do.
                [.pane(.tasks), .pane(.pratiche), .pane(.recordings)]
            }
        }
    }
}
