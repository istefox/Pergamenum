Status: Approved (2026-10-04)

# SPEC — N1 Seams of the note workflow (PG-384)

## Destination

A SPEC handed to `/workplan`, built in about two `/build` sessions and shipped as one or two PRs.
Closes the ledger entry `PG-384` minus its task 8 (`PG-219`, the cursor, stays its own ticket).
Source: `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N1, tasks 1-7 and 9. Facts re-read on
`origin/main` @ `6c03f024` on 2026-10-04: none of the eight tasks is done, no file named by the roadmap
was renamed, and four claims in the roadmap needed correcting (see Decisions).

## Objectives

- A note born without a topic is never silently non-conformant. Today `perg lint` fails on a note made
  with Cmd+N, Quick Open create, the Workspace «Documento» sheet, `perg note create` or the MCP create
  tool, because only the capture path ever writes `status-inbox`.
- A capture whose first line is not a legal note name produces a note with a proposed title instead of
  a refusal.
- Six small seams in the daily flow close: `[[` completion leaves `]]` open and hides aliases,
  Cmd+Shift+D and the event note do not show the note they open, Cmd+N ignores the selected folder,
  `#tag` and `>date` are not clickable, there is no paragraph spacing token and H5/H6 look identical.
- The inbox folder stops being a literal, and the SPEC stops disagreeing with the shortcuts the app has
  already shipped.

## Scope and non-goals

In: roadmap N1 tasks 1-7 and 9, ADR 0080, the SPEC amendments the roadmap §4 names for N1.
Out: `PG-219` (task 8), the hover preview and every other N2-N5 item, a template choice at birth, an
Inbox pane. Detail under Out of scope.

## Decisions

- **Scope is tasks 1-7 and 9, one SPEC** — they share one acceptance scenario and no task depends on
  another. Rejected: tasks 1-2 only (leaves four visible seams for a second interview); tasks 1-6 and 9
  without the token (the token is a one-line decision, see below, and needs no separate design pass).
