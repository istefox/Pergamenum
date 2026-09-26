# CLAUDE.md

## Project

Pergamenum - a native, fully offline macOS app for personal use that merges three
tools into one: a local markdown note vault with wikilinks and backlinks (Obsidian
model), an infinite spatial canvas called **Workspace** where notes, PDFs, images,
emails and links float as resizable cards (VisualOS / JSON Canvas model), and an
integrated task and calendar system with daily notes, `>date` scheduling,
timeblocking and two-way EventKit integration.

The authoritative source is `docs/20260811_Pergamenum_SpecApp.md` (v2.2). Every
development task must be verified against it. `PROJECT_BRIEF.md` is the condensed
handoff; the spec wins on any conflict.

## Stack

- Language/runtime: Swift 6 with strict concurrency, SwiftUI on the macOS 27 SDK
- Platform: macOS 27 or later, Apple Silicon. No compatibility fallbacks for
  earlier releases - current SwiftUI APIs are used directly. (Raised from macOS 26
  Tahoe/Xcode 26 on 2026-09-18: the dev machine moved to macOS 27.0/Xcode 27.0 and the
  build already targets the macOS27.0 SDK - confirmed live via `sw_vers`/`xcodebuild
  -version`, not assumed.)
- AppKit via `NSViewRepresentable` where SwiftUI is insufficient: the text editor
  (TextKit 2 in an `NSTextView`) and the canvas.
- Tooling: Tuist 4 for project generation, Swift Testing for tests, Xcode 27 toolchain
- Bundle identifier: `it.stefer.pergamenum` (lowercase, unlike the folder name).
  URL scheme `pergamenum://`. Automatic signing, team `T7H24G7BFW`. Developer ID
  distribution, no App Store, not sandboxed in v1. Apple Developer account:
  `istefoxdev@gmail.com`, name Stefano Ferri - this is the Apple ID notarization
  authenticates with, not the git commit address.
- Frameworks: PDFKit, EventKit, QuickLookThumbnailing, QuickLookUI, UserNotifications,
  GRDB (SQLite cache only)

## Binding architectural principles

1. **File over app.** Every piece of content lives as a readable file on disk (md,
   canvas, pdf, eml, svg). If Pergamenum disappeared, the data stays usable.
2. **Fully offline.** No network call in any feature. No server, no account, no
   telemetry. **One named exception, and only one** (ADR-0031 §D13): the update check,
   which happens when the person chooses «Cerca Aggiornamenti…» and at no other moment -
   no timer, no launch check, no background task. It carries the app's own version
   identifiers and nothing else: no vault content, no note text, no path, no file name,
   no tag, no task, no calendar data, ever. `SUSendsSystemProfile` stays `false`, so
   Sparkle's optional hardware profile is off and the telemetry sentence above is
   untouched. The exception is scoped to the updater and does not travel: no feature of
   the vault, Workspace, tasks, calendar, editor or index gains network access from it,
   and neither `perg` nor `pergamenum-mcp` knows Sparkle exists.
3. **Rebuildable index.** The SQLite cache (links, backlinks, tasks, thumbnails)
   regenerates entirely from a vault scan. It is never the source of truth; deleting
   it loses nothing. Since ADR-0017 (`PG-004`) it lives with the rest of a vault's
   derived state in `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`,
   not inside `.pergamenum/` - "delete `.pergamenum/` to reset the app" is no longer
   true, and the unit suite must always pass a temporary state base
   (`VaultState.processDefaultBase()` is test-aware; `VaultSession.init` still takes
   `stateBase` with no default) rather than resolving the real directory.
