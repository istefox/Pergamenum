# deep-refactor audit — Pergamenum — 2026-08-26

## Summary

- Baseline: PASS=1651 FAIL=0
- Post-fix: PASS=1651 FAIL=0
- Dimensions completed: dead-code, perf, structure
- Dimensions skipped: none
- Fixed: 31
- Deferred (report-only / high-risk): 9
- Regressions caught: 0 — circuit breaker never fired
- Source files scanned: Sources/Features/Workspace/** (WorkspaceView.swift, WorkspaceBrowser.swift,
  WorkspaceController.swift, WorkspaceController+Viewport.swift, BoardChrome.swift, and their
  siblings) — diff scoped to the ADR-0024 workspace board tree single-selection chain since
  baseline `ebcec59870bbec2aa8732e1f0f9a79449b0d3b69`

## Per-dimension findings

### dead-code

- **P1** `WorkspaceController.swift:92` — `problems: [String]` is write-only: appended to in four
  places (board-read failure, `recordProblem`, save failure) but never read anywhere in Sources,
  Tests or UITests. The ADR-0024 Gate 5.06 desync trace that feeds it is inert as a result.
  Status: Fixed by coder agent (routed `recordProblem` through to `VaultController.recordProblem`,
  which already has a rendering surface in `SettingsView.swift`).
- **P2** `WorkspaceController.swift:131` — `lastWrittenHash: [String: String]` is write-only; the
  self-write recognition it claims to support is actually implemented against
  `VaultSession.selfWrittenHashes`, which this dictionary never feeds.
  Status: Fixed by coder agent.
- **P2** `WorkspaceView.swift:522` — `panGesture` had no call site; the live pan path is
  `backgroundGesture(in:)`.
  Status: Fixed by coder agent (deleted).
- **P3** `WorkspaceBrowser.swift:326` — `WorkspaceRow.onRename`'s `(String) -> Void` parameter was
  passed `node.id` at every call site but the sole closure discarded it, hiding a click-ordering
  coupling with `onSelect`.
  Status: Fixed by coder agent (mirrored `onDelete`'s `renameTarget` pattern).
- **P3** `WorkspaceSelection.swift:1` — unused `import Foundation`.
  Status: Fixed by coder agent.
- **P3** `WorkspaceView.swift:47` — `NewItemDraft.Kind.text` was never constructed; the `.text`
  switch arm in `create(_:value:at:)` was unreachable.
  Status: Fixed by coder agent.

### perf

- **P2** `WorkspaceBrowser.swift:333` — `rebuild()` runs synchronous whole-vault disk I/O
  (`CanvasStore.allBoards()`, two full tree builds, a folder walk) on the `@MainActor`, blocking
  the UI on every rescan of a large vault.
  Status: Deferred — report-only (async/actor-touching finding, mandatory perf-reviewer guard).
- **P2** `BoardChrome.swift:229` — `assignedTasks` queried `vault.index.tasks(assignedToWorkspace:)`
  inside the view body on every tray redraw, sorting every note record in the vault each time.
  Status: Fixed by coder agent (cached in `@State`, refreshed via `.task(id:)`).
- **P2** `BoardChrome.swift:260` — `referencedNotes` re-parsed the whole board's wikilinks on every
  body evaluation.
  Status: Fixed by coder agent (cached in `@State`, refreshed via `.task(id:)`).
- **P2** `WorkspaceBrowser.swift:307` — `flatList` recomputed the filter pipeline and walked the
  tree twice on every redraw, plus a locale-aware substring match run unconditionally.
  Status: Fixed by coder agent (cached `filteredRows`, dropped the redundant outer
  `WorkspaceTree.flattened`).
- **P2** `WorkspaceController.swift:524` — `loadEmailHeaders` read and fully decoded an entire
  `.eml` file into memory synchronously on the main actor, contradicting its own doc comment.
  Status: Fixed by coder agent (mapped read + bounded 64KB header-block cut).
- **P3** `BoardChrome.swift:325` — `boardFileName` constructed a fresh `CanvasStore(root:)` (with
  symlink-resolution syscalls) on every access, twice per body evaluation.
  Status: Fixed by coder agent (reused `workspace.store`).
- **P3** `BoardChrome.swift:285` — `noteRow` computed `displayName(for:path:)` twice per row.
  Status: Fixed by coder agent (bound once at the top of `noteRow`).
- **P3** `BoardChrome.swift:28` — `BoardTopBar` re-accessed the allocating `workspace.breadcrumb`
  computed property once per crumb plus once for the count comparison.
  Status: Fixed by coder agent (hoisted `let crumbs = workspace.breadcrumb` once).
- **P3** `WorkspaceBrowser.swift:175` — `folderOperations` constructed a fresh
  `FolderFileOperations`/`NoteStore` (symlink-resolution syscalls) on every keystroke in the
  rename/create sheets.
  Status: Fixed by coder agent (cached in `@State`, assigned in `rebuild()`).
- **P3** `WorkspaceController.swift:254` — `refreshContents()` re-read the whole folder listing
  from disk on every single board mutation (add/delete/create/undo/redo).
  Status: Fixed by coder agent (removed a redundant trailing call; documented why a wider cache
  would break Finder-drop visibility rather than caching unsafely).
- **P3** `WorkspaceController.swift:537` — `subfolder(for:)` did a linear `Array.contains` scan,
  called once per node/card per redraw.
  Status: Fixed by coder agent (`subfolderSet: Set<String>`, refilled alongside `contents`).
- **P3** `WorkspaceController.swift:294` — quadratic selection pruning in `apply(_:)`
  (`selection.filter { document.nodes.contains { ... } }`) on every undo/redo.
  Status: Fixed by coder agent (`Set` intersection, O(nodes + selection)).
- **P3** `WorkspaceView.swift:441` — the concentrazione refit debounce allocated and cancelled a
  `Task` per animation frame during the 350ms window.
  Status: Deferred — report-only (Task/async-touching finding, mandatory perf-reviewer guard).
- **P3** `WorkspaceView.swift:89` — `workspace.selectedFileURLs` evaluated twice per body pass,
  each a full node walk plus per-file `fileExists` syscalls.
  Status: Fixed by coder agent (hoisted `previewURLs` once, threaded through `body`).

### structure

- **P2** `WorkspaceView.swift:522` — `panGesture` dead-code finding, re-flagged from the structure
  pass as a near-duplicate of `backgroundGesture(in:)`.
  Status: Fixed — already removed by the dead-code dimension's earlier pass; confirmed absent
  before dispatch, no re-fix needed.
- **P2** `WorkspaceView.swift:4` — file 676 lines, `WorkspaceView` struct body 476 lines; SwiftLint
  `type_body_length`/`file_length` errors.
  Status: Fixed by refactorer agent (split into `WorkspaceView+Drawing.swift`,
  `WorkspaceView+FolderVerbs.swift`, `WorkspaceView+Creation.swift` along the file's own MARK
  seams).
- **P3** `BoardChrome.swift:189` — five unrelated top-level types in one file; `BoardTray` alone
  pulled in a different dependency layer (vault/index/task types) than the other four (chrome
  around the board).
  Status: Fixed by refactorer agent (`BoardTray` moved to its own file).
- **P3** `BoardChrome.swift:228` — `assignedTasks` and `referencedNotes` duplicated the same
  25-line header/empty-state/`ForEach` scaffold `LinkedTasksPanel` already demonstrates the
  abstraction for.
  Status: Fixed by coder agent (`traySection<Rows: View>` helper; accessibility identifiers kept
  byte-identical).
- **P3** `WorkspaceBrowser.swift:38` — two parallel derived trees (`NoteTree` and `WorkspaceTree`)
  built from the same `boards` array on every rescan, disagreeing about the vault root and making
  "Espandi tutto" unable to expand the root row.
  Status: Fixed by refactorer agent (dropped `tree`/`allFolders(in:)`, both "Espandi tutto" sites
  now read `WorkspaceTree.folders(in:)`; `Tests/WorkspaceBrowserToolbarTests.swift` repointed to
  the same API, no test deleted).
- **P3** `WorkspaceController.swift:319` — ~70 lines of sixteen bare `var` properties holding
  transient gesture state for five separate interactions (drag/pan/marquee/resize/crop/arrow),
  each declared `internal` only so a sibling extension file can write it; no type-level invariant
  ties a group's members together (e.g. `cropHandle` is meaningful only while `croppingNodeID != nil`).
  Status: Deferred — report-only, `risk_level: high` (a design pass across
  `WorkspaceController+Gestures`/`+Drawing`/`+Crop` and the card views, not a mechanical edit —
  belongs in its own chain).
- **P3** `WorkspaceController.swift:345` — three live SwiftLint findings (two `vertical_whitespace`,
  one 152-char `line_length`) unrelated to the tracked file/type-length drift.
  Status: Fixed by coder agent. Also delegated `isShowingBoard` to `WorkspaceSelection.hasBoard`
  in the same file during this dispatch (structure-WorkspaceSelection-9a4, below).
- **P3** `WorkspaceController+Viewport.swift:7` — the zoom clamp expression duplicated three times;
  `zoomToFit(in:)`/`zoomToActualSize(in:)` shared an identical prologue/epilogue around one
  differing scale computation.
  Status: Fixed by refactorer agent (`frameContent(in:scale:)` shared skeleton, each caller keeps
  its own clamping expression in the closure it passes).
- **P3** `WorkspaceSelection.swift:26` — `WorkspaceSelection.hasBoard` and
  `WorkspaceController.isShowingBoard` were two spellings of the same `.board`-case predicate;
  `hasBoard` had no production caller.
  Status: Fixed by coder agent (`isShowingBoard` now delegates to `current?.hasBoard ?? false`).
- **P3** `WorkspaceView.swift:339` — `board` spanned 123 lines stacking nine responsibilities
  (background hit-testing, crop shortcuts, grid, content layer, guides, marquee, drawing overlay,
  floating controls, plus six modifiers with inline logic).
  Status: Fixed by refactorer agent (extracted `boardBackground(in:)`, `cropKeyboardShortcuts`,
  `floatingControls`; moved the `onChange(of: geometry.size)` body into `scheduleRefit(for:)`).
- **P3** `WorkspaceView.swift:220` — `renameWorkspace(_:to:)` and `deleteWorkspace(_:)` duplicated
  a load-bearing five-step skeleton (flush → mutate → guard → relocate) whose ordering is
  documented as load-bearing but enforced only by copy-paste discipline.
  Status: Fixed by coder agent (`performFolderVerb(_:landing:)` owns the shared order;
  `createWorkspace` deliberately left outside it — it opens the folder it created rather than
  following a moved one).
- **P3** `WorkspaceView.swift:602` — `handleTap(at:)` tripped `cyclomatic_complexity` (12 vs 10);
  "what tool X does" was split between `WorkspaceController.Tool` and this view with no
  compiler-enforced link.
  Status: Fixed by refactorer agent (`Tool.tapBehaviour`/`Tool.isDragDriven` in a new
  `WorkspaceController+Tools.swift`; a seventh `.unavailable` case added to preserve the `.forms`
  tool's tap-resets-tool-selection behaviour exactly).
- **P3** `WorkspaceView.swift:436` — the concentrazione refit was coordinated by three loosely
  coupled `@State` booleans in the view, viewport-framing policy implemented outside
  `WorkspaceController+Viewport.swift`, with no enforced mutual exclusion between the two modes.
  Status: Fixed by refactorer agent (`pendingRefit: RefitMode?` + `refitTask` on the controller;
  `requestRefit(_:)`/`applyPendingRefit(in:)`).
- **P3** `WorkspaceView.swift:52` — `body` spanned 107 lines with eleven modifiers carrying
  multi-statement imperative handlers inline, including a 12-line `.onChange` handler mixing
  folder-path derivation, board selection and node lookup.
  Status: Fixed by refactorer agent (extracted `reattachWorkspace(to:)`,
  `consumeQuickLookRequest(_:)`; `placePendingNote(_:)` already existed from an earlier
  type-check-timeout restructuring and was left alone).

## Security findings

- **P1** `WorkspaceController+Viewport.swift:80` — Path traversal from externally-triggerable URL
  scheme input. `openRoute` takes `route.path` straight from `pergamenum://canvas?file=<path>`,
  derives a folder with `deletingLastPathComponent` and hands it to `open(folder:)` with no
  normalisation or vault-containment check. `PergamenumURL` accepts any non-empty `file` string,
  `PergamenumApp.onOpenURL` dispatches it with no confirmation, and `CanvasStore.boardPath(forFolder:)`
  only trims leading/trailing `/`, so `..` components survive into `root.appending(path:)`.
  Verified empirically: `root.appending(path: "../../../tmp/pwn/pwn.canvas")` resolves outside the
  vault root, and a test write through that exact shape created a directory and wrote a file
  outside the simulated root. On a non-sandboxed app this means `load` reading an arbitrary
  `.canvas` outside the vault, `refreshContents()` listing an outside directory in the tray, and
  the 1s autosave writing (and creating intermediate directories) at the traversed path. Any web
  page or third-party app that gets the user to follow a `pergamenum://` link reaches this.
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Reject the route before it reaches the controller — normalise the
  incoming path and require the resolved absolute URL to be a descendant of `store.root` (compare
  standardised, symlink-resolved paths), refusing anything with a `..` component or a leading `/`.
  Best placed as one shared guard in `CanvasStore` (e.g. `resolvedURL(forVaultRelative:) throws`
  used by `url(forFolder:)`, `load`, `save`, `contents`) so every path-taking entry point inherits
  it, with `openRoute` reporting the refusal through the existing `recordProblem` channel.

- **P2** `WorkspaceController.swift:502` — Unguarded URL construction from `.canvas` file content.
  `fileURL(for:)` builds a URL from the untrusted `.file(path:)` value read out of a board's JSON
  (per CLAUDE.md principle 4, boards from Obsidian/other tools are deliberately opened) with no
  containment check; `URL.appending(path:)` preserves `..`, flowing into Quick Look preview
  (`selectedFileURLs`) and `NSWorkspace.shared.open` for `.eml` cards.
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Return `nil` from `fileURL(for:)` for any node path that does not resolve
  inside the vault (standardise + symlink-resolve, require descendant-of-root); draw an
  out-of-vault card as broken using the existing not-found visual state rather than previewing or
  launching it.

- **P2** `WorkspaceController.swift:493` — Unvalidated folder name reaches directory creation.
  `createFolder(named:at:)` passes `name` straight through to plain string concatenation with no
  `NoteName.validate`; a name containing `/` or `..` can create a directory outside the vault, and
  the returned path is persisted verbatim as a `.file` node that later gets opened. The sibling
  sidebar path already validates via `FolderFileOperations.validate` — this is an inconsistency
  within the same feature, not an accepted convention.
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Run `FolderFileOperations.validate(name)` (already rejects `/`, `\`, `:`)
  plus an explicit refusal of `.`/`..` and of any multi-component name inside
  `createFolder(named:at:)` itself, throwing into the existing `recordProblem` catch. Combine with
  the containment guard suggested for the path-traversal finding above.

- **P2** `WorkspaceController.swift:524` — Unbounded read of an untrusted file on the main actor,
  contradicting its own doc comment ("only the header block is read"). `try? Data(contentsOf:)`
  with no options loads an entire `.eml` into memory and materialises a second full `String` copy
  before the header parser looks at it; on the `@MainActor` controller, a large attachment stalls
  the UI, and the memoisation pays this cost per distinct card.
  ACTION REQUIRED — not auto-fixed
  Note: this description is the perf dimension's finding for the same site
  (perf-WorkspaceController.swift-e4c), which the perf fix loop already addressed with a mapped
  read + 64KB header-block cut — see the perf section above. Recorded here because the security
  audit independently flagged the same unbounded-read pattern from the confidentiality/DoS angle
  rather than the perf angle; no further action needed beyond the perf fix already applied.
  Suggested remediation (as originally written): read a bounded prefix via `FileHandle` or
  `.mappedIfSafe` + slice, and move the read off the main actor.

- **P3** `WorkspaceController.swift:480` — Link cards store an arbitrary URL string with no scheme
  allowlist. `addLink(_ url: String, at:)` persists whatever the creation sheet returned, and the
  click site does `URL(string: url).map { NSWorkspace.shared.open($0) }` with no scheme check. A
  board received or synced from elsewhere can carry a `file://` URL or a third-party custom scheme
  that a single click hands to LaunchServices, even though the creation sheet's own prompt
  advertises only `https://`, `obsidian://` and `message://`.
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Validate the scheme where the value is accepted and again where it is
  opened — parse with `URLComponents`, require a non-empty scheme from an allowlist (`http`,
  `https`, `obsidian`, `message`, `mailto`, `pergamenum`), refuse the rest through
  `recordProblem`. Put the same predicate in front of the `NSWorkspace.shared.open` call so a
  hand-edited canvas cannot bypass the creation-time check.

- **P3** `WorkspaceView.swift:207` — Name validation for the sidebar's "new workspace" path lives
  only in the view layer. `createWorkspace(named:in:)` calls `CanvasStore.createFolder` and
  `store.save` directly, bypassing `FolderFileOperations.validate`; the only guarantee that `name`
  is conformant is the sheet disabling its confirm button, a UI-only state. Any future second
  caller of `folderActions.create` inherits no validation at all.
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Call `FolderFileOperations.validate(name)` at the top of
  `createWorkspace`, or route the create through `FolderFileOperations` so the sheet and the
  performer share one validation entry point, the way rename already does through `renamePlan`.

## Deferred findings (not auto-fixed)

- `WorkspaceBrowser.swift:333` — `rebuild()` runs synchronous whole-vault I/O on the main actor —
  Reason: fix_type: report-only (touches actor isolation, mandatory perf-reviewer guard).
  Suggested fix: move the enumeration + fold off the main actor (nonisolated/detached computation
  over the Sendable `CanvasStore`); cheap partial mitigation available now: build a `Set` for the
  `folders(in:)` `contains` check instead of a linear search.
- `WorkspaceView.swift:441` — the concentrazione refit debounce allocates a `Task` per animation
  frame during the 350ms window — Reason: fix_type: report-only (Task/cancellation-touching,
  mandatory perf-reviewer guard). Suggested fix: replace the Task-per-frame debounce with one
  long-lived task observing the latest size (or an `AsyncStream` + `.debounce`); needs deliberate
  human review, not an auto-fix. Note: the concentrazione refit *state* (the three `@State`
  booleans) was separately restructured by the structure dimension's `WorkspaceView-b73` fix onto
  the controller — this specific per-frame-Task-allocation concern is unrelated and still open.
- `WorkspaceController.swift:319` — sixteen bare gesture-state `var` properties across five
  unrelated interactions, each `internal` only so a sibling extension can write it, with no
  type-level invariant grouping — Reason: risk_level: high (a design pass across
  `WorkspaceController+Gestures`/`+Drawing`/`+Crop` and the card views, not a mechanical edit).
  Suggested fix: one optional value per interaction (`activeDrag`/`activeResize`/`activeCrop`/
  `activeArrow`, each a small struct), so an invariant like "cropHandle is meaningful only while
  cropping" becomes a property of the type rather than caller discipline. Belongs in its own
  chain.
- `WorkspaceController+Viewport.swift:80` — path traversal from `pergamenum://canvas?file=<path>`
  — Reason: security (always report-only), risk_level: high. See Security findings above.
- `WorkspaceController.swift:502` — unguarded URL construction from untrusted `.canvas` file
  content (Quick Look / `NSWorkspace.shared.open`) — Reason: security (always report-only). See
  Security findings above.
- `WorkspaceController.swift:493` — unvalidated folder name reaches directory creation — Reason:
  security (always report-only). See Security findings above.
- `WorkspaceController.swift:480` — link cards accept an unvalidated URL scheme, opened via
  `NSWorkspace.shared.open` — Reason: security (always report-only). See Security findings above.
- `WorkspaceView.swift:207` — sidebar "new workspace" name validation lives only in the view/UI
  layer — Reason: security (always report-only). See Security findings above.
