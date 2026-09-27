# Plan: PG-273, the ADR reference check

- **SPEC:** `SPEC.md` (Approved 2026-09-26), success criteria R-01…R-15. Its Decisions and
  Constraints are registered as settled and not reopened. Where the re-measurement by sentence
  contradicts the SPEC's own measurement or reaches past its enumerated lists, the finding is listed
  under gate G1 with the resolution this plan recommends, none decided on Stefano's behalf.
- **Citation convention used below:** ADR-0066, ADR-0068, ADR-0073, ADR-0138, ADR-0154, ADR-0155, ADR-0158 and ADR-0159 are ADRs of the retired concept-to-code workflow, not Pergamenum ADRs.
- **ADR outcome: no new ADR.** Against the significance test: a real trade-off exists (allowlist vs
  a corrected baseline, hook vs advisory workflow), but the decision is not hard to reverse (a script,
  a workflow and a README section, each removable in one commit), and it is not surprising without
  context once the README's «Checking the rules» section and the workflow's header say why. No
  override applies: no security or compliance boundary, no constraint invisible in the code (the
  registry is a table a reader can see), no deliberate deviation from the obvious path (the
  workflow copies an existing shape), and the one explicit «no» a later reader might undo (no
  pre-push hook) is written in the README and the workflow header, where that reader will look.
  Chain 14's precedent holds: the record of an ADR-directory convention is the directory's README.
  Spending the next number, 0066, on a tool about numbering would also collide in meaning with the
  qualified external ADR-0066 citations still in the tree. Existing ADRs that govern parts of the
  work, cited unchanged:
  - **ADR-0044 §D11**: CI is advisory, never a required check; `main` stays unprotected. Task 5.
  - **ADR-0061 §D1/§D2**: the self-tested stdlib script with exit 0/1/2, and a workflow of its own
    on `ubuntu-latest` with no path filter, because `ci.yml` skips docs. Tasks 1, 2, 5.
  - **ADR-0062 §D3**: the PR's base is `refs/remotes/origin/<base.ref>` resolved in the job after a
    full-history checkout, `base.ref` passed through `env:`, the event's `base.sha` printed beside
    it. Task 5.
- **Baseline:** `HEAD` = `origin/main` = `1e09448`, read on 2026-09-26. Every count, line and hash
  below was read from that tree with `git`, `grep` and a throwaway by-sentence scanner that
  implements the rule of Task 2. None is recalled from the SPEC or PG-273.
- **Scope:** one new script, one new workflow, `docs/adr/README.md`, one `CLAUDE.md` block, and
  comment or prose edits in 53 files (49 if D2 is declined). Swift edits are comment lines only; no
  file under `Sources/` or `Tests/` is added or removed, so no `tuist generate`. `TODO.md` is not
  touched in this chain (see «After the merge»).
- **UI budget:** zero GUI tests. Nothing observable changes.
- **This plan is scanned.** It lives under `docs/plans/`, so its first citation of every external
  number carries the qualifier (the convention bullet above). Later mentions are bare on purpose.

## Before `/build` (orchestrator; each item is a HITL point)

1. **Bring `origin/main` in:** `git fetch origin`. If it moved past `1e09448`, `git merge
   origin/main` before any edit and re-run block B; a parallel chain may have added an ADR or a new
   unqualified citation.
2. **Re-measure** (block B). If a value differs, stop and report.
3. **Gate G1:** approve or decline D1–D4.
4. **Commit gates.** Every commit and the push are HITL. Recommended boundaries: SPEC and this plan;
   the script (after Task 2, not the red Task 1 state); the README; the baseline; the workflow and
   `CLAUDE.md`.

Block B (expected values on `1e09448`; bash, from the repo root):

```bash
git ls-files -- '*.swift' '*.md' '*.yml' '*.yaml' '*.py' '*.sh' | grep -vxE 'TODO.md|SPEC.md' | wc -l   # 1167
git ls-tree --name-only origin/main docs/adr/ | grep -cE '/[0-9]{4}-'                           # 65, highest 0065
git grep -F '(ADR-0068 §D1, §D11).' -- 'docs/manifests/*.yml' | wc -l                            # 35 (one line per file)
git grep -l 'ADR-0073' -- '*.swift' | wc -l                                                     # 4
git grep -n -E 'ADR-(0138|0154|0158)' -- docs/superpowers/plans docs/specs | wc -l              # 10 (first citations: see Task 4)
git grep -n 'ADR-0053' -- docs/adr/0027-*.md docs/adr/0038-*.md docs/adr/0040-*.md \
  docs/adr/0041-*.md docs/adr/0042-*.md Sources/Core/Conventions/ImportNaming.swift | cut -d: -f1,2
# 0027:334, 0038:12, 0040:39, 0040:654, 0041:671, 0042:51, 0042:629, ImportNaming.swift:123
```

## Departures from the SPEC's letter (gate G1)

**Gate G1 decided 2026-09-27 by Stefano:** D1 accepted, D2 accepted (qualify all six), D3 accepted
(named residual in the PR body, no follow-up file), D4 accepted (README sentence kept).

- **D1. R-05's status-line hashes are two, not six.** The SPEC's Decisions count six hashes in
  0029, 0043, 0048 and 0064. Four of them sit in `- Date:` bullets, not in the status line: 0029
  `bbe09a9`, 0043 `8b554b1`, and 0048 `ba09c06` and the second `ef8d28d` (lines 5–6). Each names the
  working tree the ADR was written against, which is a branch commit by construction and was never
  meant as landing evidence. Inside a status statement (Task 2's definition: the status bullet plus
  its indented continuation lines, or the first paragraph under `## Status`) there are two:
  `docs/adr/0048-…:3` `ef8d28d` and `docs/adr/0064-…:3` `c2cf19b`. Recommended: R-05's letter
  («a commit hash in a status line»), so the real-tree run prints exactly these two warnings.
