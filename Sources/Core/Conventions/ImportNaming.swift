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
