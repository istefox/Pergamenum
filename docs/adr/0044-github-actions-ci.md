# ADR-0044: CI checks that the three targets compile from a clean checkout, and nothing else

- Status: proposed — **decided, not implemented** (see §D13 and the implementation plan)
- Date: 2026-09-13. Written after reading the generated schemes, `Project.swift`, `.claude/test-cmd`,
  `scripts/uitests.sh`, `.swiftlint.yml`, `.gitignore` and the open UI-test tickets in `TODO.md`, on
  the working tree at `790bbca` (`emdash/fix-pg-072-composeruitests-zythq`, PR #258 merged). Every
  claim below about this repository was read out of the tree, not recalled. Every claim about
  GitHub's runners and billing was fetched from `docs.github.com` and `actions/runner-images` on the
  date above and is marked with what was and was not found there.
- **Relocation note:** drafted at `docs/architecture/ADR-0044-github-actions-ci.md` (the architect
  agent's enforced write scope, `test-write-scope.sh`) and relocated to `docs/adr/0044-github-actions-ci.md`,
  where this repo's ADRs live (`0001`…`0043`) and which every reference below already assumes. Same
  convention ADR-0029…ADR-0036 and ADR-0040…ADR-0043 carry in their own headers.
- **Numbering note:** `0043` is the highest on `origin/main`
  (`docs/adr/0043-vault-write-ordering-concurrency-races.md`) and no `0044` exists in any commit
  reachable from `--all`. Checked rather than assumed, because ADR-0043's own header records the
  branch listing that looked free and was not.
- **Reopens nothing.** No SPEC §14 decision is revisited. No on-disk format, no schema, no frontmatter
  key, no tag grammar, no user-visible behaviour. No file under `Sources/` or `Tests/` is touched by
  this decision, and no test is added, skipped or removed.
- **Runner amended 2026-09-18.** `runs-on: macos-26` and the `Xcode_26.6.app` pin (§D2, §D3, the
  workflow excerpt above) were raised to `runs-on: xcode-27` and `Xcode_27.0.app`, matching the
  project-wide macOS 27/Xcode 27 baseline bump (`Project.swift`'s `deploymentTarget`, CLAUDE.md).
  `xcode-27` is GitHub's own per-Xcode-major-version label (public preview at the time of this
  amendment), replacing the per-OS-version label this ADR was written against; confirmed live
  against `actions/runner-images` before pinning, not assumed. Body below is left as written for
  its own decided-at-the-time record; this note is the current state.
- **Adds no exception to CLAUDE.md principle 2, and needs none.** Principle 2 governs what the *app*
  does at runtime. A machine that compiles the app is not a feature of it. ADR-0031 §D13's updater
  exception and ADR-0032's loopback exception are untouched, and this ADR adds no third one: nothing
  in `Sources/`, `Sources/Connector/` or either `.commandLineTool` target learns that CI exists.
- Depends on: **ADR-0001 §D1** (`Sources/Core` imports no SwiftUI — the invariant this ADR exists to
  give an enforcer), **ADR-0007 §D2** (the two connectors compile the same files on disk as the app),
  **ADR-0031 §D4** (`-disableUpdater` and the test-host isolation the unit suite already relies on),
  **ADR-0017** (`VaultState.isRunningUnderTest`), and CLAUDE.md's working agreements on
  `.claude/test-cmd` and `scripts/uitests.sh`.

---

## Context

This repository has never had CI, and no ADR, `TODO.md` entry or brief records a decision not to.
The only traces are two sentences stating the fact — `PROJECT_BRIEF.md:662` («…CI configurata su
questo repository, quindi nessun check da attendere prima del merge») and `TODO.md:468` («the repo
has no CI, so "green" always means a local `xcodebuild test`») — neither of which gives a reason. So
there is no prior decision to amend here, only an absence to fill.

The honest reconstruction, offered as a reconstruction and not as a finding: for most of this
project's life a hosted macOS runner could not have built it. The app is macOS 26-only with no
compatibility fallbacks (SPEC §2, §14), Swift 6 on the macOS 26 SDK, and GitHub's `macos-26` image is
recent. That obstacle is gone, which is what makes the question live now rather than earlier.

### What was read in this repository, at the line, before deciding

1. **The per-turn check builds one target out of three.** `.claude/test-cmd` runs
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum … -only-testing:PergamenumTests test`.
   The generated `Pergamenum` scheme's build action lists exactly three buildables — `Pergamenum.app`,
   `PergamenumTests.xctest`, `PergamenumUITests.xctest`. **`perg` and `pergamenum-mcp` are not in it.**
   Read out of `Pergamenum.xcodeproj/xcshareddata/xcschemes/Pergamenum.xcscheme`, not inferred.
2. **Which means ADR-0001 §D1 currently has no automated enforcer at all.** CLAUDE.md states the
   invariant and its teeth: «a new file under `Sources/Core` that imports SwiftUI **breaks both tool
   builds**, which is ADR-0001 §D1 enforcing itself. It found three inverted dependencies the first
   time it ran.» It enforces itself only when somebody builds the connectors, and nothing on any
   automated path does. The same goes for the second consequence CLAUDE.md records — «a new file
   outside those globs that a tool needs must be added to `sharedSources` by hand» — which is 39 glob
   entries maintained by memory.
3. **There is already a scheme that builds everything.** The Tuist-generated
   `Pergamenum.xcworkspace/xcshareddata/xcschemes/Pergamenum-Workspace.xcscheme` lists all five
   buildables, and `perg` and `pergamenum-mcp` both carry `buildForTesting = "YES"` (checked by
   parsing the `BuildActionEntry` blocks). So one `test` invocation on that scheme compiles the app,
   both test bundles and both connectors. This is the finding that makes §D4 cheap.
4. **The project is generated, so CI must generate it.** `.gitignore` ignores `*.xcodeproj` and
   `*.xcworkspace`; `Tuist/Package.resolved` *is* committed, so the SPM graph is pinned and
   reproducible. `.tuist-version` is ignored, so nothing in the repo records which Tuist generated
   the project.
5. **Signing is declared on every target and is about TCC, not about distribution.** `baseSettings`
   (`Project.swift:9-30`) carries `DEVELOPMENT_TEAM: T7H24G7BFW`, `CODE_SIGN_STYLE: Automatic` and
   `CODE_SIGN_IDENTITY: "Apple Development"`, with a comment (`:12-18`) recording why the default
   ad-hoc `-` was wrong: «TCC keys a privacy grant to the signing identity, and an ad-hoc signature
   has none, so it keys on the binary hash instead. Every rebuild then throws away the Calendar and
   Reminders permission… It cost an afternoon to recognise, twice mistaken for a broken read.» That
   reasoning is about the machine the app runs on. A runner has no certificate for that team and no
   grant to lose.
6. **The unit suite runs inside the app.** `TEST_HOST` is set to
   `$(BUILT_PRODUCTS_DIR)/Pergamenum.app/…/Pergamenum` in the generated project, and CLAUDE.md says
   the same from the other end («the unit test bundle is hosted inside the app, at Contents/PlugIns»).
   Running `PergamenumTests` therefore launches the app. Two of the three things that would reach
   outward already isolate themselves under a test host: `SparkleUpdateController`
   (`:45-91`, `defaults.bool(forKey: "disableUpdater") || isTestHost`, where `isTestHost` is the
   `XCTestConfigurationFilePath` check) and `VaultState.isRunningUnderTest` (`VaultState.swift:51`).
   The third does not: `CalendarService.isIsolated` (`CalendarService.swift:151`) reads only
   `UserDefaults.standard.bool(forKey: "disableCalendar")`, so a unit-test host with no
   `-disableCalendar YES` enters EventKit on its own. No file under `Tests/` imports EventKit, so the
   likely outcome on a runner is a denied request and no events — likely, not verified. §D13 is about
   that word.
7. **The unit suite is otherwise self-contained.** 231 files, ~54k lines, 2,900 tests green as of
   `PG-149`. Nothing imports EventKit. `PlaudHTTPClientTests` uses a stubbed transport, saying so in
   its own comment («no socket, no `127.0.0.1:3777` service required»). `MailStoreFixture` builds a
   schema-accurate Envelope Index rather than reading `~/Library/Mail`. `ReleasePipelineTests` shells
   out to `scripts/appcast.py --self-test` and `bash -n scripts/release.sh`, both offline and both
   available on any runner.
8. **The UI suite is red right now, and has been for weeks, by known tickets.** `PG-149` records the
   2026-09-12 pre-merge run: «118 tests, 3 failures, all pre-existing and unrelated». The open
   tickets behind them are `PG-076` (two tests, «intermittent timing», six recorded runs, passing on
   some and failing on others) and `PG-108` (two tests, one asserting `XCTAssertGreaterThan "460.0"`
   not greater than `"460.0"`, the other reading an empty accessibility label). One of `PG-108`'s
   assertions is pixel-exact geometry.
9. **This repo has already priced a noisy suite, twice.** `PG-026`: a run started with a stale
   instance gave «18 failures that were not real defects, every one timing out at exactly 60.2 s»,
   and CLAUDE.md records that «two hours went into hunting an external culprit for something the
   assistant was doing itself». `PG-033`: three of sixty-seven UI tests «had been red since before
   the milestone about to be merged, and nothing had said so». The first is the cost of false red;
   the second is the cost of an unwatched suite. Both bear directly on what belongs in CI.
10. **SwiftLint currently fails on this codebase by design.** `.swiftlint.yml`'s own comment: the
    `file_length` defaults are «currently failing on seven types (VaultController, WorkspaceView,
    WorkspaceController, VaultBrowser, NoteListPane, MarkdownStyler, EditorDecorationDelegate). That
    is real debt, recorded rather than configured away.»
11. **The codebase is not small.** 524 files and ~90k lines under `Sources/`, ~54k under `Tests/`,
    ~5k under `UITests/`, Swift 6 strict concurrency throughout, SwiftUI-heavy. `tuist install`
    resolves Sparkle plus the MCP SDK and its transitive tree (swift-nio, atomics, collections, log,
    system, EventSource). A cold runner pays for all of it before the first line compiles.

### What was verified about GitHub, and what could not be

Fetched 2026-09-13, stated with its provenance because the numbers move:

- **`macos-26` exists, is GA, is arm64, and is what `macos-latest` currently points at**
  (`actions/runner-images` README). `macos-26-large` / `-intel` are x64; `macos-26-xlarge` is a
  larger runner. The image carries Xcode 26.0.1 through 26.6, default 26.6.
- **Standard macOS runners list at `$0.062`/minute** (3-core or 4-core); 5-core is `$0.102` and
  12-core `$0.077` (`docs.github.com/billing/reference/actions-runner-pricing`). The same page states
  «Included minutes cannot be used for larger runners» — so an `-xlarge` or `-large` job is billed
  from its first second and draws on no allowance at all.
- **Included minutes: 2,000/month on Free, 3,000 on Pro and Team.**
- **The 10x multiplier could not be confirmed as current.** Three GitHub pages were read. None
  carries the historical Linux 1x / Windows 2x / macOS 10x table any more. The usage-metrics page
  still refers to «minute multipliers» in passing, so the concept has not been declared dead; the
  December 2025 changelog announced a repricing effective 2026-01-01 and says included quotas are
  consumed «based on list price». **This ADR therefore does not rest on resolving it** — the
  arithmetic below is given under both readings, and §D6's rejection of the UI suite does not depend
  on either.

### The cost, under both readings

A Tier-1 job (§D1) is one cold runner doing: checkout, Tuist install, `tuist install`,
`tuist generate`, then one `xcodebuild` that compiles ~90k lines of Swift 6 into an app plus ~54k
lines of tests plus two more modules, then runs 2,900 tests. Estimate, not measurement: **20–35
minutes cold, 12–20 warm** with §D9's cache. Task 4 of the plan replaces this estimate with two real
numbers.

At 25 minutes and ~20 runs a month (the `pull_request` + `push: main` triggers of §D1, not every
push):

| Reading | Billable | On Free (2,000 incl.) | On Pro (3,000 incl.) |
|---|---|---|---|
| No multiplier (current docs) | 500 min | **$0** | **$0** |
| Historical 10x against the allowance, overage billed on actual minutes | 200 actual min free, then 300 × $0.062 | **≈ $19/mo** | **≈ $12/mo** |

**The plan tier changes the bill, not the decision.** Even the pessimistic reading buys, for less
than twenty dollars a month, the only mechanical enforcement ADR-0001 §D1 has ever had. That is the
number that settles this, and it is worth stating plainly because "10x macOS minutes" sounds like a
reason to refuse before anybody multiplies it out.

### Why the UI suite is the wrong thing to automate first, which is the counter-intuitive part

The obvious case for CI here is `PG-072`: a UI test that sat broken for a fortnight and was fixed
this session. It is a weaker case than it looks, and the weakness is worth writing down.

`PG-072` was never undetected. It was opened 2026-08-28, carries five recorded runs, and sat at `P3`
until somebody chose to work on it. Its siblings are the same: `PG-076` has six runs recorded across
three weeks, `PG-108` two. These tickets are not a story about a defect nobody saw. They are a story
about a defect everybody saw and nobody prioritised. **CI does not change a priority.**

What CI would genuinely add for that suite is frequency of observation — enough samples to tell a
flaky test from a broken one. Set against that: a hosted runner is slower hardware with a different
display than the machine those assertions were written against, and the open failures are precisely
the machine-sensitive kind (`"460.0"` not greater than `"460.0"`; an accessibility label read as
empty; two tests that «reproduced byte-for-byte identically across two full runs» and then passed on
a third). The expected outcome of moving that suite to a runner is *more* false red, not less — and
item 9 above is this repository's own record of what false red costs it.

And `scripts/uitests.sh` is better at this job than CI could be. It kills stale instances before
starting (the whole of `PG-026`), refuses to run while an installed copy holds the global hot key,
and prints the seconds beside each failure so that «~60s ← sospetto timeout di lancio, non un
fallimento vero» is said out loud rather than left to be rediscovered. That judgment is the script's
entire value, and a workflow has none of it.

## Decision

**Adopt CI now, in one workflow, at one tier: from a clean checkout, generate the project, compile
every target, and run `PergamenumTests`. Nothing else goes in — not the UI suite, not SwiftLint, not
the release.**

The rule that produces that scope, and the one sentence to carry out of this ADR:

> **A check goes on CI only when green is its expected state today.** A job that is red on arrival
> reports nothing, and it teaches the reader to stop reading the badge — which is `PG-033`'s problem
> with an email attached.

### §D1 — One workflow, one job, triggered on `pull_request` and on `push` to `main`

Not on every push to every branch. `pull_request` already fires on every push to a branch that has an
open PR, which is the merge path and the thing worth checking; `push: main` covers the post-merge
state; `workflow_dispatch` covers everything else by hand. Pre-PR iteration is already watched by
`.claude/test-cmd` every single turn, and this repo runs parallel agent chains across worktrees that
commit often, much of it to `TODO.md` and `docs/`.

`concurrency` is keyed on the ref with `cancel-in-progress: true`, so a second push to an open PR
kills the first run rather than paying for both. `paths-ignore` skips `docs/**`, `TODO.md` and
top-level `*.md`: a 217 KB `TODO.md` is edited constantly and compiles nothing.

One job, sequential steps, **not a matrix**. Three parallel jobs would mean three cold runners, three
Tuist installs and three SPM resolutions to produce compilations that one runner does once with a
warm dependency tree. Parallelism buys wall-clock on a queue nobody is waiting in.

### §D2 — The runner is `macos-26`, named explicitly; never `macos-latest`, never a larger runner

`macos-latest` is `macos-26` today and will not be. This app has no compatibility fallbacks below
macOS 26 (SPEC §2, §14), so the label that says «latest» is the one label guaranteed to eventually
build against a platform the app does not target — and that failure arrives on a day nobody changed
anything, which is the most expensive kind of red.

`-xlarge` and `-large` are excluded on the verified billing note above: included minutes cannot be
used for larger runners, so they are billed from the first second. Plain `macos-26` is arm64, which
also matches CLAUDE.md's «Apple Silicon».

### §D3 — The Xcode version is selected explicitly and pinned

The image carries 26.0.1 through 26.6 and defaults to 26.6. The default moves when the image is
rebuilt, and a compiler that moves under a Swift 6 strict-concurrency codebase is a build that breaks
on an unrelated day: a diagnostic promoted from warning to error is exactly the shape of change that
ships in a point release. The workflow runs `sudo xcode-select -s` against a named version.

The version pinned should be the one Stefano's Xcode is on, and the workflow says so in a comment, so
that «green on CI, red locally» has one fewer possible cause.

### §D4 — One `xcodebuild` invocation on `Pergamenum-Workspace`, plus an assertion that the connectors were built

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum-Workspace \
           -destination 'platform=macOS' -only-testing:PergamenumTests test
```

Per item 3 above this compiles `Pergamenum.app`, both test bundles, `perg` and `pergamenum-mcp`, and
runs only the unit suite.

**Why the workspace scheme rather than three named schemes:** a target added to `Project.swift`
appears in the generated workspace scheme automatically, so CI's coverage follows the manifest
instead of needing a hand-edit to the workflow. Naming `perg` and `pergamenum-mcp` explicitly would
recreate, in YAML, the exact failure mode CLAUDE.md already documents for `sharedSources` — a list
kept correct by memory.

**And an assertion anyway, because that scheme is generated, gitignored and not ours.** Its
`buildForTesting` flags are Tuist's defaults, not a choice this repo made or can see in a diff. A
Tuist upgrade that stopped building the connectors under the test action would silently retire the
single check this ADR exists to install, and the job would stay green while checking less. So after
the build the job asserts both connector binaries exist under the build-products directory and fails
loudly when they do not. Three lines of shell for a guard that cannot be silently dropped — ADR-0041
§D1's own shape, one layer out: a door, not a step somebody can forget.

### §D5 — `-only-testing:PergamenumTests` on CI too, for a different reason than `.claude/test-cmd`'s

The local restriction exists because XCUITest takes the machine: it «terminated the app the person at
the keyboard was using», and left an instance holding the global hot key so the next launch was
refused. On a runner there is no person and no app of theirs to kill, so **that reason expires** —
and it must not be mistaken for permission to run everything. The reason CI keeps the same flag is
§D6, which is a different argument that happens to reach the same flag.

Worth stating because a future reader who knows only the local rationale will correctly observe it
does not apply and draw the wrong conclusion.

### §D6 — The UI suite does not go on CI; the trigger to revisit it is named

`scripts/uitests.sh` stays exactly where it is: run by hand, before every merge to `main`, per
CLAUDE.md. Three reasons, in order of weight:

1. **Its baseline is red.** `PG-076` and `PG-108` are open, four tests between them, three failing on
   the most recent full run. A job that is red before anyone changes anything reports nothing. And
   the alternative — skipping them to get green — is forbidden by CLAUDE.md and by the global rule
   above it: never disable a test to make a suite pass.
2. **A slower, differently-configured machine makes those tests worse, not better** (see the Context
   section above).
3. **The local script does the job better**, with the stale-instance kill, the installed-copy refusal
   and the timing annotation CI cannot reproduce.

**The named trigger: when `PG-076` and `PG-108` are both closed and two consecutive full runs of
`scripts/uitests.sh` are green, reopen this.** At that point the suite has a baseline worth
defending, and a scheduled nightly on `main` becomes the cheap way to keep it — one run a night, no
gate, advisory only. Not before.

### §D7 — Nothing about the release moves to CI, and CI holds no secrets

No Developer ID certificate, no Apple ID app password, no notarization credentials, no Sparkle EdDSA
private key. `GITHUB_TOKEN` stays at the default read permissions, declared explicitly rather than
inherited. `scripts/release.sh` remains a local, manual operation that refuses to run off `main`, off
a dirty tree, or on a build stamped `0`.

This is a security boundary, not an ordering preference. `Project.swift:167` records that the EdDSA
private half «is in the Keychain and in no file here», and ADR-0031 put it there deliberately.
Copying it into a GitHub secret to save a manual step would make that sentence false in exchange for
a convenience nobody asked for, on a repository whose second binding principle is that it talks to
nothing.

### §D8 — CI overrides signing on the command line; `Project.swift` is never edited to accommodate CI

The job passes `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`. The runner has no certificate for team
`T7H24G7BFW`, and this is safe precisely because of a decision already made for another reason: the
hardened runtime is Release-only, and «Debug therefore stays unhardened» (`Project.swift:38-42`),
because a hardened app refuses to `dlopen` a test bundle signed by a different team. The app is also
not sandboxed in v1. A Debug build with signing disabled is therefore an app that can still host its
own test bundle.

**The standing rule this states: a CI failure is never fixed by changing the signing settings in
`Project.swift`.** Those settings are load-bearing for TCC on Stefano's Mac and cost an afternoon to
get right (`:12-18`). The manifest describes the machine the app ships from; the workflow describes
a machine that only checks it compiles. Where the two must disagree, **the workflow yields.**

### §D9 — Cache the SPM resolution, keyed on `Tuist/Package.resolved`. Do not cache DerivedData

`Tuist/Package.resolved` is committed, so the key is exact and the restored tree is the right one by
construction.

DerivedData is excluded deliberately. Cross-run incremental Swift builds are unreliable, and a stale
module cache fails in ways that look like code defects — which is the most expensive failure a CI job
can produce, because it sends someone to read the wrong file. This repo already has the local version
of that incident on record: CLAUDE.md's `ls -dt` note exists because an alphabetically-sorted
DerivedData listing «can silently hand you a stale build that still shows an already-fixed
regression». A cache that can lie about the result is worse than a cold build that takes eight more
minutes.

`-derivedDataPath` points inside the workspace. It must **not** be copied from `.claude/test-cmd`,
whose `/Users/stefer/Developer/Pergamenum/.build/DerivedData` is Stefano's main checkout and exists
neither on a runner nor in any worktree.

### §D10 — Tuist is pinned in the workflow

`.tuist-version` is gitignored, so nothing in the repo records which Tuist generated the project.
Installing «latest» on CI means the project's generated shape can change between two runs of the same
commit, and §D4 depends on the contents of a scheme Tuist generates. The workflow names a version.

Whether `.tuist-version` should stop being ignored — so that local and CI pin from one place instead
of two — is a real question and a `.gitignore` change this ADR does not make unilaterally. It is
listed under Open questions.

### §D11 — CI is not a required status check, and `main` stays unprotected

CLAUDE.md's "No branch protection is configured: the discipline above is the only guard" stays true.

Three reasons. A required check on a repository where the same person writes, reviews and merges
converts a signal into an obstacle. It would, today, block merges on the days the pre-existing
failures are the only red. And it is what makes §D1's `paths-ignore` safe: a filtered-out run reports
nothing at all, which is correct for an advisory check and deadlocks a required one.

The value of the job is the check appearing on the PR page as one more input to a decision a human
still makes.

### §D12 — Adding CI changes every merge flow in this repo; that is a task, not a side effect

Three statements go stale the moment the workflow lands. Grepped, not left to be discovered:

- `PROJECT_BRIEF.md:662` — «…CI configurata su questo repository, quindi nessun check da attendere
  prima del merge.» **Becomes false. Must be updated.**
- `TODO.md:468` — «the repo has no CI, so "green" always means a local `xcodebuild test`», inside the
  Invariants line. **Becomes false. Must be updated** — and the replacement should say what green now
  means, which is: CI covers the three builds and the unit suite, and `scripts/uitests.sh` by hand
  still covers the rest.
- `docs/manifests/2026-09-02-editor-wysiwyg-unification.manifest.yml:142` — «…no CI is configured in
  this repo.» **Correct as written and must NOT be changed.** It is a record of why a decision was
  made on 2026-09-03, and it was true then. Rewriting history to match the present is how a manifest
  stops being evidence.

Beyond the prose: every automation here that merges a PR has been skipping the wait-for-checks step
because `gh pr checks` answers «no checks reported». From now on it must wait — and `gh pr checks`
exits non-zero while merely *pending*, which is indistinguishable from failure if the exit code is
what gets read. The correct shape is to poll the printed bucket text, never the exit code. Whoever
implements this reviews the merge flows before closing the task.

### §D13 — The first run is discovery, not verification; it is time-boxed, and the fallback is named

Three things about this job cannot be verified from a repository, only by running it: whether
`CODE_SIGNING_ALLOWED=NO` is sufficient for an app-hosted test bundle here, whether Tuist resolves
and generates cleanly on a cold runner, and above all whether a unit suite that has only ever run on
one Mac — with Full Disk Access, Calendar and Reminders granted — behaves the same on a machine with
none of them. Item 6 above names the specific exposure: `CalendarService.isIsolated` reads only the
`disableCalendar` default, and a unit-test host on CI will enter EventKit with no grant behind it.
The likely outcome is a denied request and no events, which no test asserts on. Likely is not
verified.

So: **making the job green is a task with a budget of two sessions.** If it is spent, the fallback is
not "try harder" and not "abandon CI" — it is to drop `test` and ship the build-only job. Building
needs no TCC, no window server session and no app launch, and it alone delivers the ADR-0001 §D1
enforcement that is this ADR's main prize. **Shipping the build-only tier is a success, not a
retreat**, and it is written here so that nobody in a bad session treats it as one.

A mitigation to try before spending the budget, if EventKit is the problem: write the default into
the Debug bundle's domain on the runner (`defaults write it.stefer.pergamenum.debug disableCalendar
-bool YES`) before the test step. It needs no code change and no `Project.swift` edit. Verify which
domain `UserDefaults.standard` actually resolves to in the test host before relying on it — the Debug
configuration uses `it.stefer.pergamenum.debug` while `AppInfo.bundleIdentifier` deliberately stays
`it.stefer.pergamenum` (`Project.swift:43-50`), and those are two different answers.

### §D14 — What this does not touch

Stated so nobody has to infer it. `.claude/test-cmd` is unchanged, including its
`-only-testing:PergamenumTests` restriction and the reason for it. `scripts/uitests.sh` is unchanged
and so is the rule that it runs before every merge. `scripts/release.sh`, `scripts/install-cli.sh`,
`scripts/mcp-smoke.py`, `scripts/fetch-sparkle-tools.sh` and `scripts/appcast.py` are unchanged. No
file under `Sources/`, `Tests/` or `UITests/` changes. `Project.swift` does not change (§D8).
`.swiftlint.yml` does not change. `Tuist/Package.swift` and `Tuist/Package.resolved` do not change:
no dependency is added by any of this.

## Implementation plan

Five tasks, ordered by dependency. Small enough to be one session if the first run cooperates, which
§D13 says it may not.

### Task 1 — Pin the toolchain and prove a cold runner can generate the project (§D2, §D3, §D10)

Create `.github/workflows/ci.yml`: `runs-on: macos-26`, `permissions: contents: read`, checkout at
`fetch-depth: 1`, `sudo xcode-select -s` to the pinned Xcode, Tuist installed at a pinned version,
then `tuist install` and `tuist generate --no-open`. **Stop there — no build step yet.** First green
proves the generator works on a bare machine, which everything below rests on, and isolates the
failure if it does not.
*Budget: `.github/workflows/ci.yml` (~60 lines).*

### Task 2 — Build every target, run the unit suite, assert the connectors exist (§D4, §D5, §D8)

Add the single `xcodebuild` invocation from §D4 with `CODE_SIGNING_ALLOWED=NO` and a
`-derivedDataPath` inside the workspace. Then the assertion: both `perg` and `pergamenum-mcp` must
exist under the build-products directory, `exit 1` with a message naming §D4 if either is missing.
Do not edit `Project.swift` for any reason (§D8). If the unit step resists, §D13's budget and
fallback apply.
*Budget: `.github/workflows/ci.yml` (~40 lines).*

### Task 3 — Triggers, concurrency, path filters (§D1, §D11)

`pull_request`, `push` on `main`, `workflow_dispatch`. `concurrency` keyed on the ref with
`cancel-in-progress: true`. `paths-ignore` for `docs/**`, `TODO.md`, `*.md`. Do not enable branch
protection and do not mark the check required.
*Budget: `.github/workflows/ci.yml` (~15 lines).*

### Task 4 — Cache the SPM resolution and record the real numbers (§D9)

`actions/cache` on `Tuist/.build`, keyed on `hashFiles('Tuist/Package.resolved')`. Then **measure**:
put the cold and warm wall-clock times in the PR description. Every duration and every cost figure in
this ADR is an estimate until that PR exists, and §D13's budget is easier to judge against two real
numbers.
*Budget: `.github/workflows/ci.yml` (~12 lines).*

### Task 5 — Update what becomes false, and the merge flows (§D12)

Rewrite `PROJECT_BRIEF.md:662` and `TODO.md:468` per §D12. Leave
`docs/manifests/2026-09-02-…yml:142` alone. Review any skill or agent flow that merges a PR for the
now-missing wait-on-checks step, and make it poll the bucket text rather than `gh pr checks`'s exit
code. Add a line to CLAUDE.md's Commands or Working agreements saying what CI covers and — more
importantly — what it does not.
*Budget: `PROJECT_BRIEF.md`, `TODO.md`, `CLAUDE.md` (~25 lines).*

**After the change, run the full unit suite, not only a spot check** — Task 5 edits no code, but
Tasks 1–4 alter the build inputs the suite runs against, and this repo has `PG-110` and `PG-120` on
record as tests that fail only in full-suite context.

## Open questions for Stefano

Neither blocks implementation; both change details.

1. **Which GitHub plan is the account on — Free, Pro or Team?** It cannot be read from here. It moves
   the bill between $0 and roughly $19/month under the two readings above. It does not move the
   decision, which is why this is a question and not a gate.
2. **Should `.tuist-version` stop being gitignored (§D10)?** Un-ignoring it lets local and CI pin from
   one file instead of two that can drift. It is a `.gitignore` change and a committed file, so it is
   Stefano's call, not an agent's.

## Alternatives considered

**Continue with no CI.** The honest competitor, and it has a real case: `.claude/test-cmd` already
runs all 2,900 unit tests at the end of every turn, so a unit regression is caught within minutes
without any of this, and CI adds nothing there. Rejected on three things it cannot catch, ever.
*One*: the connector targets — the `Pergamenum` scheme builds the app and the two test bundles and
nothing else (read out of the scheme), so ADR-0001 §D1, the invariant that «found three inverted
dependencies the first time it ran», has no automated enforcer at all. *Two*: a file created, added
to `Project.swift`, and never `git add`ed — it builds forever on the machine that has it and fails on
every clean checkout, and no local run can ever see it. *Three*: anything at all about a machine that
is not Stefano's. It also leaves «was `main` green at this commit» unanswerable after the fact, which
today rests on somebody's memory of a terminal.

**Run the UI suite nightly on `main`, advisory only.** Rejected, and this is the one the cost
objection does *not* decide: under the current-docs reading a nightly run fits inside the free
allowance, so money is not the argument. It fails on signal. With `PG-076` and `PG-108` open the
nightly is red before it starts, so the first genuinely new failure arrives in an email that already
arrived thirty times. §D6's rule is not about money, and this is the alternative that proves it.

**Run the UI suite on CI as a merge gate.** Rejected on a hard constraint, not a judgment: the suite
has three known failures right now, so the gate would be unpassable from day one, and the only way to
make it passable is to skip tests — which CLAUDE.md forbids in terms («Never disable or delete a test
to make a suite pass»).

**A self-hosted runner on Stefano's Mac.** Genuinely tempting, and it solves several problems at
once: no minute cost worth naming, the exact toolchain by construction, real certificates so §D8's
override is unnecessary, and the UI suite could run against the environment its assertions were
actually written for. Rejected on this repo's own evidence. A UI run takes the machine —
`scripts/uitests.sh` says so in its own banner, «la macchina è occupata per una decina di minuti, non
toccare la tastiera» — so a runner that starts one while Stefano is working recreates `PG-026`
exactly, which is the failure the whole `.claude/test-cmd` restriction was built to prevent. Add that
self-hosted minutes stopped being free on 2026-03-01 ($0.002/min, drawn from the same allowance) and
the remaining advantage is thin. Worth revisiting only if §D6's trigger ever fires.

**Add SwiftLint to the workflow.** Rejected under §D6's rule, and called out separately because it is
the most obviously «free» thing to bolt on. `.swiftlint.yml`'s own comment records that `file_length`
is «currently failing on seven types… real debt, recorded rather than configured away». A blocking
lint job is red on arrival; a non-blocking one is a permanent yellow nobody reads. Both teach the
reader to ignore the badge, which is the thing §D6 exists to protect. Add it the day the debt is paid
or the rule is deliberately relaxed.

**A matrix of three build jobs, one per target.** Rejected. Three cold runners, three Tuist installs
and three SPM resolutions to produce three compilations one runner does once with a warm dependency
tree — under either reading of the billing, triple the setup cost for identical signal.

**Trigger on every push to every branch.** Rejected on cost and noise. `pull_request` already covers
every push to a branch with an open PR, which is the merge path; `push: main` covers the result. This
repo runs parallel agent chains that commit frequently, much of it documentation, and `.claude/test-cmd`
is already watching pre-PR iteration every turn.

**Make the job a required status check and protect `main`.** Rejected — §D11. On a solo repository
this converts a signal into an obstacle, it would block merges on days when the only red is
pre-existing, and it would make §D1's `paths-ignore` unsafe.

**Cache DerivedData to cut the build time.** Rejected — §D9. A stale module cache fails in ways that
look like code defects, and this repo already has the local version of that incident on record.

**Use `macos-latest`.** Rejected — §D2. It is macOS 26 today and will not be, and this app has no
fallbacks below macOS 26 by SPEC §2/§14.

**Move `scripts/release.sh` onto CI while we are here.** Rejected — §D7. It would require the
Developer ID certificate, the notarization credentials and the Sparkle EdDSA private key as GitHub
secrets, and ADR-0031 deliberately put that key in the login Keychain «and in no file here».

**Wait for a named future trigger instead of adopting now** (the M6 milestone, say, or the first
connector regression that reaches `main`). Rejected, and stated because deferral is the easiest
decision to reach for. There is no trigger that would make the case stronger than it already is: the
invariant is unenforced *today*, the runner image is GA *today*, and the cost is bounded at under
twenty dollars a month in the worst reading. Waiting for a regression to justify the guard that would
have caught it is the argument this repo already rejected in ADR-0043's «Do nothing until a defect is
observed in use».

## Consequences

### Positive

- **ADR-0001 §D1 gets a mechanical enforcer for the first time.** The rule that a SwiftUI import
  under `Sources/Core` breaks both connectors is currently checked by nothing on any automated path,
  and has not been since the connectors existed. After this it is checked on every PR.
- **`sharedSources` stops being maintained purely by memory.** 39 glob entries whose omissions are
  invisible until somebody builds a connector by hand.
- A clean-checkout build catches the forgotten `git add` — a file that builds forever on the machine
  that has it. No local run can catch this, by construction.
- «Was `main` green here» becomes answerable from the commit rather than from recollection, which is
  what `TODO.md:468` currently concedes it is not.
- The PR page gains a check, so the merge decision has one input that is not the developer's memory
  of the last local run.
- The cost is bounded and small under either reading of GitHub's billing, and Task 4 replaces the
  estimate with a measurement.

### Negative

- **The first run is unlikely to be green**, and §D13 exists because that should be planned for
  rather than discovered at the end of a session. Three independent unknowns — the signing override,
  Tuist on a cold runner, and an app-hosted unit suite launching with no TCC grants — none of which
  can be settled by reading a repository.
- **CI adds a wait to the merge flow that did not exist**, and the tool for reading it is
  treacherous: `gh pr checks` exits non-zero while merely pending *and* exits 1 when no checks exist
  at all. Every merge automation here has to learn the difference (§D12).
- **A green badge invites the belief that green means shippable, and it does not.** The UI suite is
  not in it, and the UI suite is where the last three merges' real failures were (`PG-149`: 118
  tests, 3 failures). CLAUDE.md's pre-merge `scripts/uitests.sh` rule becomes *more* important once a
  badge exists, not less — and that is the single most likely way this decision goes wrong.
- **The workflow is a file no local tooling exercises.** It will bit-rot, most quietly on the trigger
  that runs least.
- **Three more hand-maintained pins** — the runner label, the Xcode version and the Tuist version —
  none of which is pinned anywhere else in this repo, and two of which can drift from Stefano's local
  toolchain without anything saying so.
- A second definition of «the tests pass» now exists, with different scope from
  `.claude/test-cmd`'s. Two definitions of green is one more than one.

### Neutral

- **No app behaviour changes.** Nothing under `Sources/`, `Tests/` or `UITests/` is touched, no test
  is added, skipped or removed, no dependency is added, and no byte written into a vault differs.
- **Principle 2 is not reopened and needs no new exception.** The principle governs the app at
  runtime; a build machine is not a feature of it. ADR-0031 §D13 and ADR-0032's loopback exception
  stand untouched, and neither connector learns CI exists.
- **No new exposure of the private repository.** The source already lives on GitHub; a GitHub-hosted
  runner checking it out adds nothing the repository did not already accept. CI holds no secrets
  (§D7).
- `main` stays unprotected and CLAUDE.md's sentence about discipline being the only guard stays true
  (§D11).
- The work is reversible at zero cost: deleting one file removes every consequence above.

## References

- ADR-0001 §D1 — `docs/adr/0001-initial-architecture.md` — the invariant this ADR gives an enforcer
- ADR-0007 §D2 — `docs/adr/0007-ai-connector-mcp-over-the-vault.md` — the shared-sources architecture
- ADR-0031 §D4, §D6, §D13 — `docs/adr/0031-sparkle-auto-update-integration.md` — the updater's
  test-host isolation, and the Keychain-only EdDSA key §D7 refuses to move
- ADR-0017 — `docs/adr/0017-the-derived-stores-leave-the-vault.md` — `VaultState.isRunningUnderTest`
- ADR-0043 «Do nothing until a defect is observed in use» — the deferral argument reused above
- `Pergamenum.xcodeproj/xcshareddata/xcschemes/Pergamenum.xcscheme` — three buildables, neither
  connector among them
- `Pergamenum.xcworkspace/xcshareddata/xcschemes/Pergamenum-Workspace.xcscheme` — all five, both
  connectors at `buildForTesting = "YES"` (§D4)
- `Project.swift:9-30` (signing and the TCC reasoning), `:38-50` (hardened runtime Release-only,
  Debug bundle id), `:167` (the EdDSA private half is in no file here), `:70-138` (`sharedSources`)
- `.claude/test-cmd` — one scheme, unit tests only, and a `-derivedDataPath` that is Stefano's
  checkout
- `scripts/uitests.sh:1-30` — the rationale §D6 defers to, in the script's own words
- `.swiftlint.yml` — the `file_length` comment behind the SwiftLint rejection
- `.gitignore` — `*.xcodeproj`, `*.xcworkspace` and `.tuist-version` ignored; `Tuist/Package.resolved`
  committed
- `PROJECT_BRIEF.md:662`, `TODO.md:468`, `docs/manifests/2026-09-02-editor-wysiwyg-unification.manifest.yml:142`
  — the three stale statements of §D12, two to fix and one to leave alone
- `TODO.md` — `PG-026` (18 false failures at 60.2 s), `PG-033` (three tests red across a milestone),
  `PG-072`, `PG-076`, `PG-108`, `PG-110`, `PG-120`, `PG-149` (118 tests, 3 failures, 2026-09-12)
- `actions/runner-images` README, fetched 2026-09-13 — `macos-26` GA, arm64, `macos-latest`
- `docs.github.com/billing/reference/actions-runner-pricing`, fetched 2026-09-13 — $0.062/min
  standard macOS; «Included minutes cannot be used for larger runners»
- `docs.github.com/billing/concepts/product-billing/github-actions`, fetched 2026-09-13 — 2,000 /
  3,000 / 3,000 included minutes; **no multiplier table present**
- GitHub Changelog, 2025-12-16, «Simpler pricing… for GitHub Actions» — repricing effective
  2026-01-01, self-hosted minutes billed from 2026-03-01
