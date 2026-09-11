import Foundation

/// The closed four-key note frontmatter of SPEC §4.3.
///
/// `date` and `tags` are required, `related` and `aliases` optional, and no other key
/// is allowed **except this app's own `pergamenum-` namespace** (ADR-0032 §D6, R-05:
/// `^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$`, mirroring ADR-0020's `pergamenum-crop`
/// property on a canvas node). The parser still keeps any other key it finds, verbatim,
/// in `foreignKeys`: F-02 makes an extra key outside that namespace a non-conformity to
/// report, and dropping it on the next save would destroy data the user put there.
/// Reporting and preserving are not in tension - "file over app" means the file wins
/// even when it is wrong.
///
/// The allowance lives in `FrontmatterRules.validate` alone: a prefixed key is still a
/// `ForeignKey` here and still round-trips byte for byte, it is only no longer reported.
struct Frontmatter: Equatable, Sendable {
    /// F-03, the document's date, always present in a conformant note.
    var date: CalendarDate?
    var tags: [Tag]
    /// F-06, structural links, alphabetically ordered, written as quoted wikilinks.
    var related: [String]
    /// F-07, at most three.
    var aliases: [String]

    /// Keys outside the closed schema, preserved in source order with their original
    /// lines so a round-trip does not lose them.
    var foreignKeys: [ForeignKey]
    /// Tag strings that did not parse, kept so the linter can show what was written.
    var unparsableTags: [String]
    /// True when `tags:` used the inline `[a, b]` form, which F-04 forbids.
    var usedInlineTagList: Bool

    struct ForeignKey: Equatable, Sendable {
        var name: String
        /// Every raw line belonging to this key, including its continuation lines.
        var lines: [String]
    }

    static let empty = Frontmatter(
        date: nil, tags: [], related: [], aliases: [],
        foreignKeys: [], unparsableTags: [], usedInlineTagList: false
    )

    static let maximumAliases = 3
}

/// A calendar date with no time and no zone, which is what F-03 stores.
///
/// `Date` would carry an instant and a zone the file does not have, and round-tripping
/// through one is how a note dated the 11th becomes the 10th for someone in a western
/// timezone.
struct CalendarDate: Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    /// ISO 8601 calendar date, the form F-03 requires: `2026-08-11`.
    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The daily-note file name of naming.md 4.6: `20260811`, never hyphenated.
    var compactForm: String {
        String(format: "%04d%02d%02d", year, month, day)
    }

    /// `11/08/2026`, the way a date is written in Italian and the only form the
    /// interface shows a person. The ISO form stays for the file and the markers.
    var italianForm: String {
        String(format: "%02d/%02d/%04d", day, month, year)
    }

    init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1 else { return nil }
        guard day <= CalendarDate.daysInMonth(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Rejects anything else, including `YYYY/MM/DD` and a date
    /// with a time appended: F-03 names one format and the linter must see the rest
    /// as non-conformant rather than quietly accepting it.
    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Parses the compact `YYYYMMDD` daily-note form.
    init?(compact: String) {
        guard compact.count == 8, compact.allSatisfy(\.isNumber),
              let year = Int(compact.prefix(4)),
              let month = Int(compact.dropFirst(4).prefix(2)),
              let day = Int(compact.suffix(2))
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar date an instant falls on, in a given time zone.
    ///
    /// The calendar is a parameter rather than `Calendar.current` at the call site so
    /// that "today" is computed once, explicitly, instead of each caller silently
    /// picking up whatever locale the app happens to run under.
    init(_ date: Date, in calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    static var today: CalendarDate { CalendarDate(Date()) }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: isLeapYear(year) ? 29 : 28
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

// MARK: - Parsing

/// A markdown note split into its frontmatter and its body.
struct NoteDocument: Equatable, Sendable {
    var frontmatter: Frontmatter
    /// Everything after the closing `---`, verbatim, newlines included.
    var body: String
    /// False when the file had no frontmatter block at all.
    var hasFrontmatterBlock: Bool

    /// Splits a note's text. Never throws: an unterminated or malformed block yields
    /// an empty frontmatter and the whole text as body, because a note the app cannot
    /// parse must still open and still be editable.
    static func parse(_ text: String) -> NoteDocument {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return NoteDocument(frontmatter: .empty, body: text, hasFrontmatterBlock: false)
        }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            // An opening delimiter with no closing one: treat the whole file as body
            // rather than swallowing it into a frontmatter that was never closed.
            return NoteDocument(frontmatter: .empty, body: text, hasFrontmatterBlock: false)
        }

        let block = Array(lines[1..<closing])
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return NoteDocument(
            frontmatter: FrontmatterParser.parse(block),
            body: body,
            hasFrontmatterBlock: true
        )
    }

    /// Rebuilds the file text: conformant frontmatter in fixed key order, then any
    /// preserved foreign keys, then the body unchanged.
    func serialized() -> String {
        FrontmatterSerializer.render(frontmatter) + body
    }
}

enum FrontmatterParser {
    static func parse(_ lines: [String]) -> Frontmatter {
        var result = Frontmatter.empty
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("-") else {
                index += 1
                continue
            }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let inlineValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            // Continuation lines are the indented or dashed lines that follow, up to
            // the next top-level key.
            var block: [String] = []
            var lookahead = index + 1
            while lookahead < lines.count, isContinuation(lines[lookahead]) {
                block.append(lines[lookahead])
                lookahead += 1
            }

            switch key {
            case "date":
                result.date = CalendarDate(iso: unquote(inlineValue))
            case "tags":
                let (tags, unparsable, inline) = parseTags(inlineValue: inlineValue, block: block)
                result.tags = tags
                result.unparsableTags = unparsable
                result.usedInlineTagList = inline
            case "related":
                result.related = parseStringList(inlineValue: inlineValue, block: block)
            case "aliases":
                result.aliases = parseStringList(inlineValue: inlineValue, block: block)
            default:
                result.foreignKeys.append(.init(name: key, lines: [line] + block))
            }

            index = lookahead
        }
        return result
    }

    private static func isContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        return line.hasPrefix(" ") || line.hasPrefix("\t") || trimmed.hasPrefix("-")
    }

    private static func parseTags(
        inlineValue: String,
        block: [String]
    ) -> (tags: [Tag], unparsable: [String], usedInline: Bool) {
        var raw: [String] = []
        var usedInline = false

        if inlineValue.hasPrefix("["), inlineValue.hasSuffix("]") {
            usedInline = true
            raw = inlineValue.dropFirst().dropLast()
                .split(separator: ",")
                .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
        } else if !inlineValue.isEmpty {
            usedInline = true
            raw = [unquote(inlineValue)]
        }
        raw.append(contentsOf: block.compactMap(listItem))

        var tags: [Tag] = []
        var unparsable: [String] = []
        for item in raw where !item.isEmpty {
            if let tag = Tag(item) { tags.append(tag) } else { unparsable.append(item) }
        }
        return (tags, unparsable, usedInline)
    }

    private static func parseStringList(inlineValue: String, block: [String]) -> [String] {
        var values: [String] = []
        if inlineValue.hasPrefix("["), inlineValue.hasSuffix("]") {
            values = inlineValue.dropFirst().dropLast()
                .split(separator: ",")
                .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
        } else if !inlineValue.isEmpty {
            values = [unquote(inlineValue)]
        }
        values.append(contentsOf: block.compactMap(listItem))
        return values.filter { !$0.isEmpty }
    }

    private static func listItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("-") else { return nil }
        return unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first, last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