4. **Obsidian compatibility.** *Amended 2026-09-16 (ADR-0047 §D11).* The existing "Labs" vault
   opens without conversion, and it does so because the formats underneath are ordinary ones -
   markdown, frontmatter YAML, wikilinks, `.canvas` as plain JSON Canvas 1.0, the `|W`/`|WxH`
   embed-size suffix, 16-hex node ids, `pergamenum-` prefixed extra keys preserved and not
   interpreted - not because keeping Obsidian able to read the result is a constraint this project
   still holds. What ends is the round-trip *obligation*: a future design is no longer rejected on
   the ground that it would stop Obsidian from opening a Pergamenum-written file, and the manual
   round-trip probe (ADR-0020's Probe 2) is retired as an acceptance gate, never re-added as one.
   Nothing on disk changes shape because of this amendment. Principle 5 below is untouched by it.
5. **Harness conformance.** The naming, tag, frontmatter and wikilink conventions of
   the `harness-system` repo are the app's native schema, not an option. That repo
   stays the single source of truth: when a convention changes, the app config
   (`.pergamenum/vocabolari.json`) is updated, never the other way round.
6. **Delegated sync.** Future iPad sync happens by putting the vault in iCloud Drive.
   No proprietary transport.

Two schemas are closed and must not be extended: note frontmatter is exactly
`date`, `tags`, `related`, `aliases` (SPEC §4.3 - `title`, `status`, `type`, `draft`,
`version`, `author` are forbidden), and tags are flat namespaced strings matching
`^(client|competitor|project|type|topic|status|area|source)-[a-z0-9]+(-[a-z0-9]+)*$`
with no `/` nesting (SPEC §4.4).

## Design system

The UI is designed with Claude before implementation: every milestone screen gets an
approved mockup first. Aesthetic reference is Craft - minimal, generous whitespace,
hierarchy from weight and space rather than lines and boxes, SF Symbols, short
animations, no emoji in the interface.

Theming uses W3C DTCG design tokens in JSON under `.pergamenum/themes/`, loaded at
runtime by a `ThemeEngine` and exposed to views through the Environment. Light and
dark themes are both first class from day one.

**Binding rule: a view that uses a color or a font without going through a token
does not pass review.** No hardcoded colors in views, ever.

## Layout

```
Project.swift              Tuist manifest - single source of truth for targets
Tuist.swift                Tuist configuration
Tuist/Package.swift        SPM dependencies (GRDB to be added at indexing milestone)
Sources/                   App code, compiled into the Pergamenum target
Resources/                 Assets.xcassets and other bundled resources
Tests/                     Swift Testing suite, compiled into PergamenumTests
docs/                      Specification, ADRs and design notes
```

## Milestones

Order M0 to M6 is binding. Every milestone yields a usable app, and a milestone does
not start until Stefano has manually verified the previous acceptance criterion. See
SPEC §13 for the full table.

M0 design system, M1 vault + editor, M2 Workspace base, M3 PDF and email cards,
M4 tasks, M5 calendar, M6 URL scheme + conformance linter.

## Git conventions

- Workflow: GitHub Flow. `main` stays deployable, work happens on feature branches
  merged through pull requests.
- Commits: Conventional Commits v1.0.0 - `feat:`, `fix:`, `refactor:`, `docs:`,
  `test:`, `chore:`, `perf:`. English, imperative mood.
- Branches: Conventional Branch - `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`
  followed by a short kebab-case description.
- Default branch: `main`. Never commit directly to it, never force-push.
- No branch protection is configured: the discipline above is the only guard.
- **CI (ADR-0044, `.github/workflows/ci.yml`) builds `Pergamenum`, `perg` and `pergamenum-mcp` from a
  clean checkout and runs `PergamenumTests`, on every PR and on push to `main`.** It is advisory, not
  a required check, and it verifies nothing else: the UI suite (`scripts/uitests.sh`, run through
  `--affected` at merge per the rule below), SwiftLint and the release pipeline are not on it. A green
  CI badge means those three targets build and the unit suite passes — nothing about the UI suite.

## Commands

```bash
tuist install                                                                                   # once per fresh worktree, before the first generate (else the Stop hook reports exit 66, not a red test)
tuist generate --no-open                                                                        # regenerate after editing Project.swift
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' test
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build    # the CLI
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
scripts/release.sh                                                                              # signed, notarized, numbered build, published with its appcast
scripts/fetch-sparkle-tools.sh                                                                  # Sparkle's sign_update/generate_keys into build/, checksum-pinned
scripts/appcast.py --self-test                                                                  # the appcast generator's own assertions, offline, writes no feed
scripts/install-cli.sh [dir]                                                                    # build both connectors Release and put them on the PATH
scripts/mcp-smoke.py [binary]                                                                   # drive the MCP server over stdio and check it
scripts/uitests.sh                                                                              # the GUI suite: --affected at merge, a full run before a release
scripts/check-merge-integrity.py --self-test                                                    # ADR-0061's and ADR-0062's own assertions, offline, touches no repository
scripts/check-merge-integrity.py --landings "$(git rev-list --max-parents=0 origin/main)..origin/main"  # ADR-0062's landing audit over main's history (exits 1 on the six known historical landings)
scripts/install-git-hooks.sh                                                                    # once per machine: installs the pre-push guard from ADR-0061/0062; rerun with --force after a hook change
```

## AI connector

ADR-0007. The vault is reachable without the app, so an assistant works on the files
through the app's own conventions and Pergamenum never opens a socket.

`VaultSession` owns an open vault with no user interface under it - settings,
vocabulary, index, and the single `write` every change goes through.
`VaultController` is the observable facade over it and keeps only what the views watch:
the editor buffer, the selection, the drafts, the route state. Anything that belongs to
the vault rather than to the window goes on the session, or the CLI cannot reach it.

`perg` and `pergamenum-mcp` are `.commandLineTool` targets compiling **the same files on
disk** as the app - `Sources/Core/**`, `Sources/Connector/**` and the pure files under
`Vault` and `Index`, named explicitly in `sharedSources` in `Project.swift`. Not a
framework, not a module: nothing is `public` and there is no second implementation of the
conventions to drift. Three consequences worth remembering:

- a new file under `Sources/Core` that imports SwiftUI **breaks both tool builds**, which
  is ADR-0001 §D1 enforcing itself. It found three inverted dependencies the first time
  it ran.
- a new file outside those globs that a tool needs must be added to `sharedSources` by
  hand.
- `Sources/CLI/**` and `Sources/MCPServer/**` are excluded from the app target, because
  each holds a `main.swift` of top-level code and a module may contain only one.

`Sources/Connector/` is where anything a connector does actually lives: `VaultAPI` holds
the payload shapes both encode, the reads, the writes, and the lookups that turn a string
into a date, a view or a task. **A new capability goes there, not into one of the two
front ends** - a read implemented in `Sources/CLI` is a read the MCP server does not have.
The front ends only translate: `Sources/CLI` reads flags and prints for a person,
`Sources/MCPServer` declares JSON schemas and answers over stdio.

Writes carry three guardrails (§D6) that live on `VaultSession` and are armed in one
place, `VaultAPI.arm`: `isDryRun` computes a write without performing it, `UnifiedDiff`
shows what would change, and `WriteJournal` records what was replaced so `undo` can put
it back - refusing when the file has moved on since. The app arms none of them: a person
editing their own note does not need an undo log. On the MCP side there is a second lock:
write tools are absent from `tools/list` without `--allow-write`, and each one's `dryRun`
defaults to **true**, so a model that omits it gets a diff instead of a change.

Registering the server, read-only first:

```bash
claude mcp add pergamenum -- /usr/local/bin/pergamenum-mcp --vault ~/Labs
```

The protocol layer has no unit tests and cannot have them without linking the MCP SDK
into the app; `scripts/mcp-smoke.py` drives a real server over stdio instead, and is the
thing to run after touching `Sources/MCPServer`.

Not in either connector, on purpose: EventKit, because TCC would attribute a command-line
tool's calendar access to the terminal that launched it.

## Versioning

`CFBundleShortVersionString` is `marketingVersion` in `Project.swift`, raised by hand.
`CFBundleVersion` is the number of commits behind HEAD, handed to the manifest as
`TUIST_BUILD_NUMBER` by `scripts/release.sh` - so Informazioni shows `1.0 (56)` and
`git rev-list --count HEAD` says which commit that was. An ordinary `tuist generate`
passes no number and the build is stamped `0`, which is what marks it a development
build; the release script refuses to ship one, refuses to run off `main` and refuses a
dirty tree, because a release you cannot come back to is not a release.

Never install a release build over `/Applications/Pergamenum.app` without asking, and
move the previous copy aside rather than deleting it.

## Working agreements

- **A merge commit that silently discards a parent's content is refused, not merely logged.**
  PG-240: a branch cut before PR #515 landed merged `main` in, claimed to resolve one `TODO.md`
  conflict, and its tree quietly kept the branch's stale version of fifteen other files nothing
  had flagged as conflicted — a wholesale "ours" resolution, not a per-file one. The next merge
  carried that loss into `main` with nothing left to disagree about. `scripts/git-hooks/pre-push`
  (installed once per machine via `scripts/install-git-hooks.sh`) and the advisory
  `merge-integrity.yml` workflow both run `scripts/check-merge-integrity.py`, which recomputes
  the real merge via `git merge-tree` and fails on any non-conflicted path a committed merge
  disagrees with. A deliberate wholesale override needs `Merge-override: <path>` plus
  `Merge-override-reason: <text>` on the merge commit itself, naming every path — see ADR-0061.
  The same hook and workflow also run the landing check (`--landing BASE HEAD`, ADR-0062), which
  catches the squash/rebase shape a merge-commit check cannot see: a push or PR that would put a
  path back to a blob `main`'s own first-parent history already moved past is refused; a deliberate
  restore needs `Restore-override: <path>` plus `Restore-override-reason: <text>` on any commit in
  the PR's own range — a separate key from `Merge-override`, which does not excuse it.
- **A `SwiftUI` tree that must participate in `List(selection:)` cannot use `DisclosureGroup`.** A
  `DisclosureGroup`'s label is not a row of the enclosing `List`, so a `.tag` on it satisfies no
  binding — the list lights nothing and swallows every click, and it fails silently (`RootView.swift`
  §D-noted trap: a `.badge` applied after `.tag` drops the tag the same way). Use flat recursive rows
  instead (`NoteListPane.swift`'s shape: a `@ViewBuilder` row plus, as a sibling, `if isExpanded {
  ForEach(children) {...} }`, chevron and depth drawn by hand) — see ADR-0024.
- **A security or invariant check exposed as a separately-callable assertion gets skipped by the
  next call site, not maliciously — just by omission.** `NoteStore`'s vault-boundary check stayed
  `private` and reachable from exactly two of eleven call sites for this reason (ADR-0041). Expose
  it instead as the only way to obtain the value callers need (`VaultBoundary.url(for:) throws ->
  URL`, not `assertInsideVault(url)`) — a resolver a caller cannot route around, rather than a step
  a caller can forget.
- **A precondition evaluated before an `await` is a filter, not a guard.** Swift hands the main
  actor back to the run loop at every suspension point, so the state the precondition checked can
  change before the code it was meant to protect runs. `PraticaEntryComposer.insert`'s
  `canOperate(on:)` check, read once before two `await`s, is exactly this shape (ADR-0043 §D7) — by
  the time the write and its hand-off ran, the tab it refused to find dirty had become dirty. The
  guard belongs on the same side of the suspension as the action it protects: ask again after the
  `await`, or act on state read after it, never on a check made before it.
- **The opposite failure of the rule above: a `@State` a confirmation dialog nils on its own
  dismissal cannot be read back inside the confirm button's `Task`.** `NoteListPane`'s
  «Sposta nel Cestino» button did `Task { if let note = deleting, ... }` — pressing the button
  dismisses the dialog first, which runs the `isPresented` binding's setter and nils `deleting`,
  so by the time the `Task` body ran it always saw `nil` and silently skipped the trash call: the
  note reappeared in the sidebar with no alert and no file in the Finder Trash. Capture the value
  before the `Task`, or receive it as the closure's own parameter via `.confirmationDialog(...,
  presenting: state) { value in ... }` — the shape `WorkspaceBrowser`'s own delete dialog and
  `NoteListPane+FolderVerbs`'s folder-delete dialog already used, and the one this fix adopted.
- **A ledger, cache or registry the app holds in memory and saves back must record which file it
  was read from.** A writer that cannot prove it is writing over the file it loaded reads first, and
  never saves over a file it could not read. `PraticheController.ledger` could be written back from
  the wrong memory two ways (a folder rename or a first sync before the pane was ever opened; a
  vault switch that left vault A's ledger in memory over vault B's file) because nothing tied the
  memory to a file — and a corrupt `ledger.json` was the same loss with a third trigger. The fix is a marker
  (`LedgerOrigin`) plus one write door (`updateLedger(_:_:)`) with `private(set)` on the property,
  so a new writer cannot route around it (ADR-0052 §D1/§D3).
- **A file `VaultWatcher` cannot see is a file no automatic reconciliation can start from.**
  `.canvas` paths never reach `VaultWatcher.handle(absolutePaths:)` (it discards everything but
  `.md`), so a Workspace board open in memory has no external signal telling it another writer
  touched the same file — the shape that let a rename/move's board-repoint write get silently
  clobbered by an open board's own pending autosave (`PG-099`). The fix is not extending the
  watcher; it is the ADR-0052 pattern applied to bytes instead of a ledger: `WorkspaceController`
  records a `BoardOrigin` (the hash of what it last read or saved), `CanvasStore.save(_:board:
  expecting:)` refuses a write whose bytes moved on since, a pure `.file`-node repoint reconciles
  automatically against that refusal, and anything reconciliation cannot decide surfaces as a
  named, non-modal `.conflicted` state on the board itself rather than an overwrite or a discard
  (ADR-0054 §D2/§D5/§D7).
- Verify every change against `docs/20260811_Pergamenum_SpecApp.md`. If the spec and
  an instruction disagree, say so before writing code.
- SPEC §14 lists decisions already taken with their rationale. Do not reopen them
  without a stated reason.
- Never edit the `.xcodeproj` or `.xcworkspace` - they are generated. Change
  `Project.swift` and run `tuist generate`. The same applies to *git* operations that add
  or remove a file: `git stash`, `git checkout <branch>`, dropping a file - the generated
  project still lists what is no longer there and the build fails naming the compiler
  rather than the cause. Run `tuist generate` straight after.
- The pre-commit `weakening-scan.sh` reports every Swift Testing test as
  `zero-assertion-test`. Its body scanner skips lines starting with `#`, treating them
  as comments, and a Swift Testing assertion is `#expect(...)`. The findings are
  advisory and this one is systematically wrong for this stack; a genuinely
  assertion-free test still has to be caught by reading the diff.
- The pre-commit secret scanner's `assigned-secret` heuristic fires on this codebase's
  design-token code: it matches the keyword `token` followed by `:` or `=` and 16 or
  more identifier characters, which describes ordinary lines like `tokens =
  collector.tokens`. These are expected false positives, not credentials. Read each
  one before dismissing it - the rule still catches a real key assigned to a variable
  named `token`.
- `.claude/test-cmd` runs at the end of **every** turn, through the `Stop` hook in
  `~/.claude/settings.json`. It is therefore restricted to `-only-testing:PergamenumTests`,
  and that restriction is load-bearing rather than tidiness: with the whole suite in there,
  each turn ended by launching the UI tests, every `XCUIApplication().launch()` terminated
  the app the person at the keyboard was using, and each round left an instance alive
  holding the global hot key exclusively - so the next launch was refused. Two hours went
  into hunting an external culprit for something the assistant was doing itself. The UI
  tests still exist and are run deliberately, by hand.
- **The merge gate is the unit suite (`PergamenumTests`) plus the in-process tests
  (`Tests/HostedViewPrototypeTests.swift` and siblings), not the GUI suite.** This
  supersedes the rule bought on 2026-08-21 after three of the sixty-seven UI tests had
  been red since before a milestone merge and nothing had said so (`PG-033`) — the fix for
  that gap is now the hosted-view conversions themselves (`docs/plans/ui-suite-replacement.md`),
  not a mandatory full GUI run on every merge. The seventeen GUI tests that remain run
  through `scripts/uitests.sh --affected` at merge time and do not block it; a full run of
  all seventeen is required only before a release (`scripts/release.sh`), not before every
  merge. `--status`'s `contaminated` verdict counts as neither green nor red — the run is
  disturbed, not conclusive, and is rerun rather than acted on either way. A new feature
  carries at most two or three GUI tests, and each one is justified in the feature's own
  ADR: the GUI suite is a bounded, deliberately small backstop, not the default place a new
  test lands.
  The script is not a convenience wrapper: it kills stale instances first, refuses to run
  while a copy out of `/Applications` is open, prints the seconds beside each failure so a
  launch timeout is not mistaken for a defect, and cleans up after itself. Run it with no
  arguments for the whole bundle; an argument **replaces** the selection rather than
  adding to it, because two `-only-testing` flags are a union and would silently run
  everything.
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
- **`firstRect(forCharacterRange:)` returns a zero rectangle for a text range TextKit 2 has
  not laid out yet** — reliably true at the end of a long note, since TextKit 2 lays out
  lazily. A zero rectangle handed to a popover or panel's placement clamps it to the screen's
  bottom-left corner instead of failing loudly, so a UI test asserting on a popup's position
  can pass by accident there. Anything anchoring UI to a character range must confirm layout
  has reached that range first, not assume `firstRect` always returns something meaningful.
- **The UI-test runner's own temporary directory is unreadable from outside the sandbox, on
  or off.** A screenshot or file written to it during a test cannot be inspected afterward by
  reading the path directly. Attach it instead with `XCTAttachment`, run with
  `-resultBundlePath`, and pull it back out with `xcrun xcresulttool export attachments`.
- **`-recentVaults` needs the plist array form.** The key holds `[String]`, so
  `-recentVaults /path` leaves `stringArray(forKey:)` nil and no vault is reopened at
  launch; `-recentVaults '("/path")'` works. The launch argument outranks the persistent
  domain, so a throwaway vault reaches a Debug build without touching what the installed
  app opens.
- **Finding the latest Debug build under DerivedData needs `-t`, not plain `ls -d`.** `tuist
  generate` stamps a fresh `Pergamenum-<hash>` DerivedData folder on each regeneration, and
  stale ones accumulate. `ls -d .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`
  sorts alphabetically by hash, not by build time, and can silently hand you a stale build that
  still shows an already-fixed regression. Use `ls -dt .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`
  (or `APP=$(ls -dt ... | head -1)`) to get the most recently built bundle before an `open -n`
  hand-check launch.
- Build and tests must pass before committing. A change that does not build is not done.
- Keep commits small and atomic, one logical change each.
- Never disable or delete a test to make a suite pass.
- UI language is Italian, with the architecture ready for English localization. Code,
  comments and commits stay in English.
- Update the "Status" section of PROJECT_BRIEF.md when a milestone is reached.
- New dependencies go through `Tuist/Package.swift` followed by `tuist install`, not
  through the Xcode UI.

## Decisions from earlier chains (ADR-0019 – ADR-0026)

Full narrative for these six chains is compacted here to essentials; see the ADR files for detail.
The one-line summary of each already lives in the Chain decision index below.

- **ADR-0019 (embed drag-resize):** size lives only in the note's own text (Obsidian `|W`/`|WxH`
  suffix), no new storage. Resize handle is painted inside the attachment's own picture, not a
  separate `NSView`, so hit-testing geometry never diverges from the no-handle case. Source-text
  rewrite happens once at `mouseUp` (one undo step). CommonMark `![alt](file.png)` embeds get no
  handle — only the wikilink form has verified sizing syntax and the app never writes the other.
