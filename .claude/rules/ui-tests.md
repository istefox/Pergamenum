---
paths:
  - "Tests/**/*.swift"
  - "UITests/**/*.swift"
  - "scripts/uitests.sh"
  - ".claude/test-cmd"
---

# UI tests and the test gate

Moved verbatim from the `## Working agreements` section of `CLAUDE.md` on 2026-10-07; loaded only
when a file matching `paths:` is read.

- `.claude/test-cmd` runs at the end of **every** turn, through the `Stop` hook in
  `~/.claude/settings.json`. It is therefore restricted to `-only-testing:PergamenumTests`,
  and that restriction is load-bearing rather than tidiness: with the whole suite in there,
  each turn ended by launching the UI tests, every `XCUIApplication().launch()` terminated
  the app the person at the keyboard was using, and each round left an instance alive
  holding the global hot key exclusively - so the next launch was refused. Two hours went
  into hunting an external culprit for something the assistant was doing itself. The UI
  tests still exist and are run deliberately, by hand.
- **A UI test that reads the machine's calendar is a test about somebody's diary.** The
  suite passes `-disableCalendar YES`, which keeps `EventKitStore` out of EventKit
  entirely. Every one of the thirteen files passes it, not only the one that needed it:
  `TimelineHoursUITests` checked that nothing was drawn past a 14:00 window, and the grid
  widens itself to reach an event outside that window by design, so the assertion failed
  on the afternoon there was a real meeting at 16:30. A new UI-test file wants the flag
  too.
- **A UI test that launches the app risks a Sparkle update-check alert on screen**, the same
  shape of trap as `-disableCalendar` above. The suite passes `-disableUpdater YES` (ADR-0031),
  which keeps `SparkleUpdateController` from starting the updater at all. Every UI-test file
  passes it, not only the one that would need it — a stray modal alert during `launch()` reads
  as the app hanging, not as an update being offered. A new UI-test file wants the flag too.
- **A UI test that launches the app must never let it reach the real Apple Mail store**, the
  third flag of the same family. The suite passes `-mailStoreRoot <fixture>` (ADR-0036), which
  `MailStoreLocation.resolve()` reads before anything else, so a run resolves to a directory the
  test made and threw away rather than to `~/Library/Mail/V10`. Every UI-test file passes it, not
  only the pratiche ones — an empty temporary directory where the test has no Mail fixture of its
  own. Without it, any pratiche sync a run happens to trigger reads the person's actual mail, and
  a Full Disk Access grant is what makes that *succeed* rather than fail visibly. A new UI-test
  file wants the flag too.
- **A UI test that launches the app must never let the Contenitore touch the real drop folder**,
  the fourth flag of the same family. The suite passes `-disableContenitore YES` (ADR-0071), which
  makes `ContenitoreController.isIsolated` true, so the controller never lists, ingests, creates or
  moves anything. Without it, a run launched while `~/Pergamenum Drop` holds files moves them into
  the test's throwaway vault, and they leave the person's machine with it. Every UI-test file
  passes it, not only the one that opens the Contenitore. A new UI-test file wants the flag too.
- **A UI-test class gets those flags by subclassing `PergamenumUITestCase`, never by spelling
  them.** `UITests/PergamenumUITestCase.swift` owns the throwaway vault, `-stateBase`, the empty
  Mail store, every isolation flag above plus `-disablePlaud YES`, and the teardown; a class
  creates its vault with `makeTemporaryVault(prefix:)` and launches with
  `launchApp(extraArguments:)`, extra arguments only. Seventeen hand-kept copies are how
  `PraticheUITests` lost `-disablePlaud` and `WikilinkNavigationUITests` lost `-mailStoreRoot`
  (PG-128). `Tests/UITestLaunchHarnessGuardTests.swift` fails if a file under `UITests/` builds
  its own `XCUIApplication`, sets launch arguments, or declares a class on `XCTestCase` directly.
- **A UI test must not find a control by the words on it.** Prose grows: the quick
  switcher's placeholder gained «, o a una sezione con #…» when Quick Open learned to jump
  to headings, and two tests spent days looking for a field that no longer answered to
  that name while the feature worked perfectly. Use `accessibilityIdentifier`, which is
  the part of a view that is a contract.
- **A UI test drags through `dragTo(_:pressing:)` (`UITests/DragSupport.swift`), never through
  `press(forDuration:thenDragTo:)`.** On macOS 27 that call delivers no translation at all - a
  resize reads its untouched starting size, a sidebar drag never starts - while
  `click(forDuration:thenDragTo:)` on the same gesture works (PG-162). For weeks it read as the OS
  refusing synthesized drags and twelve tests stayed red on that theory; the helper's comment
  records the variants already tried and failed, so they are not tried again.
- **The UI suite runs only through `scripts/uitests.sh`, which owns its DerivedData, its evidence and
  what it learned.** It builds into `build/uitests-dd` (the `Stop` hook's unit build and a UI run on
  one `build.db` produced "database is locked" reds that were nobody's defect, PG-183), refuses to
  start beside another `xcodebuild`, labels a launch failure whatever its duration, and writes a
  `.xcresult` next to its log. **A red is diagnosed from that bundle (`xcrun xcresulttool get
  test-results summary --path <bundle>`) before anything is rerun.**
  **A run is paid once per tree, not once per session** (~25 minutes of the machine, and the pointer
  is shared with the person at it): a run over a clean tree writes a verdict, keyed by the tree hash,
  into the git common dir every worktree shares. **Before running anything, ask
  `scripts/uitests.sh --status`** - it answers instantly whether this tree or `main` is already
  verified and what changed since the last full green; a full run over a verified tree is skipped
  (`--force` overrides), and a second session cannot start one while another holds the lock.
  `--affected` runs only the classes a change since that green can reach, and nothing when none can,
  and is what a merge to `main` runs — not the whole suite (see the merge-gate rule above). The
  full suite is run once before a release, by whoever ships it; every other session reads the verdict.
- **A UI-test instance outlives its run.** After `xcodebuild test`, one or more copies of
  the app are usually still running on a vault inside
  `~/Library/Containers/it.stefer.pergamenum.uitests.xctrunner/Data/tmp/`, which is not
  readable even with the sandbox disabled. Any manual check reaching a window that shows
  notes nobody created is reaching one of those. `ps -Ao pid,command | grep
  Pergamenum.app/Contents/MacOS` shows the vault each instance opened; start by reading it,
  not by trusting the window.
- **A stale instance left alive from a previous run poisons the next full UI run wholesale,
  not just the test that left it.** A run started with stale instances still holding the
  app's global hot key exclusively has produced 18 failures that were not real defects, every
  one timing out at exactly 60.2 s — the launch timeout, not a broken feature. Kill every
  instance before trusting a red run, and read the per-test timings `scripts/uitests.sh`
  prints beside each failure before believing it: 60.2 s names the launch timeout, not the
  app.
- **The UI-test runner's own temporary directory is unreadable from outside the sandbox, on
  or off.** A screenshot or file written to it during a test cannot be inspected afterward by
  reading the path directly. Attach it instead with `XCTAttachment`, run with
  `-resultBundlePath`, and pull it back out with `xcrun xcresulttool export attachments`.
- **`-recentVaults` needs the plist array form.** The key holds `[String]`, so
  `-recentVaults /path` leaves `stringArray(forKey:)` nil and no vault is reopened at
  launch; `-recentVaults '("/path")'` works. The launch argument outranks the persistent
  domain, so a throwaway vault reaches a Debug build without touching what the installed
  app opens.
