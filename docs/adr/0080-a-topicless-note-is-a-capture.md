# ADR-0080: A note born without a topic is a capture, a capture's title is derived rather than refused, and the inbox folder is a setting

- Status: **accepted**. Merged to `main` via PR #897 (`5056c61f`, 2026-10-05), carrying Tasks 1 to 3
  of `docs/plans/pg-384-n1-seams.md`: the topic-less rule, the derived capture title, the inbox
  folder setting, and this record with its SPEC amendments.
- Scope: §D3's caption clause and the panel's refusal of a taken title, and §D4, amended by
  ADR-0088.
- Date: 2026-10-04. Written against `6c03f024` (branch `kepler/task-00994c70`). `origin/main` was
  at `babdbb49` when this was written; its diff against `6c03f024` touches the menus, SPEC §6.1
  and §10, the icon-size theme tokens, the hosted-view test support and `TODO.md`, none of the
  code this record decides on.
- Number: `0080` was checked free on every local and remote-tracking ref on 2026-10-04 (no ref's
  tree holds a `docs/adr/0080*`). Check again immediately before the merge (`docs/adr/README.md`
  rule 1). The roadmap reserves 0081 to 0086 for the later N chains.
- Source: `docs/specs/note-workflow-n1-seams.spec.md` (the repo-root `SPEC.md`, Approved
  2026-10-04, `PG-384`, archived by Task 3 of the plan), which declares R-01 to R-22. This record
  covers R-01 to R-06, R-16, R-17 and R-20. The other N1 seams carry no ADR; see §D7.
- **Extends ADR-0008** §D4 (the one capture write now derives a title instead of refusing) and
  §D6 (the inbox is still a real file, `Capture.md`, but its folder is now a vault setting).
- **Amends the app SPEC** (`docs/20260811_Pergamenum_SpecApp.md`): §4.1's note on the inbox
  folder, §4.3's rule line for a capture, §12's Convenzioni list (the inbox folder setting), and
  §16's inbox path and first-line behaviour. §8.1's `Cmd+Shift+D`/`Cmd+T` line is also tagged
  with this record: that is R-19's wording fix, outside the scope above, carried in this chain's
  SPEC change rather than decided here.
- No on-disk format change. The note frontmatter schema stays `date`, `tags`, `related`, `aliases`.
  No tag joins the vocabulary, since `status-inbox` is already in it. `IndexCache.schemaVersion`
  is unchanged. `settings.json` gains one optional key; an absent key reads as today's folder.
  No protected interface changes. `ImportNaming.recordingNoteTitle` and `VaultBoundary.url(for:)`
  keep their behaviour.

## Context

**The defect.** A note created with no `topic-*` fails the project's own linter on almost every
path that creates one. `TagRules.initialTags(for:topics:)` (`Sources/Core/Conventions/Tag.swift`)
adds `status-inbox` only when the caller passes `.capture`. `VaultSession.createNote` defaults to
`.note`, and only three callers pass `.capture`: the event note, the Contenitore scheda and the
inbox task note.

- **Paths affected:**
  - the Cmd+N composer with its topic field left empty;
  - Quick Open «crea nota»;
  - the Workspace «Documento» sheet;
  - capture «Nota nuova» (it reaches `VaultAPI.createNote` with `topic: nil`);
  - `perg note create`;
  - the MCP `create_note` tool.
- **What each one writes:** `type-note` alone.
- **What the linter says:** `TagRules.missingRequired` reports `topic-*` missing, because the only
  exemption it knows is a note wearing `status-inbox`.

So the app writes files that `perg lint` then flags. Issue #30 had the same shape: two places
built one tag set, drifted, and the app generated a file its own linter flagged. The fix then was
one function, `initialTags`. That function now has the wrong default for the commonest case.