- **D2. The ADR-0053 collision has six first citations, not two.** Beyond ADR-0040:39 and
  ADR-0042:51, four more first citations mean the retired workflow's ADR-0053 («protected
  interfaces are proposed by the architect and created by the operator»), each written before this
  directory's 0053 existed (added 2026-09-21):
  - `docs/adr/0027-…:334`, «this check BLOCKS once declared (ADR-0053 §D2)» (file added 2026-08-28);
  - `docs/adr/0038-…:12`, «the protected interface `VaultAPI.LintFinding` (ADR-0053)» (2026-09-11);
  - `docs/adr/0041-…:671`, the heading «Protected-interface proposal (ADR-0053 — proposed, not
    written)» (2026-09-12);
  - `Sources/Core/Conventions/ImportNaming.swift:123`, «Also `.claude/protected-interfaces`
    (ADR-0053)» (`git blame`: 2026-09-05).

  Recommended: qualify all six. The SPEC's own reason for closing the collision («a reader of those
  ADRs still lands on the wrong record») applies to each, the edit is the same, and the Swift one is
  a comment. Declining leaves four readers landing on the wrong record, and the README sentence of
  Task 3 then names them as remaining.
- **D3. The 35 run manifests carry nine more collisions, left as a named residual.** The manifest
  template under `docs/manifests/` cites ADR-0014, 0016, 0017, 0039, 0050, 0052, 0055, 0057 and 0060
  in the retired workflow's sense («Gate 0 routing result (ADR-0017)», «Tracer-bullet probe
  (ADR-0057, Step 4.5, …)»): 9 first citations per file, 315 in all. Recommended: leave them, list
  them in the PR body and under «Out of scope» below. They are machine-written run records of the
  retired workflow that no reader follows to an ADR, and 315 sentence edits is the «every citation»
  cost the SPEC rejected. Alternatives for Stefano: a follow-up ticket, or a one-file
  `docs/manifests/README.md` saying whose ADRs these are. How many such collisions exist elsewhere
  in the tree is insufficient data: a probe that flagged a file older than the ADR it cites was
  tried and discarded, because a later edit adding a citation looks the same.
- **D4. «Proposed on the base» is stricter than README rule 2 in one case.** Rule 2's third bullet
  allows `proposed` for an ADR «whose implementation is not on `main` yet», which includes a record
  that reaches `main` ahead of its implementation (chain 14 found two, 0017 and 0030). The SPEC's
  Decision reports every ADR on the base that reads `proposed`. Recommended: keep the SPEC's check
  (settled) and say so in the README's «Checking the rules» paragraph (text in Task 3), rather than
  rewrite rule 2 or add an exemption.

## Decisions this plan takes that the SPEC left open

- **File name:** `scripts/check-adr-references.py`, mode `100755` like every other script.
- **Language:** English docstrings, comments and output, per `CLAUDE.md` («Code, comments and commits
  stay in English»). The two sibling self-tested scripts are Italian; that is their history, not the
  rule to copy.
- **Python 3.9.** The machine's `python3` is 3.9.6 (read 2026-09-26); `ubuntu-latest` is newer. No
  `match`, no `X | Y` annotations evaluated at runtime, `typing.Optional`/`List`/`Dict`.
- **Exit precedence:** 2 for bad usage, for «not a git repository», and for a missing or unreadable
  registry; this outranks 1 (R-08's letter; a broken registry is the check's own configuration, the
  class `check-merge-integrity.py` ranks first as `usage_error`). Rules 1 and 2 still run and print
  before the exit. 1 for any finding. Warnings and notices never change the code.
- **An explicit `--base` that does not resolve** gets the same notice and skip as the default
  (R-02's letter). The notice names the ref, so a typo is visible.
- **The source holds no literal `ADR-` followed by four digits.** Fixtures build citations at
  runtime (`cite(n)` returning `"ADR-%04d" % n`), and the docstring points at `docs/adr/README.md`,
  `PG-273` and issue #581 instead of citing ADRs. This makes R-07's «own file produces no finding»
  hold in any repository the script is copied into, which is what lets a self-test scenario check it.
- **The self-test's git is hermetic.** Measured: `core.hooksPath` reaches git here from the
  harness's command-line configuration (`git config --show-origin` prints `command line:` and a
  Kepler worktree-hooks path), so a plain `git commit` in a throwaway repository would run those
  hooks. Every self-test git call and every CLI run it makes gets an environment with every `GIT_*`
  variable removed (this also drops `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE`, which would
  otherwise point a `git -C <tmp>` call at the real repository), then `GIT_CONFIG_GLOBAL=/dev/null`,
  `GIT_CONFIG_NOSYSTEM=1`, `GIT_TERMINAL_PROMPT=0` and a fixed author and committer. Repositories
  are created with `git init -q -b main`.

## Ownership and order

- **Task 1 (tester)** declares the command's contract and writes every self-test scenario against
  it; **Task 2 (coder)** fills the bodies until the self-test is green. Python is not compiled, so
  the stubbed script runs and the self-test reports red scenarios instead of failing to build.
- Tasks 3 and 4 touch disjoint files and do not depend on Tasks 1–2; they can run in parallel with
  them. Task 5 follows Task 2 (the workflow runs the script). Task 6 is last.
- Expected progression of the real-tree run: after Task 2 alone, exit 2 (no registry yet); after
  Task 3, exit 1 with exactly 57 `rule 3` findings; after Task 4, exit 0.

