# ADR-0062: A landing that restores a version `main` already moved past is refused, whatever the merge method

- Status: proposed. Accepted when the implementing PR merges.
- Date: 2026-09-25. Every count below comes from a read-only walk of `main` at `e5ba01a`
  (412 first-parent landings) in the design session: `git log --first-parent --raw
  --no-abbrev --no-renames` over the whole line, filtered by a throwaway text filter. **Not**
  by the shipped tool, which does not exist yet. Task 2 of the plan re-measures with the tool
  and must reproduce these numbers before the hook is wired.
- **Closes ADR-0061 §D5** (the squash/rebase gap it named and left open). Extends ADR-0061
  §D1–§D4 and amends none of them: the merge-commit check, its trailer and its hook stay
  exactly as they are.
- **Reopens nothing.** No SPEC §14 decision, on-disk format, schema, frontmatter key or tag
  grammar is touched. No `Sources/` or `Tests/` file changes. The unit suite is unaffected.
- **No new exception to CLAUDE.md principle 2.** This is tooling around the repository's own
  git history. Nothing under `Sources/` knows it exists.
- Depends on: ADR-0061 (the detector, trailer and hook this extends), ADR-0044 §D11 (CI stays
  advisory, `main` stays unprotected; not reopened here, see Open questions).
- Plan: `docs/plans/pg-242-landing-check.md`. Issue: PG-242 / GitHub #535.

---

## Context

### The gap, as ADR-0061 §D5 left it

`scripts/check-merge-integrity.py` inspects merge commits. For each one it recomputes the
merge with `git merge-tree` and fails on any path that nothing forced a choice on but that
still took one parent's version wholesale. A branch whose history has **no merge commit**
gives it nothing to inspect. ADR-0061 §D5 named the hole: someone resolves a conflict with a
wholesale `--ours`, then squashes or rebases locally before pushing. The pre-push hook sees no
merge. Neither does the PR-time job, nor the `push: main` job. The stale content lands.

### Which history shapes actually produce the hole

Not every "squash or rebase after a bad merge" is dangerous. Two common shapes fix themselves,
and the real hole is narrower than §D5's wording:

- **`git rebase origin/main` after the bad merge fixes itself.** Without `--rebase-merges`,
  rebase drops merge commits and replays only the branch's own commits onto `main`. The stale
  tree lived only in the dropped merge commit, so `main`'s newer version survives.
- **`git reset --soft <original fork point> && git commit` fixes itself too.** The squashed
  commit's parent is the *old* fork point. Landing it is a three-way merge where the stale
  path is "unchanged since base" on the branch side, so `main`'s newer version wins.
- **Dangerous: a squash onto a base that already contains the newer version.** This is what
  `git reset --soft $(git merge-base HEAD origin/main) && git commit` does after `main` has been
  merged in, and that command is *the* everyday "squash my branch" idiom. After the merge,
  the merge-base is `main`'s tip. The squashed commit sits on top of the newer version and
  carries the stale bytes as an explicit, ordinary change. `git merge --squash <bad-branch>`
  onto current `main` gives the same result. So do `git checkout <stale-rev> -- <path>`
  and copying a file in from a stale worktree. None of these is a merge.

The repository's own hazard profile makes the last shape realistic. ADR-0061's Context
records three parallel sessions re-implementing the same work on stale branches in one week.

### Why no merge-tree comparison can see it

