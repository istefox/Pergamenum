Status: Approved (2026-09-21)

# SPEC — Replace the UI suite as the merge gate

## Destination

A SPEC handed to `/workplan`: three stages, each a useful stopping point. When the work is done the
check that guards a merge to `main` is the unit suite plus in-process tests, no longer the 121-test
UI suite; 17 targeted GUI tests remain, run through `--affected` at merge and never blocking; a run
disturbed by the machine is recorded as `contaminated`, neither green nor red; and a new feature
carries at most 2 or 3 GUI tests of its own.

## Objectives

The merge gate must give the same answer whatever the Mac is doing. Today a full run takes about 26
minutes and its verdict depends on focus stolen by another app, an installed copy of the app
appearing mid-run, an external monitor and automation timeouts, so a red is often nobody's defect
(PG-182, PG-186, PG-188, PG-194). Given up first: full coverage of gestures and layout, then speed.
The per-test triage of all 121 tests, approved file by file on 2026-09-21, is the source of truth
for what leaves the suite; this SPEC does not re-decide it.

## Scope and non-goals

In: the `contaminated` verdict and its detection; one ADR for the package of test seams; the seam
refactors; the replacement unit and in-process tests; deleting the approved GUI tests; the rule
change in `CLAUDE.md`; the regime for future features.
Out: a Tart VM (PG-187), running the GUI suite in CI, a rewrite of the runner script, PG-195, any
new feature (full list in Out of scope).

## Decisions

- **Replace the merge gate, not reduce it.** The gate becomes the unit suite plus in-process tests
  (real views hosted in a never-shown window, events sent directly). Rejected: a reduced gate with a
  UI smoke set: it keeps a machine-dependent step in every merge.
- **Per-test triage, then retire.** Every one of the 121 tests is Keep, Convert or Retire, approved
  by Stefano file by file. Result: 17 keep, 42 convert (2 of them stay GUI until their replacement
  exists), 62 retire outright, so 104 leave the GUI suite. Rejected: keeping the suite whole and
  fixing its determinism: it does not remove the dependence on the machine.
- **Stage order: verdict, then seams and tests, then the gate.** Stage 1 is the `contaminated`
  verdict (relief with no production code). Stage 2 is seams and replacement tests, deleting each
  converted GUI test in the PR that adds its replacement. Stage 3 is the outright retirements and the
  `CLAUDE.md` rule change. No test is retired before its replacement exists. Rejected: the rule
  change first (for a period the gate would cover less than before); one chain with no stopping point.
- **The 17 GUI tests that remain are not a blocking gate.** The person merging runs
  `uitests.sh --affected`; a green or red is information, `contaminated` does not block. The full
  run of the 17 happens before a release. Rejected: only before a release (no GUI signal at merge at
  all); blocking as today (the cost grows with the set).
- **Retiring a test deletes it from the source**; git history keeps it. Each PR lists what it
  deleted and points at the approved census entry. Rejected: moving files to an excluded folder
  (dead code that ages).
- **Unit suite time budget: under 60 s** for the whole suite (about 18 s today), because it runs at
  the end of every turn through the Stop hook. Over budget, a block moves to a group run at merge.
  Rejected: no fixed number; 30 s (would cap how many hosted tests can exist).
- **If hosting a SwiftUI or Workspace view in-process fails**, the tests that depend on it stay GUI
  until replaced, and the cap of 17 rises only with Stefano's approval, test by test. Rejected:
  retiring them on their logic cover alone (declares the wiring lost without a decision); stopping
  the work to reopen the direction.
- **One ADR for the whole package of seams, written and Accepted before the first production
  refactor** (start of stage 2). A seam found later amends it. Rejected: an ADR written at the end
  as a register (a seam with no decision written first); one ADR per stage (contradicts the single
  ADR Stefano chose).
- **Seams are accepted only if behaviour is unchanged.** The proof is `uitests.sh --affected` on the
  seam commit before its GUI test is deleted: green, or `contaminated` then green on the rerun.
  Rejected: proof by the replacement test alone (written by the author of the seam, so circular);
  diff review alone (not repeatable).
- **Disturbance signals: installed copy appeared mid-run, launch failure or timeout, focus taken by
  another app, external monitor connected.** Rejected: none; the monitor signal needs a new
  detector, which is accepted.
- **A run with reds and at least one signal is `contaminated`, and only the failed tests are rerun
  once.** Rerun green gives `green`; rerun red with no signal gives `red`. Rejected: `contaminated`
  with no rerun (leaves the decision to the person merging); staying `red` with a note (does not
  solve the problem).
- **Exit codes: 0 green, 1 red, 2 contaminated.** `--status` shows it and does not count it as
  verified. Rejected: 0 (hides that it is not a green); 1 (blocks whoever reads only the exit code,
  against the rule that it does not block).
- **Stage 1 also fixes PG-194 (a 0-test run is not a red) and saves log evidence for PG-182.**
  Rejected: adding PG-195 (merge with no verdict), a new check, not part of the verdict.
