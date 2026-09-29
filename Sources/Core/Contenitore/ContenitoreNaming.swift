import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D5/§D7, plan
// docs/plans/contenitore.md, Task 2 - R-06, R-19.

/// What a sub-container name answers to (ADR-0071 §D7).
///
/// `yearName` is its own outcome rather than a new `NoteName.Violation` case: that type is
/// switched on by the whole linter, and a four-digit name is refused only here, because year
/// folders under the Contenitore root belong to the app.
enum ContainerNameCheck: Equatable, Sendable {
    case valid
    /// `FolderName.validate`'s own findings.
    case invalid([NoteName.Violation])
    /// Four digits: the name of a year folder, which a sub-container may not take.
    case yearName
}

/// The names of a document pair and of the folders it lives in (ADR-0071 §D5).
///
/// Its own type rather than a widening of `ImportNaming`: `recordingNoteTitle` is a protected
/// name, and `truncatedAtWordBoundary` splits on hyphens only, so it cannot cut the
/// space-separated name a scheda carries.
enum ContenitoreNaming {
    /// The name part a stem takes when the original sanitises to nothing: `20260929` alone
    /// would be read as a daily note (`NoteName.category`).
    static let fallbackName = "documento"

    /// Room kept for a `-NN` suffix, so a unique stem still fits `NoteName.maximumLength`.
    static let suffixReserve = 3

    /// `YYYYMMDD <name>`: the import day, a space, and the original name without its
    /// extension, sanitised with the note-title rules. A trailing version token (`v2`,
    /// `_v10`) is dropped, so the scheda passes `NoteName.validate`; the name part is cut at
    /// the last space that lets the stem plus a `-NN` suffix fit the title limit; a dot inside
    /// the name is kept.
    static func stem(forOriginal originalName: String, importDate: CalendarDate) -> String {
        let prefix = "\(importDate.compactForm) "
        let budget = NoteName.maximumLength - prefix.count - suffixReserve
        let rawName = (originalName as NSString).deletingPathExtension

        var name = droppingVersionSuffix(NoteName.sanitized(rawName))
        name = droppingVersionSuffix(cutAtSpace(name, toFit: budget))
        if name.isEmpty { name = fallbackName }
        return prefix + name
    }

    /// The first of `stem`, `stem-2`, `stem-3`, … that is free as a pair: neither
    /// `<candidate>.<ext>` nor `<candidate>.md` is in `takenFileNames` (the target folder's
    /// listing), and no note in the vault is titled `<candidate>` (`takenTitles`, gate G4).
    /// Compared case-insensitively, as the default APFS volume and the title index compare.
    static func uniquePairStem(
        _ stem: String,
        extension ext: String,
        takenFileNames: Set<String>,
        takenTitles: Set<String>
    ) -> String {
        let files = Set(takenFileNames.map { $0.lowercased() })
        let titles = Set(takenTitles.map { $0.lowercased() })
        func isTaken(_ candidate: String) -> Bool {
            let lowered = candidate.lowercased()
            return files.contains(fileName(stem: lowered, extension: ext.lowercased()))
                || files.contains("\(lowered).md")
                || titles.contains(lowered)
        }

        var candidate = stem
        var suffix = 2
        while isTaken(candidate) {
            candidate = "\(stem)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// The companion's file name for a stem: `<stem>.<ext>`, or the bare stem when the dropped
    /// file had no extension.
    static func fileName(stem: String, extension ext: String) -> String {
        ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// `<container>/<YYYY>`, the folder a document dated `date` sits in inside `container`
    /// (a vault-relative folder path, `""` for the vault root).
    static func yearFolder(for date: CalendarDate, in container: String) -> String {
        let year = String(format: "%04d", date.year)
        let parent = trimmedSlashes(container)
        return parent.isEmpty ? year : "\(parent)/\(year)"
    }

    /// Whether a folder's own name is a year folder's: exactly four ASCII digits.
    static func isYearFolderName(_ name: String) -> Bool {
        name.count == 4 && name.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// A sub-container name: `FolderName.validate`, then the year-name refusal.
    static func validateContainerName(_ name: String) -> ContainerNameCheck {
        let violations = FolderName.validate(name)
        if !violations.isEmpty { return .invalid(violations) }
        return isYearFolderName(name) ? .yearName : .valid
    }

    // MARK: - Pieces

    /// Whole space-separated words only, so the name never ends mid-word. A first word that
    /// on its own exceeds the budget is cut at the budget: there is no space to cut at, and a
    /// name must still fit.
    private static func cutAtSpace(_ name: String, toFit budget: Int) -> String {
        guard budget > 0 else { return "" }
        guard name.count > budget else { return name }

        var kept: [Substring] = []
        var length = 0
        for word in name.split(separator: " ", omittingEmptySubsequences: true) {
            let addition = kept.isEmpty ? word.count : word.count + 1
            guard length + addition <= budget else { break }
            kept.append(word)
            length += addition
        }
        let cut = kept.isEmpty ? String(name.prefix(budget)) : kept.joined(separator: " ")
        return cut.trimmingCharacters(in: .whitespaces)
    }

    /// The name without the trailing version tokens `NoteName.validate` flags, along with the
    /// separator before each. The token survives in `pergamenum-contenitore-original`.
    private static func droppingVersionSuffix(_ name: String) -> String {
        var result = name
        while case .hasVersionSuffix(let token)? = NoteName.validate(result).first(where: {
            if case .hasVersionSuffix = $0 { return true }
            return false
        }) {
            let shortened = String(result.dropLast(token.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
            guard shortened.count < result.count else { break }
            result = shortened
        }
        return result
    }

    private static func trimmedSlashes(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
