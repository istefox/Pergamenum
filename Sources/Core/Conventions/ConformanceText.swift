import Foundation

/// Renders violations as Italian sentences, kept out of the views so the wording is
/// in one place and testable.
///
/// Pure code motion off `VaultBrowser.swift` (PG-035/ADR-0045's own pattern): this type
/// used no `View` state of its own even there, and adding `categoryLines(_:)` for
/// ADR-0047 §D10 is what pushed that file over `file_length`. It then moved from
/// `Sources/Features/Editor` to `Core` (PG-147): seven call sites across four feature
/// folders read it, and it imports nothing but `Foundation`.
enum ConformanceText {
    static func lines(_ violations: NoteViolations) -> [String] {
        nameLines(violations.name)
            + frontmatterLines(violations.frontmatter)
            + tagLines(violations.tags)
            + relatedLines(violations)
            + taskMarkerLines(violations.taskMarkers)
            + categoryLines(violations.categories)
    }

    private static func nameLines(_ violations: [NoteName.Violation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .empty: lines.append("Il titolo è vuoto")
            case .containsForbiddenCharacter(let character): lines.append("Carattere vietato nel titolo: \(character)")
            case .tooLong(let count): lines.append("Titolo di \(count) caratteri, massimo \(NoteName.maximumLength)")
            case .hasVersionSuffix(let suffix): lines.append("Suffisso di versione nel titolo: \(suffix)")
            case .hasLeadingOrTrailingWhitespace: lines.append("Spazi all'inizio o alla fine del titolo")
            case .malformedDailyName(let name): lines.append("Daily note non in formato YYYYMMDD: \(name)")
            }
        }
        return lines
    }

    private static func frontmatterLines(_ violations: [FrontmatterViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .missingBlock: lines.append("Frontmatter assente")
            case .missingDate: lines.append("Manca la chiave date")
            case .missingTags: lines.append("Manca la chiave tags")
            case .foreignKey(let name): lines.append("Chiave fuori schema: \(name)")
            case .inlineTagList: lines.append("tags in forma inline, serve la lista a blocco")
            case .unparsableTag(let raw): lines.append("Tag non conforme: \(raw)")
            case .tooManyAliases(let count): lines.append("\(count) alias, massimo \(Frontmatter.maximumAliases)")
            case .unresolvedRelatedLink(let target): lines.append("related punta a una nota inesistente: \(target)")
            case .relatedOutOfSyncWithSection: lines.append("related e Note correlate non coincidono")
            case .secondFrontmatterBlock, .duplicateKey, .lineWithoutColon:
                if let line = damageLine(violation) { lines.append(line) }
            }
        }
        return lines
    }

    /// The three advisory damage findings of ADR-0065 §D11 (R-22).
    private static func damageLine(_ violation: FrontmatterViolation) -> String? {
        switch violation {
        case .secondFrontmatterBlock: "Secondo blocco frontmatter all'inizio del corpo"
        case .duplicateKey(let name): "Chiave ripetuta nel frontmatter: \(name)"
        case .lineWithoutColon(let line): "Riga del frontmatter senza due punti: \(line)"
        default: nil
        }
    }

    private static func tagLines(_ violations: [TagViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .malformed(let raw): lines.append("Tag malformato: \(raw)")
            case .notInVocabulary(let tag): lines.append("\(tag) non è nel vocabolario chiuso")
            case .vocabularyUnavailable(let namespace): lines.append("Vocabolario \(namespace.rawValue) non importato: non verificabile")
            case .tooMany(let count): lines.append("\(count) tag, massimo \(TagRules.maximumTagsPerNote)")
            case .multipleStatus(let tags): lines.append("Più di uno status: \(tags.map(\.description).joined(separator: ", "))")
            case .dateTag(let tag): lines.append("Tag data non ammesso: \(tag)")
            case .statusNotAllowedOnNote(let tag): lines.append("\(tag) non ammesso su una nota")
            case .missingRequiredTag(let name): lines.append("Manca il tag obbligatorio \(name)")
            }
        }
        return lines
    }

    private static func relatedLines(_ violations: NoteViolations) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: violations.relatedMissingInSection.map {
            "\($0) è in related ma non in Note correlate"
        })
        lines.append(contentsOf: violations.relatedMissingInFrontmatter.map {
            "\($0) è in Note correlate ma non in related"
        })
        return lines
    }

    /// ADR-0021 §D11. The line number is written 1-based, as an editor shows it, while
    /// `TaskMarkerViolation` carries the 0-based index every other reader of a note
    /// uses.
    private static func taskMarkerLines(_ violations: [TaskMarkerViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .duplicateWorkspace(let line, let kept, let ignored):
                lines.append("Riga \(line + 1): due Workspace sullo stesso task, vale \(kept) e \(ignored) è ignorato")
            case .orphanedParent(let line, let parent):
                lines.append("Riga \(line + 1): ^parent(\(parent)) senza ^id(\(parent)) in questa nota")
            }
        }
        return lines
    }

    /// ADR-0047 §D10 (R-10).
    private static func categoryLines(_ violations: [CategoryViolation]) -> [String] {
        var lines: [String] = []
        for violation in violations {
            switch violation {
            case .unknownSlug(let slug):
                lines.append("pergamenum-category punta a uno slug non registrato: \(slug)")
            case .duplicateHome(let slug, let home):
                lines.append("\(slug) è già collegata a \(home)")
            }
        }
        return lines
    }
}

extension ConformanceText {
    static func creationFailure(_ error: Error) -> String {
        guard let creation = error as? VaultSession.CreationError else { return "\(error)" }
        switch creation {
        case .alreadyExists(let path):
            return "Esiste già una nota in \(path)"
        case .invalidTitle(let violations):
            let named = NoteViolations(
                name: violations, frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            )
            return lines(named).joined(separator: "; ")
        }
    }
}
