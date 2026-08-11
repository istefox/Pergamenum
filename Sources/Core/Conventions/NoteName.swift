import Foundation

/// The file-naming rules of naming.md §4.6, as applied to notes (SPEC §4.2).
///
/// The title is the file name, so every rule here is also a rule about what the user
/// may type in the rename field. Renaming happens only inside the app or Obsidian
/// (W-08), because a rename from Finder leaves every inbound wikilink pointing at a
/// title that no longer exists.
enum NoteName {
    /// Characters a note title may not contain. The first group is what the file
    /// system and the wikilink syntax reserve; `#` and `^` would be read as a section
    /// or block reference inside `[[…]]`.
    static let forbiddenCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]
    static let maximumLength = 60

    enum Violation: Equatable, Sendable {
        case empty
        case containsForbiddenCharacter(Character)
        case tooLong(count: Int)
        case hasVersionSuffix(String)
        case hasLeadingOrTrailingWhitespace
        /// A daily note whose name is not exactly `YYYYMMDD` (naming.md 4.6 forbids
        /// the hyphenated form).
        case malformedDailyName(String)
    }

    /// Validates an ordinary note title.
    static func validate(_ title: String) -> [Violation] {
        var violations: [Violation] = []

        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return [.empty]
        }
        if title != title.trimmingCharacters(in: .whitespaces) {
            violations.append(.hasLeadingOrTrailingWhitespace)
        }
        for character in title where forbiddenCharacters.contains(character) {
            violations.append(.containsForbiddenCharacter(character))
        }
        if title.count > maximumLength {
            violations.append(.tooLong(count: title.count))
        }
        if let suffix = versionSuffix(in: title) {
            violations.append(.hasVersionSuffix(suffix))
        }
        return violations
    }

    /// Validates a daily-note file name, which must be exactly `YYYYMMDD`.
    static func validateDaily(_ name: String) -> [Violation] {
        CalendarDate(compact: name) == nil ? [.malformedDailyName(name)] : []
    }

    /// Detects the `v2` / `_v10` suffixes naming.md forbids on notes. Version numbers
    /// belong on exported deliverables, not on the note that produced them.
    private static func versionSuffix(in title: String) -> String? {
        let separators: Set<Character> = [" ", "_", "-"]
        guard let last = title.split(whereSeparator: { separators.contains($0) }).last else { return nil }
        guard last.count >= 2, last.first == "v" || last.first == "V" else { return nil }
        let digits = last.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return String(last)
    }

    /// Strips what a title may not contain, so a title suggested from arbitrary text
    /// (an email subject, a dropped file name) is conformant before it reaches disk.
    static func sanitized(_ title: String) -> String {
        var cleaned = String(title.filter { !forbiddenCharacters.contains($0) })
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > maximumLength {
            cleaned = String(cleaned.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }

    /// The file name for a note titled `title`, inside `Labs/…`.
    static func fileName(for title: String) -> String { "\(title).md" }

    /// The file name of the daily note for a date.
    static func dailyFileName(for date: CalendarDate) -> String { "\(date.compactForm).md" }

    /// Recovers the title from a file name, which is just its stem.
    static func title(fromFileName fileName: String) -> String {
        fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
    }

    /// Classifies a note by its file name, which is what decides the tag rules that
    /// apply to it (tag.md 5.1).
    static func category(forFileName fileName: String, dailyFolder: String?, path: String) -> NoteCategory {
        let stem = title(fromFileName: fileName)
        if CalendarDate(compact: stem) != nil {
            if let dailyFolder, !dailyFolder.isEmpty {
                return path.contains("\(dailyFolder)/") ? .daily : .note
            }
            return .daily
        }
        return .note
    }
}
