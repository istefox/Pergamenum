# SPEC — Fix Pratiche attachment reliability bugs (amends ADR-0036)

**Topic slug:** pratiche-attachment-reliability-bugs

## Objective

Pratiche (ADR-0036) syncs Apple Mail messages into vault notes with attachments copied into an
`allegati/` subfolder. Attachments are unreliable today: some are written to disk empty or
truncated (typically because Mail/iCloud has not yet fully materialized the attachment on this
Mac at the instant Pergamenum reads the `.emlx` file), a corrupt file fails to open both in Finder
and inside the Pratiche timeline UI ("file is empty"), and some emails with visible attachments in
Mail end up with none written at all. Once a message note is written as `.complete`, ADR-0036
never revisits it automatically, so a message captured at a bad instant stays broken forever
unless the user manually triggers «Rigenera».

This fix makes attachment capture self-healing without adding any network dependency: Pergamenum
detects an incomplete/corrupt attachment at decode time, treats the affected message as
"not yet available", and automatically retries at every subsequent sync — with no retry cap —
until Mail has the bytes. It also guards both the write path and the open path so a known-bad
file is never silently written to disk or handed to QuickLook/`NSWorkspace`.

Dedup does **not** change: `PraticaSyncEngine.digest(of:)` already computes SHA-256 over decoded
attachment bytes and keys placement/reuse on that digest, not on filename. The only defect fixed
here is that it can currently hash empty/corrupt bytes, which is eliminated once corrupt bytes are
never placed in the first place.

## Scope

**In scope:**
- Attachment integrity validation at decode time (`bytes.count > 0` plus a magic-byte sanity check
  for common formats: PDF, PNG, JPEG, ZIP/Office-based formats which are ZIP containers).
- A new "not yet available" state for an individual attachment, distinct from the existing
  `.pending` (headers-only/no-body) message state.
- Extending the existing automatic self-heal retry mechanism (today: `regeneratePending`, fires
  only on `.pending → .complete`) so it also revisits messages that were written `.complete` but
  contain one or more "not yet available" attachments — every sync, no attempt cap.
- Partial-completeness handling: a message with some valid and some not-yet-available attachments
  is written `.complete` immediately with the valid attachments linked; the not-yet-available ones
  are represented as a distinct placeholder entry in the same note and are added when they later
  validate.
- The over-threshold "store-reference" attachment path (large attachments left in Mail's own
  `Attachments/` folder, only referenced by path) gets the same integrity check before being
  linked or opened.
- Timeline UI (`AttachmentChip`/`AttachmentChipModel`): a chip for a not-yet-available attachment
  renders a distinct "in attesa" badge/state instead of the filename; clicking it shows an
  informational message and performs no open/preview action (no call to QuickLook or
  `NSWorkspace.open`).
- One-time repair pass: on the first sync after this fix ships, any existing file in an
  `allegati/` folder that fails the new integrity check is deleted and its owning `.complete`
  message is transitioned back to the new "not yet available" state so it re-enters the automatic
  retry cycle.