---

### Task 1 — The contract and the self-test scenarios (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09; tester)

File: `scripts/check-adr-references.py` (new, `100755`).

Write, with stub bodies:

- The module docstring: what the three rules are and where they live (`docs/adr/README.md`), the
  usage lines, the exit codes, and one paragraph on why the check is advisory and has no pre-push
  hook. No literal `ADR-` plus four digits.
- Constants: `ADR_DIR = "docs/adr"`, `README = "docs/adr/README.md"`,
  `REGISTRY_HEADING = "## External ADR series"`, `PHRASE_COLUMN = "Qualifying phrase"`,
  `SCANNED_SUFFIXES = (".swift", ".md", ".yml", ".yaml", ".py", ".sh")`,
  `EXCLUDED_ROOT_FILES = ("TODO.md", "SPEC.md")`,
  `STATUS_WORDS = ("accepted", "proposed", "superseded", "deprecated", "rejected")`,
  `DEFAULT_BASE = "origin/main"`.
- The CLI (`argparse`): `[--base REF] [--verbose]`, and `--self-test` alone (combined with anything
  else: exit 2, the `check-merge-integrity.py` guard). `main(argv=None) -> int`,
  `self_test() -> int`, `run(repo, base, verbose) -> int`. The stub `run` prints the summary line
  with zeros and returns 0.
- The output contract, which the scenarios assert on:
  - a finding: `<path>:<line>: rule <N>: <message>`, path relative to the repository root;
  - a warning: `<path>:<line>: warning (rule 2): <message>` (never contains `: rule 2:`, so a grep
    for findings does not count it);
  - a notice: `notice: <message>`;
  - with `--verbose`: `base: <ref> -> <sha>`, `merge-base: <sha>`, `scanned: <n> files`,
    `phrases: "<p1>", …`;
  - last line: `check-adr-references.py: rule 1: <a>, rule 2: <b>, rule 3: <c> findings; <w> warnings`;
  - an exit-2 cause on stderr: `check-adr-references.py: error: <message>`, never a traceback.

The self-test follows `check-merge-integrity.py`'s shape: `tempfile.mkdtemp(prefix=
"pergamenum-adr-references-selftest-")`, one throwaway repository per scenario, the CLI driven
through `subprocess.run([sys.executable, __file__, …], cwd=<tmp repo>, env=<hermetic>)`, a report
line per check, `rmtree` guarded to that prefix under `tempfile.gettempdir()`. Report lines start
with `ok: <R-id> <kind>: ` or `FAILED: <R-id> <kind>: `, kind being `pass`, `fail`, `warn` or
`notice`, so the Acceptance block can count per requirement. A fixture repository has a
`docs/adr/README.md` with the registry table (one row, `concept-to-code workflow`) unless the
scenario is about the registry.

Scenarios, one per pass and fail case:

| R-id | Kind | Fixture | Expected |
|---|---|---|---|
| R-01 | pass | three ADRs, distinct numbers | exit 0, summary `rule 1: 0` |
| R-01 | fail | `0002-a.md` and `0002-b.md` | exit 1, one `rule 1` line naming both files |
| R-02 | fail | branch adds `0003-bar.md`; `main` then adds `0003-foo.md`; `--base main` | exit 1, the line names both |
| R-02 | fail | same, no `--base`, `refs/remotes/origin/main` set with `git update-ref` | exit 1 (default base) |
| R-02 | pass | `0001-foo.md` at the merge-base, branch `git mv` to `0001-bar.md` | exit 0 |
| R-02 | pass | base holds `0002-a.md` and `0002-b.md`, branch `git mv` `0002-b.md` → `0004-b.md` | exit 0 |
| R-02 | notice | clean tree, `--base no-such-ref`; and no remote, no `--base` | exit 0, a `notice:` line saying the base checks were skipped |
| R-02 | notice | base is an orphan branch (no merge-base) | exit 0, notice |
| R-02 | fail | unresolvable base plus an in-tree duplicate | exit 1 (in-tree checks decide) |
| R-03 | pass | one ADR per form: `- Status: accepted`, `- **Status**: Accepted`, `- **Status:** Accepted (date)`, `- Status: **accepted**, date`, `## Status` as first H2 with «Accepted — …», «accepted, proposed for the `x` branch», and `superseded`, `deprecated`, `rejected` | exit 0 |
| R-03 | fail | no status line | exit 1 |
| R-03 | fail | `- Status: draft` | exit 1 |
| R-03 | fail | `## Context` before `## Status`; and `## Context` before a `- Status:` bullet | exit 1 each |
| R-04 | fail | ADR reading `proposed` committed on the base, unchanged on the branch | exit 1 |
| R-04 | pass | ADR reading `proposed` only on the branch | exit 0 |
| R-04 | pass | `proposed` on the base, `accepted` in the working tree | exit 0 |
| R-05 | warn | status line cites a branch-only commit and a hash that is no commit | two `warning (rule 2)` lines, exit 0 |
| R-05 | pass | status line cites a first-parent commit of the base; a `- Date:` bullet cites a branch commit | no warning, exit 0 |
| R-05 | fail | a warning plus an R-01 duplicate | exit 1, the warning still printed |
| R-06 | fail | unqualified first citation of an unheld number in a markdown paragraph | exit 1, reported at its line |
| R-06 | pass | qualifier in the same sentence across a line wrap, different case | exit 0 |
| R-06 | pass | qualifier across a wrap of `///` and `//` in `.swift`, and of `#` in `.py`, `.sh`, `.yml` | exit 0 |
| R-06 | fail | qualifier only in the next sentence; and only in the next list item | exit 1 each |
| R-06 | pass | first citation qualified, second bare | exit 0 |
| R-06 | fail | first bare, second qualified | exit 1, at the first's line |
| R-06 | pass | a held number cited bare, and in another file qualified | exit 0 |
| R-07 | fail | one unqualified unheld first citation in each of `.swift .md .yml .yaml .py .sh` and in `docs/TODO.md`; the same in a tracked `notes.txt`, root `TODO.md`, root `SPEC.md` and an untracked `extra.md` | exit 1, exactly 7 `rule 3` lines, none for the last four |
| R-07 | pass | this script copied to `scripts/check-adr-references.py` in a clean fixture and committed | exit 0, no line names it |
| R-08 | fail | no `docs/adr/README.md` | exit 2 |
| R-08 | fail | README without the heading | exit 2 |
| R-08 | fail | heading with no data row; with an empty phrase cell; with no `Qualifying phrase` column | exit 2 each |
| R-08 | pass | registry phrase `other series`; a citation qualified with «Other↵Series» | exit 0 |
| R-08 | fail | same registry; a citation qualified only with «concept-to-code workflow» | exit 1, one `rule 3` line |
| R-08 | fail | broken registry plus an in-tree duplicate | exit 2, the `rule 1` line still printed |
| CLI | fail | `--self-test --verbose`; an unknown option; a directory that is not a repository | exit 2 each, no traceback |

