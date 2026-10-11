# ADR-0086: Templates where notes are born

- Status: **planned**. Written before the implementation, for `PG-387`/#889 (N4 of the
  note-workflow chain).
- Date: 2026-10-04. Written against `48a2d912`. Every line number below was read there.
- Number: `0086` was reserved for this record by the chain's dispatch. It was checked free on every
  ref on 2026-10-04 (`git log --all -- 'docs/adr/0086*'` printed nothing). Check again immediately
  before the merge (`docs/adr/README.md` rule 1).
- Source: root `SPEC.md` (Approved 2026-10-04), milestone N4, R-31 (and R-32 for the composer's
  template menu). Plans: `docs/plans/note-workflow-n4-mockup.md` and `docs/plans/note-workflow-n4.md`.
  Companion record: ADR-0085.
- Depends on ADR-0080 (N1) for the initial-tags rule every creation below inherits and for
  `CaptureTitle.derive`, which titles a capture «Nota nuova» with or without a template.
- **Extends** ADR-0011 §D5–§D7: the folder rule is unchanged, application stays at creation time,
  and the placeholder set grows by two, which §D7 itself says needs no reopening. **Amends SPEC
  (app)** §8.1 («Template configurabile» gets a meaning), §12 (Convenzioni gains one setting) and
  §16 (capture «Nota nuova» offers a template), each as a dated note. **Supersedes** `PG-121`'s
  template engine: it is not built.
- No on-disk format, frontmatter key, `IndexCache.schemaVersion` or protected-interface change. One
  key is added to `.pergamenum/settings.json`, which is app configuration, not note content.

## Context

### What the SPEC already settled (registered here, not reopened)

- A daily-template setting: a note under `Templates/`, absent means none. Cmd+Shift+D,
  `pergamenum://today` and the capture «Oggi» destination create today's note from it.
- Two new placeholders. `{{time}}` resolves. `{{cursor}}` is never written and yields the caret's
  place. A template naming `{{cursor}}` twice keeps the first and removes the others.
- Capture «Nota nuova», Workspace «Documento» and Quick Open offer a template choice. `perg` and MCP
  accept `--template`.
- `PG-121` closes as superseded.
- One GUI test for the daily template.

### What the code does today

- `NoteTemplate` (`Sources/Core/Conventions/NoteTemplate.swift`) reads a template's body and
  substitutes `{{title}}` and `{{date}}`. An unknown `{{…}}` is left as written (`:48-57`).
- `VaultSession.dailyNote(for:)` (`Sources/Vault/VaultSession+Notes.swift:120-131`) creates the
  day's note with no body. Its doc comment says "created from the template", which nothing does.
  ADR-0080's R-12 corrects that sentence; this record makes it true.
- Five paths reach a day's note through `dailyNote(for:)`:
  - `VaultController.openDailyNote` (Cmd+Shift+D, `pergamenum://today`, Quick Open's today row and
    the Oggi pane);
  - capture «Oggi» (`VaultCapture.swift:117`);
  - the event note's link from its day (`VaultSession+EventNotes.swift:78`);
  - the Pratiche diary mirror (`PraticaEntryComposer.swift:152`).
- Only the composer offers a template. Capture, Quick Open's create row, Workspace «Documento» and
  both connectors cannot.
- `TemplateSheet` (applying a template into the open note) inserts the body at the caret through
  `Navigation.insert(_:cursorBack:)` and has no way to say where the caret should go.

## Decision

**D1. Two placeholders, resolved by one function.**
`NoteTemplate.resolve(_ template: String, title: String, date: CalendarDate, time: TaskTime) ->
NoteTemplate.Resolved`, where `Resolved` holds `body: String` and `caretOffset: Int?`. The offset is
in UTF-16 units into `body`, which is what an `NSRange` counts.

- **`{{time}}`.** It becomes the creation moment as `HH:mm`, spelled by `TimeOfDay.formatted`, the
  one spelling of a time this app writes (PG-263).
- **`{{cursor}}`.**
  - It is located in the template text before any other substitution. A title or a date that
    happens to contain the marker is therefore written as typed, never mistaken for a caret.
  - The first occurrence gives the offset and every occurrence is removed.
  - A template without one gives `nil`, and the caret goes where it went before.
- **Unchanged from ADR-0011 §D7.** `{{title}}` and `{{date}}` resolve as today, and any other
  `{{…}}` stays exactly as written.
- **`substituting(title:date:in:)` keeps its signature.** It becomes `resolve(…).body` with the time
  at midnight, so `NoteTemplateTests` and its two callers keep their bytes. The callers move to
  `resolve` as they gain a caret.
