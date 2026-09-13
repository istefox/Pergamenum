## Coder Report

### Files modified
- `Sources/Vault/VaultSession+TagRename.swift` — converted `renameTag`'s hand-rolled write-and-collect loop to build `[VaultFileChange]` and call `VaultPlanApplication.apply`, the same shared helper the other nine copies already use (ADR-0041 §D4/§D5).

### Sub-steps
1. Read `Sources/Vault/VaultSession+TagRename.swift` in full, focusing on the loop at line ~79 — done.
2. Read `Sources/Core/Vault/VaultPlanApplication.swift` and `Sources/Core/Vault/VaultFileChange.swift` — done.
3. Read an already-converted call site (`Sources/Vault/NoteFileOperations.swift`'s `rename`, lines 223–234) to confirm the established pattern — done.
4. Converted the tenth copy the same way: built `let fileChanges = changes.map { VaultFileChange(path: $0.path, before: $0.before, after: $0.after) }`, then `let result = VaultPlanApplication.apply(fileChanges) { try write($0.after, to: $0.path) }`, then `var outcome = TagRenameOutcome(changed: result.rewrittenPaths, failures: result.failures)` — done. The failure format naturally became `"\(change.path): \(error)"` in place of `"\(change.path): \(error.localizedDescription)"`, as approved.

Nothing was left out.

### Key decisions
- `TagRenameChange` (the preview type, with its extra `title` field used by the UI sheet) was left untouched — only the internal `renameTag` loop needed the narrower `VaultFileChange` shape, built with a one-line `.map` right before the `apply` call. No caller of `tagRenamePreview` is affected.
- `TagRenameOutcome`'s own shape (`changed`, `journalIDs`, `failures`) did not need to change: `result.rewrittenPaths` maps directly onto `outcome.changed` and `result.failures` onto `outcome.failures`, so no caller adjustment was needed anywhere (`VaultController+Files.swift`, `TagBrowserView.swift`, `TagRenameSheet.swift` all consume `.changed`/`.failures` by name and are untouched).
- The `write($0.after, to: $0.path)` closure returns `VaultSession.WriteResult` but is used where `(VaultFileChange) throws -> Void` is expected — Swift discards the value implicitly for a single-expression closure body, matching how `NoteFileOperations.rename` already discards `store.write`'s `String` return the same way. No explicit `_ =` was needed and none of the other nine call sites use one either.
- Left `undoJournalledWrites`/`preflightUndo`/`performUndo` (lines 96–133) untouched — the brief scoped the conversion to the `renameTag` loop only, and those functions already build their `TagRenameOutcome` independently of any per-file write loop (they go through `preflightUndo`/`performUndo` on `VaultSession+Journal`, outside this task's scope).

### Verification
`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath ".build/DerivedData" -only-testing:PergamenumTests test`
Exit code 0. `** TEST SUCCEEDED **`. Confirmed via `xcrun xcresulttool get test-results summary` against the produced `.xcresult`: `"result" : "Passed"`, `"totalTestCount" : 2892`, `"passedTests" : 2892`, `"failedTests" : 0`, `"skippedTests" : 0` (plus 60 tests ran with dynamic parameters across 289 additional runs, all passed, 0 failed). Individually confirmed all of `Tests/TagRenameTests.swift`'s six tests passed by name in the xcresult tree, including `renamingWritesEveryNoteAndJournalsEachWrite`, `aNoteEditedAfterTheRenameMakesTheWholeUndoRefuse`, and `renamingATagNobodyUsesChangesNothing`.

An earlier narrow run with `-only-testing:PergamenumTests/TagRenameTests` reported "Executed 0 tests" — this file's `@Test` functions are free functions with no `@Suite` wrapper, so that selector (which matches type names) silently selected nothing; this is a known trap (see `[[only-testing-selects-suite-names-not-file-names]]` in coder memory) and was not treated as a signal either way. The full-suite run above is the real verification.

`git status --porcelain` shows exactly one modified file, `Sources/Vault/VaultSession+TagRename.swift`; no other file changed.

### Drafted commit
```
refactor(vault): route tag-rename writes through VaultPlanApplication

VaultSession+TagRename's renameTag was the tenth hand-rolled apply-plan
loop left over from before ADR-0041 Task 5, kept separate only because
it formatted failures with error.localizedDescription instead of the
shared "\(path): \(error)" format the other nine copies already use.
Converts it to build [VaultFileChange] and call
VaultPlanApplication.apply like every other copy, accepting the
resulting failure-message text change.
```

### Cleanup
No scratch files, scripts, or temp branches were created. The `.build/DerivedData` directory produced by the verification build is build output, not a scratch artifact, and is left in place (untracked, ignored).

### Plan deviations
None. The brief's instructions were followed exactly; no test file was touched, and no gap between the brief and the existing code was found.
