# ADR-0011: Templates are notes in a folder; version history is a new store, not WriteJournal

- Status: accepted
- Date: 2026-08-18, accepted 2026-08-18 after an interview with Stefano. The four points put
  to him were the motivation for history over git/Time Machine, snapshot granularity, where
  the store lives, and how a template is applied; all four were accepted as written below.
- Supersedes: nothing.
- Depends on: nothing. Read alongside ADR-0007 §D6, which is the decision this one is
  deliberately not extending (see D1).

## Context

M9 (`PG-010`, `docs/20260816_Pergamenum_Roadmap.md`) asks for two things under one milestone:
templates as real notes, and local version snapshots. They share nothing structurally - one is
about how a note starts, the other about what happens after every save - but they share a
constraint worth stating once: neither has a line in `docs/20260811_Pergamenum_SpecApp.md`.
§13's table stops at M6, and M7 and M8 shipped the same way, with the amendment tracked as
debt in `PG-015` rather than written first. This ADR follows that precedent rather than the
letter of the working agreement in CLAUDE.md: the SPEC gains §16bis and §17bis after this
ships, filed onto `PG-015` alongside the six sections already waiting there.

**Version history was the one with an existing wrong answer to correct.** `WriteJournal`
(`Sources/Vault/WriteJournal.swift`) already keeps "the text that was there before" every
write, and its own doc comment says, in as many words, that it is *not* a version history -
"the vault's own history is git, or Time Machine, or the fact that these are plain files." It
is also scoped to connector writes only: `VaultSession.journal` is nil for the app,
"which is the point: a person editing their own note in their own editor does not need an
undo log beside the file" (`VaultSession.swift:116-118`). Reopening that decision needed a
reason, and the interview supplied one directly: Stefano wants the kind of per-note restore
Bear or iA Writer offer, browsable inside the app, that does not need the vault to be a git
repository. That is a different job from a connector's safety net, not a bigger version of it.

**Where the open note actually saves matters more than it looks like it would.** The editor is
not autosaving per keystroke: `VaultController.saveOpenNote()` is the one place the app writes
the currently-open note, and it fires only from the explicit `.save` command
(`CommandActions.swift:98-99`) or the toolbar button, guarded by `note.hasUnsavedChanges`. A
snapshot taken there is a snapshot of a deliberate save, not a keystroke - the natural unit
this feature wants, with no debounce to invent.

**Where a hook belongs, if not `saveOpenNote()`.** `VaultSession.write(_:to:)` is the one write
every change goes through, per CLAUDE.md's own description of the type - the editor's save,
`createNote`, the CLI and the MCP server all end there. A hook placed at `saveOpenNote()` alone
would miss every note a connector writes, which is exactly the audience most likely to want a
"what did that change" browsable after the fact, since nobody was watching it happen.

**Why templates avoid the tag question entirely.** SPEC §4.4's tag namespace is closed and
harness-owned: `client-`, `competitor-`, `project-`, `type-`, `topic-`, `status-`, `area-`,
`source-`, and "the harness-system repo is the single source of truth: when a convention
changes, the app config is updated, never the other way round" (CLAUDE.md). A tag-based
"this note is a template" marker (`type-template`) would mean asking the harness repo to grow
a value it does not have, for a convention that is this app's alone. A dedicated `Templates/`
folder needs no vocabulary change at all - it is a location, the same kind of fact
`NoteFolding`'s heading rule or `IndexSnapshot` already read off a note without touching tags.

## Decision

**D1. Version history is a new store, `NoteHistory`, not an extension of `WriteJournal`.**

Two safety nets for two different failures, kept apart rather than merged: `WriteJournal`
answers "what did the AI just do to my file", scoped to connector writes, with `undo` refusing
if the file moved on since (ADR-0007 §D6, unchanged by this decision). `NoteHistory` answers
"show me this note five saves ago", and is what a person browses. Merging them would mean
teaching one type two audiences and two refusal rules; `WriteJournal`'s own doc comment already
disclaims the job this ADR is giving to something else.

**D2. `NoteHistory` hooks `VaultSession.write(_:to:)`, unconditionally, scoped to `.md` paths.**

Not gated behind `journal != nil` the way the connector safety net is - every write to a note,
app or connector, gets a snapshot, because the choke point that makes `VaultSession.write` "the
single write every change goes through" is exactly what makes it the right place to keep this
symmetric rather than re-deriving "was this a note write worth remembering" at each of
`saveOpenNote`, `createNote`, the CLI and the MCP server separately. Non-`.md` writes (canvas
files, settings) are out of scope for this milestone; nothing in the design forecloses adding
them later at the same hook.

Recorded **after** the write succeeds and the index is updated, mirroring the "files first,
index second, journal third" order `write(_:to:)` already keeps (ADR-0001 §D2.3) - a snapshot
of a write that did not happen would be worse than no snapshot.

**D3. One file per snapshot, laid out under `.pergamenum/history/` mirroring the vault's own
paths.**

