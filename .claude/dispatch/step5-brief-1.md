<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md tasks=1 lines=125-155 -->
# Step 5 Batch Brief -- 2026-09-09-pratiche.md -- tasks 1-1

## Task text (verbatim, plan lines 125-155)

### Task 1 — the two probes, the code-built fixture store, and `MailStoreReader` (R-02, R-03, R-19)

- Budget: `Sources/Core/Email/MailStoreLocation.swift`, `MailStoreConnection.swift`,
  `MailStoreCopy.swift`, `MailStoreReader.swift`, `MailMessageRow.swift`,
  `Tests/MailStoreFixture.swift`, `Tests/MailStoreReaderTests.swift` (~700 lines)
- **Probe first, with Stefano present, before any design is fixed.** Two questions, both answered
  by reading *schema and paths only*, never message content, and both recorded in the plan file and
  in an ADR follow-up note:
  1. `PRAGMA table_info(messages)`, `table_info(addresses)`, `table_info(recipients)`,
     `table_info(attachments)`, `table_info(mailboxes)` on a **copy** made by the code written in
     this task — never on the live file. Answer C9: is `messages.message_id` an integer hash or a
     queryable text id?
  2. For three arbitrary ROWIDs from three mailboxes, print the `.emlx` path the fan-out rule
     predicts and the path that actually exists (`find` limited to that mailbox). Answer C10.
- Tester writes: `MailStoreLocation.resolve()`; `MailStoreCopy.publish(from:into:)` returning
  `.published(URL)` / `.unchanged(URL)` / `.mailIsWriting` / `.storeMissing`;
  `MailStoreConnection` (open/close, `prepare`, typed row accessors);
  `MailStoreReader` with the five R-03 queries; the value types `MailMessageRow`, `MailboxRef`,
  `MailAttachmentRef`, `MailConversation`. Plus `Tests/MailStoreFixture.swift`, a helper that
  **creates** a small Envelope Index (the probed schema) plus `.emlx` files in a temp directory.
- Tests (red): the copy skips when the source mtime is unchanged and republishes when it changes;
  a deliberately truncated source produces `.mailIsWriting` after exactly one retry, never a
  half-populated reader; the five queries return the fixture's known rows; `SQLITE_OPEN_CREATE` is
  never passed (a missing store gives `.storeMissing`, not an empty database); `MailStoreLocation`
  returns the fixture under xctest and honours `-mailStoreRoot`; **no file outside
  `Sources/Core/Email/MailStoreConnection.swift` contains `sqlite3_`**.
- Coder: bodies. Staging directory → copy db + `-wal` (never `-shm`) → open read-write, no CREATE →
  `PRAGMA quick_check` + `SELECT count(*)` → `CREATE INDEX IF NOT EXISTS` on `conversation_id` and
  `sender` → `PRAGMA query_only = 1` → publish by one directory rename → delete older generations.
- `tuist generate --no-open`; full unit suite.

## File map (from Budget: declarations, tasks 1-1)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 1 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum/docs/adr/0036-pratiche.md -- D1-D4 fix the SQLite access rule (one file, transient destructor, no CREATE), the published-copy protocol and the ledger/emlx-locator design the two probes decide
- SPEC: /Users/stefer/Developer/Pergamenum/SPEC.md -- requirement IDs R-02, R-03, R-19 for this batch's tests
- CLAUDE.md: /Users/stefer/Developer/Pergamenum/CLAUDE.md -- sharedSources rule: a file under Sources/Core must stay Foundation-only or both connector builds break; tuist generate after adding files