- **The verdict logic gets an offline `--self-test` mode**, on the model of the appcast script's.
  Rejected: a hand check only (not repeatable); rewriting the 581-line runner in Python (out of
  proportion for this stage).
- **One PR per functional area in stage 2**, roughly six to eight. Rejected: one PR per UI test file
  (about 16 small PRs, more merge rounds); a single PR (one huge diff, no stop).
- **The cap of 17 is informational, and the future regime is convention.** `--status` prints the GUI
  test count against 17; `CLAUDE.md` and the plan template carry the rule of at most 2 or 3 GUI tests
  per new feature, justified in the feature's ADR. Rejected: a check that fails above the cap (one
  more thing to maintain); text only.
- **VM (PG-187) on hold.** The in-process route comes first. Rejected: starting the VM now.
- **A `contaminated` verdict does not block a merge on its own.** Rejected: treating it as red.

## Constraints

- **No test is retired without Stefano's approval of its entry** — origin: user mandate. The
  triage in the census is that approval; a new candidate needs a new one.
- **A seam changes no behaviour** — origin: user mandate.
- **A test is never disabled to make a suite pass** — origin: global rules. Deleting an approved
  test is not disabling; disabling stays forbidden.
- **The Stop hook runs the unit target only** — origin: the repository's working agreements, after
  UI launches killed the app in use. Hosted tests join that target and must never show a window or
  take focus.
- **Files shared with the two command line tools must not import SwiftUI** — origin: ADR-0001 §D1.
  A seam placed there stays Foundation-only.
- **Every UI-test file keeps its launch flags** (calendar, updater, Mail store, and the others in the
  working agreements) — origin: existing rules.
- **The generated project is never edited by hand**; a change that adds or removes a file is
  followed by regeneration — origin: working agreements.
- **Work happens on a feature branch, never on `main`**, with `/plan` and `/build` in separate
  sessions — origin: user mandate.

## Stack

Swift 6 with Swift Testing for the unit and hosted tests, on the existing unit target; XCTest for
the surviving GUI tests; the shell runner script for verdicts; Tuist for regeneration.

## Data model

The verdict record, one per tree and scope, gains a third result and its reasons.

| Field | Values |
|---|---|
| result | green, red, contaminated |
| scope | full, partial (unchanged) |
| reasons | zero or more of: installed copy, launch failure, focus taken, external monitor |
| executed | number of tests that ran |

A run that executes zero tests is an error state: reported, never stored as `red`, and it does not
overwrite the tree's existing verdict.

Classification after a run: all tests passed gives `green` whatever the signals (they are recorded);
reds and no signal gives `red`; reds and at least one signal gives `contaminated` and triggers one
rerun of the failed tests; the rerun settles it (green, red with no signal), or leaves it
`contaminated` if the rerun was disturbed again.

## API / interfaces

The runner script: a third exit code (2), `--status` output naming `contaminated` and its reasons,
the GUI test count against the cap, and a `--self-test` mode. Production interfaces are the seams the
ADR lists; each is a refactor with unchanged behaviour: entering a folder from the Workspace
controller (replacing three copies of the resolver switch), the row label, the drawn embed's
accessibility summary, the Cmd-state at the editor coordinator, focus derivation on navigation,
the Task view's day-to-view mapping, whether a row can move to a destination, the diary drag
geometry, the category editor's disable predicate, and the day timeline's hours as a pure function.
Protected interfaces named in the working agreements stay untouched.

## Edge cases

- A run over a dirty tree records no verdict (existing behaviour, kept).
- An installed copy already open before the run still refuses the run (existing behaviour, kept); one
  that appears during the run is a signal, and its surrounding launch log is saved.
- The rerun is itself disturbed: the verdict stays `contaminated`.
- A green run with signals stays green; the signals are recorded, not acted on.
- The external monitor is connected for the whole run: it counts as a signal only alongside reds.
- Two hosted tests share a window or a controller: each test builds its own; nothing is shared.
- A converted test whose replacement cannot be written: it stays as a GUI test and the cap
  conversation is reopened with Stefano.

## Test seams

Existing over new, highest possible, few:
1. The unit target: logic and the pure functions the seams extract.
2. The same target for hosted views, reusing the existing editor and Workspace harnesses. The first
   step of stage 2 is a prototype proving that a SwiftUI view and a Workspace view can be hosted.
3. An offline self-test of the runner script's verdict logic, the only new seam.
4. The affected GUI tests, used as the proof that a seam changed nothing, not as a new test.

## Success criteria

Stage 1: the verdict.
- [ ] R-01 — A run records `contaminated` as a third result, with its reasons, in the same per-tree
  record as green and red.
- [ ] R-02 — The four signals are detected during a run: installed copy appeared, launch failure or
  timeout, focus taken by another app, external monitor connected.