- **`Resolved.caret(inWritten:)`.** It turns the body offset into an offset in the whole written
  file, as `length(written) - length(body) + caretOffset`. `createNote` writes the frontmatter,
  then one line break, then `body`, so the body is a suffix of the file. That one subtraction is
  the only arithmetic the caret needs.

**D2. The daily template is a vault setting.**

- `VaultSettings.dailyTemplate: String?`, JSON key `dailyTemplate`, decoded with `decodeIfPresent`
  like every key since ADR-0036 §D10. Absent or empty means none.
- The value is a vault-relative path that `NoteTemplate.isTemplate` accepts. Any other value is
  ignored, with a recorded problem naming it.
- Impostazioni › Convenzioni gains «Modello della nota del giorno», a picker of the vault's
  templates plus «Nessuno», beside «Cartella daily».

**D3. The template is applied at the one door every day's note is born through.**
`VaultSession.dailyNoteBirth(for:at:) async throws -> DailyNoteBirth`, holding `path`, `created`
and `caret`. It lives in `Sources/Vault/VaultSession+NoteBirth.swift`, which ADR-0085 adds to
`sharedSources`.

1. When the note exists, it returns the note unchanged.
2. When the note is missing, it reads the setting.
3. It reads the template's body through `NoteTemplate.body(of:)`. The template's frontmatter is
   discarded (ADR-0011 §D6).
4. It resolves the body with the day's compact title, the day, and the time of `at`.
5. It creates the note with that body through `createNote(… category: .daily, body:)`.

`dailyNote(for:)` keeps its signature and returns `dailyNoteBirth(for: date, at: Date()).path`, so
every path in the context inherits the template with no change of its own. That includes the event
note's day and the Pratiche mirror, and it is deliberate: a day's note is born one way whichever
gesture caused it.

A template that is missing, unreadable or outside `Templates/` never blocks the day. The note is
created as today, with no body, and the problem is recorded. The daily note is a navigation target,
and a refusal would strand Cmd+Shift+D.

**D4. The caret is a property of the tab, consumed once.**

- **The field.** `NoteTab.pendingCaret: Int?` is an absolute UTF-16 offset in the note's text. It
  is transient and never persisted.
- **Who sets it.** `openNoteInNewTab(at:caret:)` and `openNote(at:caret:)` set it. The column that
  shows the tab consumes it on its first update, places the caret there and clears it. This is the
  "consumed once" shape `pendingInsertion` and `pendingJump` already use in `EditorColumnView`.
- **Who passes it.** `VaultController.openDailyNote` passes the birth's caret only when this call
  created the note: reopening an existing day moves nobody's caret. The pane-host composer passes
  its composition's caret (ADR-0085 §D7).
- **`TemplateSheet`.** Applying a template into the open note maps `caretOffset` to `cursorBack`
  (`body.utf16.count - caretOffset`). `Navigation.insert` already places the caret that way.
- **Not covered.** The Oggi pane's embedded daily editor (`TodayView.swift:211`) is not a tab and
  does not consume the caret. The caret applies when the day's note opens in the Note pane, which
  is where Cmd+Shift+D shows it (ADR-0080, R-04). Cmd+Shift+D pressed inside Oggi keeps today's
  behaviour.

**D5. A template choice wherever a note is named.**

- **The composer.** It keeps its template menu (ADR-0011 §D6) in every host but the extract mode
  (ADR-0085 §D8). Quick Open's create row and Workspace «Documento» reach the composer, so both get
  the choice with no menu of their own (ADR-0085 §D7). The composer's preview and its creation use
  `resolve`.
- **Capture «Nota nuova».** It gains a template menu under the destination row:
  `CaptureController.template: String?`, identifier `capture-template`, remembered with the last
  destination. `VaultAPI.capture(… template:)` composes the note in one write.
  - The title comes from `CaptureTitle.derive` (ADR-0080 §D3).
  - The rest of the capture goes at `{{cursor}}`, or after the resolved body, separated by one blank
    line, when there is no marker.
  - If `CaptureTitle` kept the first line, that line leads the captured text, as without a template.
  - The composition is the pure `NoteTemplate.composing(captured:into:)`.
- **No template elsewhere in capture.** «Task», «Oggi» and «In una nota» take none: the panel shows
  no menu there, and the connector refuses `template` with any destination but a new note. «Oggi»
  still gets D3's daily template when it is the one creating the day.

**D6. The connectors name a template by title or by path.**

- **Where it is accepted.** `perg note new --template <titolo|percorso>`, `perg capture --template …`
  (note destination only), and a `template` property on the MCP `create_note` and `capture` tools.
- **How it resolves.** `NoteTemplate.reference(_:among:) -> Result<String, TemplateReferenceError>`
  takes an exact vault-relative path. Failing that, it takes a title among the notes under
  `Templates/`. Unknown and ambiguous references are refused, and the refusal lists the available
  templates.
