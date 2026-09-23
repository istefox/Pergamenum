# PG-187 handoff: run the UI suite in a Tart macOS 27 VM

Date written: 2026-09-20. Ledger entry: `PG-187` (Not yet specified, `kind:roadmap`).
Status: research done, nothing installed, nothing downloaded, no decision taken.
Decision owner: Stefano.

**Scope note (2026-09-23, PG-215/#430):** this spike's own question, VM isolation, is still open
and `PG-187` is still open in the ledger — `SPEC.md:27` puts it explicitly out of scope rather than
deciding it. What no longer holds is the payoff this spike was costed against: the "full UI suite
before every merge" rule (CLAUDE.md, Working agreements) was replaced on 2026-09-21 (`SPEC.md`,
Approved; `docs/adr/0053-test-seams-for-the-in-process-merge-gate.md`, Accepted), so section 2's
motivation and section 11's question 1 no longer hold as priced. The census recorded the spike as
on hold in favour of the in-process route. Section 4's facts, verified live on 2026-09-20, stand.

This document is self-contained. It is meant to be read cold, days later, by a person or a
fresh session, and to be enough to decide and to start. Facts are separated from assumptions:
section 4 holds what was checked live on 2026-09-20 with its source, section 5 holds what is
still an assumption and how each one gets settled.

## 1. Goal

Run `scripts/uitests.sh` (the XCUITest suite, 120 tests, about 25 minutes) inside a macOS 27
virtual machine on the development Mac, so that the run has its own screen, its own pointer and
its own focus. The person at the keyboard keeps working, and nothing on the host can disturb the
run.

## 2. Why this is on the table

**Void as of 2026-09-23:** the first bullet's premise and the closing line below both price the
"full UI suite before every merge" rule, which was replaced on 2026-09-21 — see the scope note
above. The pointer-sharing evidence (`PG-180`) and the two unexplained observations (`PG-182`,
`PG-186`) are unaffected.