enum FrontmatterSerializer {
    /// Writes the block in the fixed key order of SPEC §4.3, omitting optional keys
    /// that have no value (F-08 forbids an empty `related:` or `[]`).
    static func render(_ frontmatter: Frontmatter) -> String {
        var lines = ["---"]

        if let date = frontmatter.date {
            lines.append("date: \(date)")
        }
        if !frontmatter.tags.isEmpty {
            lines.append("tags:")
            lines.append(contentsOf: TagRules.ordered(frontmatter.tags).map { "  - \($0)" })
        }
        if !frontmatter.related.isEmpty {
            lines.append("related:")
            // F-06: alphabetical, and quoted because a bare `[[…]]` starts a YAML
            // flow sequence and would not survive a round-trip through a real parser.
            lines.append(contentsOf: frontmatter.related.sorted().map { "  - \"\($0)\"" })
        }
        if !frontmatter.aliases.isEmpty {
            lines.append("aliases:")
            lines.append(contentsOf: frontmatter.aliases.map { "  - \($0)" })
        }
        for foreign in frontmatter.foreignKeys {
            lines.append(contentsOf: foreign.lines)
        }

        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Validation

enum FrontmatterViolation: Equatable, Sendable {
    case missingBlock
    case missingDate
    case missingTags
    case foreignKey(String)
    case inlineTagList
    case unparsableTag(String)
    case tooManyAliases(count: Int)
    case unresolvedRelatedLink(String)
    /// `related` and the `## Note correlate` section disagree (W-06).
    case relatedOutOfSyncWithSection(missingInSection: [String], missingInFrontmatter: [String])
}

enum FrontmatterRules {
    static func validate(_ document: NoteDocument) -> [FrontmatterViolation] {
        var violations: [FrontmatterViolation] = []
        let frontmatter = document.frontmatter

        if !document.hasFrontmatterBlock {
            return [.missingBlock]
        }
        if frontmatter.date == nil { violations.append(.missingDate) }
        if frontmatter.tags.isEmpty { violations.append(.missingTags) }
        if frontmatter.usedInlineTagList { violations.append(.inlineTagList) }

        violations.append(
            contentsOf: frontmatter.foreignKeys
                .filter { !isAppNamespaced($0.name) }
                .map { .foreignKey($0.name) }
        )
        violations.append(contentsOf: frontmatter.unparsableTags.map { .unparsableTag($0) })

        if frontmatter.aliases.count > Frontmatter.maximumAliases {
            violations.append(.tooManyAliases(count: frontmatter.aliases.count))
        }
        return violations
    }

    // ADR-0032 (Plaud recording import into Pergamenum), plan
    // docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 9 -
    // R-05; ADR §D6.
    //
    /// Whether a foreign key belongs to this app's own namespace and is therefore not
    /// reported: `^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$`, exactly - a wrong-case
    /// `Pergamenum-Plaud-Id`, the bare word `pergamenum`, and any other vendor's
    /// `obsidian-foo` all stay non-conformities.
    ///
    /// The whole namespace rather than the three `pergamenum-plaud-*` keys by name: the
    /// prefix is what makes an app-written key greppable, and a fourth one is then free of
    /// a second decision here.
    private static func isAppNamespaced(_ name: String) -> Bool {
        name.range(of: "^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}
