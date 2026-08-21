import Foundation

/// The note an event gets when somebody asks for one (ADR-0013 §D2, §D3).
///
/// `Calendar/YYYYMMDD-<slug>.md`, in the folder SPEC §8.1 already configures for daily notes,
/// **beside** `YYYYMMDD.md` rather than in a reserved folder of its own: an event note is part
/// of that day, and a vault whose daily folder is called something else gets its event notes
/// there without a second setting.
///
/// The name is safe against the rules that already exist, and this was checked rather than
/// assumed: `NoteName.category` calls a note *daily* only when its stem parses as a compact
/// date, so `20260820-riunione-tecnica` is an ordinary note, judged by `NoteName.validate`,
/// which it passes.
///
/// Pure, and outside `Sources/Calendar` on purpose: everything here can be wrong - a slug that
/// collides, a body that loses the hour - without EventKit being involved, and a test that
/// needed calendar permission to run is a test that does not run.
enum EventNote {
    /// `20260820-riunione-tecnica` from "Riunione tecnica" on that day.
    ///
    /// The slug comes from `ImportNaming.kebabCase`, the same function that names an imported
    /// email, so an event and a message about it are named by one rule rather than two.
    /// An event with no usable title keeps the date alone, which is a conformant name.
    static func title(for eventTitle: String, on day: CalendarDate) -> String {
        let slug = ImportNaming.kebabCase(eventTitle)
        return slug.isEmpty ? day.compactForm : "\(day.compactForm)-\(slug)"
    }

    /// What the note says the moment it is created.
    ///
    /// The hour and the attendees stamped from the event, and a link back to the day. Ordinary
    /// markdown throughout: the link is a `[[…]]` like any other, so the backlink panel already
    /// answers "which day was this meeting on" without anything new being indexed.
    ///
    /// An all-day event has no hour to stamp, so it says so rather than writing `00:00-00:00`.
    static func body(
        eventTitle: String,
        start: TaskTime?,
        end: TaskTime?,
        attendees: [String],
        day: CalendarDate
    ) -> String {
        var lines: [String] = []
        if let start, let end {
            lines.append("\(start.text)–\(end.text) · \(eventTitle)")
        } else {
            lines.append("Tutto il giorno · \(eventTitle)")
        }
        if !attendees.isEmpty {
            lines.append("Con: " + attendees.joined(separator: ", "))
        }
        lines.append("")
        lines.append("Da [[\(day.compactForm)]]")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

/// The list of event notes inside a daily note.
///
/// A heading with one wikilink per line, written the way `TimeBlockSection` writes the
/// timeline: a section the app owns and rewrites, so creating two event notes for one day
/// leaves two lines rather than two paragraphs somewhere in the middle of what was typed.
enum EventNoteSection {
    static let heading = "## Note"

    /// Adds a link, or returns the body untouched when it is already there.
    ///
    /// Idempotent because the second click has to be harmless: an event whose note exists is
    /// offered "apri", not "crea", but a vault edited by hand can always end up asking twice.
    static func adding(_ title: String, to body: String) -> String {
        let link = "- [[\(title)]]"
        guard !body.contains(link) else { return body }

        guard let range = body.range(of: heading) else {
            let separator = body.hasSuffix("\n\n") ? "" : (body.hasSuffix("\n") ? "\n" : "\n\n")
            return body + separator + heading + "\n\n" + link + "\n"
        }

        // Insert at the end of the section rather than at the end of the note: the section
        // ends at the next heading, and a link written past it would belong to that one.
        let afterHeading = body[range.upperBound...]
        let nextHeading = afterHeading.range(of: "\n#")
        let end = nextHeading?.lowerBound ?? body.endIndex

        var result = body
        let section = String(body[range.upperBound..<end])
        let trimmed = section.hasSuffix("\n")
            ? String(section.dropLast())
            : section
        result.replaceSubrange(range.upperBound..<end, with: trimmed + "\n" + link + "\n")
        return result
    }
}
