<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=10 lines=778-888 -->
# Step 5 Batch Brief -- 2026-09-13-vault-write-ordering-adr-0043.md -- tasks 10-10

## Task text (verbatim, plan lines 778-888)

## Task 10 — The acceptance harness, the verification sweep, and this chain's own record (R-16, R-17, R-18, R-19, R-20)

Cross-refs: ADR-0043 §D9 («the acceptance criterion is a test that forces the interleaving, never a
green suite»); ADR-0043 §D10 (what this must **not** have changed); CLAUDE.md's pre-merge rules.
Budget: `scripts/adr-0043-interleaving-check.sh`, `docs/adr/0043-vault-write-ordering-concurrency-races.md`,
`TODO.md`, `PROJECT_BRIEF.md` (~200 lines)

1. **Create `scripts/adr-0043-interleaving-check.sh`** — **bash 3.2-clean** (macOS ships 3.2: no
   `mapfile`, no associative arrays, no `${var^^}`; collect with
   `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`). Its header comment names
   `docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md` and `ADR-0043`, so the
   anchor resolves to this feature. It asserts, exiting non-zero with a named failure on each:
   - the five `@Test` function names of `R-11`–`R-15` exist in `Tests/`;
   - `grep -c "index\.update" Sources/` is exactly `1`, and that line is inside
     `VaultSession+WriteOrdering.swift`'s `apply` (R-02);
   - `grep -rn "writeSynchronously\|updateIndex" Sources/ Tests/` returns nothing (R-02, R-03);
   - `grep -rn "reloadFocusedNote" Sources/Features/Pratiche/` returns nothing (R-08);
   - the five tests are reported as **passed** in the most recent result bundle, read with
     `xcrun xcresulttool get test-results tests --path <bundle>` — a test that exists but did not
     run is not acceptance. If a bundle path is not supplied the script says so and exits non-zero
     rather than silently skipping the check.
2. **Full unit suite** via `.claude/test-cmd`, unmodified (R-17).
3. **Both connector targets build:**
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
   and the same for `pergamenum-mcp`. A file added under `Sources/Core` that imports SwiftUI breaks
   both, which is ADR-0001 §D1 enforcing itself.
4. **`python3 scripts/mcp-smoke.py <binary>` passes, with `scripts/mcp-smoke.py` unmodified** (R-16).
   The MCP tool surface does not change: `tools/list` answers the same names with the same schemas
   (§D10). If the smoke test needs an edit, something in scope was got wrong — stop and report,
   do not edit the smoke test.
5. **Manual `perg` pass**: a `--dry-run` write, a real write, a `journal log`, an `undo`. ADR-0007
   §D6's three guardrails must all still hold: `--allow-write` gating, `dryRun` defaulting to true,
   the journal recording path/hash-before/hash-after/previous-text — §D5 makes the third *more*
   accurate, not different.
6. **`scripts/uitests.sh`** before the merge to `main`, per CLAUDE.md's standing rule. Kill stale
   instances first; read the per-test seconds beside each failure before believing a red run
   (60.2 s names the launch timeout, not the app).
7. **R-18: update ADR-0043's header status line** from «proposed — **decided, not implemented**
   (see §D9)» to record implementation, with the PR number, once R-01–R-17 hold. Nothing else in
   the ADR's decisions changes. Add the release-note line Task 8 step 6 owes: ADR-0001 §D3.4's
   conflict prompt now fires when the app writes a note out from under a dirty buffer, at nine
   call sites, previously silent.
8. **File the three follow-ups this chain surfaced and deliberately did not fix**, as `TODO.md`
   entries with GitHub issues, each naming ADR-0043 and this plan: (a) `transaction`'s
   `currentOperation` is scoped state that now spans a suspension, so two concurrent transactions
   can join the wrong gesture (Task 3 step 1); (b) `readDiary` → user gesture → `writeDiary` is a
   read-modify-write window wider than §D8 can close (Task 9, declined); (c) the tag-rename and
   note-rename batch appliers have the same window at batch scope. None is a regression this chain
   introduces except (a), which ADR-0041 §D9 introduced and this chain widens the reach of.
