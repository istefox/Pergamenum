Status: Approved (2026-09-26)

# SPEC — ADR reference check: the three README rules become one self-tested command

## Destination

A self-tested Python command under `scripts/` that enforces the three rules the ADR directory
README writes down (one number per file, a status line that says what landed, a citation that
says where the ADR lives), run by hand and by an advisory CI workflow, and a tree on which its
first run exits clean because the measured baseline is corrected in the same chain. Closes
`PG-273`, the follow-up of chain 14 (#581, PR #592).

## Objectives

Chain 14 checked the three rules by hand, once. Nothing stops the next chain from taking a number
another branch already took (the 0061 collision of 2026-09-25), leaving an ADR on `main` that
still reads proposed, or citing an ADR of the retired concept-to-code workflow as if it lived
here. This chain turns the hand check into a command whose red means a new defect, not a known
backlog: the rules are mechanical, and a mechanical rule nobody runs decays the way the 19
proposed status lines did.

## Scope and non-goals

In:
- The check command, with an offline `--self-test` in the shape `check-merge-integrity.py` and
  `appcast.py` already use.
- Rule 1 inside the tree and against a base ref; rule 2 presence, status word and «proposed on
  the base»; rule 2 landing hashes as warnings; rule 3 on the first citation per file.
- A registry of external ADR series in the ADR directory README, read by the command.
- Amendments to the README's rule 3 (first citation per file; a qualified citation outranks the
  local number) and a pointer to the command.
- The baseline corrected: every unqualified first citation of an external ADR, plus the 0053
  collision in ADR-0040 and ADR-0042.
- A new advisory CI workflow and a `CLAUDE.md` Commands entry.

Out (detail below): the full rule 2 (accepted names PR, hash and date), a pre-push hook, a
semantic collision detector, citation forms other than `ADR-NNNN`, `TODO.md` and the root
`SPEC.md`.

## Decisions

- **Correct the baseline in this chain** — the script is born green, so every future red is new.
  Rejected: a versioned allowlist — it rots and hides the next collision among known ones;
  report-only with exit 0 — a check that cannot fail is not a check.
- **Command plus advisory CI workflow** — a new lightweight workflow without `paths-ignore`,
  because docs-only PRs are exactly the ones that add or edit ADRs; not a required check, like
  `merge-integrity.yml`. Rejected: a blocking pre-push hook — it would stop a push over a comment
  citation; manual only — the rules already decayed once with nobody running them.
- **Rule 2 checks presence, the status word and «proposed on the base»; landing hashes are
  warnings** — ~30 ADRs read a bare «accepted», and backfilling them is a different chain.
  A hash cited in a status line that is not a commit on the base's first-parent line is reported
  as a warning (measured today: 6 hashes in ADR-0029, 0043, 0048 and 0064), never a failure.
  Rejected: the README's full rule 2 (PR, hash and date on every accepted) — ~30 status lines to
  read from git in this chain; only PG-273's literal wording — misses recalled hashes, the defect
  rule 2 names.
- **External origins are declared in a README table the command reads** — one «External ADR
  series» table maps an origin to the phrase that qualifies a citation. Today it has one row: the
  retired concept-to-code workflow. A new origin is added there, nowhere else. Rejected: a phrase
  constant in the script — the rule would live in two places; an explicit marker syntax — rewrites
  the 13 qualifications already in the tree.
- **Rule 3 applies to the first citation of a number per file** — the README is amended to say
  so, matching what chain 14 did (the second ADR-0155 mentions in ADR-0040 and two superpowers
  plans stay bare). Rejected: every citation — dozens more rewritten lines for no reader benefit.
- **Scan every tracked `.swift`, `.md`, `.yml`, `.yaml`, `.py`, `.sh` file except the root
  `TODO.md` and `SPEC.md`** — both are working records that quote ADR numbers as data, and
  closed tickets keep historical numbers by rule 1. Rejected: PG-273's literal Sources/Tests/docs
  — misses `PROJECT_BRIEF.md`, `ROADMAP.md` and `CLAUDE.md`, two of which are in the baseline;
  everything including `TODO.md` — contradicts rule 1 on closed tickets.
- **Rule 1 compares against a base ref too** — `--base <ref>`, defaulting to `origin/main` when
  it resolves; the CI workflow resolves the PR's base in the job, as `merge-integrity.yml` does.
  Rejected: in-tree duplicates only — the 0061 collision was invisible on each branch alone and
  surfaced only after both landed.
