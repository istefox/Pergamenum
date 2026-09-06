import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Tasks 4-5 -
// R-05, R-08; ADR §D6, §D7, §D9, §D10, §D11.
//
// The note builder: a pure function, proposal + accepted task ids + speaker renames +
// existing note text (optional) -> the full file text. No `VaultSession`, no disk - that is
// what makes R-05 and R-08 unit-testable at all. `RecordingsController` (Task 6) is the only
// caller; it reads and writes the actual file.
//
// The whole merge is line arithmetic over one shape: a body is a preamble plus a list of
// `## ` sections, and rebuilding it concatenates exactly what was parsed. That is what makes
// a re-run over an unchanged proposal byte-identical rather than merely equivalent.
enum TranscriptNote {
    /// The one heading this file owns outright: replaced wholesale on every re-run, since a
    /// forced re-run may produce a better transcript (ADR §D11). Every other section is
    /// merged and never overwritten.
    static let transcriptHeading = "Trascrizione"

    private static let headingPrefix = "## "
    /// The five characters `TaskParser` reads as grammar (`>date`, `#tag`, `^marker`,
    /// `[[wikilink]]`) inside a task line's body.
    private static let charactersTheTaskGrammarOwns: Set<Character> = [">", "#", "^", "[", "]"]

    // MARK: - Quote sanitation (D10)