**The premise, corrected.** The roadmap (`docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N1)
and the ledger entry for `PG-384` both say ADR-0008 §D6 promised `status-inbox` for every
topic-less note. It did not. §D6 covers two things: the four capture destinations, and the real
file `00 Inbox/Capture.md`. The promise lives elsewhere:

- app SPEC §4.3: «Capture inbox senza argomento: `- type-note` + `- status-inbox`»;
- app SPEC §4.4: the daily and capture exceptions to the topic rule;
- the harness `tag.md` 5.1.

SPEC §4.2 is about file naming and has no capture wording. This record therefore extends
ADR-0008 and amends SPEC §4.3 and §16, not §4.2. The ledger wording is corrected when the chain
closes.

**Capture refuses its own input.** `captureAsNote` (`Sources/Connector/VaultCapture.swift`) uses
the first line as the title. It passes that line through `NoteName.validate` and throws a
`ConnectorError` when the validator objects. This is pinned by
`CaptureTests.aTitleTheConventionsRefuseStopsTheCaptureInsteadOfBeingCorrected`.

- **Where capture happens:** the panel floats over another application. The person typed an idea
  between two other things.
- **What triggers a refusal:** a colon, a question mark, a `v2` at the end or a long sentence.
- **What a refusal leaves behind:** a sentence on top of Safari that nobody reads, and a draft
  that lives for sixty seconds.

**The inbox folder is a literal in four kinds of place:**

- `VaultAPI.CaptureDestination.defaultFolder` (`"00 Inbox"`);
- `VaultSession.TaskDestination.inboxPath` (`"00 Inbox/Capture.md"`), read through `relativePath`;
- file import (`VaultController+Import.swift`);
- the strings that name the folder: the import alert, `FileImportSheet`, `HelpSheets`, the
  capture panel's folder label, `perg` help, and the MCP `capture` schema.

A vault whose triage folder is called something else cannot say so.

## Decision

**D1. One rule decides `status-inbox`, in the one function that already decides a new note's tags.**

`TagRules.initialTags(for:topics:)` keeps its signature. Its rule becomes:

| Category | Tags given | Born with |
|---|---|---|
| `.daily` | any | `type-note` (today's bytes) |
| `.capture` | any | `type-note` + the given tags + `status-inbox` (today's bytes) |
| `.note` | at least one tag of namespace `topic` | `type-note` + the given tags (today's bytes) |
| `.note` | no tag of namespace `topic` | `type-note` + the given tags + `status-inbox` |

The test is on the **namespace**, not on whether the list is empty. The `topics:` parameter has
carried any conformant tag for a while:

- the Cmd+N composer accepts whatever `Tag(_:)` accepts in its «topic-…» field;
- Pratiche passes `topic-pratica` plus a `client-*`.

A note born with a `client-acme` and no topic is a capture. That is what SPEC §4.3 calls a note
«senza argomento».

No caller changes its category or its arguments. Every creation path reaches this function
through `VaultSession.createNote`, so all of them inherit the rule together. That covers the
composer, Quick Open, «Documento», capture, `perg`, MCP and Pratiche create-and-link. Pratiche
always passes `topic-pratica` today, so its output does not change. This is the #30 lesson
applied again: one place decides, so the app cannot write a file its linter flags.

**D2. What does not change, and why nothing else has to.**

- **Byte-identical to today.** Four notes reach `initialTags` as `.daily` or `.capture`, so their
  bytes are unchanged:
  - the daily note;
  - the event note (`VaultSession+EventNotes.swift`, `.capture`);
  - the Contenitore scheda (`ContenitoreScheda.render`, `.capture`);
  - the inbox task note (`inboxTemplate`, `.capture`).
- **Untouched.** The Plaud transcript and the Nuova pratica wizard build their own tag lists and
  are not touched.
- **The linter needs no change.** `TagRules.missingRequired` already exempts a note wearing
  `status-inbox` from the topic rule, and `NoteCategory.note.allowsStatus("inbox")` is already
  true. A topic-less note made by any of these paths lints clean.
- **Not retroactive** (frontmatter.md 6.2, SPEC §4.3). Notes that already exist without a topic
  are not rewritten. They keep being flagged until someone touches them.
- **The connectors inherit the rule with no code of their own.** The visible consequence is in
  their output: the MCP dry-run diff of a topic-less `create_note` now shows `+  - status-inbox`.
  A model that reads that diff sees one more line.

**D3. A capture's first line yields a derived title. `createNote` itself still refuses.**

The rule is one pure function in the shared sources, `CaptureTitle.derive`
(`Sources/Core/Conventions/CaptureTitle.swift`). Both connectors and the app compile it. It runs
on the capture text's first line. "First line" is read exactly as today: up to the first
`LineBreak.isTerminator`, then trimmed of outer whitespace. Today's trim already repaired outer
whitespace silently, so outer whitespace does not count as a difference.
One departure from "exactly as today": a lone `\r`, which `LineBreak.isTerminator` does not read
as a break, also ends the first line (`CaptureTitle.endsTypedLine`), and the body splits at the
same character. Otherwise the `\r` would reach a file name, or the text after it would be lost
from the body.

1. **The line is already a legal name** (`NoteName.validate` returns nothing). It is the title,
   unchanged. The rest of the text is the body, as today.
2. **Otherwise the title is derived.** The steps below repeat until the result stops changing,
   so a cut that exposes a version token or a leading dot is repaired too:
   - replace every character in `NoteName.forbiddenCharacters` with a space, so `3/10` does not
     become `310` and `Idea:usare` does not become `Ideausare`;
   - collapse each run of whitespace to one space and trim;
   - remove leading dots, then trim;
   - remove a trailing version token (`v2`, `_v10`, `-V3`) together with its separator, as
     `NoteName`'s own suffix rule recognises it;
   - if the result is longer than `NoteName.maximumLength` (60), cut it at the last space that
     keeps it within 60, or at 60 characters when a single word is longer.

   The result passes `NoteName.validate`, or it is empty.
3. **When the derived title differs from the line, the whole text goes to the body**, the first
   line included. Nothing the person typed is lost.
4. **When nothing survives step 2**, the title is `YYYYMMDD HHmm Cattura`, in the Mac's calendar
   and time zone at the moment of the capture.
5. **Only an empty capture is refused**, which is today's guard at the top of `VaultAPI.capture`.
   A derived title that is already taken is refused exactly as a typed one is today
   (`CreationError.alreadyExists`, through `ConnectorError`).

`VaultSession.createNote` keeps refusing an invalid title and never sanitises one. Its other
callers (the composer, Quick Open, «Documento», `perg note create`, MCP `create_note`) show or
return the validator's reason before anything is written, and the person fixes it in place.
Capture is the one surface that is fire-and-forget over another application. It is also the one
surface where a refusal costs the moment the text was captured in, so it is the one that derives.

The panel shows the result before sending. `CaptureController` asks the same function and shows
«Titolo: …» under the field, while the destination is «Nota nuova» and the derived title differs
from the typed line. One function means the caption and the file name cannot disagree, with one
named exception: a fallback title computed in one minute and sent in the next shows the earlier
minute.

**D4. The free-text truncation sits beside the slug truncator and does not touch it.**

`ImportNaming.truncatedAtWordBoundary(_:toFit:)` cuts a hyphen-separated slug. It is the one
truncator behind two protected names: `ImportNaming.recordingNoteTitle` and
`PraticaNaming.messageFileName` (ADR-0045). A capture title is space-separated prose.

A new `ImportNaming.truncatedAtSpace(_:toFit:)` cuts at spaces. Generalising the slug truncator
was rejected, because that would change the input path of two protected interfaces to serve a
caller they were never written for. Their existing tests, in `ConventionsNamingTests` and
`PraticaNamingTests`, stay green unmodified.

**D5. The inbox folder is a vault setting, and every place that names the folder reads it.**

- **The setting.** `VaultSettings.inboxFolder` is a vault-relative folder, default `00 Inbox`
  (`VaultSettings.defaultInboxFolder`). A `settings.json` without the key decodes to the default,
  so no vault migrates.
- **Resolved where it is read, never trusted as stored.** `settings.json` is a file a person or
  another tool can edit, so the settings field cannot be the only guard. Resolution:
  - trim it, and refuse it when it starts with `/` (absolute);
  - split it on `/` and trim each component; refuse it when any component is `..`;
  - drop every empty and `.` component, and rejoin the rest with `/`;
  - refuse it when nothing is left, or when `VaultBoundary.url(for:)` throws;
  - on any refusal, use the default.

  The explicit `..` check is needed because `VaultBoundary` accepts `a/../b`: that path collapses
  back inside the vault, but it is not a folder name anyone means.
  One departure from a plain trim: the value is canonicalised component by component rather than
  losing only one trailing `/`. `00 Inbox/`, `./00 Inbox` and `00 Inbox//` name one folder, which
  the scanner reports as `00 Inbox`, so the resolved value takes that one spelling. Otherwise the
  capture would write to a path that compares unequal to the one the index and the sidebar hold
  for the same folder. A space hugging a separator is dropped with the component trim, since no
  one types a folder name that ends in a space on purpose.
- **The places that read it:**
  - the capture default (`folder: nil` writes to the resolved folder);
  - the task inbox file (`<inbox>/Capture.md`);
  - file import's destination;
  - the in-app strings that name the folder;
  - `perg` help and the MCP `capture` schema, which say «la cartella inbox (00 Inbox se non
    impostata)» since they cannot know a vault's setting before one is open.
- **One resolver, no literal left to drift.** The literal `VaultAPI.CaptureDestination.defaultFolder`
  is deleted. So is `TaskDestination.relativePath`, which hid the literal behind a computed
  property. The session answers both questions instead: `VaultSession.inboxFolder`,
  `VaultSession.inboxNotePath` and `VaultSession.relativePath(of:)`. A call site that needs the
  inbox cannot reach a literal by accident. This is ADR-0041 §D1's resolver-not-assert rule
  applied to a path. `TaskDestination.inboxPath` stays as the name of the default path, which a
  vault with no setting resolves to and which many tests read.
- **Changing the setting moves nothing.** An existing `Capture.md` in the old folder stays where it
  is. The new folder's `Capture.md` is created from `inboxTemplate` on first use. A change takes
  effect at the next capture without a relaunch, because nothing caches the resolved folder.

**D6. Where the setting is edited.**

Impostazioni › Convenzioni gains «Cartella inbox» beside «Cartella daily» and «Cartella diario».
It writes through `VaultSession.updateSettings`, the same as its neighbours.

**D7. What this record does not decide.**

The other N1 seams carry no ADR. Each follows a pattern the code already has, and each is cheap
to reverse.

- **`[[` completion** closes `]]` (without doubling one already ahead) and offers aliases. It
  reuses `CardWikilinkCompletion`'s ranking and `IndexSnapshot`'s aliases.
- **Cmd+Shift+D and the event note** switch to the Note pane; «Documento» opens no tab. These are
  pane changes on `CommandActions`, in the shape of `.newNote` and `open(link:)`.
- **Cmd+N** seeds the composer from the sidebar's selection. This is `NoteDraft.folder`, seeded
  only for a fresh draft.
- **Cmd+click on `#tag`, `>date` and `!date`** follows `.editorLink` and
  `MarkdownAttributedText.clickTarget(for:)` (issue #188), then `WindowPlace`'s `.day`
  destination.
- **`spacing.paragraph`** and the H6 face go through tokens (ADR-0002, ADR-0030).

The plan records them, and the SPEC holds their decisions and rejected alternatives.

One reversal is named so nobody "fixes" it back. `CompletingTextView.apply` used to leave `[[Nota`
open on purpose («the `]]` is left for the person to close»), and
`CompletionPanelTests.returnWritesTheCandidateOverExactlyWhatWasTyped` pinned it. SPEC R-07
reverses that choice: completion now writes the `]]`.

## Alternatives considered

- **Keep `status-inbox` on the capture-shaped notes only** (the status quo). Rejected, because it
  is the defect: a topic-less note from six of the seven creation paths SPEC R-01 names fails
  `perg lint` on the day it is born.
- **Add `status-inbox` to the daily note too.** Rejected. The linter's daily exemption already
  covers a daily note, a daily is not an unfiled idea, and every daily note's bytes would change
  for nothing.
- **Let each surface decide by passing `.capture` itself.** Rejected. There are about a dozen
  `createNote` call sites, each able to forget. Issue #30 was exactly this: two places built one
  tag set and drifted. The rule belongs in the function every path already reaches.
- **Recognise a capture by its folder** (anything in the inbox folder is a capture) instead of by
  its tag. Rejected. `TagRules.missingRequired` is written on the opposite principle: a note is a
  capture because of what it declares, not where it sits. A folder rule would give the linter
  path knowledge it does not have. Moving a note out of the inbox would silently change its
  category, and the configurable folder of D5 would make that category depend on a setting.
- **A timestamp title for any long or prose-shaped first line.** Rejected. It needs an arbitrary
  "prose" threshold, and it throws away a title that was useful.
- **A timestamp title always.** Rejected. It is predictable, but useless in a note list.
- **Sanitise inside `VaultSession.createNote` for every path.** Rejected. Every other surface
  shows the validator's reason before it writes. `createNote`'s refusal is what stops a vault from
  filling with titles nobody chose (its own doc comment), and only capture has no moment in which
  to show a reason.
- **Strip forbidden characters without a replacement** (what `NoteName.sanitized` does). Not
  chosen for capture: it joins the words on either side (`3/10` becomes `310`, a different
  number), and the space it would have left is collapsed anyway where one was already there.
- **Generalise `truncatedAtWordBoundary` to take a separator.** Rejected, see D4: it would put two
  protected names behind changed code for a caller they do not serve.
- **Make only the two constants configurable** and leave the strings. Rejected, because the
  strings would lie the first time someone changed the folder.
- **Validate the inbox folder only in the settings field.** Not chosen. `settings.json` is
  hand-editable and read by `perg` and `pergamenum-mcp`, which have no settings field, so the
  resolver at the point of use is the guard. The field could also say when a value falls back;
  that caption is left as a follow-up, not decided here.

## Consequences

**Positive**

- A topic-less note from any surface lints clean on the day it is born, and the app no longer
  writes files its own linter flags.
- A capture never loses its text to a naming rule. The person sees the title it will get before
  sending, and the original line survives in the body.
- One function decides a new note's tags, and one decides a capture's title. The panel, `perg`
  and MCP cannot disagree on either.
- The inbox folder can be renamed, and nothing in the app keeps naming the old one.

**Negative**

- More notes carry `status-inbox`, and nothing takes it off again:
  - a note that later gains a topic keeps `status-inbox` until someone removes it;
  - the linter does not object to the pair, because `.note` allows `status-inbox`;
  - the Inbox pane that would surface and clear these is N4's (`PG-387`, its ADR 0085), not this
    chain's.
- A derived title can surprise. `Idea: usare i token anche per i font?` becomes
  `Idea usare i token anche per i font`. The caption is the mitigation.
- The connectors' observable output changes. A topic-less `create_note` or `perg note create`
  writes and diffs one more tag line, and the capture schema's wording changes.
- `CaptureTests.aTitleTheConventionsRefuseStopsTheCaptureInsteadOfBeingCorrected` and two byte
  pins in `NoteTemplateTests` assert the old behaviour and are rewritten, not deleted. The plan
  lists them.

**Neutral**

- No schema, index, format or protected-interface change.
- The harness `tag.md` wording on the lint-equivalent exemption is not touched. The harness repo
  is the source of truth for conventions (principle 5), and the SPEC leaves it out of scope.

## References

- `docs/specs/note-workflow-n1-seams.spec.md` (SPEC, R-01 to R-06, R-16, R-17, R-20);
  `docs/plans/pg-384-n1-seams.md`; `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N1; `PG-384`.
- ADR-0008 §D4 and §D6 (extended); ADR-0007 §D2 (connector parity); ADR-0041 §D1 (a resolver, not
  a skippable step); ADR-0043 §D8 and ADR-0057 §D3 (the one write door, unchanged); ADR-0045
  (the slug truncator's two callers).
- App SPEC `docs/20260811_Pergamenum_SpecApp.md` §4.3, §4.4, §12 and §16; harness `tag.md` 5.1;
  frontmatter.md 6.2.
- Code: `Sources/Core/Conventions/Tag.swift` (`initialTags`, `missingRequired`, `NoteCategory`),
  `Sources/Core/Conventions/NoteName.swift`, `Sources/Core/Conventions/ImportNaming.swift`,
  `Sources/Connector/VaultCapture.swift`, `Sources/Vault/VaultSession+Notes.swift`,
  `Sources/Vault/VaultSession+Tasks.swift`, `Sources/Vault/VaultSettings.swift`,
  `Sources/Core/Vault/VaultBoundary.swift`.
