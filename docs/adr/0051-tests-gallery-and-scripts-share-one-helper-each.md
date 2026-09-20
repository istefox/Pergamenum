# ADR-0051: Tests, the design gallery and the scripts each get one shared helper, and the copies not worth closing are named

- Status: accepted (see the plan at `docs/plans/pg-148-tests-gallery-scripts.md`)
- Date: 2026-09-19. Written on branch `248-pg-148-test-files-past-500-lines-wit`, based on
  `main` at `5570583`. Every count below was read out of the tree, or produced by running
  `swiftlint`, `PergamenumTests`, `appcast.py --self-test` and `scripts/mcp-smoke.py` on it. None is
  recalled from the issue text, which is seven days old and already wrong in several places (see
  Context).
- **Numbering note:** `0050` is the highest under `docs/adr/` and no `0051` exists in any commit
  reachable from `--all`. Checked, not assumed.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no tag
  grammar, no protected-interface signature. No test is disabled, skipped or deleted. One
  behaviour changes and is named: §D3.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- Depends on, and amends none of: **ADR-0045** (§D1 the obligation is the error threshold, §D8
  out-of-scope findings are recorded rather than left unsaid, the `Type+Aspect.swift` split
  convention), **ADR-0031** (§D10, `appcast.py`, and the release pipeline whose text
  `ReleasePipelineTests` pins).

---

## Context