- **The 0053 collision is closed by qualification, and a qualified citation outranks the local
  number** — the first mentions in ADR-0040 and ADR-0042 become «ADR-0053 of the retired
  concept-to-code workflow»; the README's rule 3 says a citation qualified with another origin
  means that origin even when the number exists here. Rejected: rewriting the sentences without
  the number — edits the body of two accepted ADRs; leaving it as a documented residual — a
  reader of those ADRs still lands on the wrong record.
- **One test seam: `--self-test` plus the run on the real tree** — scenarios in temporary git
  repositories, one per pass and fail case, the shape of the two existing self-tested scripts; the
  real-tree run exiting 0 is an acceptance criterion. Rejected: a separate pytest file — no
  precedent in the repo and a second runner to keep.

## Constraints

- **Python 3 with the standard library only, invoked as `python3`** — origin: the existing
  self-tested scripts and the global environment rules.
- **Exit codes 0 clean, 1 finding, 2 not verifiable or bad usage** — origin: the convention of
  `check-merge-integrity.py`.
- **The CI workflow is advisory, never a required check; branch protection is not reopened** —
  origin: ADR-0044, ADR-0061, ADR-0062.
- **Swift edits are comment-only** — origin: user mandate (the baseline fix touches four test
  files' comments); the unit suite stays green.
- **No sentence other than the one holding the corrected citation changes** — origin: chain 14's
  «no normalising» rule, carried over.
- **The next ADR number, if `/workplan` decides this chain needs one, is re-read from
  `origin/main` immediately before the merge** — origin: README rule 1.

## Stack

Python 3 (standard library, `git` via subprocess), GitHub Actions for the advisory workflow.

## Data model

The external series registry, a markdown table in the ADR directory README:

| Origin | Qualifying phrase |
|---|---|
| The retired concept-to-code workflow (vibe-coding harness, pre 2026-09-14) | concept-to-code workflow |

Matching is case-insensitive, with whitespace (including a line wrap) normalised. A row is an
origin; the table is the only list of accepted qualifiers.

A status word is the first word after the status marker (a `- Status:` bullet, bold or not, or
the first paragraph of a `## Status` section), lower-cased, stripped of markdown emphasis and
punctuation. Recognised words: `accepted`, `proposed`, `superseded`, `deprecated`, `rejected`.

## API / interfaces

- `check-adr-references.py [--base <ref>] [--verbose]` — runs the three rules on the working
  tree; with no `--base`, uses `origin/main` if it resolves, otherwise runs the in-tree checks
  and prints a notice that the base checks were skipped.
- `check-adr-references.py --self-test` — offline, builds and discards its own repositories,
  never reads or writes the real one.
- Output: one line per finding, `path:line: rule N: message`, then a count per rule; warnings on
  their own lines, marked as warnings.

The exact file name is the plan's call; the name above is the working one.

## Edge cases

- **A slug rename of an existing number** (`0022-foo` → `0022-bar`) is not a collision: rule 1
  against the base fails only for a number the branch introduced since its merge-base with the
  base and the base holds under another file name.
- **A renumbering by `git mv`** (chain 14's 0061 → 0064) passes: the new number is absent on the
  base.
- **An ADR proposed on its own branch** passes; it fails only once it is on the base.
- **The base does not resolve** (shallow clone, no remote): base checks skipped with a notice,
  exit decided by the in-tree checks alone.
- **A sentence wrapped across lines** of a markdown paragraph or of one comment block (`//`,
  `///`, `#`) is one sentence: comment markers are stripped before joining.
- **The registry table is missing or unreadable**: exit 2, never a silent pass of rule 3.
- **The command's own source and self-test fixtures** produce no finding on the real tree.
- **An ADR-0053-style collision on a number held here and cited unqualified** is invisible to
  the command by construction; stated in the README, not detected.
- **A second or later citation in a file** is not checked, whatever it says.

## Test seams

One seam: `--self-test`, with one scenario per pass and fail case of R-01 to R-08, run locally
and first in the CI workflow. Acceptance adds the run on the real tree (exit 0) and a reviewer
read of the README, workflow and `CLAUDE.md` changes. No new Swift test; the Swift unit suite is
touched only through comments and must stay green.

## Success criteria

- [ ] R-01 — Two files under the ADR directory sharing a number make the command exit 1, naming
  both files.
- [ ] R-02 — With a base, a number the branch introduced since its merge-base with the base,
  held on the base by a different file, makes the command exit 1 naming both; a slug rename of
  a number present at the merge-base and a `git mv` to a free number do not; an unresolvable base
  prints a notice and skips the base checks.
- [ ] R-03 — An ADR with no status line in its head (a status bullet or a `## Status` section
  before any other second-level section), or whose status word is not one of the five recognised
  words, makes the command exit 1.
- [ ] R-04 — An ADR present on the base whose status word is `proposed` makes the command exit 1;
  the same ADR present only on the branch does not.
- [ ] R-05 — A commit hash in a status line that is not a commit on the base's first-parent line
  is reported as a warning and does not change the exit code.
- [ ] R-06 — In every scanned file, the first citation `ADR-NNNN` of a number the ADR directory
  does not hold makes the command exit 1 unless the same sentence contains a qualifying phrase
  from the registry; a qualified first citation of a number the directory holds passes; later
  citations in the same file are not checked.
- [ ] R-07 — The scanned set is every tracked `.swift`, `.md`, `.yml`, `.yaml`, `.py` and `.sh`
  file except the root `TODO.md` and `SPEC.md`, and the command's own file produces no finding.
- [ ] R-08 — The qualifying phrases are read from the registry table in the ADR directory README;
  a missing or unreadable table makes the command exit 2.
- [ ] R-09 — `--self-test` runs offline in temporary repositories, covers every pass and fail
  case of R-01 to R-08, touches nothing in the real repository, and exits 0.
- [ ] R-10 — The ADR directory README gains the «External ADR series» table and amends rule 3:
  the first citation per file carries the origin, and a citation qualified with another origin
  means that origin even when the number exists here; it names the command and states that a
  collision on a held, unqualified number is not machine-detectable.
  (no-test: documentation, read by the reviewer)
- [ ] R-11 — The baseline is corrected: the first unqualified citation per file of ADR-0073
  (4 test files), ADR-0068 (35 manifests), ADR-0138/0154/0158 (superpowers plans and the pg-066
  spec), ADR-0159 (`PROJECT_BRIEF.md`), ADR-0155 (`ROADMAP.md`), the external numbers in the
  chain-14 plan, and ADR-0053 in ADR-0040 and ADR-0042 each carry the registry's qualifier; no
  other sentence changes; `/workplan` re-measures the list by sentence before the edits.
  (no-test: text edit, covered by R-12)
- [ ] R-12 — The command run on the tree at the end of the chain, against `origin/main`, exits 0;
  its warnings are listed in the PR body.
- [ ] R-13 — A new advisory workflow, with no `paths-ignore`, runs on every PR and on push to
  `main`, resolves the PR's base in the job, runs `--self-test` and then the check; it is not a
  required check. (no-test: CI configuration, read by the reviewer)
- [ ] R-14 — `CLAUDE.md`'s Commands block lists the check and its self-test.
  (no-test: documentation, read by the reviewer)
- [ ] R-15 — Swift edits are comment-only and the unit suite passes.
  (no-test: covered by the existing unit suite run)

## Not yet specified

_none_

## Out of scope

- **The README's full rule 2** (every accepted names PR, merge hash and date): ~30 ADRs read a
  bare «accepted»; backfilling them from git is a chain of its own, and ADR-0049's status line
  (no PR, hash or date) stays as chain 14 left it.
- **A blocking pre-push hook**: the check is about prose, and a comment citation should not stop
  a push.
- **Semantic collisions**: an unqualified citation of a number this directory holds but meant in
  another series cannot be told apart from a correct one by text alone.
- **Citation forms other than `ADR-NNNN`** (`ADR 0061`, `adr-0043` in a file name, a bare
  `0061`): not a citation the README's rules name.
- **`TODO.md` and the root `SPEC.md`**: working records that quote numbers as data; closed tickets
  keep historical numbers by rule 1.
- **Fixing the six warning hashes**: chain 14 decided ADR-0064's `c2cf19b` stays; the others are
  reported, not rewritten.

## Domain terms

- **External ADR** — an `ADR-NNNN` number that names a record of another series, not a file of
  this repository's ADR directory.
- **Qualified citation** — a citation whose sentence contains a qualifying phrase from the
  registry.
- **Base** — the ref the branch will land on (`origin/main` by default, the PR's base in CI).
