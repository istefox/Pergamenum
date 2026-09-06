# SPEC — Plaud recording import into Pergamenum

**Topic slug:** plaud-recording-import-into-pergamenum

## Objectives

Consume the local `plaud-service` HTTP contract (already shipped, separate repo `Plaud`,
`http://127.0.0.1:3777`, loopback-only, no auth — contract at
`/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md`) so that a Plaud voice recording can become
a real note in the currently open vault: a transcript note with speaker labels, and a set of real
task-lines built from the themes/tasks the service extracted — after the person reviews and
accepts or rejects each proposed task individually.

Nothing on the Plaud service side is touched. This SPEC covers only the Pergamenum-side consumer:
HTTP client, a new "Registrazioni" sidebar section, the review UI, and the vault-write mapping.

## Scope

**In scope:**
- A new sidebar section, "Registrazioni", listing recordings from `GET /recordings?days=N` with
  status badges (new/processing/ready/failed/imported), manual refresh only.
- Starting processing (`POST /recordings/{id}/process`), polling `GET /jobs/{job_id}` every 3
  seconds while a job is queued/running.
- A review screen for a `ready` recording's proposal (`GET /proposals/{id}`): per-theme grouping,
  per-task accept/reject checkboxes, an optional speaker-rename field per speaker label.
- On confirm: write a transcript note into the vault (new frontmatter keys, see Data model) with
  one H2/H3 section per theme holding the accepted tasks as real task-lines with `>due_hint`
  dates; call `POST /proposals/{recording_id}/imported` with the accepted task ids.
  Rejected tasks are never reported to the service (per contract).
- Force re-run (`?force=1`) on an already-`ready`/`failed`/`imported` recording; on success,
  update the existing transcript note in place rather than creating a second one, without
  duplicating previously-accepted tasks.
  **Task dedup rule across re-runs (needs an architecture decision — quote-based, not id-based):
  the service does not guarantee a task's UUID is stable across two separate `process` runs of the
  same recording (only "stable across reads of the same proposal" per contract), so dedup on
  re-import must match on quote text, not on the task id. This is a real open question for Step 2,
  not resolved here.**
- Deleting a managed recording from the list: moves the transcript note (and its tasks, being in
  the same file) to the macOS Trash, with a confirmation dialog — same convention as every other
  delete in the app. No call to the Plaud service (no delete endpoint exists); the recording stays
  known server-side.