`PG-148` (GitHub issue #248, P3) reports three unrelated pockets of copy-paste: test files past 500
lines with duplicated fixtures, the design gallery's "17 copies of one helper", and script
prologues "copy-pasted four times". Re-measured against the tree:

| Issue claim | Measured state |
|---|---|
| `PraticaSyncTests.swift` declares `makeEngine` twice | Already fixed. The file no longer exists; `makeEngine` is declared once, in `Tests/PraticaSyncFixtures.swift`. |
| "four diverged copies" of the repo-root resolver | **Eight.** Seven were visible when the plan was written; `PlaudIsolationTests.swift` held an eighth, under another name (`resolvedSourcesRoot`). One of the eight had no `Sources` guard at all. |
| The gallery's "17 copies of one helper" | Right, and it is two helpers: `scene(_:_:)` and the page chrome. The chrome had drifted into two incompatible widths. |
| Script prologues copy-pasted four times | **Three** scripts, about 20 lines, not uniform. No colour codes exist anywhere, and the claimed duplicated `xcodebuild` wrapper is two call sites sharing a flag prefix. |
| `uitests.sh` needs a `kill_instances` helper | `kill_and_wait()` already exists. The two loops around it are not the same loop. |

The chain therefore does what still has value, and records each refusal with its reason.

## Decisions

### D1. The obligation is SwiftLint's error threshold

Inherited from ADR-0045 §D1 and restated because §D5 depends on it. File length errors at 1000
lines and type body length at 350; the 400 and 250 warnings are taken where the same move reaches
them. `Tests`, `UITests` and `Sources` are all inside `.swiftlint.yml`'s `included:`, so a test
file is measured like a production one.

None of the three files this chain splits (`ConventionsTests` 832, `TaskTests` 524,
`MockupScreens` 514) was over the error threshold. They are split anyway because the issue names
them and because each is a sequence of independent sections with almost no shared state (which is
what makes a split cheap and checkable). The split is judged by what it costs, not by a violation
it removes.

### D2. A shared test helper is an internal free function

`resolvedRepoRoot() throws -> URL` and `RepoRootResolutionError` live in
`Tests/RepoRootSupport.swift`. It is a free function and not a `static` on a suite because six of
the eight copies were `private static` and two (`NoteStoreReadTests`, `InlineSpanRevealFenceTests`)
were already free functions: only the free form lets those two adopt it by deleting their local
declaration and changing nothing else. The `private static` call sites lose their `Self.` prefix.

The five files that each declared a `private enum RepoRootResolutionError` are changed in the same
commit as the shared one is added, because an internal type of that name collides with every one
of them.

### D3. `MailStoreReaderTests` gains a guard it never had

`MailStoreReaderTests.repoRoot()` was declared `throws` but could not throw: it returned a path
without checking that `Sources` exists under it, while its doc comment claimed to be "the same
resolution `SharedSourcesPurityTests` uses". Adopting the shared resolver makes it able to fail.
That is a behaviour change inside a refactor and is recorded here, not slipped into a
`refactor:` diff. It can only turn a silently wrong path into a loud error.

`PlaudIsolationTests.resolvedSourcesRoot()` is now `resolvedRepoRoot()` plus `Sources`, and its
private error enum is gone.

### D4. A helper that diverged is not merged

Only byte-identical fixtures are shared. `EmbedEditorFixtures.makeTempVaultRoot` gained a `prefix`
parameter (the copies differed in nothing else); `writeImage`, `waitForRendition`, `note`,
`embedOffset` and the marker run length are adopted by `EmbedDrawingTests` and
`EmbedResolutionTests`.

Two helpers stay local, each with a comment naming the difference: `editor(...)` in
`EmbedDrawingTests` (a plain `NSTextView`, no window, no `claimsCommand`, a tuple return) and in
`EmbedResolutionTests` (no window, `hidesMarkup` left at its default), and
`EmbedDrawingTests.waitForSubstitution`, which asserts one level lower than `waitForRendition`. A
shared signature over two different assertions is how a fixture stops meaning anything.

### D5. `MockupPage` is the one page chrome, and the width is the point

`Sources/Features/DesignGallery/MockupPage.swift` holds `MockupPage` (the `ScrollView`, spacing,
padding, background and a content width of `MockupGalleryView.contentWidth`), `MockupScene` (a
caption above its content, with `.fixedSize(horizontal: false, vertical: true)` on the caption as
the default) and `MockupCell` (a titled card at a fixed width, with `alignment` as a parameter).

The argument is not the line count. Nine mockups used `.frame(maxWidth: .infinity, ...)` and eight
used `contentWidth`. A vertical `ScrollView` does not scroll sideways, so anything the sheet cannot
hold is centred and clipped at both edges at once, which is the trap `MockupGalleryView`'s own
comment documents. The eight had been fixed one at a time after a review round; the nine had not.
Written once, a new mockup cannot be the tenth. This does change how those nine draw when their
content is wider than the sheet, which is the intended correction.

Six mockups keep a thin private `scene` over `MockupScene`, because their backdrop or column width
is their own decision: `CaptureMockup`, `SlashMenuMockup`, `FindBarMockup`, `FormatBarMockup`,
`EmbedMockup`, `TransclusionMockup`. `EmbedMockup.labelled` differs from the other three (tertiary
caption, no padding, no background, no clip, width 300) and is not folded into `MockupCell`;
Outline, History and Template are.

`MockupScreens.swift` is not a registry, despite the name. It held four unrelated whole-window
compositions that share no code, and is split one file per type: `EditorMockup`,
`WorkspaceMockup`, `TodayMockup`, `TasksMockup`.

### D6. The design gallery ships in the app

The gallery compiles into the shipping app target unconditionally: `Sources/**` is globbed
(`Project.swift`), there is no `#if DEBUG` anywhere in the folder, and Impostazioni reaches it in
a Release build through the "Mostra i mockup…" button. This chain does not change that. It is
stated because a reader of a gallery refactor will assume it is debug-only, and it is not.

It also has no unit-test coverage. The one UI test that touches it,
`UITests/DesignAndReadingUITests.swift`, asserts the absence of sidebar strings, not the shape of
any screen. §D5's change is therefore verified by the build and by a by-hand pass, not by a test.

### D7. `scripts/lib/common.sh` is not created

The issue's remedy for the prologue duplication. It is three files (`fetch-sparkle-tools.sh`,
`install-cli.sh`, `release.sh`), about 20 lines, and not uniform: `fail()` carries a different
literal prefix in each, `uitests.sh` uses `printf '%s\n' "$1"` and has no `step()`, and
`adr-0043-interleaving-check.sh` shares none of it on purpose (`set -u` only, because it counts
failures instead of aborting on the first).

