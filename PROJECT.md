# Project: Pergamenum backlog roadmap

## Overview
Clears the open TODO.md backlog (35 items, 0 P1) through project-conductor: correctness
bugs first, then Workspace/card architecture debt from the review chains, then SPEC gaps,
accessibility, lint/complexity debt, Tasks-module debt, and the remaining M13/M14 SPEC
milestones. Excluded on purpose (not feature chains): PG-006 (manual verification only),
PG-072/PG-076 (UI-test flakiness needs debugging, not design), PG-018 (blocked on an ADR
decision to reopen SPEC §14).

## Phases

### Phase 1 — Correctness bugs (P2)
- [x] PG-054 fix folder double-click navigation sometimes not opening subfolder  (completed: 2026-08-30)
- [x] PG-053 fix WorkspaceBoardUITests openWorkspace no longer opening any board  (completed: 2026-08-30)
- [x] PG-045 reject . and .. as a folder name in FolderFileOperations validate  (completed: 2026-08-30)
- [x] PG-063 surface the real read error in BoardFileOperations renamePlan  (completed: 2026-08-30)
- [x] PG-062 fix WorkspaceController stale board data after folder selection  (completed: 2026-08-30)

### Phase 2 — Workspace selection and type consolidation
- [x] PG-058 stop discarding and reconstructing WorkspaceSelection at the view boundary  (completed: 2026-08-30 — already fixed on main by 994a795, no code change)
- [x] PG-060 make WorkspaceController folder/current split enforced by the type system  (completed: 2026-08-30)
- [x] PG-057 record a failed board load instead of claiming it opened  (completed: 2026-08-30 — already fixed on main by the ADR-0025 chain, no code change)
- [x] PG-065 add a wrapper type distinguishing board-file path from folder path
- [x] PG-066 deduplicate OperationError across Note/Folder/Board file operations  (completed: 2026-08-30)
- [x] PG-080 deduplicate OperationError and the moved-note tuple across outcome types  (completed: 2026-08-30)
- [x] PG-046 give FolderRenamePlan/RenameOutcome named types instead of anonymous tuples  (completed: 2026-08-30)
- [ ] PG-064 use error interpolation consistently in BoardFileOperations catch blocks
- [ ] PG-081 deduplicate breadcrumb rendering between VaultController and WorkspaceController
- [ ] PG-071 split WorkspaceFolderActions pure rules from its DI closures

### Phase 3 — Card and canvas debt
- [ ] PG-078 share one accessor for the Nota-vs-Testo color check across three files
- [ ] PG-079 make CardCommand's button-vs-submenu split a property instead of three switches
- [ ] PG-068 report a problem on BoardCardMenu copyLink miss instead of a silent return
- [ ] PG-069 make board-lookup nil fallbacks consistent instead of asymmetric
- [ ] PG-070 consume RenameOutcome.rewrittenPaths or drop it
- [ ] PG-061 reuse WorkspaceBoardResolver.matches in BoardFileOperations renamePlan

### Phase 4 — SPEC gaps
- [ ] PG-074 give the To Do tool an interactive checkbox and task indexing
- [ ] PG-073 add an editable title affordance to the Link card
- [ ] PG-075 conceal markdown markers in Workspace text cards like the note editor
- [ ] PG-086 draw a real checkbox glyph on task lines instead of coloured characters
- [ ] PG-085 compute list nesting depth by CommonMark's content-column rule
- [ ] PG-084 make MarkdownStyler's inline-span parser recursive for nested spans

### Phase 5 — Accessibility and polish
- [ ] PG-077 add accessibilityLabel to CardFormatBar's format buttons
- [ ] PG-041 keep board content in the accessibility tree at low zoom
- [ ] PG-044 add a deselect affordance for the Workspace sidebar folder selection
- [ ] PG-043 stop an intermediate folder from vanishing when it loses its only board
- [ ] PG-042 add an app-wide right-click context menu exposing every command

### Phase 6 — Lint and complexity debt
- [ ] PG-056 bring WorkspaceController.swift under the type_body_length error threshold
- [ ] PG-055 clear the SwiftUI SwiftLint drift on WorkspaceBrowser.swift
- [ ] PG-036 reduce bySubtasks cyclomatic complexity under the configured limit
- [ ] PG-035 clear the file_length/type_body_length warning drift from ADR-0021

### Phase 7 — Tasks module debt
- [ ] PG-037 replace TaskGroup's parallel optionals with a discriminated union
- [ ] PG-038 deduplicate case-insensitive workspacePath matching
- [ ] PG-040 surface a linter finding for malformed caret id/parent markers
- [ ] PG-039 document CanvasStore.allBoards' try? fallback as deliberate
- [ ] PG-082 discriminate note vs folder ids by a typed lookup, not a .md suffix check

### Phase 8 — Remaining SPEC milestones (M13/M14)
- [ ] PG-014 finish M13 vault: rename/move/trash under the journal, prompts, export, import, AppIntents
- [ ] PG-019 make outline section drag-to-move a real text rewrite through VaultSession.write
- [ ] PG-030 fix status-* board columns refusing every drop per tag.md 5.1
- [ ] PG-029 show on screen that a note draft is parked
- [ ] PG-015 apply SPEC amendments §5, §12, plus new §16 Cattura and §17 Viste
- [ ] PG-026 fill the three gaps measured in CLAUDE.md on 2026-08-18
