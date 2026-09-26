Status: Approved (2026-09-26)

# SPEC — Connector input hardening: malformed numbers, the flag parser, board creation through the dry-run lock, boundary defence in depth

## Destination

A SPEC handed to `/workplan`. Closes issue #570 (Audit Fable chain 3, promoted from `PG-256`)
in one PR: the two connectors stop trusting the shape of what they receive, the one connector
write that bypassed the dry-run lock goes through a session door, and five disk-touching sites
resolve their paths only through the vault boundary resolver. The same PR closes `PG-151` by
adding that resolver to the protected-interfaces registry.

## Objectives

- A malformed number handed to `perg` or to the MCP server produces one sentence, never a dead
  process and never a silently substituted default. Today `perg journal log --limit -1` kills
  the CLI and a `resources/list` cursor of `-1` kills the MCP server mid-session.
- A mistyped `--dry-run` can never become a real write. Today `--folder --dry-run` writes into
  a folder named `--dry-run`, and `--dry-run=true` writes for real too.
- Every write a connector performs honours the dry-run lock and lands in the journal, board
  creation included. Today «create and link a board» writes the `.canvas` even when the MCP
  `dryRun` default (`true`) is in force, and the journal never hears of it.
- The five disk-touching sites the audit named resolve caller-derived paths only through the
  vault boundary resolver, and that resolver becomes a protected interface so its signature
  cannot drift silently.

## Scope and non-goals

In: the two connector reads that take a `limit` (journal log, search); the MCP resources
listing's `cursor`; the hand-written argument parser both connectors share; a board-creation
door on the vault session and its adoption by the connector's «create and link a board» verb;
the rehearsal summary of the three «create and link» verbs; the five named boundary sites; the
protected-interfaces registry line.

Out (detail in *Out of scope*): the app's own board-creation call sites; a full sweep of every
path-building site in the repository; extending undo to delete a created file; an upper bound on
`limit`; the CLI help text; the other fifteen chains of the audit.

## Decisions

- **A malformed `limit` is refused, not clamped and not defaulted.** A limit that is negative, or
  given as text that does not read as an integer, is a usage error carrying one sentence. The
  rule lives in the shared connector layer so `perg` and the MCP server say the same thing; each
  front end's reader refuses unreadable text instead of quietly falling back to the default. It
  applies to both reads that take a limit, search included, even though search today only
  answers empty rather than crashing: a silent empty answer to `--limit -1` is the same class of
  trap. `0` stays legal and answers empty. A number with a fractional part keeps the MCP reader's
  existing leniency (truncated), because it says something; text that says nothing does not.
  Rejected: clamp to `0` — it hides the caller's mistake, and the caller here is a script or a
  model whose bug the sentence is for. Rejected: the issue's literal scope (journal log only) —
  search's silent empty answer is the same defect with a quieter symptom.
- **A malformed `cursor` is a JSON-RPC invalid-params error.** A cursor that is negative or not a
  number is refused; the MCP specification says an invalid cursor should be an invalid-params
  error, and today a non-numeric cursor silently restarts the listing at page zero, so a client
  that mis-echoes a cursor once loops on the first page forever. A cursor past the end keeps
  answering an empty page, as today. Rejected: clamp to page zero — same silent-restart shape.
- **The flag parser refuses three shapes, not one.** A token starting with `--` is never an
  option's value: an option followed by one is a missing value. A `--name=value` spelling of a
  boolean flag is refused («the flag takes no value»): otherwise `--dry-run=true` lands among the
  options, the flag test fails, and the write is real — the same trap through the other door. A
  bare `--` is refused as unrecognised syntax instead of consuming the next token. A value that
  legitimately starts with `--` is written `--option=--value`, which the parser already accepts;
  a value starting with a single `-` (a negative number) is still a value, so `--limit -1`
  parses and is then refused by the limit rule, not by the parser. Rejected: the issue's single
  case — the `=` form of the safety flag is the same mistake one keystroke away. Rejected: a new
  help line for the `=` form — the form already works and nobody has reached that corner.