- A `days` setting in Impostazioni (default 14, matching the service's own default) that the
  person can change to any value they type.
- Vault-scoped: the section and its recording list reflect the currently open vault; switching
  vault shows that vault's own state.
- Explicit, narrow exception to CLAUDE.md Principle 2 (fully offline), documented in the ADR with
  the same shape as ADR-0031 §D13 (Sparkle): loopback-only (`127.0.0.1:3777`), no data ever leaves
  the machine, nothing beyond this feature gains network access as a result.
- Service-down UX: `GET /health` failing (or unreachable) shows a status message plus the
  `launchctl load ~/Library/LaunchAgents/it.stefer.plaud-service.plist` command as text to copy —
  the app never executes it.
- Failed job UX: readable error message (not the raw `extraction_invalid: ...` string) plus a
  "Riprova" button that re-calls `process?force=1`.
- Review-state persistence: accept/reject selections made mid-review survive an app restart
  before the import is confirmed (local persistence outside the vault, exact location an
  architecture decision — likely alongside other per-vault derived state,
  `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`, per ADR-0017's precedent).

**Out of scope (this SPEC):**
- Anything on the `plaud-service`/`Plaud` repo side.
- `perg` CLI / `pergamenum-mcp` exposure — this feature is app-only; no new
  `Sources/Connector` surface.
- Apple Reminders/EventKit integration for imported tasks — due date only, on the task-line
  itself, no Reminder object created.
- Workspace canvas cards for recordings (deferred; the transcript note stands alone).
- Renaming speakers retroactively after import (only available during the pre-import review).

## Stack

No new external dependency. `URLSession` for the HTTP client (loopback, JSON, no auth — no need
for anything beyond Foundation). SwiftUI for the new sidebar section and review screen, following
the app's existing sidebar-section/list/detail patterns. Local persistence for pending review
state and per-vault import tracking through the existing `VaultState`/Application Support
mechanism (ADR-0017), not a new storage technology.

## Architecture (decisions for Step 2 to formalize)

- New read-only HTTP client type under `Sources/Features/` (not `Sources/Core`, not
  `Sources/Connector` — this feature is explicitly app-only, see Scope). Owned by a new
  controller analogous to `WorkspaceController`/`VaultController`'s own shape.
- The client polls `GET /health` on demand (when the section is opened or refreshed), never on a
  background timer — same "manual only, no timer" posture as ADR-0031's updater.
- Per-vault tracking of "which recordings has this vault seen, and what's their local status"
  needs a small persisted structure (recording id → imported/deleted/note path), scoped under the
  vault's own Application Support directory, not the index cache (this is Plaud-side state, not
  vault-content-derived — it must not be lost on `clearCache()`, unlike `IndexCache`).
- Frontmatter schema reopening: this feature adds prefixed keys to the closed 4-key note
  frontmatter (`date`, `tags`, `related`, `aliases`), following the existing precedent of
  `pergamenum-*` prefixed keys already used for `.canvas` node extra properties (ADR-0020). The
  ADR must state this explicitly as a deliberate, scoped reopening of SPEC §4.3/§14's closed
  schema — not a silent extension — and confirm the note-frontmatter YAML parser/writer accepts
  and round-trips unknown-to-Obsidian keys without stripping them (Obsidian compatibility,
  Principle 4).

## Data model

**New frontmatter keys (prefixed, additive to the closed 4-key schema):**
- `pergamenum-plaud-id: <recording id>` — the Plaud recording id, for idempotency (re-run
  detection) and to anchor re-imports back to the right note.
- `pergamenum-plaud-recorded-at: <ISO 8601>` — the recording's own `recorded_at`.
- `pergamenum-plaud-duration-ms: <integer>` — the recording's `duration_ms`.

**Tags:** the transcript note also carries a `type-*` namespaced tag (exact value TBD at Step 2,
e.g. `type-trascrizione`) alongside the frontmatter keys above — the two are not alternatives,
they serve different purposes (tag = vault-wide taxonomy/filtering, frontmatter keys =
machine-readable anchor for this feature's own logic).

**Note body shape:**
```markdown
---
date: 2026-09-04
tags: [type-trascrizione]
related: []
aliases: []
pergamenum-plaud-id: "8f2a1e40-..."
pergamenum-plaud-recorded-at: "2026-09-04T11:44:51Z"
pergamenum-plaud-duration-ms: 3120000
---

[transcript text, speaker labels renamed if the person chose to at review time]

## <Theme name>

- [ ] <Task title> >2026-09-12 (urgenza 4/5, importanza 5/5 — "quote verbatim")
- [ ] <Task title 2>
```

**Local (non-vault) state, exact shape TBD at Step 2:**
- Per-vault recording tracking: recording id, local status, note path once created.
- Pending review draft: recording id, per-task accept/reject state, speaker renames — cleared once
  import is confirmed.

## API (consumed only — contract already fixed, not designed here)

```
GET  /health
GET  /recordings?days=N
POST /recordings/{id}/process[?force=1]
GET  /jobs/{job_id}
GET  /proposals/{recording_id}
POST /proposals/{recording_id}/imported   body: { "task_ids": [...] }
```
Full field shapes: `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md` (out of this repo,
read-only reference — do not copy it into this repo, cite it from the ADR instead).

## UI flows

1. **Sidebar → "Registrazioni".** List of recordings (current vault's `days` setting), each row:
   name, recorded date, duration, status badge. A "Aggiorna" toolbar button re-fetches
   `/recordings`. If `GET /health` fails: a banner replaces the list with the status message and
   the copyable `launchctl load ...` command.
2. **Row action, by status:**
   - `new` → "Elabora" button, calls `process`, row becomes `processing`, polls `/jobs/{id}` every
     3s.
   - `processing` → progress indicator, step name (transcript/extract/cleanup) if available.
   - `ready` → "Rivedi" opens the review screen.
   - `failed` → readable error + "Riprova" (re-calls `process?force=1`).
   - `imported` → "Apri nota" jumps to the existing transcript note; row also offers "Elimina"
     (Trash + confirmation) and "Rielabora" (`force=1`, updates the note in place).
3. **Review screen** (`GET /proposals/{id}`): recording header (name, date, duration,
   `recording_kind`); per-speaker rename fields (optional, pre-filled with "Speaker N"); per-theme
   sections, each listing its tasks with a checkbox (default: all checked), title, quote,
   urgency/importance shown as plain text, `due_hint` shown as a date; a `no_action_items` warning
   banner when `themes` is empty; a `warnings` array (e.g. `cleanup_ratio_low`) shown as a
   dismissible notice, informational only. "Importa" button (disabled if nothing checked is
   required? — no, zero tasks accepted with a transcript-only import is valid) writes the note,
   calls `imported`, returns to the list with the row now `imported`.
4. **Impostazioni** gains a "Giorni registrazioni Plaud" numeric field (default 14) feeding the
   `days` query parameter.

## Edge cases

- `GET /recordings` returns `400 invalid_days` — should not happen if the setting is validated at
  entry (positive integer ≤ 3650), but if it does, show a readable message and fall back to the
  service default rather than crashing.
- `503` (Plaud disconnected) on `/recordings` or `/process` — treated the same as a `/health`
  failure banner.
- `404` on `/jobs/{id}` or `/proposals/{id}` (unknown id, e.g. local state stale after a service
  restart) — readable "non trovato" message, offer to refresh the list.
- Import confirmation (`POST .../imported`) fails after the note was already written locally —
  the note stays (file-over-app: local write already succeeded), but the recording stays `ready`
  server-side; a retry of the confirm call must not re-write the note or duplicate tasks.
- Recording name collides with an existing note title — same collision handling already used
  elsewhere in the vault (numeric suffix).
- Force re-run whose new proposal fails (`extraction_invalid`) — per contract, the previous
  proposal stays readable and the recording state is `failed`; the existing transcript note (if
  any) is left untouched, only the row shows the failure.
- Zero themes/tasks in a ready proposal (`no_action_items`) — importing is still meaningful (the
  transcript alone), no forced rejection of the import.

## Success criteria

- [ ] R-01 — A "Registrazioni" sidebar section lists recordings from the current vault's Plaud
  service within the configured `days` window, with a manual "Aggiorna" action.
- [ ] R-02 — `GET /health` failure shows a status banner with the copyable `launchctl load`
  command; the app never executes it itself.
- [ ] R-03 — Starting processing on a `new` recording enqueues the job and polls `/jobs/{id}`
  every 3 seconds until it reaches `done` or `failed`.
- [ ] R-04 — A `ready` recording opens a review screen showing every theme with its tasks,
  per-task accept/reject checkboxes (default checked), and per-speaker optional rename fields.
- [ ] R-05 — Confirming the review writes a transcript note into the currently open vault with
  the `pergamenum-plaud-*` frontmatter keys, a `type-*` tag, the (possibly speaker-renamed)
  transcript text, and one H2/H3 section per theme containing only the accepted tasks as real
  task-lines with their `due_hint` as `>date` and urgency/importance/quote as inline text.
- [ ] R-06 — Confirming the review calls `POST /proposals/{id}/imported` with exactly the accepted
  task ids; rejected tasks are never sent.
- [ ] R-07 — A `failed` job shows a readable error message (not the raw error string) and a
  "Riprova" action that re-calls `process?force=1`.
- [ ] R-08 — Force re-running an already-`imported`/`failed`/`ready` recording updates the
  existing transcript note in place (matched via `pergamenum-plaud-id`) rather than creating a
  second note, and does not duplicate previously-accepted tasks (matched by quote text).
- [ ] R-09 — Deleting a managed recording from the list moves its transcript note to the macOS
  Trash after an explicit confirmation dialog, and calls no delete endpoint on the service.
- [ ] R-10 — Review selections (accept/reject, speaker renames) made before confirming survive an
  app restart and are restored when the same proposal is reopened.
- [ ] R-11 — Impostazioni exposes a numeric "giorni" field that changes the `days` window used by
  the Registrazioni section for the current vault.
- [ ] R-12 — Switching the open vault shows that vault's own recording list and import state, not
  a shared global one.
- [ ] R-13 — 404/503/400 responses from any endpoint surface a readable, non-crashing message in
  the relevant part of the UI.
- [ ] R-14 — The ADR documents the loopback-only network exception to CLAUDE.md Principle 2 with
  the same explicit scoping shape as ADR-0031 §D13, and documents the frontmatter schema
  reopening as a deliberate, scoped decision against SPEC §4.3/§14. (no-test: this is a
  documentation obligation on the ADR itself, not a runtime behavior a test can assert)
- [ ] R-15 — No new `Sources/Connector` surface is added; `perg` and `pergamenum-mcp` build
  unaffected by this feature. (no-test: verified by running both connector build targets, not by
  a unit test asserting an absence)
