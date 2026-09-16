import Foundation

/// A flat namespaced tag, the only tag shape the app accepts.
///
/// tag.md T-01 gives the mother regex
/// `^(client|competitor|project|type|topic|status|area|source)-[a-z0-9]+(-[a-z0-9]+)*$`.
/// Nested `/` tags are not supported: SPEC §4.4 removed them.
struct Tag: Hashable, Sendable, Comparable, CustomStringConvertible {
    let namespace: TagNamespace
    /// The part after the namespace prefix, e.g. `vibration-isolation`.
    let value: String

    var description: String { "\(namespace.rawValue)-\(value)" }

    /// Parses a bare tag string. Accepts an optional leading `#` so the same parser
    /// serves the frontmatter list and the inline body form (tag.md 5.3).
    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }

        guard let separator = text.firstIndex(of: "-"),
              let namespace = TagNamespace(rawValue: String(text[text.startIndex..<separator]))
        else { return nil }

        let value = String(text[text.index(after: separator)...])
        guard Tag.isWellFormedValue(value) else { return nil }

        self.namespace = namespace
        self.value = value
    }

    init(namespace: TagNamespace, value: String) {
        self.namespace = namespace
        self.value = value
    }

    /// `[a-z0-9]+(-[a-z0-9]+)*`: lowercase alphanumeric segments joined by single
    /// hyphens, with no leading, trailing or doubled hyphen.
    ///
    /// Not `private`: `CategoryRegistry.validating(_:version:)`
    /// (`Sources/Core/Categories/CategoryRegistry.swift`) reads it too, for the same
    /// slug grammar (ADR-0047 §D3) rather than a second regex.
    static func isWellFormedValue(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let segments = value.split(separator: "-", omittingEmptySubsequences: false)
        guard segments.count >= 1 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLowercaseASCIILetter || $0.isASCIIDigit }
        }
    }

    /// Frontmatter order (F-04): by namespace in T-01 order, then alphabetically
    /// inside the namespace.
    static func < (lhs: Tag, rhs: Tag) -> Bool {
        lhs.namespace == rhs.namespace ? lhs.value < rhs.value : lhs.namespace < rhs.namespace
    }
}

private extension Character {
    var isLowercaseASCIILetter: Bool { self >= "a" && self <= "z" }
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

// MARK: - Validation

/// One violation of the tag rules, carrying enough detail for the conformance view
/// to describe it and propose a fix.
enum TagViolation: Equatable, Sendable {
    /// Does not match the mother regex, or uses a `/` nested form.
    case malformed(String)
    /// A closed family received a value that is not in the vocabulary (SPEC §4.4).
    case notInVocabulary(Tag)
    /// A closed family was checked against an empty table, so nothing could be
    /// verified. Reported rather than passed: an unrun check is not a clean result.
    case vocabularyUnavailable(TagNamespace)
    /// More than seven tags on one note (T-10).
    case tooMany(count: Int)
    /// More than one `status-*` (T-05).
    case multipleStatus([Tag])
    /// A tag that encodes a date (T-07).
    case dateTag(Tag)
    /// A note carrying a `status-*` its category does not allow (tag.md 5.1): a daily note
    /// carries none, a capture only `status-inbox`, an ordinary note anything but
    /// `status-final` (reserved for the Deliverable naming.md 6.1 describes - an exported
    /// file, never a note this linter judges).
    case statusNotAllowedOnNote(Tag)
    /// An ordinary note without `type-note` or without any `topic-*` (tag.md 5.1).
    case missingRequiredTag(String)
}

enum TagRules {
    static let maximumTagsPerNote = 7

    /// Validates the tag set of one note.
    ///
    /// `category` decides which of the 5.1 exceptions apply: a daily note carries
    /// only `type-note`, and an inbox capture may carry `status-inbox`, so neither
    /// is missing anything.
    static func validate(
        _ tags: [Tag],
        category: NoteCategory,
        vocabulary: Vocabulary
    ) -> [TagViolation] {
        var violations: [TagViolation] = []

        if tags.count > maximumTagsPerNote {
            violations.append(.tooMany(count: tags.count))
        }

        let statusTags = tags.filter { $0.namespace == .status }
        if statusTags.count > 1 {
            violations.append(.multipleStatus(statusTags.sorted()))
        }

        for tag in tags {
            if isDateLike(tag.value) {
                violations.append(.dateTag(tag))
            }
            if tag.namespace.isClosed {
                if let allowed = vocabulary.values(for: tag.namespace) {
                    if allowed.isEmpty {
                        violations.append(.vocabularyUnavailable(tag.namespace))
                    } else if !allowed.contains(tag.value) {
                        violations.append(.notInVocabulary(tag))
                    }
                }
            }
            if tag.namespace == .status, !category.allowsStatus(tag.value) {
                violations.append(.statusNotAllowedOnNote(tag))
            }
        }

        violations.append(contentsOf: missingRequired(tags, category: category))
        return violations
    }

