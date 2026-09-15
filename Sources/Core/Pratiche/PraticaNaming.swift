import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// R-08.

/// The file and tag names a pratica's own files and client folder use.
///
/// Reuses `ImportNaming.kebabCase`/`canonicalCounterparty`/`uniqueFileName` and adds
/// nothing to `ImportNaming` itself (this task's own instruction) - naming.md's rules
/// are the same rules, only the shape of the final name differs.
enum PraticaNaming {
    /// `YYYYMMDD_HHMM_<Controparte>_<oggetto-slug>.md` (R-08), extending
    /// `ImportNaming.emailFileName` with the `HHMM` component the SPEC's data model
    /// asks for - one counterpart can send several messages a day, and two files
    /// cannot share a name.
    ///
    /// Drops a leading `Re:`/`R:`/`Fwd:`/`I:`/`AW:` before slugging the subject, and
    /// caps the slug at 40 characters (R-08). No collision handling here - two
    /// messages that would otherwise share this exact name are told apart by
    /// `uniqueMessageFileName(...)`, since a same-`Message-ID` "collision" (a re-sync)
    /// is not a collision at all.
    ///
    /// Protected interface (`.claude/protected-interfaces`): re-import matches an
    /// existing message file by the name this derives, so a silent signature or
    /// behavior change orphans every message already on disk.
    static func messageFileName(
        date: CalendarDate,
        time: TaskTime,
        counterpart: String,
        subject: String
    ) -> String {
        let party = ImportNaming.canonicalCounterparty(counterpart)
        let clock = String(format: "%02d%02d", time.hour, time.minute)
        let stem = "\(date.compactForm)_\(clock)_\(party)"
        let slug = ImportNaming.truncatedAtWordBoundary(
            ImportNaming.kebabCase(strippingReplyPrefixes(subject)), toFit: slugLimit
        )
        return slug.isEmpty ? "\(stem).md" : "\(stem)_\(slug).md"
    }

    /// R-08's «max 40 characters» for the subject slug.
    static let slugLimit = 40

    /// `Re:`/`R:`/`Fwd:`/`I:`/`AW:`, repeatedly and in any case: a thread five replies
    /// deep arrives as `R: I: Re: Richiesta offerta`, and every one of those tokens
    /// would otherwise become a word of the slug.
    private static func strippingReplyPrefixes(_ subject: String) -> String {
        let prefixes = ["re", "r", "fwd", "i", "aw"]
        var text = subject.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            guard let colon = text.firstIndex(of: ":") else { break }
            let head = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            guard prefixes.contains(head) else { break }
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            changed = true
        }
        return text
    }

    /// R-08's collision rule: a file that already carries the name `messageFileName`
    /// would produce is **not** a collision when its recorded `Message-ID` matches
    /// `messageID` - a re-sync of the same message - only a genuinely different
    /// `Message-ID` gets `-2`, `-3`.
    static func uniqueMessageFileName(
        date: CalendarDate,
        time: TaskTime,
        counterpart: String,
        subject: String,
        messageID: String,
        existing: [(fileName: String, messageID: String)]
    ) -> String {
        let base = messageFileName(date: date, time: time, counterpart: counterpart, subject: subject)
        let taken = Dictionary(existing.map { ($0.fileName, $0.messageID) }) { first, _ in first }

        // The same `Message-ID` at the same name is a re-sync of one message, not two
        // messages colliding: it keeps its file, or every sync would grow a `-2`.
        func owner(of name: String) -> String? { taken[name] }
        if owner(of: base) == nil || owner(of: base) == messageID { return base }

        let stem = (base as NSString).deletingPathExtension
        var suffix = 2
        while true {
            let candidate = "\(stem)-\(suffix).md"
            if owner(of: candidate) == nil || owner(of: candidate) == messageID { return candidate }
            suffix += 1
        }
    }

    /// `YYYYMMDD_<original-name-sanitised>` (SPEC "Attachment file name").
    ///
    /// The name keeps its capitals, its spaces and its extension: this is the file a
    /// person will look for in Finder, and slugging it would make it unrecognisable.
    /// Only what a file name cannot legally hold is replaced.
    static func attachmentFileName(date: CalendarDate, name: String) -> String {
        let bare = (name as NSString).lastPathComponent
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = String(String.UnicodeScalarView(
            bare.unicodeScalars.map { illegal.contains($0) ? "-" : $0 }
        )).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "\(date.compactForm)_allegato" : "\(date.compactForm)_\(cleaned)"
    }

    /// R-01: the client is the pratica folder's own parent directory, relative to the
    /// configured Pratiche root - `"01 Progetti/Rossi/Offerta 2026"` under root
    /// `"01 Progetti"` has client `"Rossi"`. `nil` when `relativePath` is not under
    /// `root` at all, or has no parent folder below it.
    static func client(forPraticaAt relativePath: String, root: String) -> String? {
        let path = components(of: relativePath)
        let root = components(of: root)
        guard path.count >= root.count + 2 else { return nil }
        guard Array(path.prefix(root.count)) == root else { return nil }
        // `<root>/<Cliente>/<pratica>`: the client is the folder between the two, so a
        // pratica sitting directly in the root has none rather than a guessed one.
        return path[root.count]
    }

    /// What a pratica with no client folder above it is called, in the sidebar and in
    /// `perg pratiche` alike. Here rather than on `PraticheController`, which
    /// `Sources/Connector` cannot see (CLAUDE.md "AI connector").
    static let unnamedClient = "Senza cliente"

    private static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    /// The `client-<slug>` tag ADR §D11 puts in `pratica.md`'s frontmatter, derived
    /// from `client(forPraticaAt:root:)` through the same `ImportNaming.kebabCase`
    /// every other slug in this app uses.
    static func clientTag(forPraticaAt relativePath: String, root: String) -> Tag? {
        guard let client = client(forPraticaAt: relativePath, root: root) else { return nil }
        return Tag("client-\(ImportNaming.kebabCase(client))")
    }

    /// ADR-0045 §D7 (PG-143 structure refactor): `PraticheController.praticaFileName`
    /// spells the same literal on the app side, where it also names the sync engine's
    /// own writes; this is the copy `Sources/Core`, and therefore both connectors, can
    /// see.
    static let praticaFileName = "pratica.md"

    /// Moved verbatim from `PraticaCommandActions.praticaNotePath(of:)` (ADR-0045 §D7)
    /// - the same arithmetic, now reachable from `Sources/Core` without a call back up
    /// into `Sources/Features/Pratiche`.
    static func praticaNotePath(of praticaPath: String) -> String {
        "\(praticaPath)/\(praticaFileName)"
    }
}