    /// D10: the quote is written inline and verbatim, minus the five characters the task
    /// grammar owns and minus newlines, each becoming a space, then whitespace collapsed to
    /// one. Never truncated: it is the dedup key and the evidence for the task.
    ///
    /// The property that makes dedup sound: `PlaudQuote.fingerprint(sanitizedQuote(q)) ==
    /// PlaudQuote.fingerprint(q)` for every `q`, because fingerprint step 3 already replaces
    /// every non-alphanumeric character with a space.
    static func sanitizedQuote(_ raw: String) -> String {
        let neutralised = raw.map { character in
            charactersTheTaskGrammarOwns.contains(character) || character.isNewline ? " " : character
        }
        return String(neutralised).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Suppression (D9)

    /// D9's suppression set for one recording: the union of the note's own task lines (read
    /// back by matching the `(urgenza N/5, importanza N/5 — "…")` suffix and fingerprinting
    /// the quote inside it) and `ledgerFingerprints`, which only ever grows. A task line that
    /// does not match the shape (the person rewrote it) contributes nothing and is not an
    /// error.
    static func suppressionSet(existingNoteText: String?, ledgerFingerprints: [String]) -> Set<String> {
        var fingerprints = Set(ledgerFingerprints)
        guard let existingNoteText else { return fingerprints }
        for line in existingNoteText.components(separatedBy: "\n") {
            guard let quote = quote(inTaskLine: line) else { continue }
            fingerprints.insert(PlaudQuote.fingerprint(quote))
        }
        return fingerprints
    }

    /// The rendered note's whole text for a recording, fresh or merged onto `existingNoteText`.
    ///
    /// D6: frontmatter through `Frontmatter` + `FrontmatterSerializer.render`, never
    /// hand-written YAML - the three `pergamenum-plaud-*` keys are `foreignKeys` entries.
    /// D7: `type-note` + `topic-trascrizione`, plus `source-meeting` only for a meeting.
    /// D11: `## <Theme>` sections in proposal order, then `## Trascrizione` last.
    ///
    /// The merge (`existingNoteText != nil`) keeps everything the person wrote: an existing
    /// theme section gains only genuinely new, non-suppressed accepted lines; a new theme
    /// becomes a section ahead of the transcript; sections nobody proposed are left alone.
    static func render(
        proposal: PlaudProposal,
        acceptedTaskIDs: Set<String>,
        speakerRenames: [String: String],
        ledgerFingerprints: [String],
        existingNoteText: String?
    ) -> String {
        let existing = existingNoteText.map(NoteDocument.parse)
        var body = existing.map { parseBody($0.body) } ?? Body(preamble: [""], sections: [])
        var suppressed = suppressionSet(
            existingNoteText: existingNoteText, ledgerFingerprints: ledgerFingerprints
        )

        for theme in proposal.themes {
            let newLines = lines(for: theme, acceptedTaskIDs: acceptedTaskIDs, suppressing: &suppressed)
            merge(newLines, underHeading: headingPrefix + theme.name, into: &body)
        }
        replaceTranscript(
            with: transcriptLines(of: proposal, speakerRenames: speakerRenames), in: &body
        )

        return FrontmatterSerializer.render(mergedFrontmatter(for: proposal, existing: existing))
            + body.lines.joined(separator: "\n")
    }

    // MARK: - Frontmatter (D6, D7)

    private static func mergedFrontmatter(for proposal: PlaudProposal, existing: NoteDocument?) -> Frontmatter {
        var frontmatter = Frontmatter.empty
        // A note whose frontmatter block a person edited keeps it: this feature adds what is
        // missing and removes nothing, the same way the merge treats the body.
        if let existing, existing.hasFrontmatterBlock { frontmatter = existing.frontmatter }

        if frontmatter.date == nil { frontmatter.date = localDate(of: proposal) }
        for tag in tags(for: proposal) where !frontmatter.tags.contains(tag) {
            frontmatter.tags.append(tag)
        }
        for key in foreignKeys(for: proposal)
        where !frontmatter.foreignKeys.contains(where: { $0.name == key.name }) {
            frontmatter.foreignKeys.append(key)
        }
        return frontmatter
    }

    /// D8: the `date:` is the **local** calendar date of the recorded instant, never today's
    /// and never the UTC one.
    private static func localDate(of proposal: PlaudProposal) -> CalendarDate {
        guard let instant = PlaudTimestamp.parse(proposal.recording.recordedAt) else { return .today }
        return CalendarDate(instant)
    }

    private static func tags(for proposal: PlaudProposal) -> [Tag] {
        var names = ["type-note", "topic-trascrizione"]
        // `lecture`, `update` and `personal` get no `source-*` rather than a convenient lie.
        if proposal.recordingKind == .meeting { names.append("source-meeting") }
        return names.compactMap { Tag($0) }
    }

    /// The service's own strings, byte for byte (D8): this app never re-serializes a value it
    /// did not author, so a re-import compares strings that cannot have drifted. "Byte for
    /// byte" is about content, not about YAML syntax: `id`/`recordedAt` are untrusted wire
    /// values placed inside a double-quoted scalar, so a `"` or a line break from the service
    /// is escaped rather than passed through, or it would close the scalar early and let the
    /// rest of the value be read as new frontmatter keys (RTF review finding, 2026-09-06).
    private static func foreignKeys(for proposal: PlaudProposal) -> [Frontmatter.ForeignKey] {
        let recording = proposal.recording
        return [
            Frontmatter.ForeignKey(
                name: "pergamenum-plaud-id",
                lines: ["pergamenum-plaud-id: \"\(yamlEscaped(recording.id))\""]
            ),
            Frontmatter.ForeignKey(
                name: "pergamenum-plaud-recorded-at",
                lines: ["pergamenum-plaud-recorded-at: \"\(yamlEscaped(recording.recordedAt))\""]
            ),
            Frontmatter.ForeignKey(
                name: "pergamenum-plaud-duration-ms",
                lines: ["pergamenum-plaud-duration-ms: \(recording.durationMs)"]
            ),
        ]
    }

    /// Escapes a value for a double-quoted YAML scalar: backslash and `"` are the two
    /// characters that scalar syntax itself reserves, and a literal line break would end the
    /// block's single-line key before the parser ever sees a closing quote. YAML's own
    /// double-quoted-scalar grammar defines `\\` and `\n` as valid escapes for exactly this.
    private static func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    // MARK: - Task lines (C7, D9, D10)

    private static func lines(
        for theme: PlaudTheme, acceptedTaskIDs: Set<String>, suppressing suppressed: inout Set<String>
    ) -> [String] {
        var lines: [String] = []
        for task in theme.tasks where acceptedTaskIDs.contains(task.id) {
            let fingerprint = PlaudQuote.fingerprint(task.quote)
            guard !suppressed.contains(fingerprint) else { continue }
            // Inserted as it is written: two accepted tasks quoting the same sentence are
            // one line, not two, without waiting for the next run to notice.
            suppressed.insert(fingerprint)
            lines.append(taskLine(for: task))
        }
        return lines
    }

    /// `- [ ] <title>` + ` >YYYY-MM-DD` only when `due_hint` is present and is a date this
    /// app's own parser accepts + ` (urgenza N/5, importanza N/5 — "<quote>")`.
    ///
    /// The title goes through the same sanitation as the quote: it sits in the same task-line
    /// body, so a `#` or a `>` in model-written prose would be read as grammar there too
    /// (D10's reasoning, applied to the other half of the line).
    private static func taskLine(for task: PlaudTask) -> String {
        var line = "- [ ] \(sanitizedQuote(task.title))"
        if let hint = task.dueHint, let date = CalendarDate(iso: hint) {
            line += " >\(date)"
        }
        line += " (urgenza \(task.urgency)/5, importanza \(task.importance)/5"
        line += " — \"\(sanitizedQuote(task.quote))\")"
        return line
    }

    /// The quote a line of this file's own making carries, or `nil` for any other line.
    private static func quote(inTaskLine line: String) -> String? {
        guard isTaskLine(line),
              let ratings = line.range(of: " (urgenza "),
              let opening = line.range(of: "— \"", range: ratings.upperBound..<line.endIndex),
              let closing = line.range(of: "\")", options: .backwards),
              opening.upperBound <= closing.lowerBound,
              hasRatingShape(line[ratings.upperBound..<opening.lowerBound])
        else { return nil }
        return String(line[opening.upperBound..<closing.lowerBound])
    }

    /// `N/5, importanza M/5 `, the middle of the suffix - checked rather than assumed, so a
    /// line the person rewrote around a stray «— "…"» is not read as a task this app wrote.
    private static func hasRatingShape(_ middle: Substring) -> Bool {
        let parts = middle.components(separatedBy: "/5, importanza ")
        guard parts.count == 2, isPositiveInteger(parts[0]), parts[1].hasSuffix("/5 ") else { return false }
        return isPositiveInteger(String(parts[1].dropLast(3)))
    }

    private static func isPositiveInteger(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isNumber)
    }

