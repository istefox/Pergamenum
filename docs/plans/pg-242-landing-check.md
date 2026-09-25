# Fix: a landing that restores a version `main` already moved past is refused, whatever the merge method (PG-242 / #535)

No `SPEC.md` governs this task. The repo-root `SPEC.md`, `BRAINSTORM.md` and
`UX-BLUEPRINT.md` belong to unrelated, already-shipped features and are **not** this
chain's input. The dispatch brief is the whole specification. Its five questions are
answered in the table below, and every task says in plain words which one it serves. The
brief declares no requirement ids, so none are cited.

This plan was read out of the worktree `agent-a86607d92ffe59aa9` at `d630941`, with a clean
tree and `main`/`origin/main` at `e5ba01a`. Every line number, count and call-site list
below was checked against that tree and that `main`.

## ADR outcome: new ADR `docs/adr/0062-landing-check-closes-the-squash-gap.md`

It is written with status `proposed` and becomes accepted when this chain's PR merges. `0062` is free: `git log --all` over
`docs/adr` shows no `0062*` file on any ref. A parallel worktree that has not pushed is
outside what that check sees (see Risks).

A new ADR, rather than a citation of ADR-0061, because all three gates hold:

- **Hard to reverse.** It adds a new blocking condition to every push from this machine and
  a second trailer vocabulary (`Restore-override`). Trailers written into commit history
  are permanent.
- **Surprising without context.** A future reader finds a push of a plain revert refused,
  a second override key next to `Merge-override`, and a PR job that deliberately ignores
  `pull_request.base.sha`, even though ADR-0061's job uses it.
- **A real trade-off.** The choices were: build or leave §D5 open; merge-tree comparison
  or history-based detection; blocking or advisory; a mode or a new script; a shared or a
  separate trailer; a threshold/window/allowlist or none.

Overrides also apply. It closes a gap an accepted ADR named and left open (ADR-0061 §D5). It
also records explicit **no**s that a reader would otherwise undo: deletions never fail, no
automatic revert recognition, branch protection not reopened.

ADR-0062 **closes** ADR-0061 §D5, **extends** ADR-0061 §D1–§D4, and **amends none**.
ADR-0061's body is not edited. Task 5 proposes one optional forward-pointer line for Stefano
to accept or drop.

## The brief, checked against the code and the history

| Brief item | Verdict | Decided in |
|---|---|---|
| 1. Is it worth building now, given 434 merges / 2 hits? | **Yes, scoped narrowly. The reason given is not the one the brief expected.** A read-only walk of all 412 first-parent landings on `main` shows **zero** squash or direct landings ever restored anything, so the specific hole has never happened here. The case for building rests on four things. The dangerous shape is one everyday command away (`git reset --soft $(git merge-base HEAD origin/main)` after merging `main` in). The failure class is P1 silent loss. The measured noise is low: 6 of 412 landings flagged, namely the PG-240 incident, 3 deliberate restores and 2 toggles of `.claude/test-cmd`. And it is cheap. The build is **gated**: Task 2 must reproduce those 6 before Task 4 wires the blocking hook. | ADR Context, §D1 |
| 2. The concrete mechanism (`git diff base...head` vs a recomputed `merge-tree`) | **The comparison the brief proposed cannot work, so the rule is replaced.** On linear history `git merge-tree BASE HEAD` reproduces the squashed commit's own content, so it has nothing to disagree with. The squash erased the fork point. What survives is `main`'s own first-parent record of every blob each path held. The rule is therefore: compute the landing tree `T` (with `merge-tree` only when `BASE` is not an ancestor of `HEAD`), diff `BASE..T`, and fail on any path whose new blob is one the path already held on `main`'s first-parent line. The exact git operations are in ADR §D2. | ADR §D1, §D2; Task 1 |
| 3. Existing script or new one; CI only, since it "cannot run as a local pre-push hook" | **Existing script, new `--landing BASE HEAD` mode plus a `--landings RANGE` audit mode.** The premise that it cannot run pre-push is **incorrect**. It holds only for a check that needs a merge commit. This check reads content, so the hook sees the squashed commit on its first push and can refuse it. It runs pre-push (blocking) **and** in `merge-integrity.yml` on `pull_request` and `push: main` (advisory). | ADR §D4, §D5; Tasks 1–4 |
| 4. False positives on ordinary squash/rebase PRs touching files `main` also changed | **Measured.** A concurrent edit produces a three-way blob `main` never held, so it never fires: none in 406 unflagged landings. The only noise is `.claude/test-cmd` (a one-line per-machine command) toggled back to an earlier value, twice in 412 landings. Deletions are context only, because measured legitimate deletions of recently added files (1, 2 and 5 landings after the add) rule them out as a signal. There is no threshold, window or allowlist; the ADR alternatives explain why. | ADR Context, §D2, §D8 |
| 5. Advisory, or reopen branch protection? | **Blocking at pre-push, advisory in CI, branch protection not reopened.** Two of ADR-0044 §D11's three reasons do not apply to `merge-integrity.yml` (it has no `paths-ignore` and no pre-existing reds). That is recorded as an **open question for Stefano**. It is a preference, not a fact, and it is not decided here. | ADR §D7, Open questions |
| Additional finding: `pull_request.base.sha` | **Not used for this check.** GitHub does not document when it is refreshed. A stale base attributes `main`'s own later landings (including its deliberate restores) to the PR. The PR job resolves `origin/<base.ref>` at job time instead. | ADR §D3; Task 3 |