Task report: which scenarios are red against the stub (every `fail`, `warn` and `notice` row) and
that the run ends without a traceback.

### Task 2 — The three rules (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09; coder)

File: `scripts/check-adr-references.py`. Fill the bodies; the contract and scenarios of Task 1 do
not change without a note in the task report.

- **Repository and scanned set.** The root is `git rev-parse --show-toplevel`; not a repository is
  exit 2. The scanned set is `git ls-files -z` filtered by `SCANNED_SUFFIXES`, minus exactly the
  root `TODO.md` and `SPEC.md`, read from the working tree as UTF-8 with `errors="replace"`. A path
  missing from the working tree or a symlink is skipped; a regular file that cannot be read is
  exit 2 naming it.
- **Held numbers** are the working tree's `docs/adr/` entries matching `^(\d{4})-.+\.md$`.
- **Registry (R-08).** The first line equal to `## External ADR series`, then the first table after
  it before the next heading. The column is the header cell equal to `Qualifying phrase`
  (case-insensitive). Every data row's cell, trimmed and stripped of surrounding backticks, is one
  phrase. No README, no heading, no table, no data row, no such column, or an empty cell: an error,
  rule 3 not run, exit 2 after rules 1 and 2 print.
- **Base resolution (R-02).** `git rev-parse --verify --quiet <base>^{commit}`, then
  `git merge-base HEAD <sha>`. Either failing prints one notice naming the ref and the reason and
  skips every base check: rule 1 against the base, «proposed on the base», and the hash warnings.
- **Rule 1 (R-01, R-02).**
  - In-tree: a number held by two or more files gives one finding, on the first file in sorted
    order, naming the others.
  - Against the base: a working-tree file whose number the merge-base does not hold, while the base
    holds it under another file name, gives one finding naming the base's file. A number present at
    the merge-base (a slug rename) or absent from the base (a `git mv` to a free number) never
    does.
- **Rule 2 (R-03, R-04, R-05).**
  - The head is every line before the first `## ` heading that is not `## Status`.
  - A status bullet matches `^- (\*\*)?Status(\*\*)?:(\*\*)?`, case-insensitive, in the head. Its
    statement is that line plus the following lines indented by two or more spaces.
  - A `## Status` section counts only as the first `## ` heading. Its statement is the first
    paragraph after it.
  - The status word is the first run of letters after the marker, once `*`, `_` and backticks are
    stripped, lower-cased.
  - No statement, or a word outside `STATUS_WORDS`, is a finding.
  - A working-tree ADR whose word is `proposed` is a finding when the base holds its number and
    rule 1 did not report that number against the base.
  - Hash warnings: tokens of 7 to 40 hex characters, bounded by non-alphanumerics, containing at
    least one digit, inside the statement only (D1). A token that is not a commit, or not in
    `git rev-list --first-parent <base>`, is a warning. One `git cat-file --batch-check` process is
    enough for all tokens.
- **Rule 3 (R-06, R-07).** Per file, lines become blocks, blocks become sentences:
  - A line's kind is comment when its stripped text starts with `///` or `//` in `.swift`, or `#`
    in `.py`, `.sh`, `.yml`, `.yaml`; the marker is removed. Every other line, and every `.md`
    line, is plain.
  - A new block starts at a blank line (a bare `//` or `#` is blank), at a change of kind, and at a
    line whose text starts a markdown block: a heading (`#` to `######` plus a space, `.md` only),
    a list item (`- `, `* `, `+ `, `1. `, `1) `), a table row (`|`), or a fence (```` ``` ````,
    `~~~`). The list-item, table and fence starters apply to comment text too.
  - A block's lines are joined with one space and its whitespace collapsed.
  - A block splits into sentences after `.`, `!` or `?`, optionally followed by `)`, `]`, `»`, `"`,
    `'`, `*`, `_` or a backtick, when whitespace follows and then an uppercase letter or `«`,
    optionally preceded by `(`, `[`, `"`, `*`, `_` or a backtick.
  - A citation is `ADR-` plus exactly four digits, not preceded by a letter or digit and not
    followed by a digit. Case-sensitive: `adr-0043` in a file name is not one.
  - Only the first citation of each number in a file is checked. It fails when the number is not
    held and the sentence, whitespace-collapsed and case-folded, contains no registry phrase
    (whitespace-collapsed and case-folded too). The reported line is the one holding the token.
