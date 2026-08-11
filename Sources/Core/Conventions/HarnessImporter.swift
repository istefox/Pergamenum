import Foundation

/// Reads the closed vocabularies out of the `harness-system` convention documents.
///
/// SPEC §4.6 keeps that repo as the source of truth and the app as a declared replica.
/// This importer is what makes the replica reproducible: when a convention changes,
/// the user re-runs "Importa convenzioni…" instead of editing values by hand.
///
/// Sections are located by their number (`### 4.4`), never by their Italian title.
/// The number is the identifier the documents cite from every other section and from
/// this app's own specification; the wording of a heading is not.
enum HarnessImporter {
    struct Result: Equatable, Sendable {
        var vocabulary: Vocabulary
        /// Sections that could not be found or yielded nothing. Reported rather than
        /// silently producing a smaller vocabulary, which would then reject valid
        /// tags at typing time.
        var problems: [String]
    }

    /// Section numbers of the four closed tables, from tag.md 4.4, 4.6, 4.7, 4.8 and
    /// naming.md 6.1.
    private enum Section {
        static let type = "4.4"
        static let status = "4.6"
        static let area = "4.7"
        static let source = "4.8"
        static let deliverableKind = "6.1"
    }

    static func parse(tagDocument: String, namingDocument: String) -> Result {
        var problems: [String] = []

        func values(_ document: String, _ section: String, stripping namespace: String?) -> Set<String> {
            guard let rows = firstTableColumn(after: section, in: document) else {
                problems.append("section \(section) was not found, or has no table under it")
                return []
            }
            let cleaned = rows.compactMap { row -> String? in
                guard let namespace else { return row.isEmpty ? nil : row }
                let prefix = "\(namespace)-"
                guard row.hasPrefix(prefix) else { return nil }
                return String(row.dropFirst(prefix.count))
            }
            if cleaned.isEmpty { problems.append("section \(section) produced no usable values") }
            return Set(cleaned)
        }

        let vocabulary = Vocabulary(
            type: values(tagDocument, Section.type, stripping: "type"),
            status: values(tagDocument, Section.status, stripping: "status"),
            area: values(tagDocument, Section.area, stripping: "area"),
            source: values(tagDocument, Section.source, stripping: "source"),
            deliverableKind: values(namingDocument, Section.deliverableKind, stripping: nil)
        )
        return Result(vocabulary: vocabulary, problems: problems)
    }

    /// Returns the first column of the first markdown table following the heading
    /// whose number is `section`, excluding the header row and the `|---|` rule.
    private static func firstTableColumn(after section: String, in document: String) -> [String]? {
        let lines = document.components(separatedBy: "\n")
        guard let headingIndex = lines.firstIndex(where: { isHeading($0, numbered: section) }) else {
            return nil
        }

        var rows: [String] = []
        var sawHeaderRow = false
        for line in lines[(headingIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A following heading ends the search: a section without its own table
            // must fail rather than borrow the next section's.
            if trimmed.hasPrefix("#") { break }
            guard trimmed.hasPrefix("|") else {
                // Blank lines and prose before the table are fine; once the table has
                // started, anything else ends it.
                if !rows.isEmpty || sawHeaderRow { break } else { continue }
            }

            let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let first = cells.first else { continue }

            if !sawHeaderRow {
                sawHeaderRow = true          // the header row, e.g. `| Tag | ... |`
                continue
            }
            if first.allSatisfy({ $0 == "-" || $0 == ":" }) { continue }   // the rule row
            rows.append(first)
        }
        return rows.isEmpty ? nil : rows
    }

    /// Matches `### 4.4 …` and `## 6.1 …` at any heading depth, requiring the number
    /// to be followed by a space so `4.4` does not also match `4.41`.
    private static func isHeading(_ line: String, numbered section: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return false }
        let withoutHashes = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return withoutHashes == section || withoutHashes.hasPrefix("\(section) ")
    }
}
