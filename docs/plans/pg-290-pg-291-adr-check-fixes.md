# Plan: PG-290 and PG-291, two fixes to the ADR reference check

- **Brief:** issues #623 (`PG-290`) and #624 (`PG-291`), both P4 fixes found in review of PR #611.
  No SPEC applies: the root `SPEC.md` belongs to the shipped Pratiche sync chain and is not read
  here. The two fix directions each issue names are settled. Where an issue offers two, this plan
  picks one and gives the evidence (D1, D2).
- **ADR outcome: no new ADR.** Both changes complete contracts that are already written down, and
  each can be reverted in one commit, so neither is hard to reverse:
  - PG-290: `rule_one`'s own docstring says rule 2's «proposed on the base» leaves alone the numbers
    rule 1 reports. It only did that for one of rule 1's two shapes.
  - PG-291: exit 2 for bad usage is already the documented exit contract of both scripts (ADR-0061
    §D1, the `docs/adr/README.md` «Checking the rules» section).

  One choice here could get "fixed" back by a later reader: rule 2 keeps matching by number, even
  though the issue's title calls that the defect (D1). That override was considered. It is met the
  way the PG-273 plan met its own explicit «no», which was approved at its gate G1. The decision is
  written in the function docstring and in the README section a reader of this checker consults.
  Two self-test checks fail if it is switched, and their descriptions say why.
  ADRs that govern parts of this work, cited unchanged:
  - **ADR-0061 §D1:** a self-tested stdlib script with exit 0/1/2. An abbreviated option becomes
    exit 2, "bad usage", inside that contract.
  - **ADR-0062**, the hook section: the installed pre-push hook is a copy that calls the live
    checker with full option names (`--range`, `--landing`). Nothing here changes the hook, so no
    reinstall is needed.
  - **ADR-0044 §D11:** CI stays advisory, and no workflow changes.
- **Baseline:** `HEAD` = `origin/main` = `38fabc0d`, read on 2026-09-28. Every line number, count
  and output below was read from that tree or produced by running the two scripts. None comes from
  the issue text.
- **Scope:** `scripts/check-adr-references.py`, `scripts/check-merge-integrity.py`,
  `docs/adr/README.md`, and this plan. No Swift, no `Project.swift` and no `tuist generate`. No hook,
  workflow, `CLAUDE.md` or `.claude/test-cmd` change. `TODO.md` is not touched in this chain (see
  «After the merge»).
- **UI budget:** zero GUI tests. The UI doesn't change.
- **Id spaces:** the self-test's existing labels `R-01`…`R-08` are PG-273's requirement ids and
  keep that meaning. The new checks are labelled `PG-290` and `PG-291`, the way
  `check-merge-integrity.py` labels `PG-244` and `PG-248`. The `R-01`…`R-06` below are this plan's
  own ids and never appear in self-test output.

## Before `/build` (orchestrator; each item is a HITL point)

1. **Branch:** this worktree is on `chore/todo-sync-625`. Cut `fix/adr-reference-check-pg-290-pg-291`
   from `origin/main` before any edit.
2. **Bring `origin/main` in:** `git fetch origin`. If `origin/main` moved past `38fabc0d` and
   touched either script or `docs/adr/README.md`, re-run block B. Stop if a value differs.
3. **Commit gates.** Every commit and the push are HITL. Recommended boundaries: this plan; PG-290
   (Tasks 1, 2 and 5 together); PG-291 (Tasks 3 and 4 together). Never commit the red state that
   Task 1 or Task 3 leaves on its own, because `adr-references.yml` runs the self-test on every PR
   push.

Block B (bash, from the repo root; expected values on `38fabc0d`):

```bash
git rev-parse --short origin/main                                    # 38fabc0d
sed -n '321,322p' scripts/check-adr-references.py                    # elif word == "proposed" ... and number not in against_base:
sed -n '1158p' scripts/check-adr-references.py                       # if "--self-test" in argv:
sed -n '1384p' scripts/check-merge-integrity.py                      # if "--self-test" in argv:
grep -n 'against_base' scripts/check-adr-references.py | cut -d: -f1 | tr '\n' ' '   # 209 215 225 226 300 322 523 524
python3 scripts/check-adr-references.py --self-test | head -1        # ...: 42 checks, 0 failed
python3 scripts/check-merge-integrity.py --self-test | head -1       # ...: 49 controlli   (about 60 s)
python3 scripts/check-adr-references.py --self; echo $?             # the real check's summary line, then 0 (the defect)
python3 scripts/check-merge-integrity.py --self; echo $?             # "nessun merge commit in origin/main..HEAD", then 0 (the defect)
```