- Amending ADR-0036 §D6/§D21 (the "a `.complete` message is only ever rewritten via the documented
  pending→complete self-heal or explicit «Rigenera»" rule) to add this one additional, narrow
  automatic-rewrite trigger. No other aspect of that rule changes.
- Extending the existing `EmailFixtureCorpus` Swift Testing fixtures with synthetic `.emlx` cases:
  a zero-byte attachment, a mid-truncated attachment, and a message mixing a valid and a truncated
  attachment.

**Out of scope:**
- Any network call to iCloud or Mail to force/expedite attachment download (Principle 2, fully
  offline — Pergamenum has no channel to do this and must not add one).
- Adding retry/backoff logic inside `EMLXReader.read(contentsOf:)` itself — the `.emlx` file is
  still read once per sync attempt; retrying happens across sync cycles, not within one read.
- Changing the dedup algorithm (`digest(of:)` SHA-256-over-bytes) — it is already correct.
- Changing `PraticaNaming.messageFileName`, `Dossier.render`, or `VaultAPI.PraticaSummary`
  (ADR-0036's declared protected interfaces) — none of this fix's changes require touching their
  signatures or behavior.
- A manual "Verifica e ripara allegati" command — the one-time repair runs automatically on the
  first post-fix sync instead.
- Any change to the existing `.pending` (headers-only body) message-level state or its existing
  `regeneratePending` trigger condition beyond the addition described above.

## Stack

Swift 6, SwiftUI, macOS 26 SDK, Swift Testing. No new dependency: `CryptoKit` (already imported by
`PraticaSyncEngine`) is reused for nothing new here; no new framework is needed for magic-byte
detection (a handful of literal byte-prefix comparisons in pure Swift).

## Architecture

### New attachment-level state

Today a placed attachment part is either linked (copied into `allegati/` or referenced via
store-path) or silently dropped. This fix introduces a third outcome at the point where
`PraticaSyncEngine` currently does `let bytes = part.decodedData ?? Data()` and unconditionally
schedules a write (`Sources/Features/Pratiche/PraticaSyncEngine.swift:397-414`):

- **Integrity check** (new, pure function, no I/O): given decoded bytes and the part's declared
  filename/content-type, return `valid` or `notYetAvailable`. `notYetAvailable` when
  `bytes.isEmpty`, OR when a magic-byte signature is known for the declared type/extension and the
  leading bytes do not match it (PDF `%PDF`, PNG `\x89PNG`, JPEG `\xFF\xD8\xFF`, ZIP-based formats
  including Office Open XML `PK\x03\x04`). A part whose type has no known signature (not on this
  list) is validated on `bytes.isEmpty` alone — never rejected solely for lacking a signature
  entry.
- A `notYetAvailable` part is never hashed, never placed under `allegati/`, and never linked to a
  store-reference path. It is instead recorded on the message as a distinct "pending attachment"
  entry (filename known, bytes not yet usable) so the timeline chip has something to render.
- The over-threshold store-reference path applies the same integrity check to the bytes read from
  Mail's `Attachments/` folder before recording that reference as usable.

### Message-level: partial completeness

A message with N attachment parts, where M ≤ N validate and the rest are `notYetAvailable`, is
written as `.complete` with M attachments linked normally and the remaining recorded as pending
attachment placeholders in the same note. This is a refinement of the existing `place`/`commit`
flow (`PraticaSyncEngine.swift:634-737`) — it does not change when a *message* is `.complete` vs
`.pending` (that distinction stays governed by `bodyState`), it only allows a `.complete` message
to carry pending attachment entries.

### Retry trigger — extending `regeneratePending`

`regeneratePending` (`PraticaSyncEngine.swift:672-704`) today re-examines only messages whose
recorded body state is `.pending`. This fix extends its selection to also include `.complete`
messages that carry at least one pending attachment entry from a previous sync. Both categories
are re-parsed from the current `.emlx` on every `sync(_:)` call, with no attempt counter and no
cap — matching the existing pending-body behavior. A message that resolves fully (all attachments
now valid) is rewritten with all attachments linked, dropping the pending entries; a message that
still has some or all attachments not-yet-available keeps exactly those still-pending entries.

### One-time repair of pre-existing corrupt files

On the first sync run after this fix ships, before or as part of the existing
`folderContext(of:)` scan (`PraticaSyncEngine.swift:272-286`, which already digests every file
present in `allegati/`), any file that fails the new integrity check is deleted from disk and its
owning message (found via the existing digest/link bookkeeping) is downgraded so its
corresponding attachment becomes a pending entry again, making it eligible for the retry mechanism
above. This is a one-time migration path, not a recurring background scan — after the first
post-fix sync, every remaining file in `allegati/` has already passed the new check at write time.

### Timeline UI

- `AttachmentChipModel`/`AttachmentChip` (`Sources/Features/Pratiche/AttachmentChipModel.swift`,
  `AttachmentChip.swift`) render a distinct visual state for a pending attachment entry (badge or
  icon, no filename-as-action) instead of the filename-based clickable chip used for a normal
  attachment.
- Clicking a pending-attachment chip shows a short informational message (e.g. as a tooltip or a
  transient popover) stating the attachment is not yet available and will be retried at the next
  sync. It performs no `QuickLookPresenter`/`NSWorkspace.open` call.
- A normal (non-pending) chip's existing `fileExists`-only gate in `AttachmentChip.swift:72-95`
  gains the same integrity check used at write time before handing a URL to QuickLook or
  `NSWorkspace.open`, as a defense-in-depth guard against any file that reaches disk corrupt
  through a path other than `PraticaSyncEngine` (e.g. manual tampering, a future code path).

## Data model

No new persisted field format, no index schema bump. The "pending attachment" entry is expressed
the same way the existing pending-body state already is: as parsed structure recovered from
`.complete`-frontmatter's existing attachment-list encoding plus a marker distinguishing a
resolved link from a not-yet-resolved filename-only entry — encoded in the message note's existing
attachment section, not as a new frontmatter key. No change to `IndexCache.schemaVersion` (stays
3, per ADR-0021 §D1 precedent — no new table, no migration).

## API

No new connector-facing API. `VaultAPI.PraticaSummary` (protected interface) is unchanged — this
fix does not add a new field for pending-attachment counts to the connector surface; that
information stays purely inside the app's Pratiche feature layer.

## UI flows

1. **Normal attachment, always was fine:** unchanged — chip shows filename, click opens/previews
   normally.
2. **Attachment not yet available at capture time:** chip shows "in attesa" badge instead of
   filename. Click shows an informational message, no open attempt. At the next sync, if Mail now
   has the full bytes, the badge is replaced by the normal filename chip automatically — no user
   action required.
3. **Mixed email (2 of 3 attachments ready):** the 2 ready ones behave as in flow 1 immediately;
   the 3rd behaves as in flow 2 until it resolves.
4. **Pre-existing corrupt file from before this fix:** on first sync after upgrade, the corrupt
   file disappears from `allegati/` and its chip becomes an "in attesa" badge (flow 2), then
   resolves automatically once Mail has the bytes.

## Edge cases

- An attachment whose declared type has no known magic-byte signature (e.g. a plain-text `.txt`,
  a proprietary format) is validated on non-emptiness only — it is never rejected purely for lack
  of a signature entry, per the interview decision.
- An attachment that is genuinely, permanently truncated in Mail itself (Mail will never complete
  it, e.g. a message damaged in Mail's own store) stays in "in attesa" state forever, retried at
  every sync with no user-visible failure state distinct from "still waiting" — the interview
  explicitly chose unlimited retry with no cap and no distinct terminal-failure UI, since
  Pergamenum cannot distinguish "still downloading" from "will never complete" without a network
  call it is not allowed to make. Manual «Rigenera» remains available as an explicit user action if
  they want to prompt a re-check outside the normal sync cadence, unaffected by this fix.
- A store-reference (over-threshold) attachment whose Mail-side `Attachments/` file is itself
  truncated is treated identically to a copied attachment: "in attesa", retried every sync.
- Dedup interaction: a pending attachment is never hashed and never enters the dedup digest
  index, so two different corrupt attachments can no longer be wrongly treated as identical (the
  observed side effect of the pre-fix bug). Once an attachment validates, it is hashed and
  deduped exactly as today.
- Deleting the stale corrupt file during the one-time repair pass must not touch any *other* file
  already correctly placed in the same `allegati/` folder, and must not orphan the dedup digest
  index for files that remain valid.

## Success criteria

- [ ] R-01 — An attachment part whose decoded bytes are empty is never written to `allegati/` and
      never linked to a store-reference path; the message is instead recorded with a pending
      attachment entry for that part.
- [ ] R-02 — An attachment part whose decoded bytes are non-empty but fail the magic-byte check
      for its declared type (PDF, PNG, JPEG, or a ZIP-based format) is treated identically to R-01.
- [ ] R-03 — An attachment part whose declared type has no known magic-byte signature is accepted
      whenever its bytes are non-empty, regardless of content.
- [ ] R-04 — A message with some valid and some not-yet-available attachments is written
      `.complete` immediately, with the valid attachments linked normally and the others recorded
      as pending attachment entries in the same note.
- [ ] R-05 — At every `sync(_:)` call, every message carrying at least one pending attachment
      entry (in addition to the existing `.pending`-body messages) is re-parsed from its current
      `.emlx`, with no attempt cap and no cooldown.
- [ ] R-06 — When a previously-pending attachment part now validates, the message is rewritten
      with that attachment linked and its pending entry removed; other already-linked attachments
      and other still-pending entries in the same note are left untouched.
- [ ] R-07 — A store-reference (over-threshold) attachment path applies the same integrity check
      (R-01/R-02/R-03) before the reference is recorded as usable or handed to the UI.
- [ ] R-08 — The Pratiche timeline chip for a pending attachment entry renders a distinct "in
      attesa" state instead of the filename, and never triggers QuickLook or `NSWorkspace.open`
      when clicked; it shows an informational message instead.
- [ ] R-09 — A normal (already-linked) attachment chip's open/preview path re-validates the file's
      bytes with the same integrity check (R-01/R-02/R-03) before handing its URL to QuickLook or
      `NSWorkspace.open`, as a defense-in-depth guard.
- [ ] R-10 — On the first sync after this fix ships, every file already present under any
      pratica's `allegati/` folder that fails the integrity check (R-01/R-02/R-03) is deleted, and
      the message that owns it is downgraded so that attachment becomes a pending entry eligible
      for the retry mechanism of R-05.
- [ ] R-11 — The one-time repair pass of R-10 does not delete, modify, or affect the dedup digest
      of any other, valid file already present in the same or a different `allegati/` folder.
- [ ] R-12 — `PraticaSyncEngine.digest(of:)`-based dedup is never computed over a pending
      attachment's bytes; two unrelated pending/invalid attachments are never treated as
      duplicates of each other.
- [ ] R-13 — `PraticaNaming.messageFileName`, `Dossier.render`, and `VaultAPI.PraticaSummary`
      (ADR-0036's declared protected interfaces) are unchanged in signature and behavior by this
      fix. (no-test: interface-check.sh at Step 6 verifies this mechanically against
      .claude/protected-interfaces, not a Swift Testing assertion)
- [ ] R-14 — No new network call, socket, or loopback connection is introduced anywhere in this
      fix; Principle 2 (fully offline) is respected exactly as before. (no-test: verified by
      code review and the absence of any new networking API usage, not a runtime assertion)
- [ ] R-15 — `EmailFixtureCorpus` gains synthetic `.emlx` fixtures covering: a message with one
      zero-byte attachment, a message with one mid-truncated (non-empty, magic-byte-mismatched)
      attachment, and a message mixing one valid and one truncated attachment — exercising R-01
      through R-06 in Swift Testing.
- [ ] R-16 — ADR-0036 §D6/§D21 is amended (via a new ADR entry cross-referencing it, not a silent
      rewrite of the original text) to document the one narrow additional automatic-rewrite
      trigger added by R-05, with the rest of that rule unchanged. (no-test: documentation
      obligation, verified by review that the ADR amendment exists and is cross-referenced)