    private static func isTaskLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [")
    }

    // MARK: - Transcript (C6, D11)

    private static func transcriptLines(
        of proposal: PlaudProposal, speakerRenames: [String: String]
    ) -> [String] {
        var lines = proposal.transcript.text
            .components(separatedBy: "\n")
            .map { renamedSpeaker(on: $0, using: speakerRenames) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines
    }

    /// A rename applies only to a line whose trimmed prefix is exactly `<label>:` - so
    /// `Speaker 1` never matches inside `Speaker 10`, and a label the service already
    /// resolved to a real name is left alone when nobody renamed it.
    private static func renamedSpeaker(on line: String, using renames: [String: String]) -> String {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        for (label, name) in renames where !name.isEmpty {
            let marker = "\(label):"
            guard rest.hasPrefix(marker) else { continue }
            return "\(indent)\(name):\(rest.dropFirst(marker.count))"
        }
        return line
    }

    // MARK: - Body arithmetic

    private struct Section {
        var heading: String
        var lines: [String]
    }

    private struct Body {
        var preamble: [String]
        var sections: [Section]

        var lines: [String] { preamble + sections.flatMap { [$0.heading] + $0.lines } }
    }

    private static func parseBody(_ body: String) -> Body {
        var parsed = Body(preamble: [], sections: [])
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix(headingPrefix) {
                parsed.sections.append(Section(heading: line, lines: []))
            } else if parsed.sections.isEmpty {
                parsed.preamble.append(line)
            } else {
                parsed.sections[parsed.sections.count - 1].lines.append(line)
            }
        }
        return parsed
    }

    private static func merge(_ newLines: [String], underHeading heading: String, into body: inout Body) {
        if let index = body.sections.firstIndex(where: { $0.heading == heading }) {
            guard !newLines.isEmpty else { return }
            body.sections[index].lines = appending(newLines, to: body.sections[index].lines)
            return
        }
        let section = Section(heading: heading, lines: content(newLines))
        // Ahead of the transcript, which stays last (D11); on a fresh note there is no
        // transcript section yet, so proposal order is simply append order.
        if let transcript = body.sections.firstIndex(where: { $0.heading == transcriptSectionHeading }) {
            body.sections.insert(section, at: transcript)
        } else {
            body.sections.append(section)
        }
    }

    private static func replaceTranscript(with transcript: [String], in body: inout Body) {
        if let index = body.sections.firstIndex(where: { $0.heading == transcriptSectionHeading }) {
            body.sections[index].lines = content(transcript)
        } else {
            body.sections.append(Section(heading: transcriptSectionHeading, lines: content(transcript)))
        }
    }

    private static var transcriptSectionHeading: String { headingPrefix + transcriptHeading }

    /// A section's own lines: one blank line under the heading, the content, one blank line
    /// before whatever comes next (or the file's final newline).
    private static func content(_ lines: [String]) -> [String] {
        lines.isEmpty ? [""] : [""] + lines + [""]
    }

    /// Appends after the section's last line that says anything, so new task lines join the
    /// existing ones instead of landing past the blank line that closes the section.
    private static func appending(_ newLines: [String], to lines: [String]) -> [String] {
        var updated = lines
        let lastWritten = updated.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        updated.insert(contentsOf: newLines, at: lastWritten.map { $0 + 1 } ?? updated.count)
        if updated.last?.isEmpty != true { updated.append("") }
        return updated
    }
}