- **ADR-0021 (Workspace/Task/Note integration):** no new dependency, schema, or index bump —
  `StoredTask` re-parses `rawLine` via `TaskParser.parse`, so a new `TaskItem` field is free in
  cache. `^[[...]]` is a Workspace marker only when its target ends in `.canvas`. "Progetti" is a
  sixth `TaskGrouping`, never a sixth `TaskView` (the five views are closed by ADR-0013 §D6).
  Protected interfaces: `IndexCache.schemaVersion`, `VaultAPI.LintFinding`.
- **ADR-0022 (Workspace UI creazione/toolbar/rename):** a wikilink names a note by title, never by
  path, so folder rename repoints `.canvas` node paths and the folder's own board file name, not
  ordinary `[[Nota]]` links. An ambiguous board name skips the marker rewrite and reports it rather
  than guessing. Folder rename/delete are not journalled (recovery is Trash or a reverse rename).
  Delete uses `FileManager.trashItem`, never `removeItem`.
- **ADR-0023 (universal command surface parity):** a command is named once (`CardCommand`,
  `CalendarDayCommand`, `CommandActions.run(_:on:)`) and rendered on both the toolbar/menu-bar and
  the context menu, so the two cannot diverge. A folder row's context menu attaches to the row's
  label, never to its `DisclosureGroup` (which would leak onto every descendant row). The editor
  embed's `menu(for:)` always falls through to `super.menu(for:)` outside an embed, or the system
  spelling/paste menu silently disappears for the whole editor.
- **ADR-0024 (Workspace board tree single selection):** the tree is flat recursive rows with
  `.tag`, not `DisclosureGroup` (whose label is not a `List` row, so selection cannot bind to it).
  One `WorkspaceSelection` enum replaces the old two-variable model. The selection tag is always
  the folder path, never the board path.
- **ADR-0025 (Workspace folder/board separation):** a board is addressed by its own file path,
  never derived from a folder name — `load(board:)` throws instead of returning `.empty`, closing
  every silent-blank-board defect this repo had traced to that derivation. Folders and boards are
  distinct tree rows; no synthesized root row. `WorkspaceBoardResolver` is the one place that
  answers both "which board does this marker name" and "which board does this folder mean."
- **ADR-0026 (drag-and-drop board/note files into folders):** the dragged item carries two
  `Transferable` representations so the existing "drop a note title onto a task line" contract
  (`CompletingTextView+Pasteboard.swift`, now protected) keeps working untouched. Multi-selection
  is `List`'s own `Binding<Set<String>>` — no custom gesture recognizer, which would starve
  `List(selection:)`'s own tap (ADR-0025 §D9's fix). A move repoints every `.canvas` node's file
  path but rewrites no wikilink/marker (both are title/bare-name based).

## Chain decision index
ADR conventions (one number per file, the status line, citing an ADR from outside this repo) and the renumbering register: `docs/adr/README.md`.