`.pergamenum/history/<relativePath>/<ISO-timestamp>.md` - full text, not a diff. Text notes are
small and `WriteJournal` already made the same call (`textBefore` is a full copy, not a patch),
for the same reason: a diff engine is a second thing to get right for a store whose job is to
be trustworthy, not compact. The directory mirrors the note's own path rather than a hash of
it, so a person looking at `.pergamenum/history/` on disk can find a note's history by eye -
debuggability the connector journal's single JSONL file does not need but this one benefits
from, since a person is the actual reader here.

**A rename orphans its history.** `NoteFileOperations` does not go through `VaultSession.write`
(`PG-005`), so a rename or move is invisible to this hook exactly as it is invisible to the
watcher's own reconciliation. Named rather than silently accepted: fixing it is `PG-005`'s job,
not this ADR's, and `WriteJournal` has carried the identical gap since ADR-0007 without it
being a defect in that design either.

**D4. Thinning keeps every snapshot from the last 24 hours, and at most one per calendar day
before that. No expiry.**

Applied after each new snapshot is written, over that note's own directory only. The 24-hour
window is where "five saves ago" from D1's own framing actually lives; a day-old note that was
saved forty times in an afternoon does not need forty rows a week later, one per day of its
older life is what a person restoring "the version from last Tuesday" is actually asking for.
No expiry, unlike Time Machine's own eventual pruning: these are text files, not photo
libraries, and disk cost stays negligible even for a vault edited daily for years. If that
stops being true it is a later ADR's problem to reopen, not this one's to solve pre-emptively.

**D5. A template is a note under `Templates/` at the vault root. Nothing marks it as a
template beyond the folder it is in.**

`Templates/` is reserved the way `VaultLayout.privateDirectory` already reserves `.pergamenum/`
- a location the app knows, not a tag or a frontmatter key. A note inside it opens, edits and
saves exactly like any other note (`PG-010`'s own framing, "templates as real notes"), and gets
a `NoteHistory` too, with no special-casing at the write hook: D2's scope is "any `.md` path",
and a template's path is one.

**D6. Applying a template happens at note-creation time, offered alongside naming the note.**

The creation flow (`VaultController.beginNewNote` / the composer it opens) grows a "da
template..." choice listing the notes found in `Templates/`. Choosing one reads that template's
body - everything after its own frontmatter block, which is discarded rather than copied, since
the new note gets its own conformant four-key block from `createNote` exactly as it does today
- and writes it as the new note's content. A template applied after the fact, to a note that
already has content, is not this decision: SPEC's closed frontmatter schema and `createNote`'s
existing refusal to silently overwrite already draw that line, and reopening it needs its own
reason.

**D7. Two placeholders, `{{date}}` and `{{title}}`, substituted at application time. Nothing
else in v1.**

Both are values `createNote` already computes for every new note regardless of a template -
the date going into the frontmatter block, the title the user is typing in the composer - so
supporting them costs nothing beyond passing what the creation flow already has into the
substitution. A wider placeholder set was offered and declined in the interview; extending the
two is a smaller decision than choosing the mechanism was, and does not need this ADR reopened
to make.

## Consequences

- **`NoteHistory` is the third disposable-but-not-rebuildable store under `.pergamenum/`**,
  after `cache.db` (which *is* rebuildable, the difference this ADR keeps straight) and
  `WriteJournal`'s `ai-journal/journal.jsonl`. Losing `.pergamenum/history/` loses the old
  versions and nothing else - the current note is unaffected, same guarantee `WriteJournal`
  already carries for its own directory.
- **Both halves need a mockup before implementation** (SPEC §11.1, the rule this project has
  followed for every new visual element since the find bar): the "da template..." choice in
  the creation flow, and whatever surface lets a person browse and restore a note's history.
  Neither design is decided by this ADR - it decides the data model and the hook points, not
  the screen.
- **The SPEC amendment is debt, filed on `PG-015`** as §16bis (Template) and §17bis (Cronologia
  versioni), per the precedent this ADR follows rather than reopens (see Context).
- **`Templates/` is a new reserved name at the vault root**, the same category of fact as
  `.pergamenum/` itself. A vault that already has an ordinary folder called `Templates/` before
  upgrading would have its contents reinterpreted; worth a line in the release notes, not a
  migration - nothing is deleted or rewritten, the folder simply starts being read by the
  template picker.
- **Restore is not designed here.** Reading a snapshot back and either previewing it or writing
  it over the live note is plan-level work with its own small decision (does restoring itself
  create a new snapshot of what it replaced? - yes, by D2's own rule, for free, since restore is
  just another `VaultSession.write`) but no open architectural question this ADR needs to
  settle first.
- **Connector exposure is out of scope for this slice.** `perg` and `pergamenum-mcp` gain no
  new command here; a `note history` / `note restore` pair is a natural `Sources/Connector/`
  addition later, and CLAUDE.md's rule that a capability lives there once is unaffected by
  deferring when it arrives.