`ReleasePipelineTests` asserts `contents.contains("set -euo pipefail")` against
`fetch-sparkle-tools.sh`, and the test's stated intent is that the strictness be visible in the
script. Sourcing a library either turns that test red or forces it to be rewritten to follow a
`source`, which gives away the property it protects for 20 lines. Extracting only the other two
scripts leaves a library with two callers.

The same reasoning refuses `release.sh`'s phase-function rewrite: the test pins the `stapler` and
both `ditto` lines and their order, and the literal name `sparkle_tool()`, and the script cannot
be dry-run (it needs `main`, a clean tree, a Developer ID, a notarytool profile and an
authenticated `gh`, and it publishes). What is done is smaller: the appcast upload's two
`gh api` calls, identical but for one argument, become one call with a built argument array; the
`if` and the comment that explains why the 404 is distinguished stay.

### D8. `uitests.sh`'s two kill loops stay doubled

`kill_and_wait()` already exists. The remaining doubled part is the loop around it, and the two
are not interchangeable: the first kills `$debris`, a list already partitioned against `$yours`
(a copy running from `/Applications`, which aborts the run); the second re-runs
`running_instances()` unfiltered and kills everything. Merging them would delete that distinction
to save about four lines.

The asymmetry itself looks like a defect: the post-run cleanup can kill an `/Applications` copy
the person launched during the run, which is what the pre-run check refuses to do. It is filed as
its own entry, not patched inside a P3 structural chain. The bare `set -e` that closes the
`set +e` window around `xcodebuild` is correct in effect and gains a comment saying the window is
deliberate.

### D9. What is and is not known about `support.js`

`docs/design/pratiche/support.js` is a 1911-line generated bundle whose header names a
`dc-runtime` directory this repository has never contained. A sibling,
`support.js.PROVENANCE.md`, records what can be established: it arrived in `8fb5c6b`, `DESIGN.md`
records the export as Claude Design fetched through DesignSync, one file references it, and it
loads React 18.3.1, ReactDOM 18.3.1 and Babel standalone 7.29.0 from `unpkg.com` without a hash.

The plan for this chain said the origin was unrecoverable. That was too strong: the delivery
channel is recorded, in `DESIGN.md:8`, and was found only while writing the note. What is
unrecoverable is the runtime's *source*, which is what the header points to. The bundle is left
byte-faithful, which is why the record is a sibling file and not an edit to its header.

### D10. Five `.font(.system(size:))` lines stay

The plan proposed routing five gallery lines through tokens (`TransclusionMockup` ×2,
`EmbedMockup`, `ViewMockupRenderers`, `WeekMockupPieces`). Read at the line, they are not clear
violations: production code under `Sources` uses the same call seven times for a symbol or glyph
size (`RootView.swift:358`, `WeekEntryRows.swift:33`, `BoardChrome.swift:91` among them), and a
mockup that must show a specific pixel size cannot express it through a role token without
changing what it shows. Rewriting them would change how a mockup draws, which a refactor commit
does not do silently. Left unchanged.
`TransclusionMockup`'s `[.black, .black.opacity(0)]` is a `.mask` alpha ramp, not a colour, and is
left for the same reason.

## Consequences

- Eight resolver copies become one, and a ninth cannot appear without a reviewer seeing a
  duplicate of a named helper.
- `ConventionsTests` (832 lines) becomes four files of 160 to 290 lines with 74 `@Test`s before
  and after and an identical function-name set. `TaskTests` (524) becomes two files with 35 before
  and after. The moved bodies are byte-identical; the checks were a sorted multiset diff of
  non-blank lines and a `uniq -d` over the function names, which is what caught a range that
  overlapped and duplicated seven tests on the first attempt.
- `conformantNote` is used by both the Frontmatter and Related sections of `ConventionsTests`, so
  Related stays with Frontmatter instead of moving to the link file, as the plan first said. `today`
  in `TaskTests` is used on both sides of the split, so `TaskViewTests` carries a private copy.
- The gallery's 17 chrome copies become one. The nine that were `.infinity` are now bounded.
  `FoldingMockup`'s widest row is 676pt against a 720pt content width, spilling 4pt into the
  padding, and is the row to watch in the by-hand check.
