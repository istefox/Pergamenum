# ADR-0061: A merge that silently discards an ancestor's content is refused, not just noticed

- Status: accepted, implemented in this chain.
- Date: 2026-09-25. Root cause established in this session by reading the actual commit
  graph and trees with `git log --graph`, `git merge-tree`, `git rev-parse`, and `git
  ls-tree`, not from the incident's own description. Every count below (merges examined,
  merges flagged, files per merge) comes from running `scripts/check-merge-integrity.py`
  against this repository's real history on the working tree at `4079c46` (`main`, after
  PR #521 restored the lost content) — not estimated.
- **Reopens nothing.** No SPEC §14 decision, on-disk format, schema, frontmatter key or
  tag grammar is touched. No `Sources/` or `Tests/` file changes; the unit suite is
  unaffected.
- **No new exception to CLAUDE.md principle 2.** This is tooling around the repository's
  own git history, not a runtime feature of the app; nothing under `Sources/` learns this
  guard exists.
- Depends on: ADR-0044 (§D11: CI stays advisory, `main` stays without branch protection —
  this ADR does not revisit that; §D12: "adding CI changes every merge flow in this
  repo").

---

## Context

On 2026-09-25 `main` silently regressed. PR #515 had merged five vault race guards, the
diary quit-flush fix, the Workspace conflicted-board navigation guard, three test files
and ADR-0060 (the ADR-0057 §D8 follow-up chain). When PR #519 merged, all fifteen of those
files reverted to their state from *before* PR #515, even though PR #515's merge commit
(`5a6dec9`) remained an ancestor of the new tip of `main`. Restored by PR #521. Filed as
PG-240 / GitHub issue #522, priority P1.

### What actually happened, read out of the commit graph

`git log --graph --oneline --all` around the incident:

```
*   390613f Merge pull request #519 from istefox/chore/todo-sync-509
|\
| *   14d8851 chore(tasks): resolve merge conflict in TODO.md sync after #509
| |\
| * | 0e187bb chore(tasks): sync TODO.md after #509
* | |   34e6848 Merge pull request #520 from istefox/chore/todo-sync-515
|\ \ \
| |_|/
|/| |
| * | 0aeaff5 chore(tasks): sync TODO.md after #515
|/ /
*   5a6dec9 Merge pull request #515 from istefox/fix/adr0057-d8-followups-v3
```

`chore/todo-sync-509` (PR #519's source branch) was cut from `main` *before* PR #515
landed. On that branch, `14d8851` merged `main` (`5a6dec9`) in. Its subject says it
resolved a `TODO.md` conflict, and `git show --stat 14d8851` against its first parent
shows exactly that — one file, `TODO.md`, twenty lines. But `git ls-tree -r 14d8851`
shows the merge commit's *tree* keeps the branch's stale version of every other file:
`VaultUnguardedWriteGuardTests.swift` and `docs/adr/0060-….md` are absent from it
entirely, and `git merge-base 0e187bb 5a6dec9` (the branch tip and PR #515's merge
commit, computed independently of what `14d8851` claims) is `5531f72` — three commits
further back than `5a6dec9` itself, confirming `5a6dec9` really was reachable and really
should have merged in cleanly on every path the branch hadn't touched.

`git merge-tree --write-tree 0e187bb 5a6dec9` — a real three-way merge, computed
independently of the commit that was actually made — produces a tree that differs from
`14d8851`'s actual tree on **seventeen** paths. Git itself reports exactly **one** genuine
conflict among them, `TODO.md`. The other sixteen have no conflict to explain the
difference: `14d8851`'s committed blob for each one is byte-identical to `0e187bb`'s
(the stale branch's) blob. That is the signature of a wholesale "ours" resolution —
`git checkout --ours .` or `-X ours` applied to the whole working tree while resolving
the one real conflict — not sixteen individual decisions.

PR #519 then merged `chore/todo-sync-509` into `main`. Git raised no conflict at that
point, because `main` (`34e6848`) had not touched any of those sixteen files since PR
#515 landed — there was nothing left to disagree about. Git simply took `14d8851`'s
already-corrupted tree. `5a6dec9` stayed an ancestor of the resulting `main` tip the whole
time; only its content was gone. That is what made the loss read as a `gh pr merge` or
git merge-algorithm bug when it first surfaced — it is neither. It is a human (or an
agent) resolving a merge conflict by discarding a side wholesale, on a stale branch, with
nothing downstream positioned to notice.

**Why the hazard is structural, not a one-off:** the same week produced three independent
sessions re-implementing the identical ADR-0057 §D8 work under three different names
(the ADR-0058, ADR-0059 and ADR-0060 chains, visible as three near-identical commit
sequences in the graph above `5a6dec9`), and the same race produced duplicate GitHub
issues #516/#517/#518 that `14d8851`'s own message records closing. Stale branches
merging a fast-moving `main` are this repository's routine shape, not an edge case.

### What was measured, not assumed, before deciding on a detection rule

`scripts/check-merge-integrity.py --range <root>..main` (see §D1) walks all 434
two-parent merge commits reachable from `main`. Result: **2 flagged, 0 false positives.**

| merge | date | files flagged | verdict |
|---|---|---|---|
| `14d8851` | 2026-09-25 | 16 | the incident this ADR fixes |
| `7b984f1` | 2026-09-11 | 21 | second wholesale-ours merge, found by this chain — see §D6 |

Every other merge in the repository's history — including four merges that looked
suspicious under a cruder rule (see §D1) — passes clean. The tool was run against the
real incident before being trusted, not designed and assumed correct.

---

## Decision

### §D1 — Detection: a real three-way merge, diffed against what was actually committed, classified by blob identity

For a merge commit `M` with exactly two parents `P1`, `P2`:

1. `git merge-tree --write-tree --name-only --messages P1 P2` computes what git itself
   would produce — a real merge (merge-ort), not the trivial fast-path. Exit 0 = clean,
   1 = conflicts (git still writes a tree, with conflict markers, for the conflicted
   paths), 2 = cannot merge at all.
2. `git diff --name-only <computed-tree> M^{tree}` finds every path where the commit that
   was actually made disagrees with that computation.
3. Subtract git's own reported conflicts: a conflict is a place a human was *required* to
   decide, so disagreement there is expected and not evidence of anything.
4. Classify what remains by blob identity, comparing `M`'s blob at that path against
   `P1`'s and `P2`'s:
   - **side-pick** — `M`'s blob is byte-identical to one parent's (or the path is absent
     from `M` while a parent added it). A whole side was taken at a path nothing forced a
     choice on. **Fails the check.**
   - **novel** — `M`'s blob matches neither parent. An ordinary "evil merge": someone
     fixed a semantic or compile break by hand while resolving something else. **Reported
     as an advisory line, never fails.**

Step 4 is the reason this rule is usable rather than noisy. Step 3 alone (no blob
classification) flags 6 of the 434 merges; four of those six are legitimate evil merges —
one is a deliberate de-duplication of a helper function while resolving an unrelated
conflict in a sibling test file, one accompanies an ADR-0045-style file split, two are
ordinary fixups next to a real conflict. Splitting by blob identity clears all four
automatically and leaves exactly the two merges that actually discarded content with
nothing to justify it.

Implementation: `scripts/check-merge-integrity.py`, Python 3, stdlib only (the same
constraint `scripts/appcast.py`'s header already states and the same precedent
`scripts/mcp-smoke.py` set: this repository has no Python dependency file to put anything
else in). `--self-test` builds throwaway git repositories under a guarded temp directory
and asserts, by name: a clean merge passes; the wholesale-ours shape fails, naming only
the side-picked path and not the genuine conflict beside it; an evil merge with novel
content passes with an advisory; the override trailer (§D4) clears a named path; a bare
`Merge-override: all` is rejected; an octopus merge (≠2 parents) is skipped with an
explicit message, never silently treated as clean.

### §D2 — A separate workflow, not a step added to `ci.yml`

`ci.yml` carries `paths-ignore: ['docs/**', 'TODO.md', '*.md']` at the workflow level
(ADR-0044's own trigger design). The PR that caused PG-240 was exactly a `TODO.md` sync —
the hazard class this guard exists for would have skipped `ci.yml` entirely. A new
workflow, `.github/workflows/merge-integrity.yml`, triggers on `pull_request` and
`push: main` with **no** path filter. It runs on `ubuntu-latest`: the check is pure git
plus a stdlib Python script, takes seconds, and keeping it off the scarce `xcode-27`
runner (ADR-0044 §D2's pinned, non-`-latest` label) costs nothing.

The PR-time range comes from `github.event.pull_request.base.sha` and `.head.sha` —
never `HEAD`, which on a `pull_request` event is GitHub's synthetic merge-preview ref, not
a real commit in the branch's own history. The push-time range is
`github.event.before..github.event.after`, falling back to scanning only the merge at
`after` (if it is one) when `before` is all-zeros (new branch) or `github.event.forced`
is true (a rewritten history makes `before` unreliable as an ancestor).

### §D3 — The pre-push hook is what actually blocks; CI stays advisory

This repository has no branch protection (ADR-0044 §D11, restated as CLAUDE.md's "no
branch protection is configured: the discipline above is the only guard"). A CI job alone
would have reported the same finding after PG-240 happened, not before — advisory,
exactly like every other check `ci.yml` runs. The blocking half is
`scripts/git-hooks/pre-push`, installed by `scripts/install-git-hooks.sh` into
`$(git rev-parse --git-common-dir)/hooks/pre-push` — the directory every worktree of this
repository shares, confirmed empirically: the common dir's `hooks/` held only the fourteen
stock `*.sample` files before this chain, and one install covers every worktree.

The hook reads `<local_ref> <local_sha> <remote_ref> <remote_sha>` per line from stdin
and checks `<remote_sha>..<local_sha>` (falling back to `origin/main..<local_sha>` on a
brand-new remote ref, rather than scanning the full history — 434 `merge-tree` calls take
roughly a minute and a half locally, which is not acceptable push latency). If the checker
script is missing from the pushing worktree's checkout (an older commit, from before this
guard existed), the hook exits 0 rather than failing a push it cannot evaluate.

The installer refuses to overwrite an existing, different `pre-push` hook without
`--force`, verifies the installed file is actually executable (this machine's
`core.hooksPath` resolves through a Kepler passthrough shim that re-execs the real hook
only when it is `+x`, and fails silently otherwise), and warns if `core.hooksPath` is set
in the repository's *local* config to something other than the common dir's `hooks/` —
in that case the passthrough's own self-exec guard would fire and this hook would never
run.

Verified end to end in this chain, not just asserted: a scratch clone with a synthetic
"stale branch merges main, keeps a real conflict, silently drops a non-conflicting file"
merge — the same shape as `14d8851` — was pushed to a throwaway bare remote and refused by
the installed hook; the equivalent clean merge, pushed the same way, was not.

### §D4 — The override trailer, and why enumeration is mandatory

`Merge-override: <path>` (repeatable, one path per line) plus a mandatory
`Merge-override-reason: <text>` on the merge commit's own message clears a named
side-pick without disabling the check. This works because every commit the checker
inspects was authored locally — GitHub's auto-generated message only ever lands on the
*PR's own* merge commit, which every `base..head` range excludes by construction
(confirmed: PR #519's range yields `14d8851`, never `390613f`). A bare
`Merge-override: all` is rejected outright: naming the paths is what makes the exception
reviewable later, and `all` is exactly the shortcut that produced the incident in the
first place. If the merge is already pushed, the remedy is `git commit --amend` on the
merge to add the trailer, then `git push --force-with-lease` on the feature branch —
ordinary, expected friction for a branch that has not yet reached `main`.

### §D5 — Known gap: squash and rebase merges bypass the merge-commit check entirely

`gh api repos/istefox/Pergamenum` confirms all three GitHub merge methods are enabled on
this repository (`allow_merge_commit`, `allow_squash_merge`, `allow_rebase_merge` all
`true`). A squash merge flattens a branch's own bad merge commit into a single ordinary
commit on `main`; a rebase merge drops merge commits entirely. Either way, the
`push: main` half of this guard sees a normal commit, not a merge, and has nothing to
examine — the corrupted content still lands. **The PR-time check is therefore the
load-bearing half**, since it inspects the branch's own merge commits (like `14d8851`)
before any merge button is pressed, regardless of which button ends up used.

The one hole no merge-commit-based check can close: a developer who resolves a conflict
with a wholesale `--ours` and then squashes their own branch locally, before ever pushing
a merge commit for either the pre-push hook or the PR-time job to see. Named here,
deliberately not fixed in this chain — the mitigation (diffing a PR's net change against
what the fork point actually reverted) is a different, heavier check and is out of scope.

**Closed by ADR-0062** (the landing check): `docs/adr/0062-landing-check-closes-the-squash-gap.md`.

### §D6 — A second wholesale-ours merge was found, and is not folded into this fix

`7b984f1` ("Merge remote-tracking branch 'origin/main' into
feat/pratiche-attachment-reliability-bugs", 2026-09-11) has the identical signature on 21
paths, including `CLAUDE.md`, `SPEC.md`, `.claude/protected-interfaces` and
`Sources/Core/Email/AttachmentIntegrity.swift` — all byte-identical to that branch's own
stale side, none of them git-reported conflicts. Spot-checking `CLAUDE.md`'s dropped hunk
shows at least part of it was that branch's own deliberate compaction of eleven
per-chain ADR sections into the "Chain decision index" — the shape `main` still carries
today — so this is **not confirmed as PG-240-shaped data loss**, only as the same
mechanical signature. It needs its own triage against what `main` holds now for each of
the 21 paths, which this chain does not do. **A new PG issue is filed for it, not folded
into PG-240's close.**

---

## Implementation plan

### Task 1 — `scripts/check-merge-integrity.py` (§D1)
Detector, CLI, and `--self-test`. Done in this chain; verified against the real incident
(`--range 34e6848..14d8851` fails, naming exactly the sixteen paths and never `TODO.md`)
and against the whole of `main`'s history (434 examined, 2 failed, matching §Context's
table exactly).

### Task 2 — `.github/workflows/merge-integrity.yml` (§D2)
Advisory PR + push job, no path filter, `ubuntu-latest`. Done in this chain.

### Task 3 — `scripts/git-hooks/pre-push` + `scripts/install-git-hooks.sh` (§D3)
The blocking half. Done in this chain; installer and hook both verified in a scratch
clone against a throwaway bare remote, including the foreign-hook and `--force` paths.

### Task 4 — `CLAUDE.md`
`scripts/check-merge-integrity.py` added to the Commands block. One line in Working
agreements naming the rule and the override trailer, per ADR-0044 §D12's own precedent
("adding CI changes every merge flow in this repo; that is a task, not a side effect").

### Task 5 — File PG-240's closure and a new issue for §D6
Out of this ADR's implementation, handled by the surrounding chain: PG-240 / issue #522
closes once this lands, citing this ADR as the root cause and the fix. `7b984f1` (§D6) is
filed as its own new PG issue, not closed here.

---

## Open questions for Stefano

None identified that block landing this. The squash/rebase gap (§D5) and the `7b984f1`
triage (§D6) are named, not open decisions — both are explicitly out of this chain's
scope, with the reasoning for leaving them out stated above.

---

## Alternatives considered

- **Override via an environment variable** (`MERGE_INTEGRITY_SKIP=1 git push`). Rejected:
  leaves no trace in the repository's own history. Six months later nobody can tell why a
  given merge was allowed through, which is the same kind of silent, unreviewable
  exception this ADR exists to close off.
- **Warn-only, never blocking.** Rejected on the evidence: PG-240's own root cause is a
  silent loss that nothing was watching for. A CI job alone is exactly this shape — it
  would have reported the finding after the fact, the same way `git log` could always have
  shown the loss to anyone who thought to look. The pre-push hook is what changes the
  outcome.
- **Override via a tracked file**, `docs/merge-overrides/<sha>.md`, instead of a commit
  trailer. Rejected for now: a second mechanism to keep in step with the merge commit it
  describes, for no benefit the trailer doesn't already have — the trailer lives in the
  same commit it excuses, is visible in the same `git log`, and the amend-then-push
  remedy in §D4 already covers the already-pushed case. Revisit if the trailer proves too
  easy to omit by accident in practice.
- **Threshold-based failure** (fail only past *N* side-picked paths, warn below it).
  Rejected on the measured data: the historical false-positive rate at "even one path
  fails" is already zero (§Context's table) once paths are classified by blob identity.
  A numeric threshold would be an arbitrary knob solving a problem the classification
  step already solved, and a genuine two-file loss — smaller than PG-240's sixteen, still
  a real regression — would read as a mere warning under it.
- **Folding `7b984f1`'s restoration into this chain.** Rejected: whether `7b984f1` lost
  anything still on `main` today is unconfirmed (§D6), and conflating "the detector found
  a second match" with "a second incident occurred" is exactly the kind of unverified
  claim this repository's own instructions (never assert a finding without checking it
  against the live source) rule out.

---

## Consequences

### Positive
- A merge that discards an ancestor's content with no conflict to justify it can no
  longer reach `main` unnoticed from a machine with the hook installed, and is reported on
  every PR regardless.
- The detector is measured against this repository's entire real history at zero false
  positives, not tuned against a synthetic case and hoped to generalize.
- A second, previously undetected incident of the same shape (`7b984f1`) surfaced as a
  side effect of building this and now has its own tracked issue.
- `--self-test` and the scratch-clone push tests give this guard the same
  build-it-then-verify-it-actually-fires discipline `scripts/uitests.sh` and
  `scripts/appcast.py` already hold themselves to.

### Negative
- The hook is opt-in per machine (`scripts/install-git-hooks.sh` must be run once); a
  contributor who never runs it gets no local protection, only the advisory CI report.
- `merge-integrity.yml` adds roughly a minute of CI time to affected pushes/PRs (dominated
  by `fetch-depth: 0`'s full-history checkout), on a separate, cheap runner from the main
  build.
- Squash and rebase merges are not covered (§D5) — a residual gap, stated rather than
  hidden.

### Neutral
- No production code, schema, or on-disk format is touched; the change is entirely
  tooling around how commits enter this repository's history.
- Branch protection remains off; this ADR does not reopen that decision (ADR-0044 §D11).

---

## References
- PG-240 / GitHub issue #522.
- ADR-0044 (CI), §D11 (advisory, no required check) and §D12 (adding CI is its own task).
- `scripts/check-merge-integrity.py`, `scripts/git-hooks/pre-push`,
  `scripts/install-git-hooks.sh`, `.github/workflows/merge-integrity.yml`.