## Evidence

**PG-290, reproduced** in throwaway repositories built with the self-test's own `_Lab` helpers,
`--base main`:

| Shape | Today | Option A (file name) | Option B (skip rule 1's numbers) |
|---|---|---|---|
| PR merge: branch `0003-bar.md` proposed, `main` `0003-foo.md` accepted, HEAD a merge of both | rule 1: 1, **rule 2: 1** (on `0003-bar.md`) | rule 2: 0 | rule 2: 0 |
| Same, `main`'s `0003-foo.md` reads proposed | rule 1: 1, **rule 2: 2** (both files) | rule 2: 1 (`0003-foo.md`) | rule 2: 0 |
| Branch `0003-bar.md` proposed against `main`'s `0003-foo.md`, no merge | rule 1: 1 (against the base), rule 2: 0 | rule 2: 0 | rule 2: 0 |
| Slug rename `0001-foo.md` → `0001-bar.md` of an ADR reading proposed on the base | rule 2: 1 | **rule 2: 0** (lost) | rule 2: 1 |

Row 1 is the defect. With `actions/checkout`'s default PR ref, HEAD is the merge commit and the
merge-base with `origin/<base.ref>` already holds `main`'s file. Rule 1's base check therefore skips
the number (`number in merge_base_held`, line 217), `against_base` stays empty, and rule 2 fires. A
branch that merged `origin/main` in, which is this repository's habit, has the same sets. Row 3 is
already right, through `against_base`. Option B was also run on a scratch copy of the script:
42 of 42 existing checks are green and every row gives the value in the last column.

**PG-291, reproduced on the real tree:** `check-adr-references.py --self` printed the real check
(rule 1: 0, rule 2: 0, rule 3: 0 findings; 2 warnings) and exited 0. `check-merge-integrity.py
--self` printed `nessun merge commit in origin/main..HEAD` and exited 0. Both read as a passed
self-test. With `allow_abbrev=False` on scratch copies: `--self` and `--verb` exit 2 on both
scripts. `--base=origin/main`, `--landing origin/main HEAD` and `--range origin/main..HEAD
--verbose` behave as before. The merge checker's 49 self-test checks stay green. Local
`/usr/bin/python3` is 3.9.6. The documented behaviour of `allow_abbrev` for long options was checked
against the Python 3.14 argparse documentation: long options are matched exactly, and a prefix is an
error.

**Callers of both scripts, every flag spelling in the tree** (`rg` over the repo): `--base`,
`--landing`, `--landings`, `--pr-base`, `--range` and `--self-test`, plus `--pr-head` and
`--verbose` in the workflows. No caller uses an abbreviation. The call sites are:

- `scripts/git-hooks/pre-push:75` (`--range`) and `:107` (`--landing`);
- `.github/workflows/merge-integrity.yml:65-68`, `:88`, `:105`, `:128`, `:134`, `:145`;
- `.github/workflows/adr-references.yml:43`, `:59`, `:65`;
- the `CLAUDE.md` «Commands» block and `docs/adr/README.md` «Checking the rules».

## Decisions

- **D1. PG-290 takes option B: rule 1's reported numbers include its in-tree duplicates.** Rule 2
  keeps matching a file to the base by number. Reasons:
  - It completes the mechanism the code already has and documents. `rule_one` returns the numbers
    it reports so that rule 2 leaves them alone (lines 205-207), but it only collected the
    against-the-base shape. Option A would make that set dead and require deleting it across three
    functions.
  - Rule 1 treats a slug rename of a merge-base number as the same record: PG-273's R-02 pass
    scenario exits 0. Option A would have rule 2 treat that file as a different record, so the two
    rules would disagree on identity. The last row of the evidence table shows what that costs:
    today's finding on a slug-renamed proposed ADR is lost.
  - B also has a cost. While rule 1 reports a number, a file at that number the base really holds
    and that reads `proposed` is not flagged (row 2). That only happens on a run that is already
    red (exit 1) at that number. Every run without the collision flags the file: every other PR,
    and the push-to-`main` run. When `main` itself carries the duplicate (the 0061 incident's
    shape), the finding waits for the renumbering that rule 1 demands anyway. This residual is
    written in the README (Task 5).
- **D2. PG-291 takes `allow_abbrev=False`, not a post-parse rejection of `args.self_test`.** A
  post-parse rejection closes only `--self…`. `--verb`, `--bas`, `--ran` and `--pr-b` stay accepted
  by prefix. In the merge checker, which the pre-push hook runs, a prefix can also change meaning
  when a flag is added (`--landing` and `--landings` already share one). One keyword closes the
  whole class, and no caller uses a prefix.
- **D3. The fix goes into `check-merge-integrity.py` too.** Its shape is the same: a literal guard
  at `:1384` and a default-abbreviation parser at `:1340`. The defect reproduces there. Its callers
  all pass full names, and the hook file does not change: it calls the checkout's live checker, and
  `_hook_warning_for_cwd` compares the hook files, not the checker. So no
  `scripts/install-git-hooks.sh --force` is needed, and ADR-0062's old-checkout guard (`grep -q --
  '--landing'`) is unaffected. `scripts/appcast.py` was checked too. It is not affected, because it
  routes `args.self_test` after parsing, so `--self` there runs its self-test.
- **D4. No post-parse `args.self_test` check is added.** Once `allow_abbrev=False` is set,
  `args.self_test` can be true only when the literal `--self-test` is in `argv`, and the existing
  guard returns before parsing in that case. A second check would be unreachable. The literal
  guard stays as it is, because it is what refuses `--self-test` combined with anything else.
- **D5. `.claude/test-cmd` stays as it is.** The file is tracked, and ADR-0062's audit counts two
  toggles of it among the six flagged historical landings. Adding the merge checker's 60-second
  self-test to a Stop hook that runs every turn is the cost `CLAUDE.md` warns about. The Python
  self-tests run as this plan's own verification (Task 6). CI runs the ADR check's self-test.

## Ownership and order

- Tasks 1 and 3 (tester) write failing-first checks. Tasks 2 and 4 (coder) make them green. Python
  is not compiled, so a red check is reported by the self-test itself, not by a failed build.
- Progression of `check-adr-references.py --self-test`:
  - after Task 1: 46 checks, 2 failed;
  - after Task 2: 46 checks, 0 failed;
  - after Task 3: 48 checks, 2 failed;
  - after Task 4: 48 checks, 0 failed.
- Progression of `check-merge-integrity.py --self-test`: 51 controlli with 2 FALLITO after Task 3,
  then 0 FALLITO after Task 4.
- Task 5 can follow Task 2 directly. Task 6 is last.

---

### Task 1 — PG-290's failing-first scenario (R-01, R-02, R-05; tester)

Files: `scripts/check-adr-references.py`, self-test section only.

Add one fixture helper and one scenario:

- `_pr_merge_repo(lab, main_status)` builds the PR shape:
  1. `lab.repo("pg290-pr-merge")`, then `adr(repo, 1, "x")`, committed as the base;
  2. branch `feature` adds `adr(repo, 3, "bar", "- Status: proposed")`;
  3. `main` adds `adr(repo, 3, "foo", main_status)`;
  4. `checkout -q -b pr main`, then `merge -q --no-ff -m "pr merge ref" feature`. The two paths
     differ, so the merge never conflicts.
- `_scenario_pg290(lab)` holds four checks, all `lab.check("PG-290", "fail", …)`, all run with
  `--base main`. It goes in `SCENARIOS` directly after `_scenario_r04`.

| # | Fixture | Expected | Today |
|---|---|---|---|
| 1 | `_pr_merge_repo(lab, "- Status: accepted")` | exit 1; one `rule 1` line naming `0003-bar.md` and `0003-foo.md`; no `rule 2` line | red (one rule 2 line) |
| 2 | `_pr_merge_repo(lab, "- Status: proposed")` | exit 1; one `rule 1` line; no `rule 2` line | red (two rule 2 lines) |
| 3 | `_collision_repo`'s shape with the branch's `0003-bar.md` reading proposed, HEAD on `feature`, no merge | exit 1; one `rule 1` line containing `held on main`; no `rule 2` line | green |
| 4 | base `0001-foo.md` reading proposed; branch `git mv` to `0001-bar.md`, still proposed | exit 1; no `rule 1` line; exactly one `rule 2` line, starting `docs/adr/0001-bar.md:` | green |

Description texts. Checks 1 and 2 must start with `PR merge shape`, which R-01's grep counts:

1. `PR merge shape, a proposed 0003-bar.md beside main's accepted 0003-foo.md: exit 1, one rule 1
   line, no rule 2 line`
2. `PR merge shape, main's own 0003-foo.md reading proposed: exit 1, rule 1 owns a number it
   reports, no rule 2 line`
3. `a proposed 0003-bar.md against main's 0003-foo.md, no merge: exit 1, one rule 1 line, no rule 2
   line`
4. `slug rename 0001-foo.md -> 0001-bar.md of an ADR reading proposed on the base: exit 1, one rule
   2 line (rule 2 matches by number, as rule 1 does)`

Checks 3 and 4 are green today on purpose. Check 3 is the only check that proves rule 2 skips the
against-the-base shape: PG-273's collision fixture uses an `accepted` file. Check 4 pins D1 against
a later switch to file-name matching. Use `findings(out, n)` for every count, never a bare
substring: the summary line also contains `rule 2:`.

### Task 2 — PG-290's fix: rule 1 reports every number it finds, in the tree too (R-01, R-02; coder)

Files: `scripts/check-adr-references.py`.

- In `rule_one`'s in-tree loop (lines 210-213), add the duplicated number to the returned set.
- Rename `against_base` to `reported`, because its meaning widens. There are eight occurrences:
  lines 209, 215, 225, 226, 300 (the `rule_two` parameter), 322, 523 and 524. The return type does
  not change.
- `rule_one`'s docstring (lines 205-207) says that the set now holds every number rule 1 reports,
  in the tree or against the base. It also says why rule 2 leaves those numbers alone: the collision
  is already the finding, and a file that never landed must not be told to flip to `accepted`
  (PG-290).
- The module docstring's rule 2 bullet (lines 16-17) becomes: an ADR the base holds, **matched by
  number**, that still reads `proposed` is a finding, **unless rule 1 reports that number**.
- The finding's message (lines 323-325) stays. PG-273's R-04 check asserts `proposed` in it.

### Task 3 — PG-291's failing-first checks in both self-tests (R-03, R-04, R-05; tester)

Files: `scripts/check-adr-references.py` and `scripts/check-merge-integrity.py`, self-test sections
only.

- **`check-adr-references.py`:** add `_scenario_pg291(lab)` to `SCENARIOS` after `_scenario_cli`.
  It runs in one clean lab repository (`lab.repo("pg291")` plus `adr(repo, 1, "x")`, committed).
  Both checks are `lab.check("PG-291", "fail", …)`, the kind the existing unknown-option check
  uses for exit 2.
  1. `lab.cli(repo, "--self")`: the check passes when the exit is 2, `_no_traceback(err)` holds and
     `"rule 1:"` is not in `out`. Description: `--self, an abbreviation of --self-test: exit 2, the
     check does not run`. Today it exits 0 and prints the summary, so the check is red.
  2. `lab.cli(repo, "--verb")`: same assertions. Description: `--verb, an abbreviation of
     --verbose: exit 2, no long option is matched by prefix`. Red today.
- **`check-merge-integrity.py`:** add `_scenario_cli_abbreviations(base_dir, report)`. Append it to
  `self_test()`'s call list after `_scenario_cli_range_unresolvable` (line 1322). The repository is
  `_init_repo`, one committed file, then `_sh(repo, "update-ref", "refs/remotes/origin/main",
  "HEAD")`. That ref is load-bearing: without it, today's `--self` falls into `--range
  origin/main..HEAD` and exits 2 for the wrong reason ("range non risolvibile"), so the check would
  not be red first.
  1. `_run_cli(repo, "--self")`: the check passes when the exit is 2, `"Traceback"` is not in
     stderr, and neither `nessun merge commit` nor `merge esaminati` is in stdout. Description
     `PG-291: --self, abbreviazione di --self-test: exit 2, il controllo non gira (trovato: %d)`.
     The file's descriptions are in Italian, like the PG-244 and PG-248 checks.
  2. `_run_cli(repo, "--verb")`: same assertions. Description `PG-291: --verb, abbreviazione di
     --verbose: exit 2 (trovato: %d)`.
- Do not assert argparse's message text. Its wording is not something this repository controls, and
  the existing unknown-option check asserts only the exit code and the absence of a traceback.
- **Recursion safety:** writing these checks red first is safe. Today `--self` runs the real check,
  not the self-test. See the Task 4 prohibition.

### Task 4 — PG-291's fix: exact long options in both parsers (R-03, R-04; coder)

Files: `scripts/check-adr-references.py` and `scripts/check-merge-integrity.py`.

- `build_parser()` in both scripts passes `allow_abbrev=False` to `argparse.ArgumentParser(`
  (`check-adr-references.py:1138`, `check-merge-integrity.py:1340`). Add a one-line comment naming
  why: a prefix such as `--self` must not run the real check and exit 0 as if a self-test passed
  (PG-291).
- `main()`'s literal `--self-test` guard (`:1158-1163` and `:1384-1388`) is unchanged. Per D4, no
  post-parse check is added.
- **Prohibited:** routing `args.self_test` to `self_test()`. Task 3's checks call `--self` from
  inside the self-test, so that routing would make the self-test start itself again, level after
  level.

### Task 5 — Call sites and docs that assert the old behaviour (R-02, R-04, R-06; coder)

Files: `docs/adr/README.md`.

- **Docs:** in «Checking the rules», append this to the paragraph that starts «It checks less of
  rule 2 than the rule says» (lines 62-66), wrapped at the file's width:

  > The base's ADRs are matched by number, the identity rule 1 counts, so an ADR whose slug the
  > branch renamed is still checked. A number rule 1 reports, in the tree or against the base, is
  > not checked for `proposed` until the collision is resolved: the collision is already a
  > finding, and a file that never landed must not be told to flip to `accepted`.

  PG-291 needs no README change. «2 … bad usage» already covers an abbreviation.
- **Call sites (staleness rule):** the grep in «Evidence» found no caller of either script that
  uses an abbreviation, so nothing else is edited. Re-run it after the fetch:

  ```bash
  rg -n --no-heading -o 'check-(adr-references|merge-integrity)\.py( +--?[A-Za-z][A-Za-z-]*)+' \
    scripts .github CLAUDE.md docs/adr | grep -oE ' --?[A-Za-z][A-Za-z-]*' | sort -u | tr '\n' ' '
  # only full names: --base --landing --landings --pr-base --range --self-test
  rg -n --no-heading 'checker" +--' scripts/git-hooks/pre-push    # :75 --range, :107 --landing
  ```

  The search leaves out `docs/plans`, since this plan quotes `--self` on purpose. The workflows'
  `--pr-head` and `--verbose` sit on continuation lines the pattern does not cross, and they were
  read by hand.

  No existing self-test check asserts the rule 2 pile-on. Option B left all 42 green on a scratch
  copy.
- The hook and the workflows are not edited. R-04's check proves it.

### Task 6 — Full verification (R-05, R-06; reviewer)

Run the acceptance block below, all of it, not only the new checks. A change to an exit or output
contract can break a check that was not part of the change. The merge checker's self-test takes
about 60 seconds, so run it in its own call, and use `run_in_background` when it is chained with
another long command. The Stop hook's unit suite still runs every turn, and nothing here can move
it.

## Requirements

| R-id | Requirement | Acceptance criterion |
|---|---|---|
| R-01 | PG-290's defect: on the PR merge shape, a `proposed` ADR at a number `main` holds under another file name gets rule 1's finding and no rule 2 finding | both `PR merge shape` checks are `ok` (red before Task 2) |
| R-02 | PG-290's decision (D1): rule 2 keeps number identity and leaves alone every number rule 1 reports; a slug-renamed proposed ADR is still reported; the decision is written down | all four `PG-290` checks are `ok`, and the README sentence is present |
| R-03 | PG-291 in `check-adr-references.py`: no long option is matched by prefix | `--self` exits 2 on the real tree, and both `PG-291` checks are `ok` |
| R-04 | PG-291 in `check-merge-integrity.py`, with its hook and workflows unchanged | `--self` exits 2, both `PG-291:` checks are `ok`, and no diff touches the hook or `.github/workflows` |
| R-05 | Every existing self-test check is kept and green | 48 checks, 0 failed, and 51 controlli, 0 FALLITO; every pre-change check line is still printed as `ok` |
| R-06 | The real tree stays clean under the ADR check, including this plan and the README edit | `python3 scripts/check-adr-references.py` exits 0 with 0 findings |

| R-id | Task(s) |
|---|---|
| R-01 | 1, 2 |
| R-02 | 1, 2, 5 |
| R-03 | 3, 4 |
| R-04 | 3, 4, 5 |
| R-05 | 1, 3, 6 |
| R-06 | 5, 6 |

## Acceptance (reviewer; bash, from the repo root, after `git fetch origin`)

```bash
S=scripts/check-adr-references.py
M=scripts/check-merge-integrity.py
T="${TMPDIR:-/tmp}"
mb="$(git merge-base HEAD origin/main)"

# R-01
python3 "$S" --self-test | grep -c '^ok: PG-290 fail: PR merge shape'                  # 2
# R-02
python3 "$S" --self-test | grep -c '^ok: PG-290 '                                      # 4
tr '\n' ' ' < docs/adr/README.md | tr -s ' ' | grep -cF 'is not checked for `proposed` until the collision is resolved'   # 1
# R-03
python3 "$S" --self > /dev/null 2>&1; echo $?                                          # 2
python3 "$S" --self-test | grep -c '^ok: PG-291 '                                      # 2
# R-04 (the self-test takes about 60 s)
python3 "$M" --self > /dev/null 2>&1; echo $?                                          # 2
python3 "$M" --self-test | grep -c '^ok: PG-291:'                                      # 2
git diff --quiet "$mb" -- scripts/git-hooks/pre-push .github/workflows && echo unchanged   # unchanged
# R-05, ADR check: every pre-change line still printed, 48 checks, 0 failed
git show 38fabc0d:"$S" > "$T/car-old.py"
python3 "$T/car-old.py" --self-test | tail -n +2 | sort > "$T/car-old.txt"            # 42 lines
python3 "$S" --self-test | tail -n +2 | sort > "$T/car-new.txt"
comm -23 "$T/car-old.txt" "$T/car-new.txt" | wc -l                                     # 0
python3 "$S" --self-test | head -1                                                     # ...: 48 checks, 0 failed
# R-05, merge check: descriptions compared without their run-dependent "(trovato: …)" tail
git show 38fabc0d:"$M" > "$T/cmi-old.py"
python3 "$T/cmi-old.py" --self-test | tail -n +2 | sed -E 's/ \(trovat[oi]: .*$//' | sort > "$T/cmi-old.txt"
python3 "$M" --self-test | tail -n +2 | sed -E 's/ \(trovat[oi]: .*$//' | sort > "$T/cmi-new.txt"
comm -23 "$T/cmi-old.txt" "$T/cmi-new.txt" | wc -l                                     # 0
grep -c '^FALLITO' "$T/cmi-new.txt"                                                    # 0
wc -l < "$T/cmi-new.txt"                                                               # 51
# R-06
python3 "$S"; echo $?                                                                  # summary "rule 1: 0, rule 2: 0, rule 3: 0 findings", then 0
```

## Risks

- **Self-test recursion:** see the Task 4 prohibition. Only a fix that deviates from D2 can cause
  it.
- **The merge checker's self-test is not hermetic.** `_sh` and `_run_cli` inherit `GIT_*`. This
  predates the chain. Run it from a plain shell, never from inside a git hook. This chain does not
  widen it.
- **Python versions:** local `/usr/bin/python3` is 3.9.6, and CI uses `ubuntu-latest`'s `python3`.
  `allow_abbrev` has behaved the same for long options since 3.8. No check depends on argparse's
  message text.
- **The residual D1 accepts:** row 2 of the PG-290 table. It is named in the README, and the
  finding is deferred, not lost.
- **Parallel chains:** an edit to `docs/adr/README.md` can conflict with a renumbering-register row
  added by another chain. Resolve it by merging `origin/main` in, never by taking one side
  wholesale. The merge-integrity guard refuses a silent side-pick anyway.

## After the merge (orchestrator, HITL)

- The PR body says `Closes #623` and `Closes #624`.
- Close `PG-290` and `PG-291` in `TODO.md` through the usual `chore(tasks)` sync, not in this
  chain's diff, because parallel ledger edits conflict.

## Out of scope, named

- `merge-integrity.yml` never runs `check-merge-integrity.py --self-test`, while
  `adr-references.yml` does run its own. Task 3's two new checks, like the other 49, run only by
  hand. This is worth a follow-up ticket. It is not fixed here.