- A full run takes the machine for about 25 minutes. The rule "run the full UI suite before every
  merge to `main`" (CLAUDE.md, Working agreements) has been skipped five times for that reason
  (`PG-157`, always by Stefano's explicit choice at the merge gate). A run that does not take the
  machine removes the friction that made the rule skippable.
- XCUITest shares the pointer with whoever is at the machine. `PG-180` measured it: the same test
  failed 13 times in 20 with the cursor moved by another process, 0 in 30 with the machine
  untouched. The fix shipped was a retry inside one test, which reduces the symptom for that test
  only.
- Two related observations are still unexplained and would be structurally impossible in a VM:
  `PG-182` (a copy of `/Applications/Pergamenum.app` appears mid-run, launcher unknown) and
  `PG-186` (Mail and GitKraken took frontmost during a 25 s run, unconfirmed as a cause).

What is already in place and reduces the pain without a VM:
- PR #329: drag retry and launch rerun.
- PR #335: the run builds into its own DerivedData (`build/uitests-dd`) and keeps a `.xcresult`.
- PR #338: a run over a clean tree writes a verdict keyed by the tree hash, shared by every
  session and worktree; `--status`, `--affected`, a lock across sessions. The suite is paid once
  per tree.
- The suite is green: 120 tests, 0 failures on `main` at `b74d561` (`PG-184`, 1439 s).

So the VM is not fixing a red suite. It buys back the machine during a run, and it makes the
"run before merge" rule cheap enough to enforce.

## 3. The solution in plain words

A Tart virtual machine is a second, complete macOS 27 installed inside the Mac, run through
Apple's Virtualization framework. It has its own virtual display, keyboard and pointer. The UI
tests run inside it, so they never touch the real pointer or the real focus. The host only starts
it, waits for it, copies the result out and stops it.

Tart is the tool that creates and runs these VMs from the command line. Cirrus Labs publishes
ready-made macOS images in a container registry, so the OS is downloaded, not installed by hand.

## 4. Facts verified live on 2026-09-20

### 4.1 The host

| Item | Value |
|---|---|
| macOS | 27.0, build `26A428` |
| Architecture | arm64 |
| Xcode | 27.0, build version `27A266a` |
| RAM, cores | 36 GB, 18 |
| Disk | 1.8 TB volume, 650 GB free |
| `/Applications/Xcode.app` size | 3.9 GB |
| Tuist on host | `/opt/homebrew/bin/tuist`, version 4.208.0 |
| Tart | not installed; `~/.tart` does not exist |

### 4.2 The project and the suite

- The UI tests live in the `PergamenumUITests` target. `scripts/uitests.sh` calls `xcodebuild
  -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
  -derivedDataPath build/uitests-dd` (the calls are around lines 436 and 509 of the script).
- Signing in `Project.swift` (lines 11 to 19): `DEVELOPMENT_TEAM = T7H24G7BFW`,
  `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"`. The comment there says
  the identity is set on purpose, because TCC keys a privacy grant to the signing identity and an
  ad-hoc signature would key it on the binary hash.
- Debug is unhardened (`Project.swift` lines 34 to 46): the hardened runtime refuses to load a
  test bundle signed by a different team, so it is only enabled for Release.
- Every UI-test file passes `-disableCalendar YES`, `-disableUpdater YES` and
  `-mailStoreRoot <fixture>` (CLAUDE.md, Working agreements), so a run does not read the person's
  diary, start Sparkle or touch Apple Mail. This is what makes running in a VM without Mail or a
  calendar plausible.
- Candidate test classes for a first check: `TaskCategoriesUITests` (2 tests, 26.3 s on the host,
  passed on 2026-09-20 with the new script) and `WorkspaceBoardUITests` (contains drag tests, the
  class of test `PG-180` and `PG-162` are about).

### 4.3 Tart and the images

- Tart's latest release is 2.37.0, published 2026-09-09.
- **The repository now lives under `openai/tart`** (`cirruslabs/tart` redirects to it). Its README
  and quick start give the install command `brew install openai/tools/tart`. The Homebrew tap
  `cirruslabs/homebrew-cli` also carries a `tart` cask, but the current documentation points at
  `openai/tools`. Which one to trust should be settled at install time (`brew info --cask <name>`
  and the upstream README). Why the project moved was not investigated.
- Homebrew core has no `tart` formula.
- macOS 27 images exist in the registry, under the codename "golden gate":
  - `ghcr.io/cirruslabs/macos-golden-gate-vanilla`, tags `latest` and `27.0`
  - `ghcr.io/cirruslabs/macos-golden-gate-base`, tag `latest`
- There is no golden-gate image with Xcode preinstalled: the images README lists `xcode` images only
  for tahoe, sequoia and sonoma.
- The vanilla template builds from `UniversalMac_27.0_26A5416b_Restore.ipsw`, a "2026SummerSeed"
  IPSW. The template states "Requires Tart 2.33.0+ and macOS 27+ on both the host and guest VM".
- The `base` image adds Homebrew and tooling: wget, git-lfs, jq, yq, gh, cmake, mise, rbenv,
  node@24, awscli, a guest agent. It does not contain Xcode and does not contain Tuist.
- `macos-golden-gate-base:latest` carries the annotation `upload-time 2026-08-19T17:52:40Z`.

### 4.4 The permission question, what the images do

The Cirrus `base` template (`templates/base.pkr.hcl`) contains:
- A provisioner "Enable UI automation" running `scripts/automationmodetool.expect`, which runs
  `automationmodetool enable-automationmode-without-authentication`. Issue #136 of the templates
  repo states the reason: allow UI automation the way GitHub's macOS runner images do.
- A final provisioner running `scripts/update-tcc-database.sh`, which inserts TCC grants
  (Accessibility, Screen Capture, Post Event, Apple Events) for `sshd-keygen-wrapper`,
  `osascript`, `org.python.python` and the Tart guest agent.
- A commit "Support protected TCC databases on macOS 27" dated 2026-08-19 11:42Z. The golden-gate
  base image was uploaded later the same day (17:52Z), so it should include it. The 2026-08-28 run
  of the base workflow skipped the golden-gate build steps, meaning the image was considered up to
  date.
- The workflow disables SIP on the vanilla image before building the base one ("Disable SIP" step).

### 4.5 Commands, verified against Tart's own docs and source

From `docs/quick-start.md` and `Sources/tart/Commands/Run.swift` of the current default branch:
- `tart clone <registry-image> <local-name>` pulls the image implicitly if it is not present.
  `tart pull` exists for the pull alone. `tart clone --stacked` exists.
- `tart run <name>` opens a window. `tart run --no-graphics <name>` does not ("Don't open a UI
  window", "useful for integrating Tart VMs into other tools").
- `tart ip <name>` gives the guest IP. The image's default account is `admin` with password
  `admin` (`ssh admin@$(tart ip <name>)`).
- `tart run --dir=<name>:<host-path>[:ro] <vm>` mounts a host directory into the guest.
- `tart set <name> ...` changes CPU, memory and disk size after creation; see `tart set --help`
  for the exact flags. The docs state the default is 2 CPUs, 4 GB and a 1024x768 display.
- `--net-softnet` restricts networking; the default is shared (NAT) networking.

### 4.6 Measured numbers

| Item | Value | How measured |
|---|---|---|
| `macos-golden-gate-vanilla` | 29.7 GB compressed, 34.8 GB uncompressed | registry manifest layers and `uncompressed-disk-size` annotation |
| `macos-golden-gate-base` | 32.9 GB compressed, 39.9 GB uncompressed | same |
| Download throughput | 8.24 MB/s (about 66 Mbit/s) | one sample, 100 MB, from the registry, on 2026-09-20 |

## 5. Not verified: assumptions and how each one is settled

1. **The golden-gate base image really has automation mode and the TCC grants active.** Inferred
   from the template and the upload date. Settled inside the VM: run `automationmodetool` and read
   its output, inspect what the runner needs.
2. **The XCUITest runner needs no manual permission click.** Automation mode without
   authentication is the mechanism GitHub's hosted runners use, but the exact behaviour of the
   runner on macOS 27 is not confirmed. Settled by running the first UI test.
3. **A guest built from a seed IPSW (`26A5416b`) boots on this host (`26A428`).** By Apple's usual
   numbering (four-digit suffix is a beta, three-digit is a release) the host is newer, which is
   the right direction. Settled by the first `tart run`.
4. **`--no-graphics` is enough for a UI test.** The flag removes the window, and it is not known
   whether the guest keeps a usable display session for XCUITest. Settled by trying both. The
   fallback is to run with the VM window open (it does not take the host pointer unless clicked).
5. **The project builds in the VM with an ad-hoc signature.** The project asks for "Apple
   Development" and the VM has no such certificate and no Apple ID. The idea is to override on the
   command line (`CODE_SIGN_IDENTITY=-`, manual style, empty team). Because Debug is unhardened,
   a test bundle signed by the same ad-hoc identity should load. The exact set of overrides is
   not verified. This can be checked on the host, without the VM, with a build-for-testing into a
   scratch DerivedData (step 0 below).
6. **Copying the host's `Xcode.app` (3.9 GB) into the VM gives a working Xcode.** Alternative:
   `xcodes install`, which needs an Apple ID with two-factor and is therefore not autonomous.
   Settled by copying it, accepting the licence and running `xcodebuild -version` in the VM.
7. **Tuist and the SPM dependencies (GRDB, Sparkle) work in the VM.** Tuist is not in the base
   image. It has to be installed in the guest (Homebrew or mise), ideally at the host's version
   4.208.0, and `tuist install` needs network from the guest (NAT is the default). The Tuist
   install method and the formula name were not checked.
8. **Time.** The 67 minutes for the download is 32.9 GB divided by one throughput sample. Tart
   pulls layers concurrently, so the real time may be shorter. The other durations (Tart install,
   first boot, Xcode copy, first build) are estimates, not measurements.
9. **Disk peak.** Steady state of about 45 to 50 GB and a peak of up to about 80 GB are estimates.
   Whether Tart keeps the compressed layers and the expanded disk at the same time was not
   checked. Measure with `du -sh ~/.tart` during the pull.
10. **A green in the VM predicts a green on the real Mac.** Drags with a virtual pointer may behave
    differently from the real one, in either direction. Only running both a few times says.

## 6. Risks

| Risk | Effect | Mitigation |
|---|---|---|
| Signing override does not work | Build fails in the VM | Step 0 on the host, before any download |
| Guest does not boot on host | Spike ends at step 3 | Cost so far is the download only, in the background |
| Runner still needs a manual permission | Autonomy lost | Stop criterion 2 below |
| No usable display with `--no-graphics` | Needs a window | Fallback: run with the window, accept a window on the host |
| VM drifts from the host (macOS or Xcode update) | Maintenance work, false reds or greens | Record host and guest builds in the verdict; re-pull the image on macOS updates |
| VM run is slower than the host | Longer wall clock | Size CPU and memory with `tart set`; the host has 18 cores and 36 GB |
| Tool ownership moved to the `openai` organisation | Unknown maintenance trajectory | Read the upstream README at install time; keep the spike reversible (`tart delete`, remove `~/.tart`) |
| Two runs at once (host run and VM run) write the same verdict or lock | Confusing state | Reuse the existing lock; add where the run happened to the verdict |

## 7. Cost

- Disk: about 40 GB expanded image, plus 3.9 GB Xcode, plus DerivedData, capped by the image's own
  50 GB disk at build time. About 7 to 12 percent of the free space. Fully reversible.
- Time: download about 35 to 70 minutes in the background, then about 30 to 45 minutes of hands-on
  work if nothing goes wrong. The download is the only long step and needs no attention.
- Ongoing: the VM has to be kept in step with macOS and Xcode on the host. This is the recurring
  cost and it is not small.

## 8. Plan, one step at a time, cheapest question first

Each step ends with a result and a go or stop. Commands marked "proposed" have not been run.

**Step 0, on the host, no download (about 5 to 10 minutes).** Check that the project compiles for
testing with an ad-hoc signature.
Proposed: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination
'platform=macOS' -derivedDataPath <scratch dir> build-for-testing CODE_SIGN_STYLE=Manual
CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`
Rules: use a DerivedData path that is not `build/uitests-dd` and not the Stop hook's; do not start
it beside another `xcodebuild` on the project (the script refuses to); `build-for-testing` does
not launch the app, so it does not touch the pointer. Go if it builds. If it fails, find out why
before going any further, because the same failure would happen in the VM.

**Step 1, install Tart (2 minutes).** Proposed: `brew install openai/tools/tart`, then
`tart --version`. Confirm the source first with `brew info` and the upstream README.

**Step 2, pull the image (background, 35 to 70 minutes).** Proposed:
`tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest golden-base`. Watch `du -sh ~/.tart`
to settle assumption 9. Do not use the machine's bandwidth for anything else meanwhile.

**Step 3, first boot.** Proposed: `tart run golden-base` with the window. Result: does it boot and
auto-login. Stop criterion 1 if it does not.

**Step 4, look inside.** Over ssh (`admin@$(tart ip golden-base)`): `sw_vers`, `automationmodetool`,
check the tooling. Settles assumptions 1 and 3.

**Step 5, Xcode.** Mount the host's Xcode read-only with `--dir`, copy it into the guest's
`/Applications`, `sudo xcodebuild -license accept`, `xcodebuild -runFirstLaunch`, `xcodebuild
-version`. Settles assumption 6.

**Step 6, the project.** Get the sources in (mount the repo or clone), install Tuist at 4.208.0,
`tuist install`, `tuist generate --no-open`. Settles assumption 7.

**Step 7, the tests.** Run `TaskCategoriesUITests` inside the VM with the ad-hoc overrides, then
`WorkspaceBoardUITests`, with the window first and then with `--no-graphics`. Stop on any red and
read the `.xcresult` before rerunning (the repo's own rule). Settles assumptions 2, 4 and 5.

**Step 8, only if step 7 is green.** Run the same two classes three more times to see whether the
VM is stable, then decide whether to integrate (section 9).

### Stop criteria, written before starting

1. The VM does not boot on this host.
2. The runner needs a manual permission click on every run, or on every boot.
3. The project cannot be built in the VM without touching the Apple ID or the keychain.
4. A test that passes on the host fails in the VM for a reason that is not a fixable
   configuration (drags never land, elements never hittable).
5. Total hands-on time passes about two hours without a UI test having run in the guest.

On a stop: delete the VM (`tart delete`), remove `~/.tart`, close `PG-187` with the reason, and
record what was learned. The host is left as it was.

## 9. If the spike works: integration into `scripts/uitests.sh`

Design questions, none decided:
- Orchestration from the host: start the VM, wait for ssh, run `xcodebuild` in the guest, copy the
  log and the `.xcresult` back, stop the VM. A new flag (for example `--vm`) rather than changing
  the default behaviour.
- The tree hash and the verdict: computed on the host, written to the shared git common dir as
  today. The verdict should record where the run happened (host or VM) and the guest and host
  builds, so a VM green is not silently equated with a host green.
- How the source gets into the guest: read-only mount, rsync of the tree, or a clone. DerivedData
  must live on the guest's own disk.
- The lock: reuse the existing cross-session lock so a host run and a VM run cannot overlap on the
  same tree.
- It amends a working agreement in CLAUDE.md ("the UI suite runs only through
  `scripts/uitests.sh`, which owns its DerivedData"), so the change should be written as a plan
  and reviewed like the previous two `uitests` chains (#335, #338).
- Principle 2 (fully offline) concerns the app's features. Pulling an image is development
  tooling on the dev machine and touches neither the app, `perg` nor `pergamenum-mcp`; inside the
  VM the suite already runs with `-disableUpdater YES`. This is an assessment, not a ruling.

## 10. Alternatives considered

- **Do nothing.** The suite is green, runs once per tree, and the worst flake is retried. The
  cost is that the rule "run before merge" stays skipped whenever the machine is needed.
- **Another VM tool** (UTM, Parallels, VMware): not researched. Tart was chosen because it is
  scriptable, has ready-made macOS images and a documented automation mode.
- **GitHub-hosted macOS runners:** the UI suite is out of CI on purpose (ADR-0044). Whether a
  macOS 27 hosted image exists was not checked, and running the suite there would move cost and
  network use off the machine rather than solve the same problem locally.
- **A second user session on the same Mac:** speculative, not researched.

## 11. Questions for Stefano

**Q1 void as of 2026-09-23:** the rule it prices was replaced — see the scope note above.

1. Is having the rule "full UI suite before every merge" actually followed worth roughly two
   hours of spike plus recurring VM upkeep? The alternative is to accept the machine being busy for
   25 minutes per verified tree.
2. Is a VM window open on the host acceptable if `--no-graphics` does not work?
3. Should step 0 (ad-hoc signing on the host) be done first, on its own, since it costs nothing
   in disk and time and answers the most binary risk?
4. Where should the recurring upkeep live (a documented procedure in the repo, or a script that
   re-pulls the image after a macOS update)?

## 12. State of the repo and the ledger at handoff

- `main` at `037fee4`, clean, in sync with `origin/main`.
- Merged today: #338 (shared UI verdict), #339 and #344 (ledger syncs from this session), #340 and
  #342 (from a parallel session).
- Ledger entries connected to this work:
  - `PG-187` this spike, `Not yet specified`, `kind:roadmap`, opened 2026-09-20.
  - `PG-186` Mail and GitKraken took focus during a run, `Not yet specified`.
  - `PG-182` a copy of `/Applications/Pergamenum.app` appears mid-run, `Not yet specified`.
  - `PG-180` closed, cause measured (shared pointer), retry fix in one test.
  - `PG-185`, promoted to issue #343: the real-run checks of the shared verdict still owed (a
    `full` verdict, a skipped repeat run, a red verdict, the launch rerun, the cross-session lock).
    The next full UI run by whoever merges to `main` closes it.
- `PG-186` and `PG-187` came from the previous session's notes, not from direct observation in
  the session that wrote them. Confirm or drop them.

## 13. Sources, all read on 2026-09-20

- Tart source, docs and README: `github.com/openai/tart` (redirect from `cirruslabs/tart`), files
  `README.md`, `docs/quick-start.md`, `docs/faq.md`, `Sources/tart/Commands/Run.swift`.
- Images and templates: `github.com/cirruslabs/macos-image-templates`, files `README.md`,
  `templates/vanilla-golden-gate.pkr.hcl`, `templates/base.pkr.hcl`,
  `scripts/automationmodetool.expect`, `scripts/update-tcc-database.sh`, issue #136, the
  "Base Images" workflow runs.
- Image sizes and tags: the `ghcr.io` registry manifests and tag lists for
  `cirruslabs/macos-golden-gate-vanilla` and `cirruslabs/macos-golden-gate-base`.
- Project: `Project.swift`, `scripts/uitests.sh`, `CLAUDE.md`, `TODO.md`.