- **Named limit:** the rule is per sentence, not per citation, so a qualifier in a sentence
  qualifies every number cited in it. That is the SPEC's «same sentence» rule, not a defect.

Done when: `python3 scripts/check-adr-references.py --self-test` exits 0 with no `FAILED` line,
`grep -cE 'ADR-[0-9]{4}' scripts/check-adr-references.py` prints 0, and the real-tree run behaves as
the progression under «Ownership and order» says for the tasks already landed.

### Task 3 — The ADR directory README (R-10, and the registry R-08 reads)

File: `docs/adr/README.md`. Rules 1 and 2 and the renumbering register do not change. Rule 3 becomes
the text below, and two sections go between it and `## Renumbering register`.

```markdown
## 3. A citation says where the ADR lives

- A number this directory holds means the file here, unless the citation carries another origin:
  a citation qualified with an origin from the table below means that origin even when the number
  exists here.
- An ADR this directory does not hold is cited with its origin in the same sentence, for example
  ADR-0155 of the retired concept-to-code workflow, not a Pergamenum ADR.
- The rule applies to the first citation of a number in each file. Later citations of the same
  number in that file may stay bare; they mean what the first one said.
- A number this directory holds, cited bare but meant in another series, cannot be told apart from
  a correct citation by its text, so no command detects it: qualify it when you write it. Five ADRs
  and one source comment cited the retired concept-to-code workflow's ADR-0053 that way until
  PG-273, while this directory's 0053 is a different record.

## External ADR series

The origins a citation may name, and the phrase that qualifies it. A citation is qualified when its
sentence contains a phrase of the second column, whatever the case and the line wraps. A new origin
is added here and nowhere else: `scripts/check-adr-references.py` reads this table.

| Origin | Qualifying phrase |
|---|---|
| The retired concept-to-code workflow (vibe-coding harness, pre 2026-09-14) | concept-to-code workflow |

## Checking the rules

`scripts/check-adr-references.py` checks the three rules on the working tree, and against
`origin/main` (or `--base <ref>`) when that resolves, so `git fetch origin` first. Exit 0 is clean,
1 a finding, 2 a check it could not run: this table unreadable, not a git repository, bad usage.
`--self-test` runs its own scenarios in throwaway repositories. `.github/workflows/adr-references.yml`
runs both on every pull request and every push to `main`, as an advisory check, never a required
one. The check is not in the pre-push hook, because a comment citation should not stop a push.

It checks less of rule 2 than the rule says: a status line in the head with one of the words
`accepted`, `proposed`, `superseded`, `deprecated` or `rejected`; no ADR on the base that reads
`proposed`; and, as a warning only, a commit hash in a status line that is not on the base's
first-parent line. The PR, hash and date that `accepted` should name are not checked. A record that
reaches `main` ahead of its implementation is reported while it reads `proposed` there.
```

If D2 is declined, the last sentence of rule 3's fourth bullet becomes: «ADR-0040 and ADR-0042 cited
the retired concept-to-code workflow's ADR-0053 that way until PG-273, and four more such citations
remain (`docs/plans/pg-273-adr-reference-check.md`, D2), while this directory's 0053 is a different
record.» If D4 is declined, the last sentence of «Checking the rules» goes.

### Task 4 — The baseline: every first external citation carries its origin (R-11, R-15)

Re-measured by sentence on 2026-09-26: 57 unqualified first citations in 52 files, exactly the
SPEC's list, plus D2's four ADR-0053 sites. Each site changes one sentence: the one holding the
citation. The form is «… of the retired concept-to-code workflow», adapted to the grammar.

Line rule, for every site except the manifests and the ADR-0041 heading:

- Insert the text, then, if the line passes 100 columns (characters, not bytes), split it once at
  the last space at or before column 100 that keeps «concept-to-code workflow» on one line.
- The new second line takes the same prefix: indentation plus `//` or `///` in Swift, the
  paragraph's or list item's continuation indentation in markdown.
- Never rejoin, reflow or re-indent any other line.

Worked example, `Tests/CardTextViewTests.swift:122`:

```swift
    /// PLAN DEVIATION (ADR-0073 §D2 of the retired concept-to-code workflow): the plan's Task 5
    /// brief claims an existing ".italic is
```

Sites (anchor → replacement):