- **A note born with no `topic-*` is a capture and carries `status-inbox`, on every creation path.** The
  daily note is the only exception. `type-note` plus a topic stays exactly as today. Rejected: keep
  `status-inbox` on the capture path only (the status quo, and the defect); add it to the daily note
  (the linter's daily exemption already covers it and a daily is not an unfiled idea).
- **Premise correction: the `status-inbox` promise is not in ADR-0008 §D6.** §D6 is about the four
  capture destinations and the real file `Capture.md`; the promise lives in SPEC §4.3 and §4.4 and in
  the harness `tag.md` 5.1, and SPEC §4.2 is file naming with no capture wording. ADR 0080 therefore
  extends ADR-0008 and amends SPEC §4.3 and §16, not §4.2. The roadmap and the ledger entry say
  otherwise; this SPEC wins, and the ledger wording is corrected when the chain closes.
- **A non-conformant first line yields a derived title: strip the characters a name forbids, trim,
  truncate to about 60 characters at a word boundary.** When the derived title differs from the typed
  line the whole text goes to the body, so nothing the person typed is lost; when it is the same, the
  rest of the text is the body as today. If nothing survives the stripping the title is
  `YYYYMMDD HHmm Cattura`. Only an empty capture is refused. Rejected: timestamp title for any long or
  prose-shaped line (needs an arbitrary "prose" threshold and loses a useful title); timestamp title
  always (predictable but useless in a note list).
- **The event note opens in the Note pane; the Workspace «Documento» opens no tab.** The event note
  behaves like Cmd+N and Cmd+Shift+D. «Documento» creates the note and its card and stays on the board:
  the card is the visible result, and today's tab lands in a Note column the person cannot see. Rejected:
  both go to the Note pane (the board vanishes at every «Documento»); a confirmation with «Apri» (the
  sheet closes before the write ends, so it needs new UI for no gain).
- **`spacing.paragraph` is 8 pt in both themes**, applied to prose paragraphs only, and Stefano
  verifies it by eye on the Debug build, the precedent of ADR-0076 and ADR-0079. Rejected: a two-variant
  mockup before any code (an extra round for one number that is cheap to change).
- **`inboxFolder` reaches every place that names the folder:** the capture default, the task inbox file,
  file import, and the in-app strings. Default `00 Inbox`, so there is no migration. Rejected: only the
  two constants (the strings would lie the first time someone changes it).
- **Links and dates open on Cmd+click, the same gate as a wikilink.** A plain click keeps placing the
  caret. Rejected: plain click (fights editing).

## Constraints

- **The file never changes shape** — origin: roadmap §0 and `CLAUDE.md` principle 4. Note frontmatter
  stays `date`, `tags`, `related`, `aliases`; tags stay flat and namespaced.
- **Tokens only** — origin: `CLAUDE.md` design system. `spacing.paragraph` is a key in both theme files,
  declared with the other keys, read through `Theme`.
- **One write door** — origin: ADR-0043 §D8, ADR-0057 §D3. Any new creation or edit goes through
  `VaultSession.write` with `expecting:`/`expectingAbsent:`.
- **Connector parity** — origin: ADR-0007. Anything the connectors should have lives in the shared
  connector layer; the shared sources stay free of SwiftUI so `perg` and `pergamenum-mcp` build.
- **Protected interfaces untouched** — origin: `.claude/protected-interfaces`.
  `ImportNaming.recordingNoteTitle` and `VaultBoundary.url(for:)` keep their behaviour; the free-text
  title truncation must not fork or alter the slug truncator behind the first.
- **Zero GUI tests** — origin: the merge-gate rule in `CLAUDE.md`. Acceptance is the hand check.
- **UI strings in Italian, code and commits in English** — origin: `CLAUDE.md`.
- **Fixed-by-user: the three N1 seams that touch navigation behave as the interview decided** — origin:
  user mandate in this interview (event note to Note pane, no «Documento» tab, 8 pt).

## Stack

Swift 6, SwiftUI with an AppKit text editor and canvas, Swift Testing. No new dependency.

## Data model

One new setting, `inboxFolder`: a vault-relative folder, default `00 Inbox`, absent key reads as the
default. One new token, `spacing.paragraph`. A tag-filter request and a day request, both transient
navigation state: nothing is persisted and no cache schema changes. No frontmatter key and no tag
vocabulary change; `status-inbox` already exists in the vocabulary.

## API / interfaces

- The tag-initialisation rule takes the category and the topics: a topic-less note is a capture, a daily
  is not. Both connectors inherit it, so the MCP dry-run diff of a topic-less create now shows the tag.
- The capture entry point derives a title instead of failing, and exposes the derived title so the panel
  can show it before the capture is sent.
- The wikilink completion candidate carries the alias that matched, if any; the text it inserts is
  always the title.
- Two new open requests on the command layer: open the Tags pane narrowed to one tag, open the Today
  pane on one day (the history place that already does it).

## UI flows

- Capture panel, destination «Nota nuova»: while typing, a caption «Titolo: …» under the field shows the
  derived title when it differs from the typed line.
- Editor: `[[Tras` + Return gives `[[Trasmissibilità e rapporto di frequenza]]`, caret after `]]`. A row
  matched through an alias reads «Titolo · alias: X».
- Cmd+Shift+D from any pane except Oggi shows today's note in the Note pane. An event note opens in the
  Note pane.
- Cmd+N opens the composer already pointed at the sidebar's folder.
- Cmd+click on `#client-acme` opens Tags narrowed to it; on `>2026-10-12` opens Oggi on that day.
- Impostazioni › Convenzioni gains an inbox folder field beside the daily and diary ones.
- Quick Open create and the Workspace «Documento» sheet report a failed creation where the person is,
  as the Cmd+N composer already does.

## Edge cases

- A capture first line that is a legal name is left untouched; a leading dot, a version-style suffix or
  outer whitespace count as illegal and are repaired, as the name validator defines them.
- A derived title that is already taken is handled exactly as a typed one is today.
- Cmd+N with a parked draft keeps that draft's folder; the selection seeds only a fresh draft. A selected
  note seeds its parent folder; no selection seeds the vault root.
- Cmd+Shift+D from Oggi does not switch pane. A daily note that does not exist is created as today.
- A tag click with an active Tags filter replaces it rather than adding to it.
- `>2026-02-31` is not a date: it is not clickable. `@done(...)`, `@remind(...)` and `@repeat(...)` are
  not clickable.
- A `]]` already ahead of the caret is not doubled; the caret moves past it.
- The `#` completion stack-overflow guard stays green.
- `inboxFolder` empty, absolute, containing `..` or resolving outside the vault is refused by the
  boundary resolver and the default is used. Changing it moves nothing: an existing `Capture.md` in the
  old folder stays, and the new one is created on first use.
- The event note, the scheda and the inbox task note already carry `status-inbox` and their bytes do not
  change. The Plaud transcript and the Nuova pratica wizard build their own tag lists and are not touched.

## Test seams

Everything in-process under `PergamenumTests`, no GUI test. The highest seam each criterion allows:

- the tag-initialisation rule, pure, one case per category, plus the creation paths through
  `VaultSession` and the connector;
- title derivation as a pure function in the shared sources, plus the capture entry point and the
  panel's controller for the caption;
- completion through the candidate function and the real text view, in the existing completion suites;
- pane changes, tag and day opens through hosted `CommandActions` tests; Cmd+N through the note-list
  editing tests;
- the token and the heading faces through the typography and theme-decode tests;
- the setting through a decode test (key absent gives `00 Inbox`) in the shape of the Pratiche settings
  test.

Hand check by Stefano is the acceptance for R-22.

## Success criteria

- [ ] R-01 — A note created with no `topic-*` has `type-note` and `status-inbox` on every creation path:
  Cmd+N composer, Quick Open create, Workspace «Documento», capture «Nota nuova», `perg note create`,
  the MCP create tool, Pratiche create-and-link without topics. Given a topic, it has no `status-inbox`.
  One test per tag category pins the rule.
- [ ] R-02 — The daily note, the event note, the scheda and the inbox task note are byte-identical to
  today. `perg lint` reports nothing on a topic-less note created by any path in R-01, and the MCP
  dry-run diff of such a create shows the added tag.
- [ ] R-03 — Capture «Nota nuova» with a first line the name validator rejects creates a note titled by
  the derived title (stripped, trimmed, at most about 60 characters, cut at a word boundary). When the
  derived title differs from the typed line the whole text is in the body; when it does not, behaviour
  is as today.
- [ ] R-04 — A first line that strips to nothing gives the title `YYYYMMDD HHmm Cattura`. Only an empty
  capture is refused.
- [ ] R-05 — The capture panel shows «Titolo: …» live under the field when the derived title differs
  from the typed first line, and nothing otherwise.
- [ ] R-06 — The free-text truncation does not change the output of `ImportNaming.recordingNoteTitle`
  (its existing tests stay green unmodified).
- [ ] R-07 — Applying a `[[` completion in the editor inserts the title and `]]` and leaves the caret
  after it; with `]]` already ahead it inserts the title only and moves the caret past the existing `]]`.
  The Workspace card behaves the same.
- [ ] R-08 — A note whose alias matches the typed text is offered, labelled «Titolo · alias: X», and
  inserts its title. A note matched by title is labelled as today.
- [ ] R-09 — Cmd+Shift+D switches to the Note pane and shows today's note from every pane except Oggi,
  where the pane does not change.
- [ ] R-10 — Creating an event note switches to the Note pane and shows it. Creating a Workspace
  «Documento» creates the note and its card, opens no tab and leaves the pane on the board.
- [ ] R-11 — Cmd+N opens the composer with the folder of the sidebar selection (a folder gives itself, a
  note its parent, nothing gives the root), from any pane; the folder stays editable; a parked draft
  keeps its own; «Nuova nota qui» is unchanged.
- [ ] R-12 — Cmd+click on a `#tag` in the editor or a Workspace card opens the Tags pane narrowed to
  exactly that tag, replacing any filter. Without Cmd the click places the caret as today.
- [ ] R-13 — Cmd+click on a valid `>YYYY-MM-DD` or `!YYYY-MM-DD` opens the Oggi pane on that day. An
  impossible date, and any `@` annotation, is not a click target.
- [ ] R-14 — `spacing.paragraph` is 8 pt in the light and the dark theme, declared with the other
  spacing keys and read through `Theme`; it is applied after prose paragraphs only, not lists, quotes,
  code or tables. The list-indent invariant test stays green.
- [ ] R-15 — H6 is drawn at regular weight in the secondary text colour; H5 stays bold in the primary
  colour; H1-H4 are unchanged.
- [ ] R-16 — `inboxFolder` exists in the vault settings with default `00 Inbox`; a settings file without
  the key decodes to the default. The capture default, the task inbox file, file import and the in-app
  strings that name the folder read it; CLI and MCP help say «the inbox folder (00 Inbox by default)».
  A value the boundary resolver refuses falls back to the default.
- [ ] R-17 — Impostazioni › Convenzioni shows the inbox folder field and a change takes effect for the
  next capture without relaunch.
- [ ] R-18 — A failed creation from Quick Open is shown inside the switcher, which stays open; one from
  the Workspace «Documento» sheet is shown in the sheet, which stays open until the write succeeds.
- [ ] R-19 — SPEC §8.1 and §10 say Cmd+Shift+D opens the daily note, Cmd+Shift+B creates a board, and
  Cmd+T is a new tab, with no «Oggi (Cmd+T)». (no-test: documentation, checked against the shortcut
  catalogue by reading)
- [ ] R-20 — SPEC §4.3 says any note without a topic is a capture carrying `status-inbox`, and §16 says
  a non-conformant first line yields a proposed title and only an empty capture is refused. ADR 0080
  is written, extends ADR-0008, and its Chain decision index line is added to `CLAUDE.md`.
  (no-test: documentation only, ADR and SPEC text checked by reading)
- [ ] R-21 — The four doc comments that say the daily note is created «from the template» (including the
  one that says it opens with Cmd+T) state what the code does. (no-test: comment text only, checked by reading the diff)
- [ ] R-22 — Acceptance by hand: from Safari, Ctrl+Opt+Space, `Idea: usare i token anche per i font?`,
  Return, leaves `Idea usare i token anche per i font.md` in the inbox folder with `type-note` and
  `status-inbox`, and `perg lint` reports nothing. `[[Tras` + Return completes as in R-07. From
  Attività, Cmd+Shift+D shows today's note. Cmd+click on `#client-acme` opens Tags narrowed to it.
  (no-test: manual verification by hand on the Debug build)

## Not yet specified

_none_

## Out of scope

- `PG-219` (the pointer cursor): own ticket and own ADR. It lands before N3's hover preview, so the
  pointing hand over a link or a tag is not part of this SPEC: the Cmd+click works, the hand waits.
- The remaining N2-N5 work: gutter reveal, the hover preview, the Inbox pane, template choice at birth,
  the new constructs.
- Inline errors for Cmd+Shift+D and the other `recordProblem` call sites: only the two surfaces named in
  the roadmap are in. Reason: the others are not part of the creation seams.
- Fixing the lint-equivalent exemption wording in the harness `tag.md`: the harness repo is the source
  of truth for conventions and is not touched from here.

## Domain terms

- **Capture** — a note that carries `status-inbox` and no `topic-*`: an idea not yet filed. After this
  SPEC it is also what any topic-less new note is, whichever surface made it.