9. **R-19: close GitHub issue #259** once this chain's PR merges, with `state_reason` set.
10. **R-20: update `TODO.md`'s `PG-150`** (line 11) to reflect completion, in the same shape
    `PG-149` uses — implementation verified in-session, suite counts, `scripts/uitests.sh` result
    with pre-existing failures named. Update `PROJECT_BRIEF.md`'s Status section if the milestone
    line moves.

**Done when:** the harness exits zero; the full unit suite is green; both connectors build;
`scripts/mcp-smoke.py` passes unmodified; `scripts/uitests.sh` shows no new failure; the ADR,
`TODO.md` and issue #259 are updated.

---

## Risks, dependencies and HITL gates

**Risks, highest first:**

1. **The mechanical cascade is three to four times what ADR-0043 measured.** 25 test files, ~210
   call sites, 46 files. Tasks 1–3 are large diffs in which almost every line is uninteresting and
   a handful are not. The mitigation is the vertical split and the rule that no assertion is
   re-sequenced without a stated reason — not speed.
2. **`closeAfterSaving()` and `replacementsApplied()` are data-loss shaped.** An `async`
   `saveOpenNote` whose `closeTab`/next-edit is not sequenced after it writes the wrong buffer or
   closes before the write lands. Called out at Task 3 step 5; it is the single most likely way
   this chain introduces a defect worse than the four it fixes.
3. **`ViewQuerySource.move`/`.undo` becoming `async` changes a SwiftUI closure type.** A
   `.dropDestination` returns `Bool` synchronously; the decided answer (fire a `Task`, return
   `true`, report failures through the problem channel) makes a drop optimistic where it was
   authoritative. It is the right trade under ADR-0043's own rejection of in-flight refusal, and it
   is a behaviour change a reviewer should see named rather than discover.
4. **`transaction`'s `currentOperation` now spans a suspension.** Two overlapping transactions can
   join the wrong journal gesture. Not decided by ADR-0043, not fixed here, filed at Task 10 step 8.
   Flagged rather than absorbed because a journal gesture that groups the wrong writes is the same
   class of defect as Race 2.
5. **§D7 changes behaviour at nine call sites at once.** A prompt that never appeared starts
   appearing, and it will read as a regression the first time it happens. Release note, not only a
   test (ADR-0043's Negative consequences say so explicitly).
6. **§D8's refusals are new failure paths at thirteen call sites.** Each must handle
   `WriteRefusal.movedOn` — a `try?` that swallows it turns a guard into a silent no-op, which is
   the failure mode ADR-0007 §D6 exists to prevent.
7. **A green suite is not acceptance here.** ADR-0043 §D9 is explicit and the review that raised it
   routed all three findings REPORT-ONLY for this reason. If R-11–R-15 are weak — if any of them
   relies on `Task.yield()`, a sleep, or real scheduling — the chain has demonstrated nothing.
8. **Three UI tests are already red on `main`** (`PG-108` and
   `testACornerGripCanStillBeGrabbedWhenZoomedOut`, per `TODO.md` `PG-149`). Do not read them as
   this chain's damage; do not let them hide a fourth.

**Dependencies:** ADR-0041 fully merged (`main`, PR #254 / `42e25ae`) — every file this chain
touches only exists in this shape because of it. No external dependency, no new package, no network.

**HITL gates — human approval required before each:**

- **Commit** of each of Tasks 1–10. Ten commits, one logical change each.
- **Push** of the branch, and **opening the PR**.
- **Merge to `main`** — and `scripts/uitests.sh` must have run first, per CLAUDE.md.
- **Closing GitHub issue #259** (Task 10 step 9).
- **Editing `docs/adr/0043-…md`'s status line** (Task 10 step 7): an ADR edit is a record change.
- **Any deletion beyond the two named functions** (`write(_:to:) throws`, `writeSynchronously`) and
  the three named lines (`updateIndex`, `VaultController+Tabs.swift:359`, the composer's
  `reloadFocusedNote()`). Nothing else in this chain deletes anything.
- **No schema change and no migration exists in this chain** — if one appears to be needed, stop:
  §D10 says `IndexCache.schemaVersion` does not move, and a migration would mean the design was
  misread.

## File map (from Budget: declarations, tasks 10-10)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 10 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0043-vault-write-ordering-concurrency-races.md -- governing ADR for this chain
- SPEC: docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md -- task detail lives in the plan itself