| File:line | Anchor | Replacement |
|---|---|---|
| 35 × `docs/manifests/*.manifest.yml` | `(ADR-0068 §D1, §D11).` | `(ADR-0068 §D1, §D11 of the retired concept-to-code workflow).` (one line, no split; the two tracked `.manifest.yml.bak` files are not scanned and stay) |
| `Tests/CardTextViewTests.swift:122`, `Tests/MarkupHidingTests.swift:501`, `Tests/MarkdownAttributedTextTests.swift:15`, `Tests/ProseTypographyTests.swift:15` | `(ADR-0073 §D2)` | `(ADR-0073 §D2 of the retired concept-to-code workflow)` |
| `Sources/Core/Conventions/ImportNaming.swift:123` (D2) | `(ADR-0053)` | `(ADR-0053 of the retired concept-to-code workflow)` |
| `docs/specs/pg-066-dedupe-operationerror.spec.md:146` | `exit code, ADR-0138).` | `exit code, ADR-0138 of the retired concept-to-code workflow).` |
| `docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md:83` | `(ADR-0154: a harness` | `(ADR-0154 of the retired concept-to-code workflow: a harness` |
| same file `:438` | `per ADR-0158:**` | `per ADR-0158 of the retired concept-to-code workflow:**` |
| same file `:471` | `(ADR-0138).` | `(ADR-0138 of the retired concept-to-code workflow).` |
| `docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md:81` | `— ADR-0154: a harness` | `— ADR-0154 of the retired concept-to-code workflow: a harness` |
| `docs/superpowers/plans/2026-09-09-pratiche.md:92` | `— ADR-0154: a harness` | `— ADR-0154 of the retired concept-to-code workflow: a harness` |
| same file `:443` | `per ADR-0138).` | `per ADR-0138 of the retired concept-to-code workflow).` |
| `docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md:13` | `(ADR-0138).` | `(ADR-0138 of the retired concept-to-code workflow).` |
| same file `:17` | `(ADR-0154).` | `(ADR-0154 of the retired concept-to-code workflow).` |
| `PROJECT_BRIEF.md:330` (Italian) | `race ADR-0159 già documentata` | `race ADR-0159 del concept-to-code workflow ritirato già documentata` |
| `ROADMAP.md:955` | `cite "ADR-0155 §D1"**, which` | `cite "ADR-0155 §D1"**, an ADR of the retired concept-to-code workflow, which` |
| `docs/plans/chain-14-docs-consistency.md:99` | `- ADR-0073 in` | `- ADR-0073 of the retired concept-to-code workflow in` |
| same file `:101` | `- ADR-0068 in 37 files` | `- ADR-0068 of the retired concept-to-code workflow in 37 files` |
| same file `:102` | `- ADR-0138, ADR-0154, ADR-0158 in` | `- ADR-0138, ADR-0154, ADR-0158, all three of the retired concept-to-code workflow, in` |
| same file `:103` | ``ADR-0066 at `TODO.md:789`;`` | ``ADR-0066 at `TODO.md:789`, both of the retired concept-to-code workflow;`` |
| `docs/adr/0040-pratiche-attachment-reliability-bugs.md:39` | `**ADR-0053** (protected interfaces` | `**ADR-0053** (the retired concept-to-code workflow's ADR, not a Pergamenum one: protected interfaces` |
| `docs/adr/0042-pratiche-inline-image-placeholders.md:51` | `**ADR-0053** (protected` | `**ADR-0053** (the retired concept-to-code workflow's ADR, not a Pergamenum one: protected` |
| `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md:334` (D2) | `(ADR-0053 §D2).` | `(ADR-0053 §D2 of the retired concept-to-code workflow).` |
| `docs/adr/0038-remove-conformance-ui-section.md:12` (D2) | `(ADR-0053).` | `(ADR-0053 of the retired concept-to-code workflow).` |
| `docs/adr/0041-vault-layer-consistency-and-security-cha.md:671` (D2) | `(ADR-0053 — proposed, not written)` | `(ADR-0053 of the retired concept-to-code workflow — proposed, not written)` (a heading: never split) |

The 0040 and 0042 forms mirror the ADR-0155 qualification chain 14 wrote in the same «Depends on»
bullet. Their second mentions (0040:654, 0042:629, both headings) stay bare: rule 3 as amended.

Totals: 60 sites in 53 files (56 in 49 if D2 is declined). The three Swift test files and
`ImportNaming.swift` change comment lines only. `ImportNaming.recordingNoteTitle` is a protected
interface (`.claude/protected-interfaces`); its signature is not touched.

### Task 5 — The advisory workflow and the `CLAUDE.md` entry (R-13, R-14)

New file `.github/workflows/adr-references.yml`, text to copy:

```yaml
name: ADR references

# docs/adr/README.md's three rules (one number per file, a status line that says what landed, a
# citation that says where the ADR lives), checked by scripts/check-adr-references.py. PG-273, the
# follow-up of chain 14 (issue #581).
#
# A workflow of its own with no paths-ignore: ci.yml skips docs-only changes, and a docs-only PR is
# exactly the one that adds or edits an ADR. Same shape as merge-integrity.yml (ADR-0061 §D2).
#
# Advisory, never a required check (ADR-0044 §D11): main stays unprotected. Unlike the merge guard,
# nothing blocks locally either: this check reads prose, and a comment citation should not stop a
# push.
#
# The PR's base is resolved in the job as refs/remotes/origin/<base.ref> after a full-history
# checkout, never taken from pull_request.base.sha (ADR-0062 §D3): the 0061 collision of 2026-09-25
# was two branches that each looked clean against a base the other had not reached yet. A base that
# does not resolve is reported by the script, which then runs the in-tree checks only.
#
# The check runs even when the self-test is red (!cancelled()): one failure must not hide another.

on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: adr-references-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Self-test
        run: python3 scripts/check-adr-references.py --self-test

      - name: Check (pull_request)
        if: ${{ !cancelled() && github.event_name == 'pull_request' }}
        env:
          BASE_REF: ${{ github.event.pull_request.base.ref }}
          PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -euo pipefail
          base="refs/remotes/origin/$BASE_REF"
          echo "event base.sha: $PR_BASE_SHA"
          if resolved="$(git rev-parse --verify --quiet "$base^{commit}")"; then
            echo "resolved base ($base): $resolved"
          else
            echo "::warning::$base is not available in the job; base checks skipped"
          fi
          python3 scripts/check-adr-references.py --base "$base" --verbose

      - name: Check (push to main, manual dispatch)
        if: ${{ !cancelled() && github.event_name != 'pull_request' }}
        run: |
          set -euo pipefail
          python3 scripts/check-adr-references.py --base refs/remotes/origin/main --verbose
```

Facts behind it, checked on 2026-09-26 in the `actions/checkout` README and GitHub's
events reference:

