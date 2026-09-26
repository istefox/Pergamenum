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

    /// The extensions that name a note: how a note is named on disk.
    static let noteExtensions: Set<String> = ["md"]

    /// The extensions that name a file, never a note (ADR-0064 §D9.5): the attachment types the
    /// app renders or previews, plus `canvas`. Lowercase; `isNoteReference` lowercases before
    /// asking.
    static let fileExtensions: Set<String> = [
        // images
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "avif",
        // documents
        "pdf",
        // audio
        "mp3", "m4a", "wav", "aac", "flac", "ogg",
        // video
        "mp4", "mov", "m4v", "webm", "mkv", "avi",
        // office and data
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "odt", "ods", "odp",
        "rtf", "txt", "csv", "tsv", "json", "xml", "html", "htm",
        // archives
        "zip", "gz", "tar", "7z", "rar", "dmg",
        // mail and calendar
        "eml", "emlx", "msg", "ics", "vcf",
        // boards
        "canvas",
        // other apps' formats
        "drawio", "excalidraw", "sketch", "webarchive",
    ]

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
    ///
    /// Every extension the app knows is decided by name first (ADR-0064 §D9.5, R-20): the shape
    /// rule answered `true` for anything longer than five characters, which made `Q4.canvas` a
    /// note. The shape rule stays only for the long tail, so an attachment with an unlisted short
    /// extension does not become a phantom note.
    static func isNoteReference(_ target: String) -> Bool {
        guard !Attachment.isRemote(target) else { return false }
        let name = split(target).reference
        let ext = (name as NSString).pathExtension
        if noteExtensions.contains(ext.lowercased()) { return true }
        if fileExtensions.contains(ext.lowercased()) { return false }
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

    /// One transcluded note, and where its line starts.
    struct Occurrence: Equatable, Sendable {
        /// The UTF-16 offset of the line's first character, which is what the layout
        /// counts in - the same unit `NoteFolding.Layout` hands the editor.
        var lineOffset: Int
        var reference: String
        var section: String?
    }

    /// Every line of `text` that is nothing but a transcluded note, in document order.
    ///
    /// What the editor needs and the block parser cannot give: the parser answers in
    /// blocks, and decorating a line takes an offset. A file embed is not one of these -
    /// the editor already shows `![[foto.png]]` as a clickable name and that is unchanged.
    ///
    /// Frontmatter and fenced code are skipped through the same two helpers `NoteOutline`
    /// uses. This is the third feature that would get the fence rule wrong if it wrote the
    /// rule for itself.
    static func occurrences(in text: String) -> [Occurrence] {
        let fences = CodeFence.regions(in: text)
        var result: [Occurrence] = []

        var lineStart = bodyStart(of: text)
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            defer { lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex }

            guard !fences.contains(where: { $0.range.overlaps(lineStart..<lineEnd) }) else { continue }
            guard case .note(let reference, let section)? =
                    target(ofLine: String(text[lineStart..<lineEnd]))
            else { continue }

            result.append(Occurrence(
                lineOffset: text.utf16.distance(from: text.startIndex, to: lineStart),
                reference: reference,
                section: section
            ))
        }
        return result
    }

    /// Where the body starts, taken from the one frontmatter parser rather than from a
    /// second reading of the `---` rule - `NoteOutline` derives it the same way.
    private static func bodyStart(of text: String) -> String.Index {
        let document = NoteDocument.parse(text)
        guard document.hasFrontmatterBlock else { return text.startIndex }
        return text.index(text.endIndex, offsetBy: -document.body.count)
    }

    /// The files a note embeds, in document order, duplicates removed (ADR-0009 §D2).
    ///
    /// The exact complement of `NoteStore.linkTargets`, which counts a transcluded note
    /// and leaves a file out. Here it is the other half: `![[foto.png]]` and
    /// `![didascalia](foto.png)` yes, `![[nota]]` no. Both spellings, because a vault is
    /// not written by one program.
    ///
    /// A whole line and nothing else, which is what this app has always called an embed
    /// (`Attachment.embed(inLine:)` says why). A picture named in the middle of a sentence
    /// is an illustration in a sentence, and the gallery renderer M11 adds this for shows
    /// the documents a note carries, not every file name it mentions.
    ///
    /// Remote targets never appear: `target(ofLine:)` drops them, the app makes no network
    /// call, and there is nothing on disk to draw a thumbnail of.
    static func embeddedFiles(in text: String) -> [String] {
        let fences = CodeFence.regions(in: text)
        var seen = Set<String>()
        var ordered: [String] = []

        var lineStart = bodyStart(of: text)
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            defer { lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex }

            guard !fences.contains(where: { $0.range.overlaps(lineStart..<lineEnd) }) else { continue }
            guard case .file(let target, _)? = target(ofLine: String(text[lineStart..<lineEnd])) else { continue }
            if seen.insert(target).inserted { ordered.append(target) }
        }
        return ordered
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
