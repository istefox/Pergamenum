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

    /// Substitutes the placeholders, and only those it knows.
    ///
    /// An unrecognised `{{…}}` is left exactly as written. Silently emptying it would
    /// destroy text the person typed on the strength of a guess about what they meant;
    /// left visible, it is a question they can answer themselves.
    ///
    /// A forward to `resolve` since ADR-0086 §D1. Production code resolves through `resolve`;
    /// this one is kept, with the same signature, because the `NoteTemplateTests` assertions pin
    /// it. `{{time}}` reads `00:00` here and `{{cursor}}` is removed, since nothing on this path
    /// places a caret.
    static func substituting(title: String, date: CalendarDate, in body: String) -> String {
        resolve(body, title: title, date: date, time: TaskTime(hour: 0, minute: 0)).body
    }

    // MARK: - `{{time}}` and `{{cursor}}` (PG-387, ADR-0086 §D1)

    /// The placeholder that marks where the caret goes; never written.
    static let cursorMarker = "{{cursor}}"

    /// A template's body with its placeholders resolved, and where `{{cursor}}` stood.
    struct Resolved: Equatable, Sendable {
        var body: String
        /// UTF-16 offset of the first `{{cursor}}` in `body`, nil when the template had none.
        var caretOffset: Int?

        /// The absolute caret offset once `body` is written at the end of `text` (the frontmatter
        /// and its separating line break come first). Nil without a marker, or when `text` does
        /// not end with `body`.
        func caret(inWritten text: String) -> Int? {
            guard let caretOffset, text.hasSuffix(body) else { return nil }
            return text.utf16.count - body.utf16.count + caretOffset
        }

        /// How many UTF-16 units lie between the caret and the end of `body`.
        var cursorBack: Int? { caretOffset.map { body.utf16.count - $0 } }
    }

    /// `{{title}}`, `{{date}}` and `{{time}}` resolved, `{{cursor}}` located and removed.
    ///
    /// The marker is located in the template before any other substitution, so a title that
    /// contains it is typed text and is written as typed. The first marker gives the caret; the
    /// others are removed.
    static func resolve(_ template: String, title: String, date: CalendarDate, time: TaskTime) -> Resolved {
        func substitute(_ segment: String) -> String {
            segment
                .replacingOccurrences(of: cursorMarker, with: "")
                .replacingOccurrences(of: "{{title}}", with: title)
                .replacingOccurrences(of: "{{date}}", with: date.description)
                .replacingOccurrences(of: "{{time}}", with: TimeOfDay.formatted(hour: time.hour, minute: time.minute))
        }
        guard let marker = template.range(of: cursorMarker) else {
            return Resolved(body: substitute(template), caretOffset: nil)
        }
        let before = substitute(String(template[..<marker.lowerBound]))
        let after = substitute(String(template[marker.upperBound...]))
        return Resolved(body: before + after, caretOffset: before.utf16.count)
    }

    /// A capture's text put at the marker, or after the body with one blank line.
    static func composing(captured: String, into resolved: Resolved) -> String {
        let body = resolved.body as NSString
        if let offset = resolved.caretOffset, offset <= body.length {
            return body.replacingCharacters(in: NSRange(location: offset, length: 0), with: captured)
        }
        var trimmed = resolved.body
        while trimmed.last == "\n" || trimmed.last == "\r" { trimmed.removeLast() }
        return trimmed.isEmpty ? captured : trimmed + "\n\n" + captured
    }

    /// A template by path, by title or by `Titolo.md`, among the templates' paths.
    ///
    /// An exact path wins; otherwise the file name decides, and two templates sharing it in two
    /// subfolders are ambiguous rather than picked by order.
    static func reference(
        _ reference: String, among templatePaths: [String]
    ) -> Result<String, TemplateReferenceError> {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        let withExtension = trimmed.hasSuffix(".md") ? trimmed : trimmed + ".md"
        if let exact = templatePaths.first(where: { $0 == trimmed || $0 == withExtension }) {
            return .success(exact)
        }
        let fileName = (withExtension as NSString).lastPathComponent
        let matches = templatePaths.filter { ($0 as NSString).lastPathComponent == fileName }
        switch matches.count {
        case 1: return .success(matches[0])
        case 0: return .failure(.unknown(reference, available: templatePaths.sorted()))
        default: return .failure(.ambiguous(reference, candidates: matches.sorted()))
        }
    }
}

/// Why a `--template` reference named no single template.
enum TemplateReferenceError: Error, Equatable, Sendable {
    case unknown(String, available: [String])
    case ambiguous(String, candidates: [String])

    var sentence: String {
        switch self {
        case .unknown(let name, let available):
            available.isEmpty
                ? "nessun modello «\(name)»: la cartella \(NoteTemplate.folder)/ non ne contiene"
                : "nessun modello «\(name)». Modelli disponibili: \(available.joined(separator: ", "))"
        case .ambiguous(let name, let candidates):
            "«\(name)» indica più modelli, scegli il percorso: \(candidates.joined(separator: ", "))"
        }
    }
}