## How the work is split between tester and coder

Python has no compile step, but a self-test that calls a function which does not exist yet
dies with `NameError` on the first call. That kills every later scenario instead of producing
red assertions. So in every task, **the tester's commit adds the new scenarios together with
stubs that exist and return an honest empty value**:

- `check_landing` returns a report with status `"ok"` and empty lists;
- `check_landings` returns `[]`;
- `installed_hook_warning` returns `None`.

**The coder's commit replaces the stub bodies.** Scenarios that expect `"ok"` pass against
the stubs. That is intended: they are guards against over-firing, not red tests.

Constraints that hold for every task:

- stdlib only;
- user-facing messages in Italian, which is the file's existing convention;
- trailer keys in English;
- the six existing self-test scenarios stay byte-for-byte unchanged and green.

Order is by dependency and is not optional. **Task 2's measurement gate must pass before
Task 4** wires the blocking hook.

---

### Task 1: The landing check (brief items 2 and 4; ADR §D1, §D2, §D6)

**File:** `scripts/check-merge-integrity.py` only.

**Declarations and scenarios (tester).**

`class LandingReport` has these fields:

- `base`, `head`
- `status`: one of `ok`, `failed`, `cannot_verify`, `usage_error`
- `restores`: a list of `(path, introduced_sha, replaced_sha)`
- `context_deletions`: a list of `(path, added_by_sha)`
- `overridden`: a list of `(path, reason)`
- `skipped_conflicts`: a list of paths
- `note`

`def check_landing(repo, base, head) -> LandingReport` is a stub.

Fixtures and scenarios go in the self-test, each named as below:

