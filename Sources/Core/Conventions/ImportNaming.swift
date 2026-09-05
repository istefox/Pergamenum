import Foundation

/// Builds the file names that naming.md prescribes for imported material.
///
/// SPEC §4.2 says the import assistant *proposes* a name: this computes the
/// proposal, and the user confirms or edits it. Renaming without asking is how a
/// vault ends up with names nobody chose.
enum ImportNaming {
    /// `YYYYMMDD_Controparte_Email_oggetto-sintetico.eml` (naming.md 4.3 and 7.3).
    ///
    /// The counterparty is the external one - the sender when the message was
    /// received - because that is what makes the file findable later (N-07).
    static func emailFileName(
        date: CalendarDate,
        counterparty: String,
        subject: String
    ) -> String {
        let party = canonicalCounterparty(counterparty)
        let slug = kebabCase(subject)
        let stem = slug.isEmpty
            ? "\(date.compactForm)_\(party)_Email"
            : "\(date.compactForm)_\(party)_Email_\(slug)"
        return "\(stem).eml"
    }

    /// Proposes the name for an `.eml` from its own headers, falling back to the
    /// file's current name when a header is missing.
    static func proposedEmailFileName(
        headers: EmailHeaders,
        currentFileName: String,
        today: CalendarDate
    ) -> String {
        let date = headers.date.map { CalendarDate($0) } ?? today
        let counterparty = headers.from?.name
            ?? headers.from?.address.split(separator: "@").last.map(String.init)
            ?? NoteName.title(fromFileName: currentFileName)
        return emailFileName(
            date: date,
            counterparty: counterparty,
            subject: headers.subject ?? ""
        )
    }

    /// The three-step canonical form of naming.md N-07: drop the legal form when it
    /// is a separate word, replace accented letters with their ASCII counterpart,
    /// remove spaces and punctuation.
    ///
    /// The result keeps its capitals, because the Controparte segment of a file name
    /// is CamelCase while a `client-*` tag is lowercase.
    static func canonicalCounterparty(_ raw: String) -> String {
        // Held without dots, and the comparison strips them: "S.p.A." and "SpA" are
        // the same legal form, and only the dotted spelling would otherwise survive.
        let legalForms: Set<String> = [
            "srl", "spa", "snc", "sas", "srls", "sc", "scarl",
            "gmbh", "ltd", "inc", "llc", "bv", "nv", "sa", "ag",
        ]
        let words = raw
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { word in
                let bare = word.lowercased().filter(\.isLetter)
                return !legalForms.contains(bare)
            }

        let joined = words.joined()
        let folded = joined.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let filtered = folded.filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? "Sconosciuto" : String(filtered)
    }

    /// Lowercase words joined by single hyphens, accents folded, punctuation dropped.
    ///
    /// An apostrophe separates words like any other punctuation, so «Gran Premio d'Olanda»
    /// counts as four. When the cap then falls immediately after the elision, the result ends
    /// in a bare `-d`: a letter that meant something only as part of the word the cut removed.
    /// It is dropped, and **only when the text was actually truncated** - a subject genuinely
    /// ending in one letter, «Piano B», keeps it.
    ///
    /// Found on screen, in an event note named `20260821-f1-qualifiche-sprint-gran-premio-d`.
    static func kebabCase(_ raw: String, maximumWords: Int = 6) -> String {
        let folded = raw.folding(
            options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()

        let all = folded
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        var words = Array(all.prefix(maximumWords))
        if all.count > maximumWords, words.last?.count == 1 { words.removeLast() }

        return words.joined(separator: "-")
    }

    /// A name that does not collide with an existing file, by appending `-2`, `-3`…
    ///
    /// Overwriting an imported file would destroy the earlier one silently, and two
    /// messages from the same sender on the same day about the same subject is an
    /// ordinary occurrence, not an error.
    /// `immagine-20260814.png`, for a picture pasted from the clipboard.
    ///
    /// A screenshot arrives with no name of its own, so the app gives it one in the
    /// shape SPEC §6.2 already uses for drawings (`disegno-YYYYMMDD-nnn.svg`);
    /// `uniqueFileName` adds the `-2` when a day gets more than one.
    static func pastedImageFileName(on date: CalendarDate) -> String {
        "immagine-\(date.compactForm).png"
    }

    // ADR-0032 (Plaud recording import into Pergamenum), plan
    // docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 4 - R-05.
    //
    // The note title is derived from the recording, never taken from it (ADR §D5): a
    // recording's own `name` can be a human title with a colon in it and no length limit,
    // or the old `2026-09-04 13:44:51` timestamp form - neither is a conformant `NoteName`.
    // Four rules the coder implements: (1) a leading date-like token in `name` is dropped
    // before slugging; (2) the slug is truncated at a word boundary so the whole title is
    // ≤ `NoteName.maximumLength`, and never ends in a hyphen; (3) collisions are somebody
    // else's job (`uniqueFileName`, above); (4) the date is `recordedAt`'s own **local**
    // calendar date, never today's.
    //
    // Also `.claude/protected-interfaces` (ADR-0053): a silent signature/behavior change
    // here orphans every note already imported, since re-import matches an existing
    // transcript note by the name this function derives.
    //
    // A slug whose very first word is on its own longer than the budget leaves the title
    // as `YYYYMMDD_Registrazione` with no slug at all: cutting inside that word is what
    // rule 2 forbids, and a name made of one enormous word carries no word boundary to cut
    // at. The date and the kind still say what the note is.
    static func recordingNoteTitle(recordedAt: Date, name: String) -> String {
        let stem = "\(CalendarDate(recordedAt).compactForm)_Registrazione"
        let slug = truncatedAtWordBoundary(
            kebabCase(droppingLeadingDateToken(name)),
            toFit: NoteName.maximumLength - stem.count - 1
        )
        return slug.isEmpty ? stem : "\(stem)_\(slug)"
    }

    /// Rule 1: a `09-04 ` or `2026-09-04 ` head is the recording's own date repeated, and
    /// the title already opens with that date in compact form. Only the first
    /// space-separated token is considered, and only when every one of its two or three
    /// hyphen-separated parts is numeric - «Linea 4 - revisione» keeps its first word.
    private static func droppingLeadingDateToken(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else {
            return isDateLikeToken(trimmed) ? "" : trimmed
        }
        guard isDateLikeToken(String(trimmed[trimmed.startIndex..<space])) else { return trimmed }
        return String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isDateLikeToken(_ token: String) -> Bool {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Rule 2: whole words only, so the title never ends mid-word and never ends in the
    /// hyphen that joined one - `NoteName.maximumLength` is the budget the caller has
    /// already subtracted its own prefix from.
    private static func truncatedAtWordBoundary(_ slug: String, toFit budget: Int) -> String {
        guard budget > 0 else { return "" }
        guard slug.count > budget else { return slug }

        var kept: [Substring] = []
        var length = 0
        for word in slug.split(separator: "-") {
            let addition = kept.isEmpty ? word.count : word.count + 1
            guard length + addition <= budget else { break }
            kept.append(word)
            length += addition
        }
        return kept.joined(separator: "-")
    }

    static func uniqueFileName(
        _ proposed: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> String {
        let stem = (proposed as NSString).deletingPathExtension
        let ext = (proposed as NSString).pathExtension

        var candidate = proposed
        var suffix = 2
        while fileManager.fileExists(
            atPath: directory.appending(path: candidate, directoryHint: .notDirectory)
                .path(percentEncoded: false)
        ) {
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }
}
