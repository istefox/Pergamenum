import Foundation

/// What an `![[…]]` points at, and what a note shows when it points at another note.
///
/// ADR-0010: a transclusion is a *view* of another note, never a copy. Nothing here
/// rewrites anything - the line on disk stays `![[nota]]`, and this only says what to
/// draw in its place.
///
/// In `Core` and without AppKit, so `perg` and `pergamenum-mcp` compile it: deciding what
/// a link points at is a convention of the vault, and drawing it is not.
enum Transclusion {
    /// The two things `![[…]]` can mean, decided by the extension (§D2).
    enum Target: Equatable, Sendable {
        /// `![[nota]]`, `![[nota#sezione]]`. The reference is what the note wrote - a
        /// title, or a path when it ends in `.md`. Resolving it is the vault's job, not
        /// this file's.
        case note(reference: String, section: String?)
        /// `![[foto.png]]`, `![didascalia](foto.png)`: everything that was already an
        /// embed before transclusion existed, unchanged.
        case file(target: String, alt: String?)
    }

    /// What a line consisting of nothing but an embed points at.
    ///
    /// Only a whole line, for the reason `Attachment.embed(inLine:)` gives: an embed
    /// inside a paragraph is an illustration in a sentence, and a note unfolded in the
    /// middle of one would cut the sentence in two.
    static func target(ofLine line: String) -> Target? {
        guard let embed = Attachment.embed(inLine: line) else { return nil }
        // Remote targets never reach either branch: the app makes no network call, so a
        // remote embed stays a link for the inline path to draw (principle 2).
        guard !Attachment.isRemote(embed.target) else { return nil }
        guard isNoteReference(embed.target) else {
            return .file(target: embed.target, alt: embed.alt)
        }
        let (reference, section) = split(embed.target)
        return .note(reference: reference, section: section)
    }

    /// Whether a target names a note rather than a file.
    ///
    /// The extension decides, and "extension" is read strictly: one to five ASCII
    /// alphanumerics after the last dot, **at least one of them a letter**. A note title is
    /// allowed to contain a dot - *Analisi 3.5 mm* is a title, not a file of type `5 mm`,
    /// and *Riunione del 12.03* is a date, not a file of type `03` - so a rule that only
    /// asked whether a dot was present would send half the vault down the file path. The
    /// letter is what separates `mp3` and `7z`, which are real, from `03`, which is not a
    /// file type anybody has.
    ///
    /// `.md` is the one extension that still means a note: it is how a note is named on
    /// disk, so `![[Progetti/Forno.md]]` is a note written as a path.
    static func isNoteReference(_ target: String) -> Bool {
        guard !Attachment.isRemote(target) else { return false }
        let name = split(target).reference
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 5,
              ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              ext.contains(where: { $0.isLetter })
        else { return true }
        return ext.lowercased() == "md"
    }

    /// The text a transclusion shows: one section, or the note's body.
    ///
    /// Frontmatter never appears - a transcluded note shows the note, and its metadata has
    /// its own place. A section that no heading answers to returns nil, so the view can say
    /// so rather than quietly showing the whole note instead, which would look like the
    /// section had been deleted.
    static func excerpt(of text: String, section: String?) -> String? {
        let document = NoteDocument.parse(text)
        guard let section, !section.isEmpty else { return document.body }

        let wanted = normalised(section)
        let entries = NoteOutline.entries(in: text)
        for (index, entry) in entries.enumerated() {
            guard case .heading = entry.kind, normalised(entry.title) == wanted else { continue }
            guard let range = NoteFolding.sectionRange(in: text, headingAt: index) else { return nil }
            return String(text[range])
        }
        return nil
    }

    /// Splits `nota#sezione`. The first `#` wins, as it does in `WikilinkParser`: a
    /// heading may contain one, a note title may not carry it unescaped either way.
    private static func split(_ target: String) -> (reference: String, section: String?) {
        guard let hash = target.firstIndex(of: "#") else {
            return (target.trimmingCharacters(in: .whitespaces), nil)
        }
        let reference = String(target[target.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
        let section = String(target[target.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
        return (reference, section.isEmpty ? nil : section)
    }

    /// Headings are matched the way a person expects: case and surrounding space do not
    /// count. `NoteOutline` has already taken the markdown out of the heading's text, so
    /// `## Vedi [[Altra]]` is matched by writing `#Vedi Altra`.
    private static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