- A `pull_request` run checks out the synthetic merge commit (`refs/pull/N/merge`). The in-tree rule 1
  therefore sees both files when a PR would create a duplicate.
- `fetch-depth: 0` maps `+refs/heads/*` to `refs/remotes/origin/*`, so the base ref exists in the job.
- A PR with a merge conflict does not run `pull_request` workflows at all.
- Upstream's README now shows `actions/checkout@v7`. This workflow pins `@v4` like `ci.yml` and
  `merge-integrity.yml`; bumping all three is its own chore.

`CLAUDE.md`, Commands block: two lines after `scripts/install-git-hooks.sh` (line 147), comments
aligned at column 97 like the neighbours:

```text
scripts/check-adr-references.py                                                                 # docs/adr/README.md's three rules on the working tree, against origin/main (git fetch first)
scripts/check-adr-references.py --self-test                                                     # its own scenarios, offline, in throwaway repositories, touches no repository
```

Nothing else in `CLAUDE.md` changes. The Git conventions' CI bullet is about `ci.yml` and stays
true.

### Task 6 — Verification and the PR body (R-12, R-15)

- Run the whole Acceptance block. The real-tree run must exit 0.
- Paste its two warnings (D1) into the PR body, with D3's residual in one line.
- The `Stop` hook's `.claude/test-cmd` unit run must be green on the last turn.
- `scripts/check-merge-integrity.py --landing origin/main HEAD` exits 0. Every edited path gets a
  blob it never held.

## After the merge (orchestrator, HITL)

- Close `PG-273` in `TODO.md` through the usual `chore(tasks)` sync, the way PR #597 closed
  `PG-284`, not in this chain's diff (parallel ledger edits conflict). If D3's follow-up is chosen,
  file it in the same sync.
- The first push to `main` runs the new workflow on `main` itself. Green is expected. A red there is
  a finding on `main`, not a flake.

---

## Requirement coverage

| R-id | Task(s) |
|---|---|
| R-01 | 1, 2 |
| R-02 | 1, 2 |
| R-03 | 1, 2 |
| R-04 | 1, 2 |
| R-05 | 1, 2 |
| R-06 | 1, 2 |
| R-07 | 1, 2 |
| R-08 | 1, 2, 3 |
| R-09 | 1, 2 |
| R-10 | 3 |
| R-11 | 4 |
| R-12 | 6 |
| R-13 | 5 |
| R-14 | 5 |
| R-15 | 4, 6 |

Every R-id the SPEC declares is cited. The SPEC's `(no-test: …)` markers exempt the test axis only.

## Acceptance (reviewer; bash, from the repo root, after `git fetch origin`)

Run under `bash`, not zsh: the loops rely on word splitting.