- New builder `_build_stale_modify_repo(base_dir, squash)`. The base has `shared.txt` and
  `kept.txt`. Branch `old` changes `shared.txt` and adds `oldfile.txt`. `main` changes
  `shared.txt`, changes `kept.txt` (the #515 analogue) and adds `added-by-main.txt`. `old`
  merges `main`, resolves the real `shared.txt` conflict by hand, and then takes
  `kept.txt` back from its own side and removes `added-by-main.txt`. With `squash=True`,
  the builder then runs `git reset --soft main && git commit`, which is the idiom from
  ADR Context.
- **L1, squashed stale restore.** `check_landing(main, squashed)` returns `failed`.
  `restores` names `kept.txt` only, with `replaced_sha` equal to `main`'s commit.
  `shared.txt`, `oldfile.txt` and the deletion are not in `restores`.
  `context_deletions == [("added-by-main.txt", <main's commit>)]`.
- **L2, the same fixture without the squash.** `check_landing(main, merge)` gives the
  identical `restores`, which shows the result does not depend on the merge method. The
  existing `check_merge` on that merge commit also returns `failed`: both checks fire.
- **L3, `git checkout <old-rev> -- kept.txt` on a branch on top of `main`, committed.**
  Returns `failed` on `kept.txt`.
- **L4, legitimate concurrent edit.** A multi-line file; `main` edits one line and the
  branch edits another. Tested once as an unmerged branch and once squashed onto `main`.
  Returns `ok` with no restores.
- **L5, pins ADR §D8's pure-deletion residual.** The existing
  `_build_wholesale_ours_repo` fixture, whose stale merge only *drops a file `main`
  added*, evaluated as a landing into `main`. Returns `ok`, with `restores == []`. A
  future change that starts failing deletions then has to be a conscious one.
- **L6, override accepted.** `Restore-override: kept.txt` plus a reason, placed on the
  squashed commit, returns `ok` with `overridden` set. Placed instead on an extra empty
  commit in the range, it also returns `ok`.
- **L7, override rejected.** `Restore-override: all` returns `usage_error`. Paths without
  `Restore-override-reason:` also return `usage_error`.
- **L8, keys are separate.** A `Merge-override: kept.txt` trailer plus a reason on the
  squashed commit still returns `failed`.
- **L9, fresh base vs stale base (ADR §D3).** On `main`, `kept.txt` goes v1 → v2, and
  then a deliberate commit restores v1. A PR branch cut at the v2 commit later merges
  `main`. `check_landing(v2_commit, head)` returns `failed`: the misattribution the job's
  base choice exists to avoid. `check_landing(main_tip, head)` returns `ok`.
- **L10, conflicted landing.** `HEAD` does not descend from `BASE`. It conflicts on one
  path and restores another. The conflicted path appears in `skipped_conflicts`, and the
  restore is still reported as `failed`. This exercises `merge_tree` returning rc 1.
- **L11, standalone deletion.** A branch on `main` deletes a file `main` added one commit
  earlier, and restores nothing. Returns `ok`, with `context_deletions == []`.

**Bodies (coder).**

- `check_landing` follows ADR §D2 steps 1–8 exactly:
  - `merge-base --is-ancestor` fast path; `merge_tree()` otherwise;
  - `git diff-tree -r -z --raw --no-renames`;
  - one `git log --first-parent --diff-merges=first-parent --root --raw -z --no-abbrev
    --no-renames BASE`, parsed and filtered in Python;
  - trailers parsed from `git rev-list BASE..HEAD`.
- `parse_overrides(repo, sha)` becomes `parse_overrides(repo, sha,
  prefix=OVERRIDE_PREFIX, reason_prefix=OVERRIDE_REASON_PREFIX)`. Its one existing call
  site in `check_merge` stays unchanged. New constants: `RESTORE_OVERRIDE_PREFIX`,
  `RESTORE_OVERRIDE_REASON_PREFIX`.
- CLI: `--landing BASE HEAD` (`nargs=2`). It is mutually exclusive with `--range`,
  `--pr-base` and `--pr-head`. Exit codes are 0, 1 and 2, as in ADR §D2 step 8.
- `print_landing_report` shows:
  - the resolved base and head;
  - restores grouped by replacing commit, with that commit's subject;
  - context deletions;
  - the number of skipped conflicts;
  - on failure, a ready-to-paste trailer block listing every failing path.
- Update the module docstring's `Uso:` block and the `argparse` description.

**Contract change: extension only.** Existing flags, their output format and their exit
codes do not change. The only in-file consumer of `parse_overrides` is `check_merge` (grep:
line 228), and it keeps its current call.

**Done when:** `python3 scripts/check-merge-integrity.py --self-test` passes, covering all
old scenarios plus L1–L11.

### Task 2: Audit mode and the re-measurement gate (brief items 1 and 4; ADR §D4)

**File:** `scripts/check-merge-integrity.py`, plus an "Implementation notes" section
appended to `docs/adr/0062-landing-check-closes-the-squash-gap.md`.

**Tester.**

- Stub `def check_landings(repo, range_spec) -> list[LandingReport]`.
- Scenario **A1**: a scratch repo with three first-parent landings, the third of which
  restores a path. The result is exactly one `failed` report, attributed to that third
  commit.

**Coder.**

- Iterate over `git rev-list --first-parent --reverse RANGE` and call
  `check_landing(repo, L^1, L)` for each commit. Skip a parentless commit with an explicit
  note.
- Print a summary line that counts landings examined, failed, and cannot-verify.
- CLI: `--landings RANGE`, mutually exclusive with the other modes.
- Keep a single classification function; do not add a second fast-path implementation of
  the rule. If a single pass turns out to be needed for speed, it must call the same
  classifier.

**Measurement, recorded in the ADR's implementation notes.**

- `python3 scripts/check-merge-integrity.py --landings "$(git rev-list --max-parents=0
  origin/main)..origin/main"`. At `e5ba01a` it must report exactly 6 failures:
  - `ab36722` (#196, `.claude/test-cmd`);
  - `32bfea7` (#201, 16 paths, plus 8 context deletions added by `9f6ff14`);
  - `1d9d7b2` (#202, 21 paths);
  - `d778cda` (#306, `.claude/test-cmd`);
  - `390613f` (#519, exactly the 13 paths `CLAUDE.md`, `Sources/App/PergamenumApp.swift`,
    `Sources/Connector/VaultWrites.swift`, the two `Diary` files, the two `Workspace`
    files, the five `VaultSession+*.swift` files and `Tests/WorkspaceAutosaveRaceTests.swift`,
    all replaced by `5a6dec9`, plus context deletions `Tests/DiarySettleTests.swift`,
    `Tests/VaultUnguardedWriteGuardTests.swift` and `docs/adr/0060-…md`);
  - `4079c46` (#521, 16 paths).
- Zero failures among the 30 non-merge landings.
- Any landing that reached `main` after `e5ba01a` and is flagged must be classified by hand
  in the notes. It must not be waved through.
- Re-run the existing full-history merge scan,
  `--range "$(git rev-list --max-parents=0 origin/main)..origin/main"`. It must still fail
  exactly `14d8851` and `7b984f1`. This proves the `parse_overrides` refactor left the
  merge mode alone.

**GATE.** If the tool's result differs from the six above (more flags, fewer flags, or
different paths), **stop before Task 4**. Reconcile the difference and report to Stefano.
ADR Context names this measurement as the thing that would reverse the decision to block.

### Task 3: The workflow steps (brief items 3 and 5; ADR §D3, §D7)

**File:** `.github/workflows/merge-integrity.yml`.

- Add a step **"Check landing (pull_request)"**.
  - `if: ${{ !cancelled() && github.event_name == 'pull_request' }}`, so a red merge scan
    does not hide it.
  - `env:` carries `BASE_REF: ${{ github.event.pull_request.base.ref }}`,
    `PR_BASE_SHA` and `PR_HEAD_SHA`.
  - Resolve `base="$(git rev-parse --verify "refs/remotes/origin/$BASE_REF")"`.
  - Print `git --version`, the event's `PR_BASE_SHA` and the resolved base.
  - Run `python3 scripts/check-merge-integrity.py --landing "$base" "$PR_HEAD_SHA"`.
- Add a step **"Check landing (push to main)"**.
  - `if: ${{ !cancelled() && github.event_name == 'push' }}`.
  - Use the same `before`/`after`/`forced` inputs as the existing step. `base` is `before`
    normally, or `$(git rev-parse "${after}^1")` when `before` is all-zeros or `forced`
    is true.
  - Run `--landing "$base" "$after"`.
- Leave `workflow_dispatch` unchanged. Any range covering the historical hits would be red
  forever (ADR §D4).
- Update the header comment to name ADR-0062, the landing check, and why the PR step
  ignores `base.sha`.
- There is no `paths-ignore`, which stays as ADR-0061 §D2 decided.

**Verification.** Actions cannot be run locally, so this chain's own PR is the first run,
in ADR-0044 §D13's discovery sense. Its log must show both the event `base.sha` and the
resolved `origin/main` sha, and a clean landing. The `push: main` step is checked on the
merge commit's run after landing. If `actionlint` is installed (`command -v actionlint`),
run it on the file. If it is not, say so rather than claiming the YAML was validated.

### Task 4: The pre-push hook and the stale-hook warning (brief item 3; ADR §D5), only after Task 2's gate

**Files:** `scripts/git-hooks/pre-push`, `scripts/check-merge-integrity.py`.

**Tester.**

- Stub `def installed_hook_warning(installed_path, tracked_path) -> str | None`.
- Scenario **H1**: identical files give `None`. A missing installed file gives `None`.
  Differing files give a message that names `scripts/install-git-hooks.sh --force`.

**Coder (checker).** In `main()`, outside `--self-test`, call `installed_hook_warning` with
`$(git rev-parse --git-common-dir)/hooks/pre-push` and `<toplevel>/scripts/git-hooks/pre-push`.
Print the warning once when it is non-`None`. In CI no hook is installed, so nothing is
printed. Remember that the currently installed ADR-0061 hook calls the checker's `--range`
mode, so the warning must fire in that mode too.

**Coder (hook).**

- Read the remote name from `$1`.
- For each stdin line:
  - Keep the existing merge scan unchanged.
  - Skip the landing check when `local_sha` is all-zeros or `remote_ref` is not
    `refs/heads/*`.
  - Set `BASE`: use `remote_sha` when `remote_ref` is `refs/heads/main` and non-zero;
    otherwise use `refs/remotes/$1/main`.
  - If `BASE` does not resolve, or `git cat-file -e "$BASE^{commit}"` fails, print a
    notice and skip; do not block.
  - If the checkout's checker does not contain `--landing` (use `grep -q -- '--landing'`),
    print a notice and skip; do not block.
  - Otherwise run `python3 "$checker" --landing "$BASE" "$local_sha"`, printing the base it
    used.
- The refusal message names both trailer forms and says which check failed.
- Update the header comment.

**Verification (manual, in a scratch clone with a throwaway bare remote, never against
`origin`).** The ADR-0061 §D3 procedure: install the hook into the **scratch clone's own**
common dir by running that clone's copy of `scripts/install-git-hooks.sh`, then push and
confirm each of the following:

1. A squashed stale restore (L1's shape) is refused, and the output names the path and
   prints the trailer block.
2. The same push with a `Restore-override` trailer is accepted.
3. A clean squash (L4's shape) is accepted.
4. ADR-0061's bad-merge push is still refused (regression check).
5. A tag push skips the landing check.
6. A branch checked out at a commit whose script lacks `--landing` prints the notice and is
   not blocked.
7. With `refs/remotes/<remote>/main` missing, the push prints the notice and is not blocked.
8. With the **old** ADR-0061 hook installed and the new checker, every push prints the
   reinstall warning.

Record the results in ADR-0062's implementation notes. Do **not** run
`scripts/install-git-hooks.sh --force` in the real repository as part of this task. That is
a HITL step (see below).

### Task 5: Update the call-sites and docs that assert the old behaviour (all items; ADR §D5, §D6)

The observable contract changes in three ways:

- the checker gains two modes;
- the pre-push hook gains a blocking condition;
- the guard's documented gap closes.

Grep run for this plan: `rg -l --hidden -g '!.git' "check-merge-integrity|merge-integrity|install-git-hooks|Merge-override|git-hooks/pre-push"`
(`--hidden` is needed because `.github/` is otherwise skipped). It found exactly these files,
and nothing under `Tests/`, `UITests/` or `Sources/`:

- `.github/workflows/merge-integrity.yml`: Task 3.
- `scripts/git-hooks/pre-push`: Task 4.
- `scripts/check-merge-integrity.py`: Tasks 1, 2 and 4. Its six existing scenarios are the
  only tests that assert the old behaviour, and they must stay unchanged and green.
- `scripts/install-git-hooks.sh:3-6`: the header comment names only the merge check. Add the
  landing check and the fact that upgrading from the ADR-0061 hook needs `--force`. No logic
  change.
- `CLAUDE.md:145`: the `--self-test` comment says "ADR-0061's own assertions". Name ADR-0062
  too, and add one Commands line for the `--landings` audit.
- `CLAUDE.md:146`: the installer comment. Add "rerun with `--force` after a hook change".
- `CLAUDE.md:217-226`: the "A merge commit that silently discards…" working agreement. Add
  one sentence on the landing check and `Restore-override: <path>` plus
  `Restore-override-reason:`, placed on any commit in the PR's own range. Say that it is
  separate from `Merge-override`.
- `CLAUDE.md:494`: the ADR-0061 index entry's closing clause, "Known gap, named not fixed: a
  squash or rebase merge bypasses the check entirely (§D5)", becomes false. Point it at
  ADR-0062, and add an ADR-0062 index entry right after it.
- `docs/adr/0061-merge-integrity-guard.md` §D5: this is history and its body is not
  rewritten. An **optional** one-line forward pointer ("Closed by ADR-0062") is for Stefano
  to accept or drop.
- `docs/adr/0062-landing-check-closes-the-squash-gap.md`: status `proposed` → `accepted` at
  merge, plus the implementation notes from Tasks 2 and 4.
- `TODO.md:7` (PG-242): closed at ship, citing ADR-0062. It is not edited by the coder
  mid-chain.

**Full-suite recommendation.**

- After Task 4, run `--self-test`, both full-history measurements from Task 2, and
  `bash -n scripts/git-hooks/pre-push scripts/install-git-hooks.sh`.
- The Stop hook's `PergamenumTests` run is unaffected, since no Swift is touched, but it
  must stay green like any other turn.
- The UI suite is not relevant to this change.

---

## Risks and HITL gates

- **HITL: reinstall the hook.** After this merges, every machine with the ADR-0061 hook needs
  `scripts/install-git-hooks.sh --force` to get the landing check. The installer cannot tell
  its own older copy from a foreign hook. Until the reinstall, the checker prints a warning
  on every push (Task 4). That is Stefano's action, not an agent's.
- **HITL: check a repository setting before trusting the post-hoc step.**
  `gh api repos/istefox/Pergamenum --jq '.squash_merge_commit_message'`. The
  unauthenticated API does not expose it, so it is not verified. If the answer is
  `PR_BODY` or `BLANK`, an overridden restore that lands by squash will be reported again,
  advisory only, by the `push: main` step. Record the answer in the ADR notes.
- **HITL: decisions for Stefano, from ADR Open questions.**
  - Branch protection with `merge-integrity.yml` as a required check. Not reopened; the
    recommendation is no for this chain.
  - Blocking at pre-push rather than advisory. Recommended blocking; it can be overturned.
  - The optional ADR-0061 forward pointer.
- **HITL: commit, push, PR, merge.** These follow the usual gates. This chain's own PR is the
  first live run of the new workflow steps (Task 3).
- **Measurement gate (Task 2).** If the tool does not reproduce the six historical flags,
  stop before wiring the blocking hook.
- **Friction on legitimate work.** Deliberate reverts, re-lands and repairs, and a small
  file toggled back (`.claude/test-cmd`), each need a `Restore-override` block. Measured at
  5 of 412 landings. Agents that meet a refusal must add the trailer with a real reason and
  must never use `--no-verify`.
- **Self-inflicted false positive.** If `/build` writes the TEST-CMD candidate below into
  `.claude/test-cmd` and a later chain puts the old command back, that restore is exactly
  the measured false-positive class. Don't commit the candidate into `.claude/test-cmd` (see
  below).
- **ADR number race.** `0062` was free on every ref at `d630941`. A parallel unpushed chain
  could also take it. This has happened before: 0061 is used twice.
- **Pre-existing, not fixed here.** `merge-integrity.yml`'s `workflow_dispatch` step scans
  `origin/main~200..HEAD`. That range contains `14d8851` (2026-09-25, newer than
  `origin/main~200` = `357eeef`, 2026-09-14), so every manual dispatch exits 1 on a known
  historical hit. This is derived from the range definition, not from observing a run.
  Worth its own small issue, and not folded into this chain.
- **No external resources.** No third-party API, OAuth, cloud console, environment variable
  or port is needed before `/build`. The checker is stdlib Python and git ≥ 2.38, which
  ADR-0061's `merge-tree --write-tree` already requires.

## TEST-CMD

`TEST-CMD CANDIDATE: python3 scripts/check-merge-integrity.py --self-test`
`TEST-CMD MODE: brownfield`

Reasoning:

- The chain touches only `scripts/` (Python, shell), `.github/workflows/` and docs. The
  project's `xcodebuild … -only-testing:PergamenumTests test` cannot go red or green because
  of any of it, so as this chain's red/green signal it would report green on a broken
  detector.
- `--self-test` already exists, runs now, and exits 1 on any failed assertion
  (`return 1 if failed else 0`). Tasks 1, 2 and 4 add their red scenarios to it.
- There is no `.venv` and there are no dependencies, so the command needs no activation
  prefix.
- The xcodebuild command stays the repository's `.claude/test-cmd` for the Stop hook and
  must **not** be replaced by this candidate in the tracked file.
