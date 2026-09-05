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
// Tester-declared signatures only (this dispatch's brief, tasks 4-5: "Tester first. Red
// before any body."). Every body below is an obviously-wrong-but-compiling placeholder; the
// coder implements the real frontmatter/tag/body/merge rules named in the doc comments.
enum TranscriptNote {
    /// D10: the quote is written inline and verbatim, minus the five characters the task
    /// grammar owns (`>`, `#`, `^`, `[`, `]`) and minus newlines, each becoming a space, then
    /// whitespace collapsed to one. Never truncated.
    ///
    /// The property that makes dedup sound: `PlaudQuote.fingerprint(sanitizedQuote(q)) ==
    /// PlaudQuote.fingerprint(q)` for every `q`, because fingerprint step 3 already replaces
    /// every non-alphanumeric character with a space.
    ///
    /// Stub: returns `raw` unchanged, which is why the invariant above is red until this is
    /// implemented for real (a sanitized string that still contains e.g. `>` or a newline
    /// is not what the ADR describes, even though the invariant happens to hold trivially
    /// for a `raw` with none of the five characters).
    static func sanitizedQuote(_ raw: String) -> String {
        raw
    }

    /// D9's suppression set for one recording: the union of the note's own task lines (read
    /// back by matching the `(urgenza N/5, importanza N/5 — "…")` suffix and fingerprinting
    /// the quote inside it) and `ledgerFingerprints`, which only ever grows. A task line that
    /// does not match the shape (the person rewrote it) contributes nothing and is not an
    /// error.
    ///
    /// Stub: always empty, so every caller currently sees "nothing is suppressed."
    static func suppressionSet(existingNoteText: String?, ledgerFingerprints: [String]) -> Set<String> {
        []
    }

    /// The full file text for a recording's transcript note.
    ///
    /// D6: frontmatter built through `Frontmatter` + `FrontmatterSerializer.render`, never by
    /// hand-writing YAML - the three `pergamenum-plaud-*` keys go in as `foreignKeys` entries.
    /// D7: tags are `type-note` + `topic-trascrizione`, plus `source-meeting` only when
    /// `proposal.recordingKind == .meeting`. D11: body is `## <Theme>` sections in proposal
    /// order, then `## Trascrizione` last. A task line is `- [ ] <title>` plus
    /// ` >YYYY-MM-DD` only when `due_hint` is non-null, plus
    /// ` (urgenza N/5, importanza N/5 — "<sanitized quote>")`. A speaker rename applies only
    /// to a transcript line whose trimmed prefix is exactly `<label>:` (`Speaker 1` must not
    /// match inside `Speaker 10`).
    ///
    /// The merge path (Task 5, `existingNoteText != nil`): a theme heading already present
    /// keeps the person's own edits and gains only genuinely new, non-suppressed accepted
    /// task lines; a new theme becomes a new section without disturbing the others;
    /// `## Trascrizione` is replaced wholesale, never merged, since a forced re-run may
    /// produce a better transcript. `ledgerFingerprints` and the note's own existing lines
    /// both suppress a task (D9) - an accepted task whose fingerprint is in that union
    /// contributes no line.
    ///
    /// Stub: returns the empty string regardless of input.
    static func render(
        proposal: PlaudProposal,
        acceptedTaskIDs: Set<String>,
        speakerRenames: [String: String],
        ledgerFingerprints: [String],
        existingNoteText: String?
    ) -> String {
        ""
    }
}