- `ADR-0018` still cites `MockupScreens.swift:64`, a path that no longer exists. ADR bodies are
  not rewritten; this is the record.
- Left open, filed as new entries rather than absorbed: the `uitests.sh` post-run cleanup
  asymmetry (§D8); about 20 near-identical `~Copyable` temp-vault fixtures in `Tests/`, of which
  `TaskVault` is a strict subset of `TemporaryVault`; `taskNote` declared in both `TaskTests`'s
  old body and `TaskDropTests` with different content; conflicting `tripleWidth` constants (213 in
  `TabBarMockup`, 208 in `HistoryMockup` and `TemplateMockup`); `MockupGalleryView.Screen`'s three
  hand-synchronised parallel switches.
- The collision to watch: worktree `204-pg-120-mailstorereadertestspublishre` targets
  `Tests/MailStoreReaderTests.swift:139`; this chain edits the resolver at the bottom of the same
  file.

## Amendment, 2026-09-20: the four residuals closed

The four entries left open above became `PG-176` to `PG-179` (#330 to #333). Three were closed on
branch `chore/adr-0051-residuals`; #333 was closed on `main` by #337 while it was open. Each was re-measured against the tree before any edit, and two
of the four issue texts were wrong in a way that changed the fix. This section is additive: the
body above is not rewritten.

**#331 / PG-177, `taskNote` declared twice.** Renamed to `fiveViewsNote` (`TaskViewTests`) and
`dropTargetNote` (`TaskDropTests`). They are not merged: `TaskDropTests` reads its fixture by line
offset and by the word `Collaudo`. Not fixed, out of scope: `praticaNote` is declared four times in
four files (`PraticheConnectorTests`, `PraticaLedgerFolderTrashTests`, `DossierWriterTests`,
`PraticheLinksConnectorTests`), and their contents were not compared.

**#332 / PG-178, `tripleWidth`.** The issue names 213 as the odd value out. 208 is the wrong one.
`MockupPage` pads 24 points a side and only then clamps to `contentWidth`, so a mockup's content
gets 672, not 720, and a `MockupCell` pads 8 a side after its frame. 208 was measured against 720
and gave a row of 704, 32 over. `TemplateMockup`'s `doubleWidth` of 320 was the same slip (a row of
688, 16 over) and is not named in the issue. `MockupGalleryView` now derives `rowWidth` (672),
`pairWidth` (328) and `tripleWidth` (213) once, and the mockups read them: `HistoryMockup` and
`TemplateMockup` take the outer width less the 16 a cell pads. That removed `sceneWidth` declared in
two files (one of them never read), `pairWidth` declared in three, and a bare `213` in
`TagBrowserMockup`. The single-use literals (`FoldingMockup` 330, `EmbedMockup` 300, `SlashMenuMockup`
340, `TaskControlsMockup`, `WorkspaceMockup`, `ViewMockupRenderers` 204) are not a shared grid and
are left.

**#333 / PG-179, `MockupGalleryView.Screen`.** The claim that forgetting a switch is a silent gap is
false: all three switches are exhaustive with no `default:`, so the compiler refuses the build. The
cost was edit count, not silence. This branch first merged `title` and `milestone` into one switch
returning a private `Entry`, then met a fix already on `main`: #337 had closed the same issue by
folding all three switches, the view included, into one `Screen.page` table of `Page` values (an
`AnyView` per screen). The branch's version was dropped in the merge and `main`'s kept, so this
chain changes nothing about the screen switches. It stays worth knowing that the `Entry` shape was
checked equal to the old one, all 21 titles and milestones, and that `main`'s `Page` table trades
the `@ViewBuilder` switch's type identity for the single table.

**#330 / PG-176, the temp-vault fixtures.** There were 21 struct declarations (22 `~Copyable` hits,
one of them a comment, one `TemporaryVault` itself), so 20 duplicates, not the 22 the issue says.
There are now 10. §D4 bounded the merge: only a fixture that is a subset of another is folded.