- **No caret.** A connector has no caret, so `{{cursor}}` is removed.
- **Rehearsal.** The `dryRun` diff shows the resolved body, which is the connector's acceptance.

**D7. PG-121's engine is superseded, not deferred.** The roadmap's Knap-inspired engine
(conditionals, loops, user-defined variables) is not built. The placeholder set stays a short,
fixed list resolved by one pure function, and each addition is a sentence in this record's
successor. `PG-121` closes with a pointer here. The ledger line for `PG-387` says "PG-121's engine
stays deferred". The approved SPEC (R-31) supersedes that line, and the ledger is corrected at
`/ship`.

**D8. One GUI test: the daily template.** It is the second of ADR-0085's two, in
`UITests/NoteBirthUITests.swift`, on `PergamenumUITestCase`.

- **Seed.** `Templates/Giornata.md` holds `## {{time}}`, a blank line, `{{cursor}}`, a blank line,
  and `## Note`. The `dailyTemplate` key is merged into the vault's `.pergamenum/settings.json`.
- **Steps.** Press Cmd+Shift+D, type `Primo appunto`, then press Cmd+S.
- **Assertions, on the file.**
  - `Primo appunto` sits on the line where `{{cursor}}` was, between the two headings.
  - A `## \d{2}:\d{2}` heading exists.
  - No `{{cursor}}` or `{{time}}` remains.
- **Why it has to be GUI.** The chain under test is the menu key, the pane switch, the tab opening,
  the editor taking first responder and the caret sitting at the consumed offset when the first key
  arrives. The hosted harness can neither make a window key nor send it a key event (R-15 of
  `Tests/HostedViewSupport.swift`), and "the typed text lands at `{{cursor}}`" is precisely a
  first-responder fact.
- **What other tests cover.** Resolution, caret arithmetic and the session's birth door are pure
  and session tests.

**D9. SPEC (app) amendments, as dated notes, bodies untouched.**

- §8.1: «Template configurabile» is the `dailyTemplate` setting. The day's note is born from it on
  every path, and `{{time}}`/`{{cursor}}` join the placeholders.
- §12: Convenzioni lists «Modello della nota del giorno».
- §16: «Nota nuova» offers a template, and the captured text goes at `{{cursor}}` or after the body.

## Alternatives considered

- **Applying the daily template in `openDailyNote` only (the roadmap's "dailyNote(for:) passes
  body" read narrowly).** Rejected: capture «Oggi», the event note and the Pratiche mirror would
  keep creating bare days. That would break R-31's capture clause, and the shape of a day's note
  would depend on which gesture happened first.
- **A template path in the daily note's frontmatter, or a per-folder template.** Rejected: the
  frontmatter schema is closed (SPEC (app) §4.3), and one vault setting is what the SPEC's data
  model names.
- **The caret as a navigation request (`jumpToLine`) instead of a tab property.** Rejected:
  `VaultController` holds no `Navigation`, and `openDailyNote` is called from places that do not
  hold one either (`VaultController+Routes.swift:146`). A request sent before the tab exists lands
  in the note being left, the trap `VaultBrowser.swift:89-93` already documents for heading jumps.
- **`{{cursor}}` written as a marker and found again by the editor.** Rejected: the SPEC says it is
  never written, and a marker in the file is one an external editor or a crash leaves behind.
- **A refusal when the daily template is missing.** Rejected in D3: the daily note is where
  Cmd+Shift+D goes, and a refusal would turn a configuration slip into a dead key.
- **Building PG-121's engine now.** Rejected by the SPEC, and by PG-269's own roadmap ("template
  engine not recommended now").

## Consequences

Positive:

- One template mechanism from five surfaces and two connectors, one function resolving it, and one
  door every day's note is born through.
- The "created from the template" doc comment becomes true.

Negative:

- A template change is visible only on days not yet created. Existing days are never rewritten (the
  rule is not retroactive, as ADR-0080 §D2 is not).
- The Oggi pane's embedded editor does not take the caret (D4).
- A capture that creates the day through «Oggi» places its text at the end of the templated day, not
  at `{{cursor}}`. Its line is appended, as today.

Neutral:

- `NoteTemplate.substituting` stays as a thin forward for its existing callers and tests.

## References

- SPEC.md (root), N4: R-31, R-32. Data model ("two new settings"), Edge cases (`{{cursor}}` twice),
  Test seams 1, 5 and 6.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N4 task 4. `docs/20261002_Pergamenum_NoteWorkflowReport.md`
  I-4.
- ADR-0007 §D6, ADR-0011 §D5–§D7, ADR-0036 §D10, ADR-0063, ADR-0073, ADR-0080 §D2/§D3, ADR-0085.
- `PG-121` (TODO.md), `PG-269` item 8, `PG-387`/#889.
