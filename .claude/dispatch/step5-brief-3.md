<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md tasks=4 lines=237-260 -->
# Step 5 Batch Brief -- 2026-09-09-pratiche.md -- tasks 4-4

## Task text (verbatim, plan lines 237-260)

### Task 4 — the sync: atomic writes, attachments, `.eml`, pending, deletions (R-09, R-10, R-11, R-15, R-16)

- Budget: `Sources/Core/Pratiche/PraticaSyncPlan.swift`,
  `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift` (~700 lines)
- Tester writes: `PraticaSyncPlan.workItems(dossier:candidates:onDisk:settings:)` (pure, ordered
  newest-first) and the `PraticaSyncEngine` actor's signatures (`sync(_:)`, `cancel()`, progress
  stream). Tests drive the pure plan plus the engine against a fixture store and a temporary vault.
- Tests (red): every write lands through temp-then-rename and a cancellation between two messages
  leaves only complete files, resumable from the ledger (R-11); `.eml` written with the same base
  name and referenced by `pergamenum-mail-original` when retention is on, absent when off, and
  **never written for a `pending` message** (R-09, ADR §D18); an attachment is copied as
  `YYYYMMDD_<name>`, an identical SHA-256 is linked rather than copied, a different one collides to
  `-2`, an over-threshold one is recorded as a store reference with no copy, an inline image under
  50 KB is dropped and a larger one is saved and embedded (R-10); a headers-only message is written
  with `body: pending` and a placeholder, and is the **only** file a later sync rewrites unasked
  (R-15); a message whose row disappears keeps its files and loses its link, and **no sync ever
  deletes a file** (R-16); the same `Message-ID` present in two mailboxes produces exactly one file
  (ADR §D15).
- Coder: bodies. The actor owns the connection; each finished message hops once to `@MainActor` for
  `VaultSession.write`; cancellation is checked at that boundary.
- `tuist generate --no-open`; full unit suite.

## Phase 3 — the app

## File map (from Budget: declarations, tasks 4-4)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 4 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0036-pratiche.md -- D2, D4, D5, D6, D7 and both Follow-up sections (Task 1 probes; Task 2/3: locator .notInStore/.ruleFailed split, no cache in the locator so the sync owns it, missing subject field the tester adds) bind the sync's atomic writes, attachments, pending bodies and deletions
- SPEC: SPEC.md -- requirement IDs R-09, R-10, R-11, R-15, R-16 for this batch's tests, plus the message-file frontmatter block (pergamenum-mail-subject)
- CLAUDE.md: CLAUDE.md -- sharedSources rule (Foundation-only under Sources/Core), file-over-app principle (a sync never deletes), tuist generate after adding files