- **ADR-0019** — drag-to-resize handle for drawn embeds, size persisted as Obsidian `|W`/`|WxH` → `docs/adr/0019-embed-drag-resize.md`
- **ADR-0020** — non-destructive image card crop, persisted as one prefixed scalar key `pergamenum-crop` on the canvas node, never touching the file on disk → `docs/adr/0020-image-card-crop.md`
- **ADR-0021** — Workspace browser + Task↔Workspace/Note relations + project sub-tasks, entirely as new task-line caret markers, no new storage → `docs/adr/0021-workspace-tasks-notes-integration.md`
- **ADR-0022** — Workspace sidebar toolbar, folder-backed board creation/rename/delete, no journal, no connector exposure → `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`
- **ADR-0023** — Toolbar/context-menu command parity across six clusters + Duplica card, one catalogue per cluster shared by both surfaces → `docs/adr/0023-universal-command-surface-parity.md`
- **ADR-0024** — One derived `WorkspaceSelection` for the sidebar tree, flat rows replacing `DisclosureGroup`, supersedes ADR-0022 §D9 → `docs/adr/0024-workspace-board-tree-single-selection.md`
- **ADR-0025** — Board addressed by own file path, not folder-derived; folders and boards are distinct tree rows; supersedes ADR-0024 §D2/§D3, relocates ADR-0022 §D4 → `docs/adr/0025-workspace-folder-board-separation.md`
- **ADR-0026** — Drag-and-drop for both sidebar trees, `List`'s own multi-selection, moves reuse the existing "Sposta in ▸" file operations → `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`
- **ADR-0037** — Reveal-on-caret narrows from paragraph to span for emphasis/strikethrough/link, behind a new off-by-default setting, reusing `MarkdownStyler`'s existing recursive parse → `docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md`
- **ADR-0027** — Unify Nota/Testo into one Workspace tool, selection-based rich text (bold/italic/strikethrough/lists/headings as plain markdown) plus whole-card color/alignment as `pergamenum-*` properties → `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md`
- **ADR-0028** — WYSIWYG markdown rendering (concealment + list glyphs) brought from Note into Workspace cards, reopening ADR-0027 §D10 → `docs/adr/0028-wysiwyg-markdown-in-workspace.md`
- **ADR-0029** — One editor, always editable, no Modifica/Lettura toggle; a GFM table becomes a real `NSTextAttachmentViewProvider`-hosted grid; supersedes ADR-0005 §D2 and ADR-0018's "three named constructs" scope boundary → `docs/adr/0029-editor-wysiwyg-unification.md`
- **ADR-0030** — Editor page typography: prose faces (`font.prose`/`font.proseTitle`, Avenir Next) and `spacing.readable` read through tokens by one `ProseTypography` helper, readable-width inset, prose font picker persisted in `personalizzato.json`; amends ADR-0027 §D1 and ADR-0028 §D3, reopens nothing of ADR-0018/0029 → `docs/adr/0030-editor-page-typography-noteplan.md`
- **ADR-0031** — Sparkle auto-update integration: explicit narrow exception to Principle 2 (network) for the updater only, manual-only checks, EdDSA key in Keychain, appcast/binaries hosted on a dedicated public repo `istefox/pergamenum-updates` (amends the SPEC's original private-repo hosting, which live verification found broken), `scripts/release.sh` extended end-to-end → `docs/adr/0031-sparkle-auto-update-integration.md`
- **ADR-0032** — Plaud recording import: loopback-only second exception to Principle 2, `pergamenum-*` frontmatter reopening for transcript notes, quote-fingerprint dedup over note+ledger, two-phase import with retry-only-step-2, app-only scope → `docs/adr/0032-plaud-recording-import-into-pergamenum.md`
- **ADR-0033** — Views render live in the editor again: `pergamenum-view` fences become an `NSHostingView`-hosted attachment reusing the existing `RenderedViewBlock` renderers, host keyed by fence ordinal (not paragraph offset), reveal-on-caret keyed on the fence's whole source range; does not reopen ADR-0009 or ADR-0029 → `docs/adr/0033-views-render-live-in-the-editor.md`
- **ADR-0034** — Visual query builder for `pergamenum-view` fences: one shared "Modifica query" affordance in `RenderedViewBlock`'s header (both live-render and error-card states), validity round-trips through `ViewBlock.parse` itself, flat AND-of-terms `where` with raw-text fallback for or/not/parens, commit reuses `commitTable`'s anchor-and-reload-guard shape; does not reopen ADR-0009 or ADR-0033 → `docs/adr/0034-pergamenum-view-query-builder.md`
- **ADR-0035** — View-block attachment height becomes content-adaptive, capped at the original 320pt (amends ADR-0033 §D8/R-06): measurement crosses the SwiftUI/TextKit isolation boundary via a lock-guarded box on the host, deferred `Task { @MainActor }` relayout to avoid re-entering TextKit, clamp-before-compare for convergence → `docs/adr/0035-view-block-adaptive-height.md`
- **ADR-0036** — Pratiche: a vault folder that fills itself from a published copy of Apple Mail's Envelope Index (system `SQLite3`, db+wal copied, WAL recovered, `quick_check`, own indexes, atomic rename), one markdown file per message plus `allegati/`, membership via `pergamenum-dossier-*` keys, two-lane timeline, `pratica.md` edited only in the inspector, no network, connectors read-only → `docs/adr/0036-pratiche.md`
- **ADR-0038** — Removes both Conformità UI surfaces (the dedicated pane and the note inspector's CONFORMITÀ block); keeps `perg lint`, the MCP `lint` tool, `VaultAPI.LintFinding` (protected interface) and the rule engine untouched, since Principle 5 and tag-entry blocking depend on the engine, not the review UI → `docs/adr/0038-remove-conformance-ui-section.md`
- **ADR-0039** — Task ↔ note/board link and navigation: `TaskCommand` catalogue replaces the never-working "Collega nota o board…" with a single "Collega una board…" (the note is already fixed at capture time), `CommandActions.run(_:on:)` closes the breadcrumb's missing pane-switch, `navigation.taskPickingBoard` hosts the picker at `RootView` for every surface, reopens SPEC §7.2's note-linking requirement → `docs/adr/0039-task-note-board-link-and-navigation.md`
- **ADR-0040** — Fixes Pratiche attachment reliability: an unvalidated `part.decodedData ?? Data()` wrote empty/corrupt bytes straight to `allegati/`; a magic-byte `AttachmentIntegrity` check now gates every write, a pending entry patches the message's attachment line in place rather than re-rendering, and a `.complete` message with a pending entry is now automatically retried every sync; a corrupt file already on disk is moved to the Trash. Amends ADR-0036 §D6 → `docs/adr/0040-pratiche-attachment-reliability-bugs.md`
- **ADR-0041** — Vault layer consistency and security: the vault-boundary check becomes a resolver (`VaultBoundary.url(for:) throws -> URL`, not a skippable assert) used by all 11 call sites that touch the disk with a caller-supplied path; three drifted vault-walk copies and six drifted apply-plan copies become one shared helper in `Sources/Core`; `VaultController*` (18 files) moves out of `Sources/Vault` into `Sources/App`; the write path's disk work moves to a background actor with the hash computed before the hop and a per-path sequence number guarding update order, preserving ADR-0001's index-immediately-after-write invariant. Extends ADR-0001 and ADR-0007, amends neither → `docs/adr/0041-vault-layer-consistency-and-security-cha.md`
- **ADR-0042** — An inline (`cid:`) image Mail hasn't downloaded yet stops being counted as a pending attachment: a per-image body placeholder plus a dedicated `pergamenum-mail-inline-pending` frontmatter key replace the old chip, resolved every sync with no retry cap, and dropped entirely when the body never references the image. Amends ADR-0040 §D9, widens ADR-0036 §D6 → `docs/adr/0042-pratiche-inline-image-placeholders.md`
- **ADR-0043** — Follow-up to ADR-0041, found by an independent post-implementation review: the per-path write-ordering guard (§D11) covers one of the vault's six index writers, two overlapping async writes can capture the same journal "before", and a `canOperate` check does not survive the `await` it guards. Decides one clock stamped inside `VaultDisk` with `apply` as the only index door, the journal's "before" read inside the actor, and a dirty-buffer prompt instead of an unconditional reload. The implementation chain measured the async cascade at 3-4x the ADR's own estimate (~210 call sites, 46 files, 25 test files) and named 13 call sites adopting the §D8 opt-in `expecting:` hash precondition. Extends ADR-0041 §D9/§D10/§D11, amends none → `docs/adr/0043-vault-write-ordering-concurrency-races.md`
- **ADR-0045** — PG-143 pratiche structure refactor: SwiftLint's error-level `file_length`/`type_body_length` debt across eleven pratiche files resolved by pure `Type+Aspect.swift` extension splits (signatures untouched), `private` widening to `internal` only where a split requires it with one comment per widened member naming the file that reads it, and `PraticaSyncEngine+Messages.swift`'s `fileprivate` regeneration-plan cluster kept whole to preserve ADR-0036 §D21's opacity guarantee. Reopens nothing → `docs/adr/0045-pratiche-structure-refactor.md`
- **ADR-0046** — Batch rename/move write guard, follow-up to ADR-0043 §D8: `VaultPlanApplication.Outcome`/`TagRenameOutcome`/`NoteFileOperations.Outcome` gain a `refusals` channel distinct from `failures`, driven by the existing opt-in `expecting:` hash precondition at all four batch writer closures; no preflight pass, the loop never stops on a refusal → `docs/adr/0046-batch-rename-stale-write-refusals.md`
- **ADR-0047** — Task categories as a registry in the vault (`.pergamenum/categories.json`, `#project-<slug>` stays the pointer, `IndexCache.schemaVersion` 3 → 4) plus the end of the Obsidian round-trip as a binding constraint: amends `CLAUDE.md` principle 4 and SPEC §14, no on-disk format changes, eleven prior ADRs (0009, 0010, 0018, 0019, 0020, 0021, 0022, 0023, 0024, 0025, 0027) gain a head scope note with their bodies untouched → `docs/adr/0047-task-categories-and-the-end-of-the-obsid.md`
- **ADR-0048** — A part whose inline MIME payload decodes to zero bytes is not always "not yet downloaded": Exchange sometimes externalizes it permanently to Mail's own sibling `Attachments/<ROWID>/<part>/` directory instead. `MIMEPart` gains a real RFC 3501 (IMAP-style) `partNumber`, closing a pre-existing flat-index bug in `storePath` for free; `decodeBody` tries the sibling file through the exact same integrity/threshold/place pipeline an inline attachment already uses before conceding to ADR-0040's pending retry. Amends ADR-0040 §D2, widens SPEC R-10 → `docs/adr/0048-externalized-attachments-resolved-from-sibling-directory.md`
- **ADR-0049** — A pratica links to notes, tasks and boards: three foreign `pergamenum-dossier-links-*` keys on `pratica.md`, kept out of `Dossier` on purpose so `Dossier.merging`'s own C4 rule cannot erase them; every reference is written as a wikilink (`[[Titolo]]`, `[[Nome.canvas]]`, `[[Nota]] ^id(3)`), which is what makes R-07 (rename-safe) free through the note/board rename passes that already rewrite every `[[…]]`. One resolver (`PraticaLinkResolver`) answers `unique`/`ambiguous`/`missing` for all four relations by delegating to the two resolvers that already exist; nothing is cached (`IndexCache.schemaVersion` stays 4), a link is always read off the file that owns it. `PraticaCommand`/`MessageCommand` gain link/unlink verbs and one new picker, `PraticaLinkPicker`; the inspector gains three read-only sections (R-04, R-06) and the timeline gains a per-row aligned column (R-05) that never switches the inspector's own content (R-09). The write door reuses `DossierWriter`'s `expecting:` precondition shape. The connector gets one new file, `Sources/Connector/VaultPraticheLinks.swift`, read and write, translated by both front ends → `docs/adr/0049-pratiche-links-to-notes-tasks-and-boards.md`
- **ADR-0050** — Closes `PG-152`/#281: the journal gesture (`operation` id + `command`) becomes a task-local `JournalGesture.current` (`Sources/Core/Vault/`), bound by `transaction(_:_:)` through `withValue` and read back by `currentOperation`/`journalCommand` (now computed), instead of `@MainActor` state set for the duration of an `async` body. Two transactions open at once on two tasks each stamp their own id; the nested-transaction assertion becomes exact instead of a concurrency false positive. Not the issue's «actor-owned operation stack», rejected because a stack disambiguates nesting, never interleaving. `VaultDisk` untouched, no schema/format/manifest change; the three `journalCommand`/`journal` borrow-and-return sites (`+TagRename`/`+TaskDrop`/`+BoardDrop`) are named as the same hazard shape and left for a follow-up. Acceptance is a gate-forced deterministic interleaving test (ADR-0043 §D9's rule) → `docs/adr/0050-journal-gesture-travels-with-the-task.md`
- **ADR-0052** — Closes `PG-172`/#312 and the second half of `PG-173`: `PraticheController.ledger` becomes `private(set)` with a `LedgerOrigin` marker (`none`/`loaded(URL)`/`unreadable(URL)`) recording which file the memory came from, and every ledger mutation — six save sites, not the four the SPEC counted — goes through one door, `updateLedger(_:_:)` (`LedgerTarget` live/stale, `LedgerWrite` outcome), which reads first when the marker does not match the target file, applies the change to a local copy, and saves only if it changed. A `ledger.json` that exists but cannot be read is never saved over (`PraticaLedger.read(from:) -> Read`, one visible sentence, no quarantine or repair UI). PG-169's «is the in-memory ledger empty?» heuristic in `forgetLedgerState` is deleted; a vault change resets the vault-scoped state (`pratiche`, tray proposals/counts, watchers, selection, timeline, details, links) but not the redirect map, tombstones or in-flight claims. The tombstone falls per path (`dropTombstoneIfUnclaimed`) instead of all-or-nothing, amending ADR-0026 §D7's 2026-09-19 note. The door sits at the foot of `PraticheController.swift` because Swift confines a `private(set)` setter to the declaring file; `PraticaLedger.swift` stays Foundation-only for `perg`/`pergamenum-mcp`. On-disk format, `IndexCache.schemaVersion` (4) and every protected interface untouched. Extends ADR-0036 §D3, amends ADR-0026 §D7 → `docs/adr/0052-pratiche-ledger-marker-and-one-write-door.md`
- **ADR-0054** — Closes `PG-099`/#213: a Workspace board's own pending autosave could silently clobber a rename/move's board-repoint write, since `.canvas` paths never reach `VaultWatcher`. `WorkspaceController` gains a `BoardOrigin` (the hash of the bytes last read or saved) and a `SaveState` (`saved`/`pending`/`conflicted`); `CanvasStore.save(_:board:expecting:)` refuses a write whose bytes moved on since, `CanvasDocument.reconcile(mine:base:theirs:)` adopts the refusal automatically for a pure `.file`-node repoint and diverges everywhere else, surfacing as a non-modal `.conflicted` state on the board's own toolbar with «Mantieni le mie modifiche»/«Ricarica dal disco», resolved in `WorkspaceController+Conflict.swift`. The same `writeRepoint`/`expecting:` guard, through the one apply-plan loop (`VaultPlanApplication`, ADR-0041 §D4), reaches the other four `.canvas` writers that could race the same way — `BoardFileOperations.renameBoard`/`moveBoard`, `FolderFileOperations.renameFolder`/`moveFolder`, `VaultSession+Tasks.writeTaskSource`'s board branch — each reporting a `refusals` channel distinct from `failures` (ADR-0046 §D4's shape, widened to the four rename/move outcome structs). Deliberately out of scope (§D8, filed as `PG-205`/`PG-206`): the **note** half of the same rename/move verbs stays an unguarded `store.write`, and `NoteFileOperations.rename`/`move` keep no production caller. No on-disk format, schema or protected interface touched. Extends ADR-0041 §D4/§D9, ADR-0046 §D4, amends neither → `docs/adr/0054-board-origin-marker-and-canvas-write-preconditions.md`
- **ADR-0055** — Closes `PG-205`/#402 and `PG-206`/#403, answering ADR-0054 §D8's own named gap: the **note** half of a rename/move verb now writes through one guarded door too, `NoteStore.writeGuarded` (ADR-0055 §D1), beside `CanvasStore.writeRepoint`'s `.canvas` twin — a note whose bytes moved on since the plan was read is refused, not clobbered, at `BoardFileOperations.renameBoard` and `FolderFileOperations.renameFolder` (§D2), both through the one apply-plan loop (`VaultPlanApplication`). The other half of the chain deletes rather than fixes: `NoteFileOperations.rename(_:to:knownPaths:)`, `move(_:toFolder:)`, the private `repointBoards` and `trash(_:knownPaths:)` had no production caller — the app's one note performer stays `VaultSession.renameNote`/`moveNote`/`trashNote`, which already reads a plan from this type — so the dead direct-write half leaves, and every assertion its eighteen tests made is re-pointed at a live surface rather than dropped (§D6). Every doc comment the deletion and the guard adoption made false is corrected in the same chain, including `VaultPlanApplication`'s own header and `Outcome.refusals` doc comment (§D7/§D8). A residual gap measured while writing §Context — `VaultController.reconcile` only reloads/conflicts the focused `openNote`, silently dropping an external change to any other dirty tab — is named, not fixed, and filed as `PG-209` (§D5). No on-disk format, schema or protected interface touched. Extends ADR-0054 §D6/§D8 and ADR-0046 §D1/§D3/§D4/§D8, amends neither → `docs/adr/0055-note-write-guard-and-the-dead-rename-performer.md`
- **ADR-0056** — Closes `PG-211`/#415, the gap ADR-0055 §D5 named and left open: `VaultController.reconcile`, `movedNote` and `trashedNote` asked only the focused column (`openNote`, or the focused-column `tabs`), so an external change to a background tab or to the other column was dropped (no reload, no ADR-0001 §D3.4 banner, the next save overwrote it) and a rename/trash left the other column on a dead path. One new door, `updateTabs(showing:_:)` in `VaultController+Tabs.swift`, applies a change to every tab showing a path in every column — `canOperate(on:)`'s existing all-columns shape (§D1–§D3); `closeTab` finds its tab in whichever column holds it (§D4) and now calls `rememberTabs()` on every close, after the neighbour is picked — an `if wasActive` block rather than a hoisted call, because `rememberTabs` reads the column's active path (§D5). `openNote(at:)`'s dedupe and the computed `tabs` stay focused-column on purpose (§D6). Two more sites of the same shape, found while checking the shipped diff, are fixed in this same chain (§D7): `canOperateOnFolder` now asks every column too, since the folder verbs it guards (`renameFolder`/`trashFolder`/a batch move) reach every column through §D3; and the conflict banner's two buttons now go through the column's own `focused { }` door before resolving, since a banner can now appear in a non-focused column. A third, pre-existing and not widened by this chain — `syncOpenNote(with:)` keeps `reconcile`'s old focused-only guard for ten in-process writers (task toggle, drop, time blocks, …) — is named and filed separately rather than folded in. No on-disk format, schema or protected interface touched. Extends ADR-0012 §D2/§D4 and closes ADR-0055 §D5, amends neither → `docs/adr/0056-every-tab-that-shows-the-note.md`
- **ADR-0057** — Closes `PG-153`/#262, a window ADR-0043's implementation notes filed as «wider than §D8 can close»: the diary gains its own origin marker and one guarded write door, the ADR-0052/ADR-0054 pattern applied to a third in-memory holder. `readDiary` now returns the disk state it read (present-with-hash or absent), `writeDiary(over:)` takes that state as a mandatory precondition instead of writing unconditionally, and a writer landing in between is refused — surfaced as a non-modal `.conflicted` `saveState` with «Mantieni le mie modifiche» / «Ricarica dal disco», never a silent overwrite or a silent drop. All writes serialize through one door (`enqueue`/`drain`/`runner`), so a day switch, a keystroke-triggered save and an app-quit flush can never race each other in-process. Deliberately scoped out and filed as its own four issues (§D8): five other read-then-write sites still write unguarded (#496), the quit flush is fire-and-forget (#497), the Diario pane learns of an external change only when it next tries to write (#495), and `WorkspaceController` silently discards a conflicted board on navigation (#498) — #495 closed by ADR-0058 (a parallel chain), the other three by ADR-0060. No on-disk format, schema or protected interface touched → `docs/adr/0057-diary-origin-marker-and-one-write-door.md`
- **ADR-0058** — Closes `PG-223`/#461, the gap ADR-0056 §D7.3 named and left open: a write this app makes itself is self-hashed, so `VaultSession.reconcile` drops it and the watcher never reports it, and the caller's catch-up is a tab's only chance to hear of it — yet `syncOpenNote(with:)` (ten in-process writers: task toggle, drop, time blocks, diary, categories, capture route, pratica entry), `saveOpenNote()`, `restoreVersion(_:)` and `addStructuralLink` caught up the focused tab only, leaving a clean copy in a background tab or the other column to revert the write on its next save and a dirty one never asked. One per-buffer rule, `OpenNote.catchUp(to:)` (dirty → ADR-0001 §D3.4 prompt, clean → adopt and clear a stale prompt), replaces the two word-for-word copies in `reconcile` and `syncOpenNote` (§D1); `syncOpenNote(with:)` becomes `updateTabs(showing:)` + `catchUp` (§D2). `saveOpenNote()` still writes the focused buffer, but records the writer tab's id before the `await` and hands the rest to an `internal` `syncOpenNote(with:savedBy:)`, which finds the writer by id rather than by focus — the writer takes `savedText` only and keeps any text typed during the suspension, every other copy gets §D1 (§D3). `restoreVersion` reads its path before the save instead of re-reading `openNote` after it (§D4). `VaultSession.addStructuralLink` returns `(created:, written:)` — every write that landed, even when the second fails — so «Collega» on a dirty note raises the prompt instead of discarding the edits and the target note is caught up too; the focused-only `reloadFocusedNote()` loses its one caller and is deleted (§D5). `bufferText(for:)`, `noteText(at:)`, `acceptExternalChange`/`keepLocalVersion` and the name `syncOpenNote` stay as they are (§D6). Seven writers that never catch the editor up at all (note-rename link rewrite, `renameTag`, `undoJournalledWrites`, `moveOnBoard`, Pratiche `ensuringLocalID`, the composer's diary mirror, Plaud re-import) are named, not fixed, with a post-write notification from `VaultSession.write` as the recommended follow-up (§D7). No on-disk format, schema or protected interface touched. Closes ADR-0056 §D7.3, extends ADR-0056 §D1/§D2 and ADR-0043 §D7, amends neither → `docs/adr/0058-in-process-writes-reach-every-tab.md`
- **ADR-0059** — Closes `PG-130`/#230: `pergamenum://note?id=` had returned false on every call since M6, because `RouteState.noteIDs` was read and never written and no id existed anywhere. It departs from the ticket's "index field plus `schemaVersion` bump" on measurement (gate A). A move re-derives the index row, every in-app rename ends in a rescan, the scanner drops a changed row, and «Svuota cache», a bump or a second Mac drop the cache, so an id kept there would make principle 3 false. Ids live instead in a vault file, `.pergamenum/note-ids.json` (`VaultLayout.noteIDsFile`, version 1, keyed by lowercase UUID v4, pretty-printed and sorted), with a pure `NoteIDRegistry` in `Sources/Core/Vault/` and a disk-side `NoteIDStore` (§D1). An id is minted only when a link needs it, through one door, `VaultSession.mintNoteID(for:)`, which returns an id only once it is on disk and never regenerates one; nothing is minted at indexing time (§D2). The session holds no copy: every door loads, applies one pure change, and saves only if the registry changed. A `malformed` or iCloud-`evicted` registry is never written, which closes ADR-0052's lost update across the app, `perg` and `pergamenum-mcp`, though not the read-write gap inside one call (§D3). `relocating`/`removing` match by exact path plus a `/` prefix, and a folder is carried by its own pair (§D4). They are called at `moveFile`/`trashFile`, the three folder doors and Pratiche «Sposta in…»/its undo, and never from the watcher or a scan (§D5). `trashNote`/`trashFolder` forget the id, while «Escludi»/«Rigenera» do not (§D6). `RouteState.noteIDs` is deleted and the route reads `VaultSession.lookUpNote(id:)` (`found`/`unknown`/`unreadable`). It checks the path through `VaultBoundary` with an existence check shared with `.note`, so an id never opens a tab on a missing file (§D7). «Copia link Pergamenum» now copies `note?id=` and falls back to the path link with a recorded problem (gate B, §D8). The connectors share the rename door, so they keep the registry in step, but they expose no id (§D9). `IndexCache.schemaVersion` stays 4 and no frontmatter key is added. The ADR proposes one protected-interface entry for `NoteIDRegistry`, pending approval (gate E). Its implementation notes record five departures from the literal wording. Amends ADR-0001 §D2 and SPEC §9/§14 (§D10, gate D) → `docs/adr/0059-note-ids-live-in-a-vault-registry.md`
- **ADR-0061** — Closes `PG-240`/#522: a branch cut before PR #515 landed merged `main` in, resolved one real `TODO.md` conflict, and silently kept its own stale version of fifteen other files nothing had flagged as conflicted (a wholesale "ours" resolution) — the next merge carried the loss into `main` with no conflict left to catch it. `scripts/check-merge-integrity.py` recomputes the real merge via `git merge-tree --write-tree` and fails on any non-conflicted path whose committed blob is byte-identical to one parent's (a "side-pick"); content novel to both parents is reported as an advisory "evil merge," never blocked. Measured at zero false positives and two true positives (the incident plus a second, previously undetected match, filed separately) across all 434 two-parent merges in the repository's history. `scripts/git-hooks/pre-push` (installed once per machine by `scripts/install-git-hooks.sh`, shared across worktrees via the git common dir) is the actual blocking gate, since `main` carries no branch protection; `.github/workflows/merge-integrity.yml` reports the same finding on every PR and push, deliberately without `ci.yml`'s `paths-ignore` — the incident's own PR was a `TODO.md`-only sync that would have skipped it. A deliberate override needs `Merge-override: <path>` plus `Merge-override-reason:` on the merge commit itself; a bare `Merge-override: all` is rejected. The gap it named, a squash or rebase merge bypassing the check entirely (§D5), is closed by ADR-0062's landing check → `docs/adr/0061-merge-integrity-guard.md`
- **ADR-0062** — Closes `PG-242`/#535, ADR-0061 §D5's squash/rebase gap: a history with no merge commit gives the merge check nothing to inspect, and on linear history `git merge-tree BASE HEAD` just reproduces the squashed content, so the evidence comes from `main`'s own record instead. `scripts/check-merge-integrity.py --landing BASE HEAD` computes the tree that would land (`merge-tree` only when `BASE` is not an ancestor), diffs it against `BASE`, and fails on any path whose new blob is one that path already held on `BASE`'s first-parent line — shape-independent across merge commits, squashes, rebases and hand-copied files. Deletions are context only, never a failure (measured legitimate deletions of recently added files rule them out; a pure-deletion stale snapshot is a named residual, §D8). A deliberate restore needs `Restore-override: <path>` plus `Restore-override-reason:` on any commit in `BASE..HEAD`, a separate key from `Merge-override`; `all` is rejected and a `git revert` message is not an automatic exemption. `--landings RANGE` makes the measurement a command: 6 of 411 first-parent landings flagged (the PG-240 incident, 3 deliberate restores, 2 `.claude/test-cmd` toggles), none among the 30 squash/direct landings. Blocking in `scripts/git-hooks/pre-push` (base: the remote's old tip for `main`, else `refs/remotes/<$1>/main`; an unresolvable base or a pre-ADR-0062 checker is a notice, never a block), advisory in `merge-integrity.yml`, whose PR step resolves `origin/<base.ref>` in the job instead of trusting `pull_request.base.sha`. The installed hook is a copy: machines with the ADR-0061 hook must rerun `scripts/install-git-hooks.sh --force`, and the checker warns on every run until they do. Branch protection not reopened. Closes ADR-0061 §D5, extends ADR-0061 §D1–§D4, amends none → `docs/adr/0062-landing-check-closes-the-squash-gap.md`
- **ADR-0063** — Closes `PG-256`/#570 (Audit Fable chain 3) and `PG-151`/#280: a negative or unreadable `limit` is one usage sentence from `Sources/Connector` on both connectors (`0` answers empty; `VaultSession.search`'s append-then-test off-by-one fixed), a malformed MCP `cursor` is JSON-RPC `-32602` with no overflow trap, and no `ToolArguments` reader traps on a huge number. The flag parser refuses an option whose value starts with `--`, `--flag=value` and a bare `--` (`--option=--value` is the escape hatch, `-1` stays a value). `VaultSession.createBoard(named:in:)` validates with the Workspace rule (moved to `FolderName.validate` in `Sources/Core`), spells the path through `CanvasStore.boardFilePath`, pre-checks a taken name as a filter so a rehearsal tells the truth, and writes through `writeFile(…, expectingAbsent: true)`, a new precondition on the `.canvas` door (ADR-0057 §D3's rule), so `pratica_create_board` honours `dryRun` and journals; undo of the creation is declined, the journal never deletes; unlike `CanvasStore.createBoard` it creates a missing parent folder, as `createNote` does. The app's two board creations stay on the store on purpose. The three «create and link» summaries name the created file in `note`. `importFile`, `CanvasStore.createFolder`, folder rename/trash, the pratica timeline and `Attachment` resolve through `VaultBoundary`; `Attachment` gains a `within:` form and the editor's `EmbedTable` builds its boundary once per root, so no symlink resolution is added per keystroke. `VaultBoundary.url(for:)` joins `.claude/protected-interfaces`. 31 residual root-relative sites are filed, not fixed. Extends ADR-0007 §D6, ADR-0041 §D1/§D2, ADR-0057 §D3, ADR-0043 §D7/§D8; amends none → `docs/adr/0063-connector-input-hardening.md`
- **ADR-0060** — Closes ADR-0057 §D8's remaining three follow-ups (#496, #497, #498) — #495 landed separately as ADR-0058's companion PR while this chain was in progress and is not reopened here. Five more read-then-write sites in `Sources/Vault` (`append`, `linkFromDailyNote`, the `addStructuralLink` pair, `moveOnBoard`, `captureTask`'s creation case) adopt the same `expecting:`/`expectingAbsent:` guard the diary already had; `addStructuralLink`'s doc comment is corrected from claiming full atomicity to the weaker guarantee the guard actually gives (a refusal on the second write leaves the first landed, named rather than rolled back), composed with ADR-0058 §D5's own change to that function's return shape rather than fighting it. `AppDelegate.applicationShouldTerminate(_:)` now awaits a new `DiaryController.settle()` (capped at 2s) before quitting, replacing a `willTerminateNotification` flush nothing awaited. `WorkspaceController.load(board:)`/`select(_:)` gain `refusesToLeaveConflictedBoard()`, closing two defects found during implementation beyond the original three: `select(nil)` used to wipe a conflicted board's `document`/`origin` while leaving `saveState == .conflicted`, making the state unrecoverable; and the sidebar's rename/move/trash verbs (`WorkspaceView+FolderVerbs.swift`) still performed their disk operation on a conflicted open board, stranding the conflict on a dead path — both closed by the same guard, exposed as `canLeaveOpenBoardForVerb()` for the verb call sites. `WorkspaceController`'s own quit-flush gap, the same shape as #497 but for boards, is named and filed separately (#506) rather than folded in. No on-disk format, schema or protected interface touched. Extends ADR-0057, amends none → `docs/adr/0060-adr0057-followups-five-write-sites-quit-flush-board-navigation.md`
- **ADR-0064** — Closes `PG-234`/#511: `VaultDisk.reconcile`'s failed-read branch now decides on existence, not just readability — nothing at the path and no iCloud placeholder → `ExternalChange.Content.deleted`; unreadable, evicted or a boundary failure → nothing, as before (§D2). `OpenNote.externalChangePending` becomes that `Content?` and `catchUp(to:)` reports `.adopted`/`.asked`/`.vanished`, so a vanished clean tab closes through the trash's own door (extracted as `closeTabs(_:ofVanishedNote:)`) and a dirty one is asked with «Scarta ed elimina» / «Tieni la mia versione», never «Ricarica da disco» (§D3-§D5). Gate G1 confirmed §D6 over Alternative 4b: `VaultSession.moveFile` records the source path it vacates in `selfWrittenHashes` under an absence marker (provisional before the hop, corrected after, dropped on throw or once the path is found present again), so the watcher's own reconcile of that path never races `movedNote` and closes the tab a rename or move is about to follow; `trashFile` is unchanged, an in-app trash still reaches the watcher as `.deleted` (R-09). Zero GUI tests. No on-disk format, schema or protected interface touched. Extends ADR-0043 §D3/§D6, ADR-0056 §D3 and ADR-0058 §D1, amends none → `docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md`
- **ADR-0065** — Closes `PG-254`/#568 (Audit Fable chain 1): every on-disk format round-trips faithfully or is refused. `NoteDocument` keeps a `FrontmatterSource` of the lines it read and edits the block in place: an unchanged key, a comment, a colon-less line, an unparsable tag or a duplicate is emitted byte-identical; a changed key is rewritten at its governing (last) occurrence, the one the reader already uses; an emptied duplicated key is written bare; a foreign key follows its codec, matched by name and ordinal; CRLF is kept per line and new lines take the document's line break. The BOM is a property of the file: one decode door strips it, `NoteStore.hash` skips it, `NoteStore.write` keeps it. JSON Canvas consumes keys per kind, keeps unrecognised colours as `.unrecognised` and unreadable elements at their index; `reconcile` diverges on duplicate ids and opaque differences instead of trapping. Mail: one Latin-9-aware charset table, RFC 2047 §6.2 and B-padding, RFC 2231 parameters, an HTML reducer that drains its pending buffers, an exact escape inverse, and `pergamenum-mail-date` with the sender's offset (UTC otherwise). Task tags are removed by range; `![[x]]` is an inline embed; one anchored `RelatedSection.sectionRange(in:)` serves export, the linter and «Collega»; rename matches on `resolvedTitle`; `.canvas` is never a note link target; three advisory `frontmatter` lint strings. `IndexCache.schemaVersion` 4 → 5 (G1). Extends ADR-0054 §D4, ADR-0041 §D7 and ADR-0043's hash convention; amends none → `docs/adr/0065-format-round-trip-faithful-or-refused.md`

## Decisions from later chains (ADR-0027 – ADR-0041)

Full narrative for these chains is compacted here to essentials; the one-line summary of each
already lives in the Chain decision index above.

- **ADR-0027 (Nota/Testo unification + rich text):** the Workspace card gets its own lightweight
  `NSTextView`, sharing no class with the note editor — only `InlineFormat.swift` (pure
  markdown wrap/unwrap) is reused. The floating format bar positions itself in board-space
  coordinates (`p * zoom + pan`), never screen coordinates, or it drifts at any zoom other than 1.
  Text color/alignment are whole-card `CardCommand`s, not selection-bar controls.
- **ADR-0028 (WYSIWYG markdown rendering in Workspace):** the card's text view reuses
  `EditorDecorationDelegate` directly rather than forking it, so the two surfaces cannot silently
  diverge. A list marker is substituted character-for-character, never inserted/collapsed —
  TextKit 2 forbids changing a paragraph's length mid-layout. Feature lives behind the existing
  `VaultSettings.hidesMarkup` toggle, no new switch.
- **ADR-0029 (editor WYSIWYG unification):** removes the Modifica/Lettura toggle everywhere (it
  lived in six places, not two) — the editor is now always editable and always styled. A GFM
  table becomes a real `NSTextAttachmentViewProvider`-hosted `NSView` grid, not a fourth
  length-preserving substitution; cell edits commit on Tab/blur/Enter, never per keystroke.
  Workspace `.text` cards are explicitly excluded (a live `NSView` grid must never land in a
  culling-deallocated card).
- **ADR-0030 (editor page typography):** one helper, `ProseTypography` (`Sources/DesignSystem/`),
  is the only place outside `Sources/Core` allowed to construct an `NSFont` in editor/Workspace
  scope. Two new tokens, `font.prose`/`font.proseTitle` (Avenir Next), sit beside the untouched
  interface faces. Bold/italic on a named font family goes through `withSymbolicTraits`, never a
  weight trait — measured: a `.weight: .bold` trait on Avenir Next silently returns the regular
  face.
- **ADR-0031 (Sparkle auto-update):** first explicit, narrow exception to Principle 2 (fully
  offline) — manual-only update check (`SUEnableAutomaticChecks: false`), no telemetry
  (`SUSendsSystemProfile` false), Sparkle enters through exactly one file under `Sources/App/`,
  invisible to `Sources/Core`/`Sources/Connector`/both CLI targets. Appcast/binaries are hosted on
  a dedicated public repo (`istefox/pergamenum-updates`), not the main repo — the SPEC's original
  private-repo hosting plan was verified broken. EdDSA private key lives only in this Mac's login
  Keychain.
- **ADR-0032 (Plaud recording import):** second, narrower exception to Principle 2 — traffic never
  leaves 127.0.0.1:3777 (loopback only). Closed note-frontmatter schema is reopened only via
  `pergamenum-*` prefixed keys. Dedup across re-imports matches on quote-text fingerprint, never
  task id (the service never guarantees a stable id across separate `process` runs). Two-phase
  import: write the note locally first, `POST` accepted task ids only after. Protected interface:
  `ImportNaming.recordingNoteTitle`.
- **ADR-0033 (Views render live in the editor):** `pergamenum-view` fences become an
  `NSHostingView`-hosted attachment reusing the existing `RenderedViewBlock` renderers (query
  layer untouched). Host store is keyed by the fence's ordinal in the note, never by paragraph
  offset, or every keystroke above the fence would re-run its query. Reveal-on-caret is keyed on
  the fence's whole source range, not ADR-0018's per-paragraph set.
- **ADR-0034 (pergamenum-view query builder):** one "Modifica query" affordance shared by both
  fence states. Validity round-trips through the real `ViewBlock.parse` — no second, lenient
  grammar exists. `where` is a flat AND-of-terms model with a raw-text fallback for anything
  non-flat (or/not/nesting), so a non-flat filter is never dropped or altered.
- **ADR-0035 (view-block adaptive height):** measurement crosses from SwiftUI's `@MainActor`
  layout into TextKit's `nonisolated attachmentBounds` through a lock-guarded box on a new host
  subclass, never a shared `@MainActor` property. A height-change callback never invalidates
  TextKit synchronously — it defers one `Task { @MainActor }` hop. `storableHeight` clamps before
  it compares, which is what makes the measure→relayout→remeasure cycle actually terminate.
- **ADR-0036 (Pratiche):** a vault folder synced from a published copy of Apple Mail's Envelope
  Index (system `SQLite3`, in exactly one file, `MailStoreConnection.swift`) plus `.emlx` files —
  one markdown note per message, `allegati/` for attachments, no network. `pratica.md` has exactly
  one editor, the inspector — timeline rows are read-only, because *n* live text views bound to
  ranges of one file is the shape of every text-loss defect this repo has documented. A sync never
  deletes a file and rewrites a message file only for a `pending` body that arrived or an explicit
  «Rigenera» (amended by ADR-0040, see below). `MailStoreLocation.resolve()` is test-aware; all
  UI-test files pass `-mailStoreRoot <fixture>`. Protected interfaces: `PraticaNaming.messageFileName`,
  `Dossier.render`, `VaultAPI.PraticaSummary`.
- **ADR-0037 (word-grained markdown reveal-on-caret):** narrows reveal-on-caret from paragraph to
  span for emphasis/strikethrough/link only, behind an off-by-default setting. Construct extents
  come from `MarkdownStyler`'s existing recursive walk, never a second parser. A caret reveals only
  the innermost containing span; a non-empty selection reveals every span it intersects.
- **ADR-0039 (task-note-board link and navigation):** `TaskCommand` (mirrors `CardCommand`) is the
  one catalogue for `.linkBoard`/`.goToNote`/`.goToBoard`, replacing four hand-kept lists that had
  drifted. "Collega nota o board…" loses its note half (a task's note is already fixed at capture
  time) and becomes "Collega una board…". The board picker's `.sheet(item:)` moves to `RootView`
  so it works from every surface, not just `TasksView`.
- **ADR-0040 (Pratiche attachment reliability fix, amends ADR-0036 §D6):** root cause was one
  line — `PraticaSyncEngine`'s `let bytes = part.decodedData ?? Data()` fed empty/truncated bytes
  straight into hashing and writing; the existing SHA-256 dedup was already correct and needed no
  change. A new `AttachmentIntegrity` type (`Sources/Core/Email/AttachmentIntegrity.swift`,
  Foundation-only) checks magic bytes/terminators before every write and before the store-reference
  threshold check; an unknown format is judged on emptiness alone, never rejected for want of a
  signature. A pending attachment reuses the existing `pergamenum-mail-attachments` list (bare name
  = pending, `[[name]]` = placed) — no new frontmatter key. §D6 amended twice: a `.complete`
  message with a pending entry is now retried every sync via a one-line patch
  (`MessageAttachmentPatch`), never a full re-render, no attempt cap; and a corrupt file already in
  `allegati/` is moved to the Trash (never deleted outright) and re-enqueued as pending. Attachment
  chip UI moves from a `Bool` gate to a three-state `FileState { usable, missing, unusable }` plus a
  `.pending` chip content case. Protected interface: `MessageDocument.isPendingAttachmentEntry`.
- **ADR-0041 (vault layer consistency and security):** the boundary guard that used to be a private,
  skippable `assertInsideVault` inside `NoteStore` becomes `VaultBoundary.url(for:) throws -> URL` in
  `Sources/Core/Vault/` — a resolver is the only way to get a usable `URL`, so a new call site
  inherits the check instead of needing to remember it. The same file holds one shared vault-walk
  helper and one shared apply-plan helper, replacing three and six drifted copies respectively.
  `VaultController*` (18 files) relocates from `Sources/Vault` to `Sources/App`, wider than the SPEC's
  single-file scope because moving only the declaration would have left 17 app-shell files stranded
  in the vault layer. The write path's disk I/O moves to a background actor; the hash is computed on
  the main actor *before* the hop (not after) so `selfWrittenHashes` cannot observe an FSEvents batch
  ahead of its own bookkeeping, and a per-path sequence number — not await-ordering alone — guards
  against two rapid writes to the same file landing out of order. `VaultSession.read` deliberately
  stays synchronous: it has 25 call sites that are synchronous `@Observable` computed properties
  SwiftUI evaluates from `body`, which cannot `await`. Extends ADR-0001 (index-immediately-after-write
  invariant, made mechanical rather than convention) and ADR-0007 (VaultSession/VaultController split,
  shared-sources architecture) without amending either.
- **ADR-0042 (Pratiche inline image placeholders, amends ADR-0040 §D9):** an HTML signature's
  `cid:` images (logo, social icons) stopped being treated like attachments — an undownloaded one
  no longer records a pending entry in `pergamenum-mail-attachments`; it leaves a one-sentence
  italic placeholder (`MessageInlineImage.placeholder`) at its own position in the body and records
  its content id in a new, dedicated key, `pergamenum-mail-inline-pending`. When the body never
  references the `cid:` at all — the common case, since the body usually comes from the
  `text/plain` MIME alternative — no placeholder and no pending state are recorded for it; this is
  what removes most of the reported "In attesa" pills. A resolved image re-enters the body at its
  own placeholder on the next sync (`MessageInlineImagePatch`, count-guarded against a hand-edited
  body — a mismatch links the image as an ordinary attachment instead of touching the wrong
  placeholder), widening ADR-0036 §D6's automatic-rewrite exceptions by one clause, same no-cap
  retry policy as ADR-0040 §D5. No protected interface touched; no new frontmatter schema key
  outside the one sanctioned prefixed addition (ADR-0020's precedent).
- **ADR-0043 (vault write ordering, follow-up to ADR-0041 §D9/§D10/§D11):** `VaultDisk.IndexMutation`
  is the one currency every file-touching actor operation returns; `VaultSession.apply` becomes the
  sole door onto the index and `updateIndex(_:at:)` is deleted. The synchronous write door
  (`write(_:to:) throws`, `writeSynchronously`) is deleted — the async cascade this forces turned
  out to be ~210 call sites across 46 files and 25 test files, not the seven ADR-0043 itself
  measured, because the transitive closure runs through ~18 internal wrappers the ADR's own grep
  did not reach. The journal's "before" (`hashBefore`/`textBefore`) is read inside the actor, where
  the bytes it describes are written, not on the main actor beforehand. `selfWrittenHashes` becomes
  a per-path, sequence-tagged list pruned by the clock. `syncOpenNote`'s dirty-buffer branch now
  raises ADR-0001 §D3.4's conflict prompt instead of silently doing nothing, at all nine call sites.
  `write` gains an opt-in `expecting: String?` hash precondition, adopted at 13 named call sites. A
  known residual hazard — `transaction(_:_:)`'s `currentOperation` now spans a suspension once its
  body is `async`, so two `Task {}`-started transactions can interleave — is deliberately left open,
  tracked as `PG-152`, for its own future ADR rather than patched blind. Acceptance for this chain
  is five deterministic interleaving tests (ADR-0043 §D9), never a green suite alone.
- **ADR-0045 (PG-143 pratiche structure refactor):** SwiftLint's error-level
  `file_length`/`type_body_length` debt across eleven pratiche files becomes a pure move into
  `Type+Aspect.swift` extensions of the same type, signatures untouched — the shape forty files
  in this codebase already use. `private` widens to `internal` only where a split actually
  requires it, one comment per widened member (or contiguous run) naming the file that reads it
  (`NoteListPane.swift`'s convention, made general); a member whose callers move with it does not
  widen. Two genuine second-responsibility extractions get new types instead of plain extensions:
  `PraticaFileOperations` (the filesystem half of `PraticaCommandActions`) and
  `MailStorePreparation` (the Envelope-Index publish-and-open block, now one home for all four
  call sites). `PraticaSyncEngine+Messages.swift`'s `fileprivate` regeneration-plan cluster
  (`PreparedMessage`, `PreparedAttachment`, `RegenerationPlan.prepared`) stays whole and stays
  `fileprivate` even at ~560 lines, because splitting it would repeal ADR-0036 §D21's opacity
  guarantee that the diff shown is the bytes written. `ImportNaming.truncatedAtWordBoundary(_:toFit:)`
  becomes the one word-boundary truncator behind both `PraticaNaming.messageFileName` and
  `ImportNaming.recordingNoteTitle`, pinned by both protected names' existing regression tests.
  `Tests/PraticaSyncTests.swift` (the same two violations) is explicitly out of scope, filed
  separately rather than left unmentioned. No SPEC decision, on-disk format, frontmatter key,
  protected-interface signature or user-visible behaviour reopened.
- **ADR-0046 (batch rename/move write guard, follow-up to ADR-0043 §D8):** `VaultPlanApplication
  .Outcome` gains a third collection, `refusals`, classified apart from `failures` in both `apply`
  overloads. `VaultWriteRefusal` (was `VaultSession.WriteRefusal`) moves to a top-level
  `Sources/Core/Vault/VaultWriteRefusal.swift`, since `apply` lives in `Sources/Core` and cannot
  catch a type declared in `Sources/Vault`; `VaultSession.WriteRefusal` stays as an **unqualified**
  `typealias` so `perg`/`pergamenum-mcp`, which compile the same files under a different module
  name, keep compiling. All four batch writer closures — `renameTag`'s note writer, `renameNote`'s
  note and board writers, `moveNote`'s board writer — adopt the existing `expecting:` precondition
  through two new named seams, `VaultSession.writeGuarded`/`writeFileGuarded`, added specifically so
  a test can drive them directly: no timing-based interleaving test is ever written, since the
  plan-to-first-write window is empty in-process and the real race window opens only inside the
  loop, which a single-threaded test cannot observe without racing a concurrent `Task` (§D2, §D11).
  A refusal never stops the loop and nothing already written is rolled back — all-or-nothing in the
  batch's *decision*, best-effort in its *execution*, ADR-0026 §D6's rule applied to the other batch
  verb (§D3). `renameTag` is idempotent and re-runnable; `renameNote`/`moveNote` are not, since
  `oldTitle` derives from the file's *new* name once it has moved, so the two appliers report a
  refusal differently on purpose — a count for the tag path, a named problem for the note path
  (§D6). `writeFile` gains the same opt-in precondition as `write`, guarding the board half of a
  note rename that §D1 would otherwise leave half done (§D5); `VaultSession.writeFile`'s own
  pre-hop journal-«before» read (ADR-0043 §D5's Race 2 shape, on this one door only) is deliberately
  left unfixed and filed as `PG-161`. The connectors' JSON is unchanged: refusals fold into
  `FileMoveSummary.failures` with their own sentence rather than a new key.
- **ADR-0047 (task categories and the end of the Obsidian round-trip):** two things ship as one
  chain because they touch the same documents. The category system is a registry file,
  `.pergamenum/categories.json` (`CategoryRegistryStore`, `StarredStore`'s shape: atomic write,
  malformed reads as empty and is never overwritten by a save), validated through one pure door
  (`CategoryRegistry.validating(_:)`) before anything is written; `#project-<slug>` stays the only
  pointer, no new tag or marker. `IndexSnapshot` gains the effective-category and rollup
  derivations, and `IndexCache.schemaVersion` goes 3 → 4 so the linked note's `pergamenum-category`
  key survives a cache reuse — the exact defect shape Pratiche already paid for. `TaskView.byProject`
  and `TaskGrouping.project` deliberately keep reading `task.project` literally; inheriting through
  a linked note would change two existing surfaces nobody asked to change. The sidebar's selection
  becomes one derived `TaskPaneSelection` enum (view or category), replacing a second variable that
  could disagree with the first — ADR-0024's rule applied to the second tree in the app; the five
  `TaskView` cases stay five and unchanged (reopens ADR-0013 §D6 by addition, not by replacement).
  The second half ends the Obsidian round-trip as a binding constraint, a product decision Stefano
  took on 2026-08-22 during ADR-0020's implementation and left unpropagated: `CLAUDE.md` principle 4
  and SPEC §14 are amended, not the formats — `.canvas` stays JSON Canvas 1.0, the embed-size suffix,
  16-hex node ids and the `pergamenum-` prefixed-key discipline are unchanged, and no ADR body is
  rewritten. Eleven prior ADRs whose decision rested on the round-trip (0009, 0010, 0018, 0019,
  0020, 0021, 0022, 0023, 0024, 0025, 0027) gain a scope note at the head, verbatim, pointing here;
  §D12's rule was reformulated during the chain's fix loop from a section-position test to a
  load-bearing/counterfactual one, and the re-audit against the reformulated rule is what added
  0009 and 0018 to the original nine. 0032 mentions Obsidian only in the same consequence-shaped way
  the reformulated rule still excludes, and stays without a note, recorded as the correction R-13
  asks for rather than applied silently. `CanvasTests.roundTripsAnObsidianCanvas`
  and its siblings are untouched and stay green — they pin the JSON Canvas format, not a
  compatibility gate → `docs/adr/0047-task-categories-and-the-end-of-the-obsid.md`
- **ADR-0049 (a pratica links to notes, tasks and boards):** three keys,
  `pergamenum-dossier-links-{notes,tasks,boards}`, live in a new type, `PraticaLinks`, kept
  foreign to `Dossier` on purpose (§D1) — a key `Dossier` owned would be a key
  `Dossier.merging`'s own C4 rule erases the next time `DossierWriter.update` runs a sync write,
  and `Dossier.render` (protected) is never touched. Every reference is written as a wikilink —
  `[[Titolo]]`, `[[Nome.canvas]]`, `[[Nota]] ^id(3)`, and `pergamenum-mail-note: "[[Titolo]]"` on
  a message file — which is what makes R-07 (rename-safe) free through the note and board rename
  passes that already rewrite every `[[…]]` (§D2); the bare-title and vault-relative-path
  alternatives were rejected for reasons named in §D2. `IndexCache.schemaVersion` stays at 4 (§D4)
  — a link is read off the file that owns it every time, never off `NoteRecord.frontmatter
  .foreignKeys`, which is empty on a cache-reused record. One resolver, `PraticaLinkResolver`,
  answers `unique`/`ambiguous`/`missing` for all four relations by delegating to
  `WorkspaceBoardResolver` and `IndexSnapshot.resolve(title:)`, candidates passed in rather than
  fetched (§D5). «Rigenera» patches `prepared.noteText` (not `replacementText`) before the diff
  is computed, so the link survives a regeneration (§D7) — the ADR-0036 §D21 trap this repo has
  already paid for once. The timeline's per-message column is a fixed-width slot inside the
  existing row's own `HStack`, the lane's 70% computed on `width - gutter` because
  `containerRelativeFrame` resolves against the scroll container regardless of nesting (§D8); the
  slot is read-only and opens the note in the editor rather than binding a second live text view
  to it, and the inspector never switches on timeline-row selection (§D9, R-09). `PraticaCommand`/
  `MessageCommand` gain link/unlink verbs and one new picker, `PraticaLinkPicker`, modelled on
  `WorkspacePicker` rather than reusing `QuickSwitcher` (§D10). The write door mirrors
  `DossierWriter.update`'s read-modify-write-with-`expecting:` shape (§D11). The connector gains
  one new file, `Sources/Connector/VaultPraticheLinks.swift`, read and write, translated by both
  front ends; `VaultAPI.PraticaSummary` (protected) is untouched (§D12) → `docs/adr/0049-pratiche-links-to-notes-tasks-and-boards.md`

Detail: see each ADR under `docs/adr/`.