```bash
S=scripts/check-adr-references.py
T="${TMPDIR:-/tmp}"

# R-09
before="$(git status --porcelain; git for-each-ref; git stash list)"
python3 "$S" --self-test > "$T/adr-selftest.txt"; echo "exit $?"                   # exit 0
after="$(git status --porcelain; git for-each-ref; git stash list)"
[ "$before" = "$after" ] && echo "real repository untouched"                         # printed
grep -c '^FAILED' "$T/adr-selftest.txt"                                             # 0
grep -nE '"(fetch|clone|ls-remote|pull|push)"|urllib|socket|http\.client' "$S"      # empty: offline
git ls-files -s "$S" | cut -c1-6                                                    # 100755

# R-01..R-08, self-test half: at least one pass and one fail/warn/notice case each
for r in R-01 R-02 R-03 R-04 R-05 R-06 R-07 R-08; do
  printf '%s pass=%s other=%s\n' "$r" "$(grep -c "^ok: $r pass: " "$T/adr-selftest.txt")" \
    "$(grep -cE "^ok: $r (fail|warn|notice): " "$T/adr-selftest.txt")"
done                                                                                # every count >= 1

# R-12 (and the real-tree half of R-01..R-08)
python3 "$S" --base origin/main --verbose > "$T/adr-run.txt"; echo "exit $?"         # exit 0
grep -c ': rule [123]: ' "$T/adr-run.txt"                                            # 0
grep ': warning (rule 2): ' "$T/adr-run.txt"                                         # exactly 2: docs/adr/0048-…:3 ef8d28d, docs/adr/0064-…:3 c2cf19b (D1); into the PR body
tail -1 "$T/adr-run.txt"                                                             # rule 1: 0, rule 2: 0, rule 3: 0 findings; 2 warnings

# R-01
ls docs/adr | grep -E '^[0-9]{4}-' | cut -c1-4 | sort | uniq -d                      # empty

# R-02
grep '^base:' "$T/adr-run.txt"; git rev-parse origin/main                            # same sha
python3 "$S" --base no-such-ref | grep -c '^notice: '; echo "exit ${PIPESTATUS[0]}"  # 1, exit 0

# R-03, R-04
grep -c ': rule 2: ' "$T/adr-run.txt"                                                # 0

# R-05: see the two warnings under R-12; the exit code stayed 0

# R-06
grep -c ': rule 3: ' "$T/adr-run.txt"                                                # 0

# R-07
grep -cE 'ADR-[0-9]{4}' "$S"                                                         # 0
grep -c "^$S:" "$T/adr-run.txt"                                                      # 0
grep '^scanned:' "$T/adr-run.txt"
git ls-files -- '*.swift' '*.md' '*.yml' '*.yaml' '*.py' '*.sh' | grep -vxE 'TODO.md|SPEC.md' | wc -l   # same n (1170: 1167 + plan + script + workflow)

# R-08
grep -c '^## External ADR series$' docs/adr/README.md                                # 1
grep -c '^| Origin | Qualifying phrase |$' docs/adr/README.md                        # 1
grep -c '| concept-to-code workflow |$' docs/adr/README.md                           # 1

# R-10
R=docs/adr/README.md
grep -c 'means that origin even when the number exists here' "$R"                   # 1
grep -c 'first citation of a number in each file' "$R"                              # 1
grep -c 'no command detects it' "$R"                                                 # 1
grep -c 'scripts/check-adr-references.py' "$R"                                       # >= 1
diff <(git show "origin/main:$R" | sed -n '/^## 1\./,/^## 3\./p') <(sed -n '/^## 1\./,/^## 3\./p' "$R")   # empty: rules 1 and 2 untouched
diff <(git show "origin/main:$R" | sed -n '/^## Renumbering register/,$p') <(sed -n '/^## Renumbering register/,$p' "$R")   # empty

# R-11
files=$(git diff --name-only origin/main...HEAD | grep -vxE 'SPEC.md|CLAUDE.md|docs/adr/README.md|docs/plans/pg-273-adr-reference-check.md|scripts/check-adr-references.py|\.github/workflows/adr-references\.yml')
printf '%s\n' $files | wc -l                                                         # 53 (49 if D2 declined)
printf '%s\n' $files | grep -c '^docs/manifests/.*\.manifest\.yml$'                   # 35
git diff -U0 origin/main...HEAD -- $files | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' | wc -l            # 60 (56): one removed line per site
git diff -U0 origin/main...HEAD -- $files | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' \
  | grep -vcE 'ADR-(0053|0066|0068|0073|0138|0154|0155|0158|0159)'                    # 0: every removed line held a baseline citation
git diff -U0 origin/main...HEAD -- $files | grep -E '^\+' | grep -vE '^\+\+\+ (b/|/dev/null)' \
  | grep -c 'concept-to-code workflow'                                                # 60 (56): the phrase on one line per site
git diff --name-only origin/main...HEAD -- TODO.md                                   # empty

# R-13
W=.github/workflows/adr-references.yml
grep -c 'paths-ignore' "$W"                                                          # 0
sed -n '/^on:/,/^concurrency:/p' "$W"                                                # pull_request, push to [main], workflow_dispatch
grep -c 'fetch-depth: 0' "$W"                                                        # 1
grep -c 'refs/remotes/origin/\$BASE_REF' "$W"                                        # 1
grep -n 'check-adr-references.py' "$W"                                               # --self-test first, then the two checks
gh api repos/istefox/Pergamenum/branches/main/protection 2>&1 | grep -c 'not protected'   # 1: no required check added

# R-14
grep -c 'scripts/check-adr-references.py' CLAUDE.md                                  # 2
grep -c 'check-adr-references.py --self-test' CLAUDE.md                              # 1

# R-15
git diff -U0 origin/main...HEAD -- Sources Tests \
  | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' | grep -vE '^[-+][[:space:]]*//'      # empty: comment lines only
# and .claude/test-cmd green on the last turn (Stop hook)

# ADR-0062 landing check
scripts/check-merge-integrity.py --landing origin/main HEAD; echo "exit $?"           # exit 0
```

## Out of scope, measured and left

- The 315 manifest collisions of D3, unless Stefano chooses a follow-up.
- The full rule 2 (PR, hash and date on every `accepted`), and ADR-0049's status line: SPEC Out of
  scope.
- The two warning hashes (0048 `ef8d28d`, 0064 `c2cf19b`): reported, not rewritten (SPEC Out of
  scope; chain 14 D5 for 0064).
- Citation forms other than `ADR-NNNN`, such as the bare `0055/0058/0064` after the first number in
  ADR-0063:20: SPEC Out of scope.
- The `actions/checkout` major bump across the three workflows.

## Risks and HITL gates

- **HITL:** G1 (D1–D4); every commit and the push, where the pre-push hook runs ADR-0061's and
  ADR-0062's checks; `/ship`'s diff review; the post-merge `TODO.md` sync. No deploy, no schema
  change, no deletion.
- **The sentence rule is a heuristic.** A false split or join changes which sentence a qualifier
  belongs to. Today's tree is the proof (57 findings before Task 4, 0 after, with the rule as
  written); the scenarios pin wraps, comment blocks and list items. A future false positive is
  fixed by rewording the sentence or refining the rule with a new scenario, never by an allowlist
  (SPEC Decision).
- **A stale local `origin/main`** hides a base collision. The README says fetch first, and CI
  resolves the base fresh.
- **A parallel chain** may land an ADR or an unqualified external citation before this PR. Then the
  real-tree run turns red at merge time. Merge `origin/main` again, re-run the Acceptance block, and
  qualify the new site in this chain if it is one sentence.
- **Red on unrelated PRs.** Once this lands, a `proposed` ADR on `main` makes every PR's run red
  until it is flipped. Intended: the advisory red is the reminder rule 2 asks for.
- **Pre-commit scanners.** The secret scanner's `assigned-secret` heuristic fires on `token` next to
  `=` and a long identifier. Name the hex-scanning variables otherwise, or read and dismiss each hit.
  The weakening scan does not read Python assertions; review the self-test by reading it.
- **A comment split that breaks a Swift build** is unlikely (line comments only), and the Stop
  hook's unit build plus `ci.yml` on the PR catch it.
- **Markdown list continuation.** A split line inside a list item needs the item's indentation, or
  the rendered list breaks. The reviewer reads the rendered diff of the chain-14 plan and ROADMAP.
- No externally provisioned resource: no API, console, secret or env var. The workflow uses only
  `contents: read`.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
