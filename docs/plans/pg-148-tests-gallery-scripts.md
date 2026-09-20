# PG-148: tests, gallery, scripts

Issue #248, P3. The decisions and their reasons are in
`docs/adr/0051-tests-gallery-and-scripts-share-one-helper-each.md`; this file is what was done
and how it was checked, in the order it was done.

## Tests

| Change | Files |
|---|---|
| One repo-root resolver, `resolvedRepoRoot()` and `RepoRootResolutionError` | new `Tests/RepoRootSupport.swift`; local copies removed from `SharedSourcesPurityTests`, `PraticheIsolationTests`, `ReleasePipelineTests`, `AttachmentIntegrityTests`, `NoteStoreReadTests`, `InlineSpanRevealFenceTests`, `MailStoreReaderTests`, `PlaudIsolationTests` |
| Embed fixtures adopted | `EmbedDrawingTests`, `EmbedResolutionTests` use `EmbedEditorFixtures`; `makeTempVaultRoot` gains `prefix` |
| Stale comment naming the deleted `PraticaSyncTests.makeEngine` | `PraticaLiveSyncRecordOutcomeTests` |
| `ConventionsTests` 832 to 290 lines | new `ConventionsLinkTests` (205), `ConventionsNamingTests` (160), `ConventionsImportTests` (198) |
| `TaskTests` 524 to 293 lines | new `TaskViewTests` (241) |

Each split moved bodies verbatim. Checked with a sorted diff of non-blank lines (multiset), the
set of `@Test` function names before and after (74 and 35, identical), and `uniq -d` over the
names for duplicates.

## Design gallery

- New `MockupPage.swift`: `MockupPage`, `MockupScene`, `MockupCell`.
- All 17 mockups take their page chrome from `MockupPage`. 11 lose their private `scene` for
  `MockupScene`; six keep a thin private `scene` over it; Outline, History and Template take
  `MockupCell`.
- `MockupScreens.swift` becomes `EditorMockup.swift`, `WorkspaceMockup.swift`,
  `TodayMockup.swift`, `TasksMockup.swift`.

## Scripts and docs

- `scripts/release.sh`: the appcast upload is one `gh api` call with a built argument array; the
  `if` on the 404 and its comment stay.
- `scripts/appcast.py`: `AppcastItem` dataclass, `ITEM_FIELDS`, and `self_test()` split into
  `_case_1` to `_case_5`. `REQUIRED`, the CLI and the self-test read the field list from the
  dataclass.
- `scripts/mcp-smoke.py`: `main(argv)` and an `if __name__ == "__main__"` guard, `find_binary(argv)`,
  and a `make_check(failures)` closure so `failures` is no longer a module global. The stage
  signatures gain a `check` parameter; the 68 call sites are unchanged.
- `scripts/uitests.sh`: a comment on the `set +e` window.
- New `docs/design/pratiche/support.js.PROVENANCE.md`.

## Not done, and why

`scripts/lib/common.sh`, the `release.sh` phase rewrite, merging the `uitests.sh` kill loops, and
the five `.font(.system(size:))` lines: ADR-0051 §D7, §D8 and §D10.

## Verification

Run on this tree, 2026-09-19.

| Check | Result |
|---|---|
| `PergamenumTests` (`.claude/test-cmd`) | 3257 tests in 171 suites passed, after the tests and gallery changes |
| `swiftlint lint --quiet` | 429 lines of output. No new error. `ConventionsTests`, `TaskTests` and `MockupScreens` no longer appear. The one error in a touched file, `InlineSpanRevealFenceTests.swift:351` (305 characters), is the same line that was `:373` at `HEAD` |
| `bash -n scripts/release.sh scripts/uitests.sh` | clean |
| `python3 scripts/appcast.py --self-test` | exit 0, 10 checks |
| `scripts/mcp-smoke.py` against a Debug `pergamenum-mcp` | every stage passed, "tutto a posto", exit 0 |
| Importing `mcp-smoke.py` as a module | no side effects, `main` present |
| `ReleasePipelineTests` alone, after the `release.sh` and `appcast.py` edits | 7 tests passed, exit 0 |

Not run, and required before any merge to `main`:

- `scripts/uitests.sh`, the full bundle. Baseline: 12 failures, the `PG-162` gesture set.
- The by-hand gallery pass: Impostazioni, "Mostra i mockup…", all 21 screens in a Debug build,
  looking at the nine mockups that used `.infinity` for clipping at either edge, and at
  `FoldingMockup`'s 676pt row. No test covers the gallery, so this is the only check the
  `MockupPage` change gets beyond the build.

## Ledger, after the last merge

`/project-tasks` closes `PG-148` and opens: the `uitests.sh` post-run cleanup asymmetry; the ~20
`~Copyable` temp-vault fixtures in `Tests/`; `taskNote` declared twice with different content;
the conflicting `tripleWidth` constants (213 and 208); `MockupGalleryView.Screen`'s three parallel
switches.