The direction #535 suggested is to compare the PR's resulting tree with an honest `git
merge-tree` of the PR into `main`. On a linear branch that comparison is blind by
construction. When the head descends from the base, `git merge-tree BASE HEAD` returns
exactly `HEAD`'s tree. When it does not, the three-way merge in the dangerous shape above
still takes the squashed commit's stale bytes, because relative to the merge-base they are
the branch's own change. A merge commit makes a claim ("I integrated both parents") that its
tree can contradict. A squashed commit makes no claim beyond its content, so a recomputation
has nothing to disagree with.

The fork point that would expose the staleness is exactly what the squash erased from the
graph. What survives is **`main`'s own record of every version each path ever held**. A stale
snapshot can only reproduce bytes `main` once had. So the evidence has to come from `main`'s
history, not from the branch's history.

### What was measured before deciding

The candidate rule is "a landing sets a path to a blob that the path already held at an
earlier first-parent commit of `main`". It was applied to every one of the 412 first-parent
landings on `main` (382 merge-commit landings, 30 squash or direct commits). Result:
**6 landings flagged.**

| landing | PR | flagged paths | verdict |
|---|---|---|---|
| `390613f` | #519 | 13 modified paths back to their pre-#515 blobs, all superseded by `5a6dec9`; the same landing deletes the 3 files `5a6dec9` added | **the PG-240 incident, a true positive** |
| `4079c46` | #521 | 13 modified + 3 re-added | the deliberate PG-240 repair. Correctly detected, and needs an override |
| `32bfea7` | #201 | 16 modified (plus 8 deletions of files the same superseding landing added) | the deliberate revert of the accidental merge #199. Correctly detected, and needs an override |
| `1d9d7b2` | #202 | 15 modified + 6 re-added | the deliberate re-land of #199's content. Correctly detected, and needs an override |
| `ab36722` | #196 | 1: `.claude/test-cmd` | a one-line per-machine command toggled back to an earlier value. **False positive** |
| `d778cda` | #306 | 1: `.claude/test-cmd` | same file, same shape. **False positive** |

The table gives four findings:

- The rule catches PG-240 on the net effect of landing PR #519. That is independent of
  whether #519 was merged with a merge commit, squashed or rebased. ADR-0061's check caught
  it only through the merge commit `14d8851` inside the branch.
- **None of the 30 squash or direct landings is flagged.** The specific hole in §D5 has
  never occurred in this repository. That rules out the frequency argument for building this;
  the proportionality argument below does not rest on it.
- An ordinary concurrent edit never fires. When a PR and `main` both change a file, the
  landing blob is a three-way combination that `main` never held. In 406 unflagged landings
  there is no case where legitimate work came out byte-identical to an older version.
- Of the 5 flags on legitimate work, 3 are deliberate restores whose reason is worth writing
  down. Only 2 (0.5% of landings, one file) are noise.

### Is it worth building now?

Yes, scoped narrowly. The one-line reason is that the hole is one everyday command away and
the check that closes it is cheap and measured quiet. The measured record does **not** show
that the hole has happened here, and the argument does not depend on it:

- **Severity.** The failure class is silent loss of already-merged work. PG-240 was P1 and
  surfaced by chance.
- **Reachability.** `git reset --soft $(git merge-base HEAD origin/main)` is the standard
  squash idiom, and squash landings are in active use (five on 2026-09-24 alone).
- **Measured cost.** 2 true false positives in 412 landings, plus 3 deliberate restores that
  each need one trailer. The tool prints that trailer ready to paste.
- **Implementation cost.** One mode in an existing stdlib script, two CI steps and a few hook
  lines. No app code.

What would have reversed this: if the measurement had come back noisy, comparable to
ADR-0061's pre-classification rule (6 of 434 flagged, 4 of them false), the right answer
would have been to keep §D5 open. Task 2 re-checks this with the real tool, and the plan
makes wiring the blocking hook conditional on reproducing the table above.

---

## Decision

### §D1 — The unit of detection is the landing, not the merge commit

The new check asks one question about a pair `(BASE, HEAD)`: *if `HEAD` landed on `BASE` now,
would any path go back to a version `BASE`'s own history already moved past?* It reads the
content that would land and `main`'s record of each path. It does not care how the branch's
history is shaped: merge commits, squashes, rebases and hand-copied files all look the same
to it. That shape-independence is what closes §D5. It is also why the check applies to all
three GitHub merge methods: it computes what lands before any button is pressed.

It **complements** ADR-0061's merge-commit check and does not replace it. The two catch
different things. The merge check catches the act: a bad merge commit anywhere in a branch's
history, even one a later commit on the same branch repaired. The landing check catches the
effect: stale bytes about to reach `main`, however they got there. Both run.

### §D2 — The rule, as exact git operations

Inputs: two commit-ish revisions `BASE` and `HEAD`.

1. **Resolve** both with `git rev-parse --verify --quiet <rev>^{commit}`. Failure exits 2.
2. **Compute the landing tree `T`.**
   - If `git merge-base --is-ancestor BASE HEAD` succeeds, then `T = HEAD^{tree}`. This is
     the linear case: every squash- or rebase-shaped branch, and every historical landing
     in audit mode.
   - Otherwise, use `git merge-tree --write-tree --name-only --messages BASE HEAD`. This is
     the existing `merge_tree()` helper, so it has the same merge-ort semantics and the same
     `merge.*.driver` caveat that `config_warnings()` already prints. Its first line is `T`,
     followed by the conflicted paths. rc 1 means conflicts, and the check continues on the
     remaining paths. rc 2 means cannot verify, and the check exits 2.
3. **Compute the landing diff** with `git diff-tree -r -z --raw --no-renames BASE^{tree} T`.
   Drop conflicted paths, gitlinks (mode `160000`) and mode-only changes (same oid on both
   sides). What remains is **candidates** (new oid non-zero, status `M` or `A`) and
   **deletions** (status `D`).
4. **Read `main`'s record of each path** with one `git log --first-parent
   --diff-merges=first-parent --root --raw -z --no-abbrev --no-renames BASE`. This lists
   every first-parent commit of `BASE` with its raw diff against its first parent (the root
   commit against the empty tree). Pass `--diff-merges=first-parent` explicitly rather than
   relying on what `--first-parent` implies. Filter in Python to the candidate and deleted
   paths, with no pathspec on the command line: this avoids the argv length limit and the
   pathspec-quoting problems. For each path, build:
   - the set of blob oids it has held, meaning every non-zero oid on either side of its
     raw lines;
   - for each such oid, the newest commit that introduced it (new side) and the newest
     commit that replaced it (old side);
   - the newest commit that added the path (status `A`).
5. **Classify each candidate.** If its new oid `t` is in the path's held set, it is a
   **restore**. `t` cannot equal `BASE`'s blob, because the path is in the diff. Everything
   else is an ordinary change and prints nothing.
6. **Deletions are context, never a failure.** They are reported only when at least one
   restore fails, and only for a deleted path whose adding commit is one of the failing
   restores' replacing commits. For PR #519 that means "also removes 3 files added by
   `5a6dec9`".
7. **Overrides.** See §D6.
8. **Report and exit.** Each restore is printed with its provenance ("back to the version
   `main` held from `<introduced>` until `<replaced>` *subject*"), grouped by replacing
   commit. A reviewer then sees "13 paths return to the state before `5a6dec9` Merge pull
   request #515", not 13 unrelated lines. On failure the tool prints a ready-to-paste trailer
   block that names every failing path. Exit 0 means clean, 1 means an un-overridden restore,
   2 means cannot verify or usage error. These are the same codes as ADR-0061.

Only **first-parent** history counts, because the rule is about versions `main` itself held.
A blob that existed only inside a feature branch was never `main`'s content, so going back to
it does not revert `main`. Only **exact blob identity** counts, which is ADR-0061 §D1 step 4's
discipline applied to history instead of to parents. A stale file with even one new byte
passes, and that residual is named in §D8.

### §D3 — The base is resolved fresh in the job, not taken from the event's `base.sha`

For the landing check, a stale base changes the answer, not just the cost. Suppose a PR is
opened while `main` is at `B0`. Later `main` lands a deliberate restore (a #521) and the PR
branch merges `main` in. Checked against `B0`, that restore is part of the landing diff and
gets attributed to the PR. GitHub's own documentation does not say when
`github.event.pull_request.base.sha` is refreshed. The community reports linked under
References describe it as a point-in-time value, and they disagree on whether it moves on PR
creation only, on force-pushes, or on every synchronize. A check whose answer depends on the
base cannot rest on undocumented behaviour. So:

- **At PR time**, `BASE` is `refs/remotes/origin/<base.ref>`, resolved inside the job after
  `actions/checkout` with `fetch-depth: 0`. The checkout README documents that this fetches
  every branch (`+refs/heads/*:refs/remotes/origin/*`), so this is the base branch's tip at
  job time. `base.ref` is passed through `env:`, never interpolated into the script, which
  follows ADR-0061's workflow style. The job prints the event's `base.sha` next to the
  resolved base for traceability.
- **At `push: main`**, `BASE` is `before` and `HEAD` is `after`, which is the net effect of
  the push. When `before` is all-zeros or `forced` is true, `BASE` is `after^1`. This is the
  same fallback ADR-0061 §D2 uses for its range.
- **At pre-push**, see §D5.

ADR-0061's merge scan keeps using `base.sha`. For a *range of merges to inspect*, a stale
base only widens the range, which is harmless, so the two checks deliberately use different
bases.

### §D4 — One script, a new mode, plus an audit mode that makes the measurement reproducible

The check lives in `scripts/check-merge-integrity.py` and is not a new script. It reuses
`_git`, `merge_tree`, `blob_oid`, `config_warnings` and the trailer parser, which gets its
prefixes as parameters with defaults so existing callers stay unchanged. A second file would
carry a second copy of each of these, the drift ADR-0041 spent a chain removing. The hook and
the workflow already invoke this file.

CLI, mutually exclusive with the existing `--range`/`--pr-base`/`--pr-head`:

- `--landing BASE HEAD` evaluates one landing. It is used by the PR-time job, the `push:
  main` job and the pre-push hook.
- `--landings RANGE` evaluates each first-parent commit `L` in `RANGE` as its own landing,
  with `BASE = L^1` and `HEAD = L`. This is the audit mode. It exists so this ADR's table
  can be reproduced by a command, as ADR-0061's `--range <root>..main` reproduces its own.
  It is **not** wired into `workflow_dispatch`: any range covering the six historical
  landings exits 1 forever.
- `--self-test` still runs everything, old scenarios and new. The old scenarios stay
  byte-for-byte unchanged.

User-facing messages stay in Italian, which is the file's existing convention. The trailer
keys stay in English, like `Merge-override`.

### §D5 — It runs at pre-push (blocking) as well as in CI (advisory)

The brief assumed the gap cannot be closed by a local pre-push hook, "since the gap is
precisely squashed before push, no merge commit to inspect locally". That holds only for a
check that needs a merge commit, and this one does not. When the squashed commit is pushed
for the first time, the hook sees it. The ADR-0061 hook let it pass only because it looked
for merges. The pre-push hook is the only gate here that sees a local operation before it
leaves the machine, and it is the only blocking gate the repository has (ADR-0061 §D3). So
the landing check goes there too. Advisory-only would repeat the "warn-only" option ADR-0061
rejected.

Hook changes, per `<local_ref> <local_sha> <remote_ref> <remote_sha>` line:

- Deletions (`local_sha` all-zeros) and non-branch refs (anything not `refs/heads/*`, tags
  included) are skipped. ADR-0061's merge scan is unchanged.
- `BASE` is `remote_sha` when pushing `refs/heads/main` over an existing ref. Otherwise it
  is `refs/remotes/<remote>/main`, where `<remote>` is the hook's own `$1`. The ADR-0061 hook
  hardcodes `origin/main`; the new line reads the remote name the hook is actually given.
- If `BASE` cannot be resolved, or its object is missing locally, the hook prints one notice
  and skips the landing check for that ref instead of blocking. This follows ADR-0061's
  "never fail a push it cannot evaluate" rule. A push to `main` from a stale local view is
  rejected by the server as non-fast-forward anyway.
- If the pushing checkout's script predates this ADR (no `--landing` in the file), the
  landing check is skipped with a notice. This is the same principle as the existing
  "checker missing" guard. Without it, the new hook would turn an argparse error into a
  blocked push from an older worktree.

The installed hook is a **copy** made by `scripts/install-git-hooks.sh`, not a link. Every
machine with the ADR-0061 hook keeps running the old copy until someone runs
`scripts/install-git-hooks.sh --force`. The installer refuses a differing hook without
`--force`, and it cannot tell its own older version from a foreign hook. The old copy still
calls the live checker. So the checker (both modes, outside `--self-test`) compares
`$(git rev-parse --git-common-dir)/hooks/pre-push` with the checkout's
`scripts/git-hooks/pre-push`, and prints one warning naming the reinstall command when both
exist and differ. That turns a silently missing gate into a visible line on every push.

**Stale local `origin/main`.** The hook does not fetch. That is acceptable because the
dangerous shape (§Context) is a squash onto a `main` commit that already has the newer
version, and every ordinary route to that commit (`git fetch`, `git pull`, `git merge
origin/main`) also moves `origin/main` to it or past it. A stale remote-tracking ref can cost
a detection only in shapes the hole does not produce. The hook prints the base sha it
compared against.

### §D6 — The override: `Restore-override`, enumerated, on any commit in the landing's own range

A deliberate restore is cleared by `Restore-override: <path>` (repeatable, one path per line)
plus a mandatory `Restore-override-reason: <text>`. The trailers go in the message of **any
commit in `git rev-list BASE..HEAD`**, meaning the PR's own commits. In audit mode that is
`L^1..L`, which covers the landing plus the branch commits a merge landing brings in. The
rules are the same as ADR-0061 §D4: `Restore-override: all` is rejected, a commit that names
paths without a reason is a usage error (exit 2), and naming each path is mandatory. The
printed ready-to-paste block keeps that cost low.

It is a **separate key** from `Merge-override`. The two sit in different places: the merge
commit itself for one, any commit in the range for the other. They also excuse different
things: a side-pick at one merge, versus a net restore of `main`'s content. With a shared key,
a trailer written to excuse one merge would silently excuse a later PR's net restore of the
same path. Each check honours only its own key. The price is that a deliberate wholesale
side-pick that also lands as a restore needs both trailers. That combination is not in the
measured history.

A `git revert` message ("This reverts commit …") is **not** recognised automatically. It
would be a second exemption channel, and it would not cover re-lands (#202) or repairs
(#521), which make up two of the three deliberate restores measured.

**Post-hoc caveat.** The `push: main` step reads trailers from `before..after`. A
merge-commit landing and a rebase landing keep the branch's commit messages there. A squash
landing keeps them only if the repository's `squash_merge_commit_message` setting includes
commit messages. If it does not, an overridden restore that passed at PR time gets reported
again after it lands, advisory only. The setting has not been verified, because the
unauthenticated API does not expose it. It is a HITL check in the plan, not an assumption.

### §D7 — Advisory in CI, blocking at pre-push, branch protection not reopened

The stance is unchanged from ADR-0061 §D3 and ADR-0044 §D11. `merge-integrity.yml` reports,
and the pre-push hook blocks. This ADR does not add a required status check or protect
`main`. One new fact is recorded for whoever reconsiders that decision. Two of ADR-0044
§D11's three reasons do not apply to `merge-integrity.yml`: it has no `paths-ignore` that a
required check would deadlock on, and it has no pre-existing reds. The remaining reason, "on
a solo repository a required check converts a signal into an obstacle", is a preference, not
a fact. It is listed under Open questions and not decided here.

In `merge-integrity.yml`, the landing step runs even when the merge-scan step failed
(`if: ${{ !cancelled() && … }}`). A red merge scan must not hide the landing finding, or the
reverse.

### §D8 — What still passes, named

- **Partial restores.** A stale file carrying any new byte, such as a stale `TODO.md` plus
  one new row, is novel content and passes. Hunk-level detection is the next step if this
  shape ever causes an incident (see Alternatives).
- **Pure-deletion stale snapshots.** If `main` only *added* files since the stale fork, a
  wholesale-ours squash lands as pure deletions, and deletions never fail (§D2 step 6,
  Alternatives). The mitigating factor is that GitHub shows a deleted file as a whole red
  file in the PR diff, far louder than an in-place revert. ADR-0061's merge check still
  catches it wherever a merge commit is pushed. ADR-0061's own self-test fixture
  (`_build_wholesale_ours_repo`, which drops a file `main` *added*) is exactly this shape,
  and the plan pins it as a named pass rather than letting it pass unremarked.
- **Pushes without the hook.** That covers another machine, a clone whose common dir never
  had the hook installed, `--no-verify`, and a conflict resolved in GitHub's web editor. CI
  reports these, advisory only.
- **A PR check that goes stale.** `pull_request` runs only on PR activity. If `main` moves
  later without a PR push, the result is not recomputed. The `push: main` step reports what
  actually landed, after the fact. Every PR check in this repo has the same limit.
- **Conflicting PRs.** GitHub does not run `pull_request` workflows while a PR has a merge
  conflict. Such a PR cannot be merged either, and the check runs once the conflict is
  resolved.
- **The PR runs its own version of the checker.** It comes from the PR's merge checkout, so
  a PR that edits the checker can make its own check pass. This is pre-existing and
  unchanged. The detector is for honest mistakes, not adversaries.

---

## Implementation plan

`docs/plans/pg-242-landing-check.md`, in five tasks: the landing mode and its self-test
scenarios (§D1, §D2, §D6); the audit mode plus the re-measurement gate (§D4); the workflow
steps (§D3, §D7); the hook and the stale-hook warning (§D5); and docs and call-sites.

---

## Open questions for Stefano

1. **Branch protection with `Merge integrity / check` as the only required check.** Not
   decided here. §D7 records why two of ADR-0044 §D11's three reasons do not apply to this
   workflow. The recommendation is to leave it off for this chain. It changes every merge
   flow (ADR-0044 §D12), and whether it binds the repository owner at all depends on
   GitHub's admin-enforcement setting, which would need checking against the live settings
   first. It is your call.
2. **Blocking at pre-push, not advisory.** Decided in §D5 for consistency with ADR-0061 §D3.
   The measured price is one trailer on roughly 1 landing in 80. Overturn it at review if
   that friction is not wanted.
3. **A one-line forward pointer in ADR-0061 §D5** ("closed by ADR-0062") is proposed as
   optional, on the same terms as the cross-reference precedent in earlier chains. Accept it
   or drop it. ADR-0061's body is otherwise untouched.

---

## Alternatives considered

- **Leave §D5 open.** Rejected because `git reset --soft $(git merge-base HEAD origin/main)`
  turns the hole into a routine command, and the measured cost of closing it is low. It
  would have been the recommendation if the measurement had come back noisy (see Context).
- **Compare the landing with a recomputed `git merge-tree`, as #535 phrased the direction.**
  Rejected: blind on linear history. It reproduces the squashed commit's own content and
  finds nothing to disagree with (Context).
- **Recover the fork point and reuse ADR-0061's classification against it.** Rejected.
  `git merge-base --fork-point` reads the local reflog of the remote-tracking ref, which CI
  and other clones do not have. GitHub's timeline API (force-push events) needs a token and
  pagination and still does not bring back the erased merge. The content rule needs no fork
  point at all.
- **Use every blob reachable from `BASE`, not just first-parent.** Rejected. Going back to a
  version that existed only inside a feature branch does not revert `main`. It widens the
  semantics beyond "main moved past it", and it was not measured.
- **A recency window, a numeric threshold, or a path allowlist to silence the two
  `.claude/test-cmd` hits.** Rejected. A window would miss long-lived stale branches, which
  have the most to lose; the true positive's gap was 2 landings only because its stale
  window happened to be short. A threshold was already rejected by ADR-0061, because a
  one-file loss is still a loss. An allowlist is a second mechanism to maintain for 2 hits
  in 412. Revisit it only if that class recurs.
- **Deletions as a failure signal, alone or with a recency window.** Rejected on the
  measured data. Legitimate deletions of recently added files happen (`main`'s history has
  deletions 1, 2 and 5 landings after the add, in ordinary refactors), so this would fire on
  normal work.
- **Hunk-level detection (a hunk that exactly inverts one `main` landed).** Not now. It would
  catch partial restores (§D8), but it is heavier, unmeasured, and noisy on legitimate edits
  that revert a single line. It is the named next step if a partial restore ever costs work.
- **A new script instead of a mode.** Rejected (§D4). It would duplicate the git plumbing and
  the trailer parser.
- **Reusing `Merge-override`.** Rejected (§D6). The two keys differ in scope and placement.
- **Treating `This reverts commit …` as an automatic override.** Rejected (§D6). It is a
  second channel, and it would not cover re-lands or repairs.
- **Advisory-only, CI with no hook change.** Rejected (§D5). The hole is a local operation,
  and only the hook sees it before it leaves the machine.
- **Moving the per-ref loop into Python so the hook becomes a thin shim.** Not in this chain.
  This change would still need one reinstall, plus a fallback for older checkouts. The
  checker-side stale-hook warning (§D5) covers the rollout risk. Reconsider it the next time
  the hook's logic changes.
- **`github.event.pull_request.base.sha` as the base.** Rejected (§D3). When it is refreshed
  is undocumented, and a stale value blames the PR for `main`'s own later landings.
- **GitHub's synthetic merge commit (`GITHUB_SHA`, `refs/pull/N/merge`) as `T`.** Rejected.
  It exists only on GitHub, while the hook needs the identical computation locally. It is
  recomputed only on PR pushes, and `merge-tree` produces the same tree in both places.

---

## Consequences

### Positive

- A squash, a rebase or a hand-copied file that puts a version `main` already moved past
  back onto `main` is refused before it leaves a machine that has the hook. It is reported on
  every PR and every push to `main` whatever the merge method. ADR-0061 §D5's hole is closed
  at the blocking gate, not just reported.
- The check would have caught PG-240 at PR time under any of the three merge methods, from
  the landing alone. It did not need the merge commit that happened to be there.
- The provenance line tells a reviewer which landing is being undone. PG-240 would read
  "13 paths return to the state before #515" instead of a list of unrelated files.
- `--landings` makes the measurement a command, which keeps the ADR-0061 discipline:
  measure against real history, then trust.

### Negative

- Deliberate restores (reverts, re-lands, repairs) need a `Restore-override` block. That was
  3 of 412 landings. Toggling a small file back to an earlier value needs one too, which was
  2 of 412, all on `.claude/test-cmd`.
- A second trailer vocabulary exists beside `Merge-override`.
- Every machine with the ADR-0061 hook must run `scripts/install-git-hooks.sh --force` once.
  Until then the checker warns on every push.
- Partial restores and pure-deletion stale snapshots still pass (§D8).

### Neutral

- No production code, schema or on-disk format is touched.
- ADR-0061's merge-commit check is unchanged and still needed. It catches the act inside a
  branch's history, which the landing check deliberately ignores.
- Branch protection stays off (ADR-0044 §D11). See Open questions.

---

## References

- PG-242 / GitHub issue #535. ADR-0061 §D1–§D5 (`docs/adr/0061-merge-integrity-guard.md`).
- ADR-0044 §D11 (advisory CI, unprotected `main`) and §D12 (adding CI changes merge flows).
- GitHub Docs, "Events that trigger workflows", `pull_request`: `GITHUB_SHA` is the last merge
  commit on `refs/pull/N/merge`, and workflows do not run while the PR has a merge conflict.
  <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows>
- Community reports on when `pull_request.base.sha` is refreshed, which disagree with each
  other: <https://github.com/orgs/community/discussions/59677> and
  <https://www.kenmuse.com/blog/the-many-shas-of-a-github-pull-request/>
- `actions/checkout` README: `fetch-depth: 0` fetches all branches and tags
  (`+refs/heads/*:refs/remotes/origin/*`).
- `scripts/check-merge-integrity.py`, `scripts/git-hooks/pre-push`,
  `scripts/install-git-hooks.sh`, `.github/workflows/merge-integrity.yml`.

---

## Implementation notes

Recorded during `/build` on 2026-09-25, on `feature/pg-242-landing-check`, git 2.54.0
(Apple Git-157), Python 3.9.6. `git fetch origin` immediately before the measurement left
`origin/main` at `e5ba01a`. No landing reached `main` after `e5ba01a`, so there was nothing
newer to classify by hand.

### Task 2: the measurement gate, reproduced with the shipped tool

`python3 scripts/check-merge-integrity.py --landings "$(git rev-list --max-parents=0 origin/main)..origin/main"`
exits 1. The summary line reads: 411 landings examined, 6 failed, 0 could not be verified,
0 skipped. The range excludes the root commit, which is why the count is 411 of the
412 first-parent commits. The run took about 44 s. The six flags are exactly the six in
Context:

| landing | PR | tool output |
|---|---|---|
| `ab36722` | #196 | 1 path, `.claude/test-cmd`, back to the version held from `a13d476` until `0c47d3a` (#179) |
| `32bfea7` | #201 | 16 paths, all before `9f6ff14` (#199), plus 8 context deletions, all added by `9f6ff14` |
| `1d9d7b2` | #202 | 21 paths, all before `32bfea7` (#201) |
| `d778cda` | #306 | 1 path, `.claude/test-cmd`, back to the version held from `fdc23dc` until `a13d476` (#97) |
| `390613f` | #519 | exactly the 13 paths the plan names, all before `5a6dec9` (#515), plus 3 context deletions: `Tests/DiarySettleTests.swift`, `Tests/VaultUnguardedWriteGuardTests.swift`, `docs/adr/0060-…md`, all added by `5a6dec9` |
| `4079c46` | #521 | 16 paths, all before `390613f` (#519) |

All six are merge-commit landings. None of the 30 non-merge first-parent landings (`git
rev-list --first-parent --no-merges --count origin/main` = 30, `--merges` = 382) is flagged.

The merge-mode regression uses the same range with `--range`. It exits 1 with 442 merges
examined and 2 failed, `14d8851` and `7b984f1`, the same two as ADR-0061. The count is 442
rather than ADR-0061's 434 because merges have landed since. The `parse_overrides` refactor
left the merge mode's verdicts unchanged.

The gate held, so Task 4 went ahead.

Both measurements were re-run on the final tree after Task 5. By then `origin/main` had
advanced to `05ccad7` (#537, one new first-parent landing after `e5ba01a`). The results
were 412 landings with the same 6 failed, and 443 merges with the same 2 failed. The
landing `05ccad7` is not flagged, so there is still nothing newer to classify by hand.

### Decisions the plan did not fully specify

- **`LandingReport.restores` holds only restores that are not overridden.** Overridden ones
  move to `overridden`. The status and the trailer block both read `restores`, so the two
  cannot disagree.
- **`--landings` reports a parentless commit as status `skipped`, with a note.** That is a
  fifth status, used only by the audit mode. `check_landing` itself still returns only the
  four statuses in the plan.
- **`--landing` always prints its report, a clean one included.** A push log or a job log
  then always shows which base the landing was compared against.
- **The stale-hook warning goes to stdout with the prefix `AVVISO HOOK:`.** This matches
  the existing `AVVISO CONFIGURAZIONE:` line. It is printed once per invocation, in every
  mode except `--self-test`, and `--range` is included.
- **Python 3.9 compatibility.** The dev machine's `python3` is 3.9.6, and PEP 604 unions
  fail at definition time there. The new signatures therefore use `typing.Optional`.
- **Mode-only and gitlink lines in `main`'s history are ignored when the per-path record is
  built.** A `chmod` commit does not introduce a blob, so it must not appear as the
  provenance of one.

### Task 3: workflow

`actionlint` is not installed on this machine, so the workflow was **not validated** by it.
It was only parsed as YAML (Ruby `YAML.load_file`: the five steps are present and in the
intended order). This chain's own PR is the first live run of both landing steps.

### Task 4: manual hook verification

The hook was tested in a scratch clone of a throwaway bare remote under the session scratch
directory. It was never run against `origin`, and `install-git-hooks.sh` was never run in
this repository. The upstream had two commits. `c0` carried the ADR-0061-era checker, hook
and installer from `origin/main`, with `kept.txt` at v1. `c1` carried this chain's scripts,
with `kept.txt` at v2, a first-line edit to `shared.txt` and a new `added-by-main.txt`. The
hook was installed with the clone's own `scripts/install-git-hooks.sh`.

1. **Squashed stale restore (L1's shape): refused**, exit 1. The output names `kept.txt`, the
   commit it undoes (`c1`) and a ready-to-paste `Restore-override` block. The refusal says
   the landing check failed.
2. **The same push with `Restore-override: kept.txt` plus a reason: accepted**, exit 0. The
   output reads `Restore-override applicato: kept.txt (…)`.
3. **Clean squash (L4's shape): accepted**, exit 0, with `OK landing …`.
4. **ADR-0061's bad merge** (a merge dropping a file `main` added, not squashed): **still
   refused**, exit 1, by the merge check. The refusal is labelled with the merge check. The
   landing check passed on the same push, because a pure deletion is the §D8 residual.
5. **A tag push of the stale commit: the landing check was skipped** ("non è un branch"),
   and the push was accepted, exit 0.
6. **A branch whose checker predates `--landing`**, which also restores `kept.txt` v1: the
   hook printed the notice and did **not block**, exit 0.
7. **`refs/remotes/origin/main` deleted, pushing an update to an existing remote branch**:
   the hook printed the notice and did **not block**, exit 0.
8. **The old ADR-0061 hook installed, with the new checker in the checkout**: the push printed
   `AVVISO HOOK: … Reinstalla con scripts/install-git-hooks.sh --force` and was accepted.

**Found during case 7. Pre-existing, and not changed here.** Delete `origin/main` and push a
**brand-new** branch, and the push is still blocked. The block does not come from the landing
check. It comes from ADR-0061's unchanged merge scan, whose hardcoded `origin/main..<sha>`
range makes `git rev-list` fail. The checker exits with a traceback, and the hook then prints
the merge-check refusal. That contradicts ADR-0061's own "never fail a push it cannot
evaluate". It predates this chain, and the plan keeps the merge scan unchanged. It is worth a
small issue of its own.

### Still open, HITL

- `gh api repos/istefox/Pergamenum --jq '.squash_merge_commit_message'` (§D6 post-hoc
  caveat) has **not** been checked. It needs an authenticated call and is Stefano's check.
- Every machine with the ADR-0061 hook must run `scripts/install-git-hooks.sh --force` after
  merge. The installed hook in this repository's common dir is still the ADR-0061 copy, so
  every run of the checker from this checkout prints the stale-hook warning until then.