| Outcome | Fixtures |
|---|---|
| Folded into `TemporaryVault` (7) | `TaskVault`, `LinkVault`, `RouteVault`, `ComposerVault`, `DayVault`, `AttachmentVault`, `CacheVault` |
| Compose a `TemporaryVault`, forward `root` and `write` (4) | `OpsVault`, `BoardOpsVault`, `FolderOpsVault`, `CharacterizationVault` |
| Folded into `CanvasTemporaryRoot`, now in `CanvasTestSupport.swift` (4) | the three `TemporaryRoot`s and `DrawingRoot` |
| Kept local, each with a comment naming why (4) | `VaultWalkFixture`, `BoundaryFixture`, `CallSiteFixture` at the declaration; `TemporaryDirectory` (`ThemeCustomizationTests`) in `TemporaryVaultSupport.swift`, because that file sits exactly at SwiftLint's 400-line warning threshold and five lines of comment there would add a warning |

`TemporaryVault` gained nothing and moved to `Tests/TemporaryVaultSupport.swift` (§D2). Its surface is
still `root`, `stateBase`, `init`, `deinit` and `write(_:to:)`. `text(at:)`, `bytes(at:)`,
`createDirectory`, a `write` that supplies its own contents, and a `prefix:` parameter were each
refused: every one has one call-site family, and a shared fixture that grows a member per suite is the
unbounded superset §D4 forbids. Three decisions differ from what the plan said, each for a reason found
while doing it:

- `CacheVault` became a file-private `extension TemporaryVault` in `IndexCacheTests.swift` carrying
  `cacheURL` and `corruptCache()`, not two free functions. The effect is the same, `TemporaryVault`'s
  shared surface is untouched, and the 15 `vault.cacheURL` call sites did not have to change.
- `CharacterizationVault` was to stay local because its file header calls it a baseline to re-run
  unedited after ADR-0041's `rename` refactor. That refactor has landed (`NoteFileOperations.swift:218-237`
  runs `renamePlan` and `VaultPlanApplication.apply`), and the file, untouched since it was written,
  passes against the refactored code, so the reason expired and it is composed like the other three.
- `VaultWalkFixture` stays local, but not for the reason first given. No caller reads the `URL` its
  `makeFile` returns (0 of 30 calls), so it is a strict subset of `CanvasTemporaryRoot`. What is left is
  the name: that fixture is documented for canvas suites and no walk test touches a board. It is the
  first candidate if a neutral name for the plain-directory fixture is ever wanted.

Things a reader of the diff should know:

- The `#expect` comments in `VaultMoveTests.swift:443`, `FolderFileOperationTests`,
  `NoteFileOperationTests` and `NoteRenameCharacterizationTests` read as if a call on a `~Copyable`
  value cannot appear inside `#expect`. That is wider than the truth. 155 lines under `Tests/` put
  `vault.` inside one and compile, including a throwing method call
  (`#expect(try vault.text(at:) == sampleBoard)` in `FolderFileOperationTests`). What fails is
  passing the value itself by name as an argument. The comments are left as they were; `TemporaryVaultSupport.swift` states the narrow form.
- The per-suite temp-directory prefixes (`pergamenum-tasks-`, `-links-`, `-composer-`, `-day-`,
  `-cache-`, `-ops-` and the rest) collapse to `pergamenum-vault-` or `pergamenum-canvas-`. No test
  reads a directory name (grepped). What is lost is diagnostic: debris under the system temp directory
  no longer says which suite left it.
- Ten fixtures that had no `stateBase` (the six folded into `TemporaryVault` other than `CacheVault`,
  and the four composed ones) now create and remove one nobody reads. It does not hide a leak: under test `VaultController.open` resolves `VaultState.processDefaultBase()`, an isolated
  per-process directory, not the real Application Support.
- The plan expected `grep -rn '~Copyable' Tests/` to fall to 8 lines. It falls to 12: the four composed
  fixtures are still `~Copyable`, since a struct holding a noncopyable value must be. That is 10
  declarations and 2 comments, and 12 is the number a ninth copy has to be measured against.