    private static func missingRequired(_ tags: [Tag], category: NoteCategory) -> [TagViolation] {
        guard category.requiresTopic else { return [] }
        var missing: [TagViolation] = []
        if !tags.contains(where: { $0.namespace == .type && $0.value == "note" }) {
            missing.append(.missingRequiredTag("type-note"))
        }
        // A capture has no subject yet, and SPEC §4.7 lists it beside `daily` as an
        // exception to the topic rule. It is recognised here, by the tag, rather than in
        // `NoteName.category`: that function is handed a file name and a path and knows
        // nothing about frontmatter, and a note is a capture because of what it declares
        // rather than because of where it sits. `status-inbox` is one of several statuses
        // an ordinary note may carry (tag.md 5.1/1.5), and saying "not filed yet" is its
        // whole job - so a note wearing it is exempt until somebody files it. The other
        // allowed statuses (active/waiting/archived) carry no such exemption.
        let isCapture = tags.contains { $0.namespace == .status && $0.value == "inbox" }
        if !isCapture, !tags.contains(where: { $0.namespace == .topic }) {
            missing.append(.missingRequiredTag("topic-*"))
        }
        return missing
    }

    /// The tags a note of a category is born with (SPEC §4.3, tag.md 5.1).
    ///
    /// One place rather than two. The inbox note used to have its tag set written out by
    /// hand in `inboxTemplate`, next to a `createNote` that built the same set from the
    /// same rule - which is how the app came to generate a file its own linter flagged
    /// without anybody noticing (#30).
    static func initialTags(for category: NoteCategory, topics: [Tag] = []) -> [Tag] {
        ordered([Tag(namespace: .type, value: "note")] + topics + (
            category == .capture ? [Tag(namespace: .status, value: "inbox")] : []
        ))
    }

    /// T-07 forbids date tags. Catches the shapes a date actually takes in practice:
    /// `2026`, `2026-08`, `2026-08-11` and `20260811`, in any namespace.
    private static func isDateLike(_ value: String) -> Bool {
        let digitsOnly = value.allSatisfy { $0.isNumber }
        if digitsOnly, value.count == 4 || value.count == 6 || value.count == 8 {
            return isPlausibleYearPrefix(value)
        }
        let parts = value.split(separator: "-")
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let first = parts.first, first.count == 4
        else { return false }
        return isPlausibleYearPrefix(String(first))
    }

    /// Restricts the digit heuristic to values that could be a year, so an ordinary
    /// numeric tag such as `topic-4140` is not mistaken for a date.
    private static func isPlausibleYearPrefix(_ value: String) -> Bool {
        guard let year = Int(value.prefix(4)) else { return false }
        return (1900...2199).contains(year)
    }

    /// Sorts tags into the order the frontmatter requires (F-04).
    static func ordered(_ tags: [Tag]) -> [Tag] {
        tags.sorted()
    }
}

/// The note kinds whose tag rules differ (tag.md 5.1).
enum NoteCategory: Equatable, Sendable {
    /// An ordinary note: needs `type-note` plus at least one `topic-*`, unless it is
    /// wearing `status-inbox`. May carry any `status-*` from the closed vocabulary except
    /// `status-final` - see `allowsStatus(_:)`.
    case note
    /// A daily note: `type-note` alone is correct and complete.
    case daily
    /// An inbox capture with no subject yet: `type-note` + `status-inbox`.
    ///
    /// Used when a note is *written*, to say which tags it starts with. It is not what
    /// the linter sees: `NoteName.category` derives a category from a file name and a
    /// path, and a capture is not recognisable from either. When a note is *judged*, the
    /// exemption comes from `status-inbox` itself - see `missingRequired`.
    case capture

    var requiresTopic: Bool { self == .note }

    /// tag.md 5.1 (1.5): whether a note of this category may carry the given `status-*`
    /// value. A daily note is zero-status and a capture only ever wears `status-inbox`;
    /// an ordinary note may take anything from the closed vocabulary (4.6) except
    /// `status-final`, reserved for a Deliverable - an exported file (naming.md 6.1),
    /// never a note this app's linter judges.
    func allowsStatus(_ value: String) -> Bool {
        switch self {
        case .note: value != "final"
        case .daily, .capture: value == "inbox"
        }
    }
}