- **Board creation gets a session door modelled on note creation.** The vault session gains a
  «create board» door taking the board's name and parent folder, which validates, refuses a
  taken name, and writes an empty canvas through the session's existing file-write door for
  `.canvas` bytes. That door already honours the dry-run switch, records a journal entry and
  keeps the index out of it. The board's file path has one spelling, shared with the canvas
  store's own creation, never a second. The connector's «create and link a board» adopts the
  door; its rescan after a real creation stays, and a rehearsal rescans nothing. Undo of the
  entry is declined with the existing «that write created the file» sentence — the journal
  never deletes, and the note-creation precedent and its test say so. Rejected: teaching undo to
  delete a created board — deleting a file on a model's say-so is what that sentence exists to
  refuse. Rejected: teaching the canvas store about the session — it inverts the dependency;
  the store stays a pure file layer.
- **A rehearsal names the file it would create.** The write summary of each of the three
  «create and link» verbs (a pratica's note, a pratica's board, a message's note) carries in its
  existing `note` field the file the verb creates, on rehearsal and on a real run alike. Today
  the summary is the link's diff only, so a rehearsal of a two-write verb shows one write. No
  new JSON key: `note` already exists on the summary. Rejected: leave the summary as it is — a
  rehearsal that hides one of two writes is weaker than the promise the server makes in its own
  description («the first call returns the diff»).
- **The app's board-creation call sites stay as they are.** The app arms no journal and no
  dry-run switch, so routing its two direct canvas-store creations through the new door buys no
  guarantee and turns synchronous UI closures into an async cascade. Rejected: one spelling
  everywhere — measured against the cost the last async cascade had (ADR-0043's implementation
  notes), the cost is not paid for a guarantee the app does not use.
- **Five boundary sites, not thirty-eight, and the resolver becomes protected.** The five sites
  the audit named (drop-import beside a note, canvas-store folder creation, folder rename and
  folder trash, the pratica timeline directory, attachment existence probing) resolve through the
  boundary resolver. A count made during this interview found thirty-eight other path-building
  sites across twenty-five files that do not; they are named in *Out of scope* and filed as a
  follow-up at ship time, untouched here. The protected-interfaces registry gains the resolver
  entry `PG-151` has waited on since 2026-09-13; the operator decision it asked for is taken here.
  Rejected: the full sweep — twenty-five files of review for a chain the audit sized at one
  afternoon, all of them gated upstream today. Rejected: five sites without the registry line —
  the whole item rests on the resolver being the only door, and a protected line is what keeps
  it one.

## Constraints

- **A connector capability lives in the shared connector layer, not in a front end** — origin:
  CLAUDE.md «AI connector». A check implemented in the CLI is a check the MCP server lacks.
- **Every file under the shared-sources globs compiles into both command-line tools** — origin:
  ADR-0001 §D1 / ADR-0007. Nothing new there may import SwiftUI; the board door lives on the
  session, which is already shared.
- **The journal never deletes a file** — origin: existing decision, pinned by the connector
  test that declines undoing a creation.
- **Write-summary JSON shape is unchanged; the two protected payload shapes (lint finding,
  pratica summary) are untouched** — origin: `.claude/protected-interfaces` (ADR-0053).
- **The boundary resolver refuses the vault root itself** — origin: ADR-0041 §D1. A site that
  needs a directory URL resolves a path inside the directory, or the directory's own relative
  path when it is never empty; none of the five sites hands it the root.
- **Attachment resolution sits on the editor's path** — origin: the embed cache keyed by note
  path and target. Resolving through the boundary there must not add a symlink resolution per
  keystroke; how the boundary reaches that pure helper is the plan's call under this constraint.
- **The MCP protocol layer has no unit tests** — origin: CLAUDE.md «AI connector». Its
  acceptance runs through the smoke script over a real server, which already fails the run when
  the server stops answering.
- **Merge gate is the unit suite plus in-process tests; zero GUI tests** — origin: CLAUDE.md
  working agreements. Nothing in this chain is visible in the app's interface.
- **A precondition before an `await` is a filter, not a guard** — origin: CLAUDE.md working
  agreements / ADR-0043 §D7. The board door's taken-name check runs on the same side of the
  suspension as the write it protects, or the write door's own refusal is what decides.

## Stack

Swift 6, the existing `perg` and `pergamenum-mcp` command-line targets, the Swift Testing suite,
the Python smoke script that drives the MCP server over stdio. Nothing new.

## Data model

None. No on-disk format, no frontmatter key, no index schema change. `IndexCache.schemaVersion`
stays 4.

## API / interfaces

- **Journal log and search reads**: a `limit` that is not a non-negative integer is refused with
  a usage error; the sentence is the same on both connectors. `0` answers empty.
- **MCP `resources/list`**: a `cursor` that is not a non-negative integer answers a JSON-RPC
  invalid-params error; the server keeps answering afterwards. Past-the-end answers an empty page.
- **Argument parser**: three new refusals (option value starting with `--`; `=`-valued boolean
  flag; bare `--`), two existing behaviours pinned (`--option=--value` as the escape hatch;
  `-1` as an ordinary value).
- **Vault session**: a board-creation door (name, parent folder) returning the board's relative
  path; refuses a taken name; dry-run and journal semantics identical to note creation.
- **Connector «create and link» verbs**: summaries carry the created file in `note`; the board
  verb writes through the session door.
- **Protected-interfaces registry**: one new line for the boundary resolver.

## Edge cases

- `limit` given as `-1`, `"abc"`, `""`: refused. Given as `0`: legal, empty. Given as `3.7` on
  MCP: `3`, the reader's existing leniency for a number.
- `cursor` given as `"-1"` or `"abc"`: JSON-RPC error, session continues. Given as a number past
  the last note: empty page, no `nextCursor`.
- `--folder --dry-run`: missing value for `--folder`, nothing written. `--dry-run=true`,
  `--json=1`: «takes no value». `--`: unrecognised syntax. `--title=--strange`: title is
  `--strange`. `--limit -1`: parses, then the limit rule refuses it.
- Board name already taken: refused before any write, on a rehearsal too — a rehearsal that
  says it would create a board that exists would be false.
- Board rehearsal: no `.canvas` on disk, no journal entry, no rescan, `applied` false, `note`
  names the file. Real run: file exists, link written, journal entry under the verb's command
  label; undoing that entry is declined and the file stays.
- Drop-import beside a note whose path escapes the vault: refused, a problem is recorded,
  nothing lands outside. Today the copy lands outside.
- Canvas-store folder creation with a name that escapes: refused at the store, not only by the
  folder-verb layer above it.
- Folder rename or trash on a directory path that escapes the vault (a sibling directory of the
  vault root exists and is named with `..`): refused, nothing moved or trashed. Today the
  normalisation only trims slashes, so the path reaches the move.
- Attachment resolution beside a note path that escapes: no result, no probe outside the vault.
  Today it can return a relative path pointing outside.
- Pratica timeline directory: the folder comes from the index, so no escaping input can reach
  it; the resolution is adopted for consistency and cannot be exercised by a test.

## Test seams

Five seams, four of them existing, confirmed in the interview:

1. **Connector-layer unit tests** (the existing connector test file): limit refusals on journal
   log and search, `0` answering empty.
2. **The MCP smoke script** (existing, the protocol layer's only seam): cursor refusals with the
   server still answering, limit refusal on the journal tool, limit as text refused. The harness
   already fails the run when the server dies, which is the crash assertion.
3. **A new pure unit test file for the argument parser**: the three refusals and the two pinned
   behaviours. No seam existed; a pure parser is the cheapest possible new one.
4. **The existing pratiche-links connector tests**: board rehearsal, board real run with journal
   entry and declined undo, the three summaries' `note`.
5. **The existing canvas-store and folder-operation tests**: escaping inputs at folder creation,
   folder rename, folder trash; the session's drop-import and the attachment resolver are driven
   directly in the same files or their nearest existing sibling. The pratica timeline site is
   review-only.

The `perg` front end has no harness; what it alone does (turning `--limit abc` into a refusal
rather than a default) is verified by review and marked so below.

## Success criteria

- [ ] R-01 — Journal log with a negative `limit` is refused with one usage sentence on both
  connectors; no process dies.
- [ ] R-02 — Search with a negative `limit` is refused with the same sentence; it no longer
  answers empty.
- [ ] R-03 — On the MCP server a `limit` given as text that does not read as an integer is
  refused with the usage sentence, not defaulted.
- [ ] R-04 — On `perg` a `--limit` value that does not read as an integer is refused with the
  usage sentence, not defaulted. (no-test: no CLI harness; verified by review)
- [ ] R-05 — A `limit` of `0` is legal and answers an empty list on both reads.
- [ ] R-06 — `resources/list` with a negative or non-numeric `cursor` answers a JSON-RPC
  invalid-params error, and the same server answers the next request.
- [ ] R-07 — `resources/list` with a `cursor` past the last note answers an empty page.
- [ ] R-08 — The parser refuses an option whose next token starts with `--` as a missing value;
  `--folder --dry-run` performs no write.
- [ ] R-09 — The parser refuses a boolean flag spelled with `=value`, and a bare `--`.
- [ ] R-10 — The parser accepts `--option=--value` as the value `--value`, and `-1` as an
  ordinary option value.
- [ ] R-11 — «Create and link a board» on a rehearsal leaves no `.canvas` on disk and no
  journal entry, answers `applied` false, and its `note` names the board file.
- [ ] R-12 — «Create and link a board» on a real run writes the board and the link, records a
  journal entry for the board file under the verb's command label, and undoing that entry is
  declined with the creation sentence while the file stays.
- [ ] R-13 — «Create and link a board» with a name already taken is refused before any write,
  on a rehearsal too.
- [ ] R-14 — The three «create and link» summaries (pratica note, pratica board, message note)
  name the created file in `note`; the summary's JSON keys are unchanged.
- [ ] R-15 — Drop-import beside a note path that escapes the vault is refused, records a
  problem, and writes nothing outside the vault.
- [ ] R-16 — Canvas-store folder creation with a name that escapes the vault is refused at the
  store.
- [ ] R-17 — Folder rename and folder trash on a directory path that escapes the vault are
  refused; nothing is moved or trashed.
- [ ] R-18 — Attachment resolution beside a note path that escapes the vault returns no result
  and probes nothing outside.
- [ ] R-19 — The pratica timeline directory is resolved through the boundary resolver.
  (no-test: its folder comes from the index; no input reaches it)
- [ ] R-20 — The protected-interfaces registry names the boundary resolver, and `PG-151` is
  closed by this PR. (no-test: a registry line and a ledger entry, checked by review)
- [ ] R-21 — The thirty-eight residual path-building sites are recorded as one follow-up ledger
  entry at ship time, with the count and the three heaviest files named. (no-test: ledger
  entry)

## Not yet specified

_none_

## Out of scope

- **The app's own board-creation call sites** (the pratiche link actions and the Workspace
  sidebar verb) keep calling the canvas store directly: the app arms no journal and no dry-run
  switch, so the door buys it nothing, and the async cascade into synchronous UI closures is a
  cost measured once already.
- **A full sweep of path-building sites.** Thirty-eight `root`-relative path constructions in
  twenty-five files bypass the resolver today; the heaviest concentrations of direct file-manager
  calls are the pratiche file operations, the vault disk actor and the canvas store. All are
  gated upstream as far as the interview could see. Filed as a follow-up (R-21), not fixed here.
- **Undo that deletes a created file.** The journal never deletes; the board door inherits the
  note precedent rather than reopening it.
- **An upper bound on `limit`.** Nothing in the issue or the interview asked for one; a large
  limit is a slow answer, not a crash.
- **CLI help text.** The `--option=value` form already works; no help line is added.
- **The other fifteen audit chains.** One chain is one SPEC, one ADR, one PR.