- [ ] R-03 — Reds and at least one signal produce one rerun of only the failed tests; rerun green
  gives `green`, rerun red with no signal gives `red`, a disturbed rerun leaves `contaminated`. A run
  with no reds is `green` whatever the signals.
- [ ] R-04 — Exit code is 0 for green, 1 for red, 2 for contaminated; `--status` shows the reasons and
  never treats `contaminated` as verified; only `green` lets a later run be skipped.
- [ ] R-05 — A run that executes zero tests is reported as an error, is never stored as `red`, and
  does not overwrite the tree's existing verdict (PG-194).
- [ ] R-06 — When an installed copy appears mid-run, about 10 seconds of the launch log around that
  moment are saved next to the run's evidence (PG-182).
- [ ] R-07 — The offline self-test asserts R-03, R-04 and R-05 with fabricated logs and signals, and
  needs neither a build nor a GUI.

Stage 2: seams and replacement tests.
- [ ] R-08 — A prototype hosts one SwiftUI view and one Workspace view in a never-shown window with
  events sent directly, inside the unit target, and its outcome is recorded before any dependent test
  is converted. A view that cannot be hosted keeps its GUI test (cap changes need approval).
- [ ] R-09 — One ADR, Accepted before the first production refactor, lists every seam of the census
  and the rule that a seam changes no behaviour; a later seam amends it.
- [ ] R-10 — Each seam is proved neutral by `--affected` on its commit before its GUI test is
  deleted: green, or contaminated then green on the rerun.
- [ ] R-11 — Every converted test has its replacement (unit or hosted) in the same PR that deletes
  its GUI test; the two keep-until-replaced tests are deleted only when theirs exists.
- [ ] R-12 — The unit tests the census names as coverage to add (for the day and task controllers,
  `WindowPlace` and `DiaryGeometry`, among others) exist and pass.
- [ ] R-13 — Each PR covers one functional area and lists the tests it deleted with their census
  entry and the wiring lost.
- [ ] R-14 — The whole unit suite stays under 60 seconds after every PR; over that, a block moves to
  a merge-only group.
- [ ] R-15 — No hosted test shows a window, takes focus or reads calendar, Mail or update state.

Stage 3: the gate.
- [ ] R-16 — The 62 outright retirements are deleted in their approved groups, only after stage 2's
  replacements exist; afterwards exactly 17 GUI tests remain.
- [ ] R-17 — `--status` prints the GUI test count against the cap of 17.
- [ ] R-18 — `CLAUDE.md` states: the merge gate is the unit suite and in-process tests; the 17 GUI
  tests run through `--affected` at merge and do not block; the full 17 run before a release;
  `contaminated` is neither green nor red; a new feature carries at most 2 or 3 GUI tests, justified
  in its ADR. (no-test: documentation obligation, checked by review)
- [ ] R-19 — The rule text about the UI suite that now contradicts the above (run before every merge,
  the last regressions found there) is amended, not left beside it. (no-test: documentation
  obligation, checked by review)

## Not yet specified

- Whether SwiftUI and Workspace views can be hosted in-process at all: proven only for one SwiftUI
  entry point today; R-08 is the way to find out.
- The detection method for the external monitor, a new detector with no precedent here.
- Who sends the launch request that starts the installed copy: seen once in the log, sender not
  visible (PG-182); R-06 collects evidence, it does not promise a cause.
- Whether the surviving GUI suite can run on the hosted macOS 27 runner (label `xcode-27`, public
  preview, checked 2026-09-21 in the images repository): a trial run is needed, and CI does not run
  the GUI suite in this SPEC.
- Several converted tests rest on seams or existing tests the census marks "to verify in `/plan`":
  those checks belong to planning, not to this SPEC.

## Out of scope

- **A Tart VM (PG-187):** on hold by Stefano's choice, in favour of the in-process route.
- **The GUI suite in CI:** the runner exists, but whether it gives a usable GUI session is
  unverified, and the gate no longer needs it.
- **Rewriting the runner script in another language:** out of proportion for a verdict change.
- **PG-195 (a merge with no verdict for the tree):** a separate check, not part of the verdict.
- **A check that fails above the cap:** the cap is informational by decision.
- **Enforcing the full run of the 17 inside the release script:** a documented process step, not a
  change to the release pipeline.
- **New features:** none, apart from the regime that governs their GUI tests once they exist.
- **Changing what the 17 surviving tests assert:** two defects noted in the census (a negative check
  with no wait, a fixed sleep) are fixed only when those files are next touched.

## Domain terms

- **Contaminated:** a run with reds and at least one machine-disturbance signal that the rerun did
  not settle; neither green nor red, and it does not block a merge by itself.
- **Hosted test:** a test that builds a real AppKit or SwiftUI view in a window that is never shown
  and sends it events directly, inside the unit target.
- **Seam:** a small production refactor whose only purpose is to make behaviour testable, with no
  change in what the app does.
- **Keep-until-replaced:** a test that stays a GUI test only until its hosted replacement exists.
