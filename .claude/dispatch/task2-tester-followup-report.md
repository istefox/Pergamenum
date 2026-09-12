# Task 2 tester follow-up — CanvasDuplicateTests unblock

## Change made

`Tests/CanvasDuplicateTests.swift`, line 167 (inside
`duplicatingChangesOnlyTheCanvasFilesBytesNotTheFolderListing`, in suite
`CanvasDuplicateWorkspaceControllerTests`):

```diff
-        let canvasURL = store.url(forBoard: "\(root.url.lastPathComponent).canvas")
+        let canvasURL = try store.url(forBoard: "\(root.url.lastPathComponent).canvas")
```

Only one call site to `CanvasStore.url(forBoard:)` exists in this test file (confirmed via
`grep -n "url(forBoard" Tests/CanvasDuplicateTests.swift`). The enclosing test function was
already declared `throws`, so no signature change was needed there.

No other file or test was touched.

## Pre-check

Read `Sources/Vault/CanvasStore.swift` first: `url(forBoard:)` is currently non-throwing
(`func url(forBoard board: String) -> URL { root.appending(...) }`), a pure path-join with no
boundary check. The `try` added above is a no-op against today's signature and will only bite
once the Task 2 coder changes it to `throws` (routing through `boundary.url(for:)` the way
`load`/`save`/`createBoard` already do).

## Verification

Fresh worktree needed setup first (no generated workspace yet):

```
tuist install
tuist generate --no-open
```

Then:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -derivedDataPath ".build/DerivedData" \
  -only-testing:PergamenumTests/CanvasDuplicateTests test
```

That filter selected 0 tests (the file declares one `@Suite struct
CanvasDuplicateWorkspaceControllerTests`, not a type named `CanvasDuplicateTests` — a known
Swift Testing `-only-testing` gap). Reran with the real suite name:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -derivedDataPath ".build/DerivedData" \
  -only-testing:PergamenumTests/CanvasDuplicateWorkspaceControllerTests test
```

Result: **TEST SUCCEEDED** — 8 tests in 1 suite passed, including
`duplicatingChangesOnlyTheCanvasFilesBytesNotTheFolderListing`. As expected, behavior is
unchanged (the accessor is still non-throwing today) — this only removes the compile blocker
for Task 2's coder.
