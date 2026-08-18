import Foundation

/// Notes kept as starting text for other notes (ADR-0011 D5-D7).
///
/// A template is an ordinary note that happens to live in `Templates/`. Nothing marks
/// it beyond the folder: SPEC §4.4's tag namespace is harness-owned and closed, so a
/// `type-template` marker would mean asking the `harness-system` repo to grow a value
/// for a convention that is this app's alone. A location needs no vocabulary change.
///
/// It follows that a template opens, edits, saves, indexes and appears in search exactly
/// like any other note, and gets its own `NoteHistory` for free. There is no second
/// class of file here, only a reserved place.
enum NoteTemplate {
    /// The reserved folder, at the vault root.
    ///
    /// A vault that already had an ordinary folder by this name has its contents read as
    /// templates from now on. That is a line in the release notes and not a migration:
    /// nothing is moved, rewritten or deleted, the folder simply starts being offered.
    static let folder = "Templates"

    static func isTemplate(_ relativePath: String) -> Bool {
        relativePath.hasPrefix(folder + "/")
    }

    /// What a template actually contributes: everything after its own frontmatter.
    ///
    /// **The template's frontmatter is discarded, never copied.** The new note gets the
    /// conformant four-key block `createNote` computes for it, exactly as it does with
    /// no template at all - copying the template's would carry over its date and its
    /// tags, which belong to the template rather than to what is being written.
    ///
    /// Leading blank lines go too, because the caller supplies the single separating one
    /// itself; without this a template whose body began after a blank line would open a
    /// note with two.
    static func body(of text: String) -> String {
        // Reuses the parser the rest of the app reads notes with, rather than splitting
        // on `---` again here: it already answers the awkward cases - no block at all, an
        // opening delimiter that is never closed - by treating the whole file as body,
        // which is what a template wants too.
        let document = NoteDocument.parse(text)
        var body = Substring(document.body)
        while body.first == "\n" || body.first == "\r" {
            body = body.dropFirst()
        }
        return String(body)
    }

    /// Substitutes the two placeholders v1 knows, and only those.
    ///
    /// An unrecognised `{{…}}` is left exactly as written. Silently emptying it would
    /// destroy text the person typed on the strength of a guess about what they meant;
    /// left visible, it is a question they can answer themselves.
    static func substituting(title: String, date: CalendarDate, in body: String) -> String {
        body
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{date}}", with: date.description)
    }
}
