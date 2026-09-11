# deep-refactor audit — Pergamenum — 2026-09-11

## Summary

- Baseline: RED (exit 65, 0 failed)
- Post-fix: RED (exit 65, 0 failed)
- Dimensions completed: dead-code, perf, structure
- Dimensions skipped: none
- Fixed: 100
- Reverted: 0
- Deferred: 137
- Regressions caught: 3
- Source files scanned: 758
- Run branch: refactor/deep-refactor-2026-09-11
- Report-only mode: no

## Per-dimension findings

### dead-code

Checkpoint: 29b8621

- **P2** `Sources/Core/Pratiche/PraticaLedger.swift:142` — `memberMessageIDs(forConversation:praticaPath:)` has no call site; only two doc comments mention it. Its exact body is hand-duplicated at the one place it was written for — `PraticheController.swift:1475` does `ledgerEntries.filter { $0.conversationID == conversation }.map(\.messageID)` before calling `MembershipRule.recoverConversationID`. Two implementations of ADR-0036 R-14's member lookup, one of them dead. (`dead-code-PraticaLedger.swift-df3`)
  Status: SKIPPED
  Suggested fix: Replace the inline filter/map at PraticheController.swift:1475 with a call to `ledger.memberMessageIDs(forConversation:praticaPath:)`, or delete the ledger method and its two doc references.

- **P2** `Sources/Features/Editor/QuickSwitcher.swift:21` — QuickSwitcher.Mode.pick is unreachable. The only instantiation in the repo is VaultBrowser.swift:41 `QuickSwitcher(mode: .navigate)`; the `.pick` value survives solely as the property default on line 37. Every `mode == .navigate` false branch is therefore dead: the `if` at :48, the placeholder ternary at :59, and the guards at :154, :201 and :213. ADR-0039 already names this as a deliberate follow-up after the note-linking handler (its only `.pick` caller) was removed. (`dead-code-QuickSwitcher.swift-d37`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Remove the `Mode` enum and the `mode` property, collapsing the five `mode == .navigate` branches to their navigate arm; or, if a picker is still planned, add the missing call site.

- **P2** `Sources/Features/Pratiche/AttachmentChipModel.swift:57` — `contextMenuTitles` is never read by production code. AttachmentChip.swift:55 hardcodes `Button("Mostra nel Finder")` (and the Copia twin) instead of consuming the constant, so the only reference in the repo is Tests/AttachmentChipTests.swift:97, which asserts the constant equals its own literal — a tautology that pins nothing about the menu actually drawn. The constant's doc comment claims it is "R-27's context menu, exact wording and order", which is no longer true. (`dead-code-AttachmentChipModel.swift-580`)
  Status: SKIPPED
  Suggested fix: Either drive AttachmentChip's context-menu buttons from `contextMenuTitles`, or delete the constant and the tautological assertion.

- **P2** `Sources/Features/Pratiche/PraticaSyncEngine.swift:537` — Three fields of `RegenerationPlan` are populated at construction (lines 610, 615, 616) and never read by any consumer: `messageID` (537), `attachmentFileNames` (542) and `rewritesOriginalEML` (543). The «Rigenera» sheet (PratichePane.regenerationReadySheet) reads only `diff`/`notePath`/`currentText`/`replacementText`. They look like intended sheet copy («which attachments get rewritten») that was never wired. (`dead-code-PraticaSyncEngine.swift-e75`)
  Status: Deferred — report-only
  Suggested fix: Either surface `attachmentFileNames`/`rewritesOriginalEML` in the regeneration preview sheet as evidently intended, or delete the three fields and their assignments at lines 610/615/616.

- **P2** `Sources/Features/Recordings/ReviewSheet.swift:56` — `ReviewSheetState.renameText(for:)` is never called. The only other occurrence of the name in the repo is the doc comment at line 39 that references it; the review sheet's speaker fields bind to `state.speakerRenames` directly. (`dead-code-ReviewSheet.swift-09d`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `func renameText(for label: String)` and drop the reference to it from the line-39 doc comment.

- **P2** `Sources/Features/Today/DayController.swift:94` — `DayController.move(by:)` has no callers. The only `.move(by:)` call sites in the repo belong to `DiaryController` (DiaryToolbar.swift, DiaryControllerTests). It was superseded by `moveSpan(by:)` directly below it, whose doc comment states it is what the toolbar chevrons and the Calendario menu call. (`dead-code-DayController.swift-b11`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `func move(by days: Int)` from DayController; `moveSpan(by:)` is the live navigator.

- **P2** `Sources/Features/Workspace/WorkspaceController+Drawing.swift:84` — `discardDrawing()` has zero call sites in the whole repository (Sources and Tests, verified by grep and by a Periphery index scan of the Pergamenum target). Cancelling a drawing session is done elsewhere; this entry point is orphaned. (`dead-code-WorkspaceController+Drawing.swift-180`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `func discardDrawing()`, or wire it to the drawing-cancel path if the cancel currently duplicates its two assignments inline.

- **P2** `Sources/Index/IndexCache.swift:34` — `private var handle: OpaquePointer?` is declared on IndexCache and never assigned or read anywhere in the file (the only declaration site is its own line). Every method opens and closes its own connection via `open(create:)`/`sqlite3_close`. Beyond being dead, the field is actively misleading: it suggests the cache retains a live SQLite handle it does not. (`dead-code-IndexCache.swift-dd5`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the `private var handle: OpaquePointer?` stored property from IndexCache.

- **P2** `Sources/Vault/VaultController+Routes.swift:155` — `RouteState.noteIDs` is read at line 54 and written nowhere in the repository, so the dictionary is permanently empty and the `.noteID` branch of `perform(_:)` can only ever take its failure path (`recordProblem("nessuna nota con id …")`). The `openNote(at: path)` success branch of `pergamenum://note?id=` is unreachable code. (`dead-code-VaultController+Routes.swift-6be`)
  Status: SKIPPED
  Suggested fix: Either populate `routeState.noteIDs` from the index when a vault opens, or drop the field plus the `.noteID` case so the scheme stops advertising a route that always fails.

- **P2** `Sources/Vault/VaultController+Tabs.swift:256` — `closeOpenNote()` has no callers anywhere in Sources, Tests or UITests. Its stated purpose ("closes the note in the editor, for when the file it shows is no longer there") is served by the live `trashedNote(at:)` at line 321, which closes every tab showing the missing note and also prunes `closedTabPaths`/`recentNotePaths`. The stale twin only closes the focused tab and leaves those lists pointing at a deleted file. (`dead-code-VaultController+Tabs.swift-972`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `closeOpenNote()`; `trashedNote(at:)` is the surviving implementation of the same job.

- **P3** `Sources/Calendar/ReminderScheduler.swift:30` — Static analysis reports `userNotificationCenter(_:willPresent:)` as having zero callers, but it is a `UNUserNotificationCenterDelegate` protocol witness dispatched by the system through `center.delegate = self` (line 21). Recorded here so a later automated sweep does not delete it: it is reachable at run time and a grep for callers proves nothing. (`dead-code-ReminderScheduler.swift-b9e`)
  Status: Deferred — report-only
  Suggested fix: Do not remove. No action needed; flagged only to pre-empt a false-positive deletion by an unused-symbol pass.

- **P3** `Sources/Vault/VaultSettings.swift:68` — `harnessRepositoryPath` is declared, given a default in `VaultSettings.default`, decoded at line 188 and assigned in the memberwise init, but no feature ever reads or writes it: "Importa convenzioni…" passes the picked URL straight to `importConventions(from:)` and never records it. Dead settings state. Flagged high-risk because the property participates in the persisted Codable shape of settings.json. (`dead-code-VaultSettings.swift-e71`)
  Status: Deferred — report-only
  Suggested fix: Decide deliberately: either store the picked repository here and pre-fill/re-run the import from it, or drop the key (settings.json uses decodeIfPresent, so old files still load).

- **P3** `Sources/App/CommandActions+CanRun.swift:1` — `import AppKit` is unused: the file contains no `NS*` symbol and no other AppKit type (verified by extracting every `NS[A-Z]` token — the set is empty, unlike every other AppKit-importing file in the shard). It only touches `ShortcutCommand`, `WindowPlace`, `Destination` and the controllers. (`dead-code-CommandActions+CanRun.swift-820`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Drop `import AppKit` (the file needs no import at all; add `import Foundation` only if the build asks for it).

- **P3** `Sources/App/ShortcutStore.swift:73` — `hasConflicts` has no production call site — the only references are Tests/ShortcutTests.swift:201 and :213. The settings UI uses the per-command `conflicts(with:)` instead (ShortcutSettings.swift:54), so this aggregate is production-dead code kept alive solely by its own test. (`dead-code-ShortcutStore.swift-35f`)
  Status: SKIPPED
  Suggested fix: Remove `hasConflicts` and the two assertions on it, or surface it in ShortcutSettings as the "there are conflicting shortcuts" banner it reads like.

- **P3** `Sources/Calendar/CalendarService.swift:499` — `EventKitStore.writableReminderListTitles` has zero references anywhere in Sources, Tests, UITests, scripts or docs. It is not a `CalendarStore` protocol requirement either — the protocol declares only `writableCalendarTitles` (line 102), which is the one the new-event UI reads. The reminder-list equivalent was written and never wired to any picker. (`dead-code-CalendarService.swift-3de`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Remove the computed property, or promote it to a `CalendarStore` requirement and wire it into the new-reminder list picker if the list choice was the intent.

- **P3** `Sources/Core/AppInfo.swift:7` — `AppInfo.tagline` has no production reference; the single repo-wide use is in a test. `name`, `bundleIdentifier` and `urlScheme` beside it are all live. The string itself is also stale for a repo at marketing version 1.4. (`dead-code-AppInfo.swift-7c7`)
  Status: SKIPPED
  Suggested fix: Delete `tagline` and the test assertion on it, since the about panel reads the bundle plist rather than this constant.

- **P3** `Sources/Core/Conventions/Frontmatter.swift:44` — `Frontmatter.allowedKeys` is referenced nowhere — not in code, not in comments, not in tests. The closed four-key schema (SPEC §4.3) is actually enforced by the hardcoded `switch` arms in the parser (`case "aliases":` etc. around line 210), so this constant is a dead second declaration of the same rule that can silently drift from the switch. (`dead-code-Frontmatter.swift-4b9`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Either delete `allowedKeys`, or make the parser/foreign-key split consult it so the closed schema is declared exactly once.

- **P3** `Sources/Core/Conventions/NoteName.swift:67` — `NoteName.sanitized(_:)` has no production call site — the only reference repo-wide is Tests/ConventionsTests.swift:450. Its own doc comment names the callers it was written for ("an email subject, a dropped file name"), and those paths now go through `PraticaNaming`/`ImportNaming` instead, so either this is dead or a title-sanitising step is missing on one of them. (`dead-code-NoteName.swift-a42`)
  Status: Deferred — report-only
  Suggested fix: Decide between the two: delete `sanitized` with its test, or call it from the email-subject / dropped-file title derivation paths it documents.

- **P3** `Sources/Core/Conventions/Wikilink.swift:21` — `Wikilink.looksLikeFileReference` is never read. A repo-wide fixed-string grep returns only the declaration line — no call site in Sources, Tests or UITests. Callers that need this distinction use `isEmbed` directly instead. (`dead-code-Wikilink.swift-fa2`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the computed property; `isEmbed || target.contains(".")` is inlined at the sites that need it.

- **P3** `Sources/Core/Email/MailLink.swift:3` — Both `#if canImport(AppKit)` guards (lines 3-5 and 46-77) are unconditionally true in every target that compiles this file. Project.swift:79 explicitly excludes `Sources/Core/Email/MailLink.swift` from `sharedSources`, so neither `perg` nor `pergamenum-mcp` ever sees it; the only target left is the macOS app, where AppKit always imports. The conditional is dead. (`dead-code-MailLink.swift-f00`)
  Status: Deferred — report-only
  Suggested fix: Either drop both `#if canImport(AppKit)` guards as always-true, or keep them deliberately and note in the file header that they exist only as a guard against a future re-inclusion in a CLI target.

- **P3** `Sources/Core/Tasks/TaskItem.swift:159` — `TaskRecurrence.isFinished` is never read. Repo-wide grep for `isFinished` matches only this declaration. The `@repeat(n/N)` completion check is done elsewhere by comparing `completed`/`total` directly, so this accessor is unused surface on a shared-sources type. (`dead-code-TaskItem.swift-a30`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Remove `isFinished`, or route the existing completed/total comparisons through it so there is one spelling of the rule.

- **P3** `Sources/Core/URLScheme/PergamenumURL.swift:90` — `PergamenumRoute.raisesApp` is never read in production (only Tests/URLSchemeTests). Both URL entry points — AppDelegate.application(_:open:) at PergamenumApp.swift:17 and .onOpenURL at :227 — call `vault.handle(route)` unconditionally, and the delegate carries a comment saying no `NSApp.activate` is issued. So the property encodes SPEC §9's "capture must not raise the app" rule that nothing consults. (`dead-code-PergamenumURL.swift-af1`)
  Status: Deferred — report-only
  Suggested fix: Either remove `raisesApp` as unread, or consult it at the two URL entry points so SPEC §9's capture exclusion is enforced rather than only described.

- **P3** `Sources/DesignSystem/ThemeEngine.swift:3` — Unused import: `import SwiftUI`. The file names no SwiftUI symbol — the only non-project, non-Foundation identifier it uses is `Observable`, which comes from the `Observation` import on line 2. Verified by extracting every capitalised identifier outside comments and by grepping for SwiftUI property wrappers, free functions (`withAnimation`, `withTransaction`) and `#Preview`. (`dead-code-ThemeEngine.swift-30e`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 3 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/DesignSystem/ThemeEnvironment.swift:51` — `ColorScheme.asThemeAppearance` is declared in a `private extension` and never referenced anywhere in the repository, not even inside its own file. The conversion it performs is done inline instead by `syncSystemAppearance` on line 45 (`scheme == .dark ? .dark : .light`), which is the live path. (`dead-code-ThemeEnvironment.swift-ab5`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the private `extension ColorScheme` block (lines 50-54), or have `syncSystemAppearance` call `scheme.asThemeAppearance` so the helper has a user.

- **P3** `Sources/Features/Editor/CompletingTextView.swift:2` — Unused import: `import SwiftUI`. This file is a plain NSTextView subclass; the only non-project, non-Foundation identifier it uses is `Selector` (ObjC runtime), and it declares no SwiftUI property wrapper, view body or preview. AppKit on line 1 covers everything it touches. (`dead-code-CompletingTextView.swift-3c3`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 2 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Editor/EditorColumn+Text.swift:190` — Orphaned documentation comment: the `///` block on lines 190-191 ("An external edit arrived while this note had unsaved changes...") is followed by a blank line and then an ordinary `//` note, so it documents no declaration. It is leftover from a symbol removed when conflict handling moved to EditorColumn+Conflict.swift, and a `///` attached to nothing is invisible in generated docs. (`dead-code-EditorColumn+Text.swift-3c5`)
  Status: Fixed (commit 368035f)
  Suggested fix: Delete lines 190-191, or re-attach them to the conflict declaration they describe in EditorColumn+Conflict.swift.

- **P3** `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift:2` — Unused import: `import SwiftUI`. The extension names no SwiftUI type — `ViewBlockHostView`, `ViewBlockAttachment` and `ViewBlock` are all project symbols and the rest is AppKit/Foundation. The sibling rendering extensions it was modelled on do not need SwiftUI either. (`dead-code-EditorDecorationDelegate+ViewBlockRendering.swift-f9f`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 2 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Editor/MarkdownBlocksView.swift:1` — Unused import: `import AppKit`. The file contains zero `NS`-prefixed identifiers (verified with a count over the whole file); it is pure SwiftUI plus Foundation's `AttributedString`, both reachable through the `import SwiftUI` on line 2. (`dead-code-MarkdownBlocksView.swift-738`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 1 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Editor/MarkdownReadingView.swift:25` — `MarkdownReadingView` (167 lines) is the only whole-file-dead unit in this shard: no top-level symbol in it is referenced from anywhere outside the file, in Sources, Tests or UITests. This is deliberate — the file's own header and ADR-0029 §D14 record it as a retained seam for a future print/preview surface, explicitly asking that it not be deleted as dead code. Reported for the audit record only, not for removal. (`dead-code-MarkdownReadingView.swift-8fa`)
  Status: Deferred — report-only
  Suggested fix: Leave in place. If the audit wants it gone, that reverses ADR-0029 §D14 and needs an explicit decision, not a refactor.

- **P3** `Sources/Features/Editor/MarkdownStyler.swift:478` — `viewBlockRuns(in text:outside:)` never reads its `text` parameter — the body works exclusively off `fences`. Unlike the two deliberately-unread parameters nearby (`NoteListPane.opening(from old:)` and `ViewBlockHostStore.host(for:in:)`), this one carries no note explaining why it is kept. It is private with a single call site (line 140). (`dead-code-MarkdownStyler.swift-718`)
  Status: Fixed (commit 368035f)
  Suggested fix: Drop the `in text: String` parameter and update the single call at MarkdownStyler.swift:140, or document why it is retained as the sibling helpers do.

- **P3** `Sources/Features/Editor/NoteTextView+EmbedResize.swift:2` — Unused import: `import SwiftUI`. Extracting every capitalised identifier outside comments yields nothing outside the project, Foundation and the NS/CG AppKit prefixes; the file declares no view, property wrapper or preview. (`dead-code-NoteTextView+EmbedResize.swift-f57`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 2 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Editor/NoteTextView+Tables.swift:2` — Unused import: `import SwiftUI`. The file holds the Coordinator's table half plus a `DrawnTable` value over `TableGridView` (an NSView) and NSRange; no SwiftUI symbol, property wrapper or preview appears in it. (`dead-code-NoteTextView+Tables.swift-658`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 2 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Editor/NoteTextView+Transclusion.swift:195` — `decoration(at point:in:claimedBy:)` never uses `point`; the fragment walk only consumes `textView` and the `claim` closure, and each of the four callers already captures the point inside its own closure. The parameter reads as if it drove hit-testing when it does not, which is misleading at a hot path shared by folding, transclusion, embed caret and embed resize. (`dead-code-NoteTextView+Transclusion.swift-8dd`)
  Status: Fixed (commit 368035f)
  Suggested fix: Remove the `at point:` parameter and update the four call sites (Transclusion :158/:179, EmbedResize :61, EmbedCaret :152), or document the retention the way the sibling helpers do.

- **P3** `Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift:2` — Unused import: `import SwiftUI`. The extension only manipulates NSString ranges and the text view's atomic replace path; no SwiftUI symbol appears anywhere in it. (`dead-code-NoteTextView+ViewBlockEditing.swift-2d2`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Delete line 2 and rebuild the Pergamenum scheme to confirm.

- **P3** `Sources/Features/Pratiche/PraticaCommand.swift:49` — `PraticaCommand.symbol` is never read. Its doc comment claims «the SF Symbol both surfaces draw», but the only rendering site (PraticaTopBar.swift:66) builds `Button(command.title)` with no image, and PraticheListColumn uses hand-written accessibility labels. The catalogue's icon half is dead. (`dead-code-PraticaCommand.swift-1b0`)
  Status: Deferred — report-only
  Suggested fix: Either render it (`Label(command.title, systemImage: command.symbol)`) as ADR-0023 §D1 intends, or delete the `symbol` property and its doc comment.

- **P3** `Sources/Features/Pratiche/PraticaCommandActions.swift:382` — The `praticaPath` parameter of the private `moveFiles(of:from:to:)` is never used in the body — the source folder is re-derived from `detail.notePath`. A dead parameter on a file-moving helper reads as if the source were honoured when it is not. (`dead-code-PraticaCommandActions.swift-ae9`)
  Status: Fixed (commit 368035f)
  Suggested fix: Drop the `from praticaPath: String` parameter and its argument at the call site, or use it instead of re-deriving the folder from `detail.notePath`.

- **P3** `Sources/Features/Pratiche/PraticaCommandActions.swift:667` — The `entry` parameter of the private `praticaPath(of:detail:)` is never read; the function derives everything from `detail?.notePath`. The doc comment says the answer must come from the row rather than the selection, which the unused `entry` parameter suggests but does not do. (`dead-code-PraticaCommandActions.swift-12f`)
  Status: Fixed (commit 368035f)
  Suggested fix: Remove the unused `_ entry: PraticaTimelineEntry` parameter (updating call sites), or use it if the row identity is meant to participate.

- **P3** `Sources/Features/Pratiche/PraticaSyncEngine.swift:296` — `PreparedAttachment.digest` is written once at line 736 (`PreparedAttachment(fileName:bytes:digest:)`) and never read. Dedup by digest is done through the separate `nameByDigest` dictionary, not through this field. (`dead-code-PraticaSyncEngine.swift-666`)
  Status: SKIPPED
  Suggested fix: Remove `var digest: String` from `PreparedAttachment` and the corresponding argument at line 736.

- **P3** `Sources/Features/Settings/CanvasSettings.swift:10` — `@Environment(\.theme) private var theme` is declared but never read in this view: it only uses `.themedText(...)`, and that ViewModifier reads the theme from the environment itself (ThemeEnvironment.swift). The redundant declaration still subscribes the view to the theme environment key. (`dead-code-CanvasSettings.swift-d9d`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the unused `@Environment(\.theme) private var theme` line.

- **P3** `Sources/Features/Settings/SettingsView.swift:10` — Unused `@Environment(\.theme) private var theme` on this view: every theme access in the file goes through `.themedText(...)`, which resolves the theme itself. The property is never referenced. (`dead-code-SettingsView.swift-e7f`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the unused `@Environment(\.theme) private var theme` line.

- **P3** `Sources/Features/Settings/ShortcutSettings.swift:108` — Unused `@Environment(\.theme) private var theme` on the private `KeyRecorder` view (the outer view's declaration at line 10 is genuinely used at 56/62/68; this second one is not). (`dead-code-ShortcutSettings.swift-812`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the `@Environment(\.theme) private var theme` line inside `KeyRecorder`.

- **P3** `Sources/Features/Settings/TaskSettings.swift:8` — Unused `@Environment(\.theme) private var theme`: the view's only theme use is `.themedText(...)`, which reads the environment inside its own ViewModifier. (`dead-code-TaskSettings.swift-a1b`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the unused `@Environment(\.theme) private var theme` line.

- **P3** `Sources/Features/Today/CalendarDayCommand.swift:52` — `CalendarDayCommand.Entry.symbol` is assigned at line 78 from `command.symbol` and never read. CalendarDayMenuItems renders `Button(entry.title)` with no image, so the whole symbol chain (the enum's `var symbol` at line 35 plus this field) exists only to be thrown away. (`dead-code-CalendarDayCommand.swift-522`)
  Status: Deferred — report-only
  Suggested fix: Either draw the icon (`Button { run(entry.command) } label: { Label(entry.title, systemImage: entry.symbol) }`) or delete `Entry.symbol` and `CalendarDayCommand.symbol`.

- **P3** `Sources/Features/Today/WeekEntryRows.swift:56` — Unused `@Environment(\.theme) private var theme` on this view (the file's first declaration at line 12 is used at line 34; this one is not — line 72 only calls `.themedText(...)`). (`dead-code-WeekEntryRows.swift-734`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the unused `@Environment(\.theme) private var theme` at line 56.

- **P3** `Sources/Features/Today/WeekEntryRows.swift:84` — Unused `@Environment(\.theme) private var theme` on this view: its body (line 90) only uses `.themedText(...)`, which resolves the theme itself. (`dead-code-WeekEntryRows.swift-1ab`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the unused `@Environment(\.theme) private var theme` at line 84.

- **P3** `Sources/Features/Views/ViewGridRenderers.swift:14` — `ViewGalleryRenderer.notePath` is passed in from RenderedViewBlock.swift:167 but never read inside the renderer: the thumbnail resolution at line 47 passes `row.path`, not `notePath`. The property is write-only. (`dead-code-ViewGridRenderers.swift-eb8`)
  Status: Fixed (commit 368035f)
  Suggested fix: Remove `var notePath: String = ""` from ViewGalleryRenderer and the `notePath:` argument at RenderedViewBlock.swift:167.

- **P3** `Sources/Features/Views/ViewQueryBuilderSheet.swift:17` — The stored property `let source: String` is assigned in the initializer (line 42) but never read afterwards: line 46 seeds the draft from the initializer's local `source` parameter, not from `self.source`. The stored copy is dead. (`dead-code-ViewQueryBuilderSheet.swift-baf`)
  Status: Fixed (commit 368035f)
  Suggested fix: Delete `let source: String` and the `self.source = source` assignment at line 42; the init parameter alone is sufficient.

- **P3** `Sources/Features/Views/ViewQuerySource.swift:1` — `import SwiftUI` appears unnecessary in this 26-line file: `ViewQuerySource` declares only closures over project types (`ViewBlock`, `ViewResult`, `Tag`, `VaultSession.BoardDropOutcome`) and an `Int`. No SwiftUI or Foundation type is named. (`dead-code-ViewQuerySource.swift-51f`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Drop `import SwiftUI` (adding `import Foundation` only if the build then needs it).

- **P3** `Sources/Features/Views/ViewRowRenderers.swift:89` — Unused `@Environment(\.theme) private var theme` on the `ViewCell` view: lines 108/113 only use `.themedText(...)`. The file's other declarations (13, 124) are genuinely used. (`dead-code-ViewRowRenderers.swift-353`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the `@Environment(\.theme) private var theme` line inside `ViewCell`.

- **P3** `Sources/Features/Workspace/BoardChrome.swift:16` — Unused `@Environment(\.theme) private var theme` on this view: it only calls `.themedText(.caption, color: .textSecondary)` at line 39. The other declarations in the file (67, 124) are used. (`dead-code-BoardChrome.swift-dc7`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the `@Environment(\.theme) private var theme` at line 16.

- **P3** `Sources/Features/Workspace/BoardCropEditor.swift:144` — `CropHandleView.node` is passed at the construction site (line 45) but never referenced anywhere in the view's body or computed properties. The handle drives crop state through `workspace` and `rect` only. (`dead-code-BoardCropEditor.swift-957`)
  Status: Fixed (commit 368035f)
  Suggested fix: Remove `let node: CanvasNode` from CropHandleView and the `node: node` argument at line 45.

- **P3** `Sources/Features/Workspace/BoardFormatBar.swift:81` — The `viewport: CGSize` parameter of this placement function is never read in the body, which computes the origin purely from `cardOrigin`/`selectionFrame`/`zoom`/`pan`. A placement that takes a viewport and ignores it cannot clamp the bar on screen. (`dead-code-BoardFormatBar.swift-e0a`)
  Status: Deferred — report-only
  Suggested fix: Either use `viewport` to clamp the returned Placement to the visible board, or delete the parameter and its arguments at the call sites.

- **P3** `Sources/Features/Workspace/BoardWikilinkCompletionLayer.swift:42` — The `viewport: CGSize` parameter of this placement function is never read — the body computes the origin from `cardOrigin`/`caretFrame`/`zoom`/`pan` only. Same shape as the BoardFormatBar placement. (`dead-code-BoardWikilinkCompletionLayer.swift-887`)
  Status: Deferred — report-only
  Suggested fix: Either use `viewport` to keep the completion popup on screen, or delete the parameter and its arguments at the call sites.

- **P3** `Sources/Features/Workspace/CanvasCrop.swift:25` — The computed property `var rect: CGRect` is never read. Every call site in Sources and Tests uses the differently-shaped `func rect(in drawnSize:)` (WorkspaceController+Crop.swift:24,80; CanvasCropTests.swift:98). Two members named `rect` with only one live is an invitation to call the wrong one. (`dead-code-CanvasCrop.swift-bd6`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }`.

- **P3** `Sources/Features/Workspace/CanvasCrop.swift:34` — `init(_ rect: CGRect)` is never called. All CanvasCrop constructions in Sources and Tests use the memberwise `init(x:y:width:height:)`. (`dead-code-CanvasCrop.swift-123`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the `init(_ rect: CGRect)` convenience initializer.

- **P3** `Sources/Features/Workspace/CardCommand.swift:1` — `import CoreGraphics` is unused: no CG type (CGFloat/CGPoint/CGSize/CGRect or any other `CG`-prefixed symbol) appears in the file. Note the file's own header comment names the import as deliberate, so the comment needs updating alongside. (`dead-code-CardCommand.swift-4a3`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import CoreGraphics` and amend the header comment's «import Foundation and import CoreGraphics only» sentence.

- **P3** `Sources/Features/Workspace/FormattingTextView.swift:252` — `PendingLinkClick.characterIndex` is written at line 233 and never read: the consumer at line 244-245 only unwraps `pending.url`. The character index is captured and discarded. (`dead-code-FormattingTextView.swift-441`)
  Status: Fixed (commit 368035f)
  Suggested fix: Drop `let characterIndex: Int` from `PendingLinkClick` and the `characterIndex: index` argument at line 233 (the local `index` is still needed for the hit test).

- **P3** `Sources/Features/Workspace/WorkspaceBrowser+Tree.swift:219` — The `old` parameter of `opening(from:to:currently:in:)` is never read — the collapse rule is decided entirely from `new`, `currently` and `tree`. The signature advertises a before/after comparison that does not happen. (`dead-code-WorkspaceBrowser+Tree.swift-5e1`)
  Status: SKIPPED
  Suggested fix: Remove the `from old: Set<String>` parameter and update its call sites and tests, unless the previous set is genuinely meant to participate in the rule.

- **P3** `Sources/Features/Workspace/WorkspaceController+Duplicate.swift:1` — `import CoreGraphics` is unused: the file names no `CG`-prefixed type. Foundation already re-exports CoreGraphics on Darwin. (`dead-code-WorkspaceController+Duplicate.swift-155`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove the `import CoreGraphics` line.

- **P3** `Sources/Features/Workspace/WorkspaceController+TextEditing.swift:1` — `import CoreGraphics` is unused: the file names no `CG`-prefixed type. (`dead-code-WorkspaceController+TextEditing.swift-498`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove the `import CoreGraphics` line.

- **P3** `Sources/Features/Workspace/WorkspaceFolderSheets.swift:306` — Unused `@Environment(\.theme) private var theme` on the private `WorkspaceNameProblems` view; it renders only through `.themedText(...)`. The file's other declarations (134, 226) are used. (`dead-code-WorkspaceFolderSheets.swift-647`)
  Status: Fixed (commit 186329a)
  Suggested fix: Delete the `@Environment(\.theme) private var theme` line inside `WorkspaceNameProblems`.

- **P3** `Sources/Features/Workspace/WorkspaceView.swift:561` — The `size` parameter of `canvasPoint(from:in:)` is never used: the inverse transform reads only `workspace.pan` and `workspace.zoom`. (`dead-code-WorkspaceView.swift-bb2`)
  Status: Fixed (commit 368035f)
  Suggested fix: Remove the `in size: CGSize` parameter and update its call sites.

- **P3** `Sources/Vault/OpenTabsStore.swift:72` — `OpenTabsStore.forget(_ root: URL)` is never called. `session(for:)` and `remember(_:for:)` are both used by the tab-restore path, but nothing ever removes a vault's stored session, so the `UserDefaults` key of a vault that is deleted or never reopened stays forever. (`dead-code-OpenTabsStore.swift-775`)
  Status: SKIPPED
  Suggested fix: Delete `forget(_:)`, or call it where a vault is dropped from the recents list so its stored desk goes with it.

- **P3** `Sources/Vault/ThumbnailStore.swift:54` — `ThumbnailStore.forgetAll()` is never called. The only calls to `forgetAll` in the repo are `RecentVaults().forgetAll()` in VaultCommands.swift; the single `thumbnails` property (VaultController.swift:24) is only ever sent `thumbnail(for:width:)`. The doc comment claims it runs "after «svuota cache»", but `VaultController.clearCache()` only touches `IndexCache`. (`dead-code-ThumbnailStore.swift-bdd`)
  Status: Deferred — report-only
  Suggested fix: Call `thumbnails?.forgetAll()` from `VaultController.clearCache()` so the memoised renditions really are discarded, or delete the method.

- **P3** `Sources/Vault/ThumbnailStore.swift:58` — `ThumbnailStore.clearCacheOnDisk()` has no callers in Sources, Tests or UITests. Nothing in the app ever removes the thumbnail cache directory, so "Svuota cache e ricostruisci" (SettingsView.swift:284) leaves every rendered PNG on disk. (`dead-code-ThumbnailStore.swift-3b0`)
  Status: Deferred — report-only
  Suggested fix: Wire `clearCacheOnDisk()` into the clear-cache flow beside `IndexCache.clear()`, or remove it.

- **P3** `Sources/Vault/VaultScanner.swift:40` — The nested `final class Statistics: @unchecked Sendable { var reused = 0 }` is never instantiated or referenced anywhere; the identifier `Statistics` occurs exactly once in the whole repository. `scan()` counts reuse with a plain local `var reused = 0` instead, so the type is a leftover of an abandoned approach. (`dead-code-VaultScanner.swift-349`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the nested `Statistics` class; `scan()`'s local `reused` counter already carries the value.

- **P3** `Sources/Vault/VaultSession+Journal.swift:50` — The computed property `openOperation` has no readers anywhere; every site that needs the running operation id reads the stored `currentOperation` directly (lines 91, 137, 177 and VaultSession.swift:208). The accessor and its four-line doc comment describe a call pattern no caller uses. (`dead-code-VaultSession+Journal.swift-49f`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `openOperation`; callers already read `currentOperation`.

- **P3** `Sources/Vault/VaultSession+Tasks.swift:15` — `VaultSession.TaskChange.link(String)` is never constructed anywhere, in Sources, Tests or UITests, so the switch arm at line 118 is unreachable. ADR-0039 records this retention as deliberate and calls it "pure, tested vault-layer capability", but no test constructs the case either — only the underlying `TaskParser.line(for:addingLinkTo:)` is covered (TaskTests.swift:199). (`dead-code-VaultSession+Tasks.swift-610`)
  Status: Deferred — report-only
  Suggested fix: Leave as documented-deliberate, but correct ADR-0039's "tested" claim or add a test that exercises `changeTask(..., .link(...))` so the retained path stays honest.

- **P3** `Sources/Vault/VaultSession.swift:234` — `clearProblems()` has no callers. `session.problems` is appended to from many places and surfaced by `SettingsView.swift:296`, but nothing ever empties it, so the list only grows for the lifetime of a session and the intended "dismiss" affordance does not exist. (`dead-code-VaultSession.swift-0f8`)
  Status: Deferred — report-only
  Suggested fix: Either wire `clearProblems()` to a clear action beside the problems list in Impostazioni, or delete the unused method.

- **P3** `Tests/BoardInteractionTests.swift:3` — `import SwiftUI` is unused: the file references no SwiftUI type at all (its geometry comes from CoreGraphics, imported on line 1, and its assertions from Testing). (`dead-code-BoardInteractionTests.swift-6b7`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import SwiftUI`; re-run the test target build to confirm.

- **P3** `Tests/CardCommandTests.swift:1` — `import CoreGraphics` is unused: the file contains no `CG`-prefixed symbol whatsoever (grep count zero), only `CardCommand` catalogue assertions. (`dead-code-CardCommandTests.swift-b66`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import CoreGraphics`.

- **P3** `Tests/DayTestSupport.swift:2` — `import Testing` is unused: this support file declares only scaffolding (stub calendar store, temporary vault, wired controllers) and references no Testing API — no `#expect`, `#require`, `@Test`, `@Suite`, `SourceLocation` or `Issue`. (`dead-code-DayTestSupport.swift-4b5`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import Testing` from the support file; the suites that consume it import Testing themselves.

- **P3** `Tests/EmbedEditorTestSupport.swift:2` — `import Testing` is unused: the file builds a temporary vault, a PNG, an `NSTextView` in a window and a landed rendition, but references no Testing API (no `#expect`, `#require`, `@Test`, `@Suite`, `SourceLocation`). (`dead-code-EmbedEditorTestSupport.swift-fc5`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import Testing` from the support file; the embed suites import it themselves.

- **P3** `Tests/EmojiCompletionTests.swift:2` — `import SwiftUI` is unused: the file drives a `CompletingTextView` through AppKit APIs only, and the one theme reference (`refreshCompletion(theme: .emergency)`) names an app-module type, not a SwiftUI one. (`dead-code-EmojiCompletionTests.swift-a37`)
  Status: Fixed (commit e3e0cf2)
  Suggested fix: Remove `import SwiftUI`; re-run the test target build to confirm.

- **P3** `Tests/FakePlaudService.swift:67` — `setProposalResult(_:)` is the only setter of the fake that no test calls (setHealthResult, setRecordingsResult, setProcessResult, setJobResult and setConfirmImportedResult all have callers). Tests rely on the default `nil` / `.proposalNotFound` behaviour instead, so no test ever supplies a successful proposal through the fake. (`dead-code-FakePlaudService.swift-0dd`)
  Status: Deferred — report-only
  Suggested fix: Keep only if a proposal-success test is coming; otherwise delete the setter. Worth checking that the missing success-path coverage is intentional.

- **P3** `Tests/MarkdownAttributedTextTests.swift:62` — `private static let familyWithItalic = "Avenir Next"` is never referenced; its sibling `familyWithNoItalic` is used at line 175. Swift emits no warning for an unused private static stored property, so it will stay indefinitely. (`dead-code-MarkdownAttributedTextTests.swift-fcb`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete `familyWithItalic`, or add the missing positive-control test that was meant to use it.

- **P3** `Tests/PergamenumTests.swift:4` — This test is the sole consumer of AppInfo.name and AppInfo.tagline: both have zero references in Sources/ (grep across Sources finds only the declaration in Sources/Core/AppInfo.swift). The tagline still holds the M0 scaffolding string "Bootstrap - under active development" while the app ships at marketing version 1.4, so the assertion is tautological and is the only thing keeping two dead constants alive. (`dead-code-PergamenumTests.swift-f31`)
  Status: SKIPPED
  Suggested fix: Either delete this test together with AppInfo.name/AppInfo.tagline, or wire tagline into the About panel so the constant has a real consumer and the test stops being tautological.

- **P3** `Tests/PlaudHTTPClientTests.swift:198` — A fileprivate extension on NSLock reimplements withLock, which Foundation already provides on NSLocking (rethrows variant). The production code proves it is available in this project: Sources/Features/Editor/ViewBlockAttachment.swift:11-12 calls lock.withLock with no such extension in scope. The local copy shadows the standard one at the call site on line 163 and is redundant. (`dead-code-PlaudHTTPClientTests.swift-5ea`)
  Status: Fixed (commit 29b8621)
  Suggested fix: Delete the fileprivate `extension NSLock { func withLock... }` block; line 163 resolves to Foundation's NSLocking.withLock unchanged.

- **P3** `scripts/appcast.py:81` — `load_feed(url, fetch=default_fetch)` is a one-line pass-through whose `fetch` dependency-injection parameter is never supplied by any caller. The only call site is `main` (`load_feed(args.feed_url)`), and the self-test bypasses it entirely by handing raw bytes straight to `build_feed` via `_feed`. Grep over the whole repo confirms `load_feed`/`default_fetch` appear nowhere outside this file, so the seam is unused indirection. (`dead-code-appcast.py-b96`)
  Status: SKIPPED
  Suggested fix: Either drop the unused `fetch` parameter and inline `default_fetch` into `main`, or add a self-test case that injects a stub `fetch` so the seam earns its keep.

### perf

Checkpoint: ad8a2e3

- **P1** `Sources/Features/Editor/EditorColumn+Text.swift:58` — `CanvasStore(root:).allBoards()` performs a full recursive `FileManager.enumerator` walk of the whole vault (synchronous disk I/O). It is called inline as a `NoteTextView` parameter inside `editing(_:)`, which `EditorColumnView.body` calls directly, so the entire vault is re-enumerated on every body evaluation, i.e. on every keystroke. The repo already forbids this elsewhere: `BoardChrome.swift:49` and `WorkspaceView.swift:209` both say "read in the hand-off, never in `body`: `allBoards()` walks the vault uncached", and Workspace caches the result in `workspace.wikilinkBoardTitles`. (`perf-EditorColumn+Text.swift-8f5`)
  Status: Fixed (commit ad8a2e3)
  Suggested fix: Hold the board list in `@State`, refreshed from `.task(id: vault.scanGeneration)` (or reuse the already-cached `workspace.wikilinkBoardTitles`), and pass the cached array instead of calling `allBoards()` in `body`.

- **P1** `Sources/Features/Editor/MarkdownStyler.swift:496` — `wikilinkSpans` recomputes loop invariants inside the per-link loop: `String(text[start...])` allocates a fresh copy of the whole note body four times per link (twice in `lower`, twice in `upper`), plus `text.distance(from:startIndex,to:start)` and `text.index(text.startIndex, offsetBy: offset)` which are O(length) walks per link. `MarkdownStyler.spans(in:)` runs on the whole note on every keystroke via `applyStyling`, so this is O(links x noteLength) string allocation per keystroke. (`perf-MarkdownStyler.swift-f6a`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Hoist `let slice = String(text[start...])` and the base index/offset out of the loop, and reuse the one slice for every link's distance computation.

- **P1** `Sources/Features/Editor/OutlinePane.swift:174` — `foldable` is a computed property, not a stored one, so it is recomputed on every access. Each evaluation runs `NoteFolding.hiddenParagraphs(in: text, foldedEntries: [index])` once per outline entry, and that helper does a full `lineStarts` pass plus a `NoteOutline.entries(in:)` parse of the whole note. `foldableOffset(for:at:)` reads it, and `chevron(for:at:)` calls that once per row, so a single body render costs rows x entries full note parses. The doc comment claims "Computed once per rebuild rather than per row", which a computed property cannot deliver. (`perf-OutlinePane.swift-1e9`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Compute `foldable` (and `hiddenByFold`) once as a `let` at the top of `body` and pass them down into `row`/`chevron`/`foldableOffset`, or derive them once per `text` change into `@State`.

- **P1** `Sources/Features/Tags/TagBrowserView.swift:237` — `usage` is a computed property that runs `IndexSnapshot.tagUsage()` (a full pass over every note's tags plus a sort) and rebuilds a Dictionary on every read. It is read inside the pinned-tag ForEach (line 92), inside the per-tag ForEach (line 104), and again from `namespacesInUse`, `tags(in:)` and `total(in:)`, so the whole vault's tags are recounted once per drawn row. (`perf-TagBrowserView.swift-95b`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Compute `let usage = usage` once at the top of `tagColumn` and pass it into `row`, `tags(in:)` and `total(in:)`; same for `notes`, read three times (lines 199, 203, 263).

- **P1** `Sources/Features/Today/MiniCalendar.swift:158` — `hasDailyNote(_:)` resolves a path with `vault.index.allNotes.contains { $0.relativePath == path }`. `allNotes` materialises and localized-sorts every note in the vault, then the closure scans it linearly. It is called once per grid cell in `cell(_:)` and a second time in that cell's `contextMenu`, i.e. up to 84 full vault sorts per redraw of the month grid. (`perf-MiniCalendar.swift-fc1`)
  Status: Fixed (commit fa67926)
  Suggested fix: Use the O(1) dictionary lookup already on the snapshot: `vault.index.note(at: path) != nil`, or build one `Set` of daily-note paths per body instead of per cell.

- **P1** `Sources/Features/Today/TodayView.swift:199` — `noteBody` builds the wikilink completion pools inside the view body: `CanvasStore(root:).allBoards()` performs a full recursive FileManager enumeration of the entire vault, and `index.allNotes` sorts every note with `localizedStandardCompare`. The body re-evaluates on every keystroke in the daily note (the text Binding writes observable state), so each character typed triggers a whole-vault directory walk on the main thread. (`perf-TodayView.swift-63f`)
  Status: Fixed (commit ad8a2e3)
  Suggested fix: Hold the board/note title pools in @State and refresh them from a `.task(id: vault.scanGeneration)`, the way TasksView.swift:47, WorkspacePicker and WorkspaceView.applyBoardSettings already do; never call allBoards() from a body.

- **P2** `Sources/Features/Pratiche/PraticheController.swift:325` — `reloadTimeline(from:)` runs on the @MainActor controller and synchronously reads every `email/*.md` of the pratica plus `pratica.md` (PraticheController.swift:735-795), parsing each one. `load(from:)` additionally opens every candidate `pratica.md` through `Dossier.parse` (line 644). All of it blocks the main thread on selection change and after every sync. (`perf-PraticheController.swift-c6e`)
  Status: Deferred — report-only
  Suggested fix: Move the already-`nonisolated` readTimeline/listItems reads off the main actor and assign results back — a concurrency/isolation change, so it needs deliberate review rather than an automated fix.

- **P2** `Sources/Vault/VaultSession.swift:218` — Every `.md` write calls `history.record(text, for:)` synchronously on the `@MainActor` session: it creates a directory, writes a full copy of the note, then `thin()` lists that directory and issues `removeItem` calls. All of this blocks the main thread on each save, on top of the note write itself. (`perf-VaultSession.swift-fc1`)
  Status: Deferred — report-only
  Suggested fix: Move snapshot writing and thinning off the main actor (detached utility task) — isolation change, so report only.

- **P2** `Sources/Core/Email/EmailHeaders.swift:234` — `RFC5322Date.parse` constructs a new `DateFormatter` (and a new `Locale`) inside the loop over six candidate formats, and recomputes `cleaned(raw)` on every iteration too. A header that matches the last format therefore builds six formatters and cleans the string six times, and this runs once per message header parsed during a pratiche sync. (`perf-EmailHeaders.swift-0f3`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist `let text = cleaned(raw)` and one `let formatter = DateFormatter()` (locale set once) above the loop, reassigning only `formatter.dateFormat` per iteration.

- **P2** `Sources/Core/Email/HTMLTextReducer.swift:148` — `HTMLTokenizer.matches` rebuilds `Array(needle)` on every call and compares characters with `$0.lowercased() == $1.lowercased()`, which allocates two Strings per character compared. `end(of:)` calls it once per character position while scanning for `-->` or `</style`, so skipping one large `<style>` block in a marketing email costs thousands of array allocations and tens of thousands of String allocations. (`perf-HTMLTextReducer.swift-b66`)
  Status: SKIPPED
  Suggested fix: Pass a pre-lowercased `[Character]` needle (built once by the caller) and compare with `Character.lowercased()` avoided via a precomputed lowercase haystack, or compare scalars directly.

- **P2** `Sources/Core/Email/HTMLTextReducer.swift:352` — `breakParagraph` allocates a full copy of the accumulated buffer via `trimmingCharacters(in:)` only to test whether it is all whitespace, and the `let current = buffers[...]` binding is still alive at the `+=` on line 354 (it is read on that line's right-hand side), so the append sees non-uniquely-referenced storage and copies the whole buffer. Both costs are O(document length) and are paid for every `<p>`, `<div>`, `<blockquote>`, `<table>` and heading tag, making the walk quadratic in body length. (`perf-HTMLTextReducer.swift-0d5`)
  Status: SKIPPED
  Suggested fix: Replace the trim with a non-allocating `buffers[last].allSatisfy(\.isWhitespace)` check and read `hasSuffix` directly off `buffers[last]` so no second reference to the string exists at the append.

- **P2** `Sources/Core/Email/MIMEDecoder.swift:116` — `bodies(of:boundary:)` allocates a fresh `[UInt8]` array for every line of the whole part body (`Array(bytes[offset..<lineEnd])`), and `delimiter` then allocates two more per line (`Array(line.prefix(...))`, `Array(line.dropFirst(...))`). A message with a 10 MB base64 attachment is ~135k lines, so this is hundreds of thousands of heap allocations to find a handful of boundary markers. `let bytes = Array(body)` on line 108 additionally copies the entire body once per multipart nesting level. (`perf-MIMEDecoder.swift-33c`)
  Status: SKIPPED
  Suggested fix: Work on `ArraySlice`/`Data` slices instead of materialising arrays: pass `bytes[offset..<lineEnd]` to `delimiter` and compare with `slice.starts(with: open)` / `elementsEqual`.

- **P2** `Sources/Core/Email/MailStoreReader.swift:150` — N+1 query: after one GROUP BY query returns the candidate conversation ids, the code runs `messages(inConversation:)` per id, and that helper itself issues two statements (the row select and the recipients join). A counterpart search returning 200 conversations therefore prepares, binds, steps and finalises 400 statements where two `IN (...)` queries would do. (`perf-MailStoreReader.swift-53f`)
  Status: SKIPPED
  Suggested fix: Batch the follow-up reads with a single `WHERE m.conversation_id IN (?1,?2,…)` row query plus one batched recipients query, then group in memory — preserving the existing 'collect ids, finalize, then read' statement-lifetime rule.

- **P2** `Sources/Core/Email/MailStoreReader.swift:281` — `emlxPath(forRow:)` calls `Self.storeDirectory(in:)`, which performs a synchronous `FileManager.contentsOfDirectory` on the `.mbox` directory — one directory enumeration per message. The function's own doc comment records that the UUID directory is identical across every mailbox of the probed store, so the result is constant per mailbox and is being re-read from disk for every row of a sync. (`perf-MailStoreReader.swift-495`)
  Status: SKIPPED
  Suggested fix: Memoise the resolved store-UUID directory keyed by mailbox path for the reader's lifetime (a small reference-type cache held by `MailStoreReader`), the way `EMLXLocator`'s doc comment already prescribes for its own enumeration.

- **P2** `Sources/Core/Pratiche/MembershipRule.swift:188` — `trayCandidates`' final comparator recomputes `left.messages.map(date).max()` and the same for the right operand on every comparison — an array allocation over all of a conversation's messages, twice per comparison, O(n log n) times. Each conversation's newest date is a fixed value. (`perf-MembershipRule.swift-3c2`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Compute the newest date per `TrayEntry` once (a `(date, entry)` pair array), sort that, then map back to `[TrayEntry]`.

- **P2** `Sources/Core/Query/Glob.swift:19` — `Glob.matches` folds the pattern and converts it to an `[Character]` array on every call, and `matchesTag`/`matchesPath` fold the pattern again on the non-wildcard path. These are called once per record for `isInScope` and once per record (or per tag) for `.path`/`.tag` filter terms, so the same short pattern is folded and arrayified N times per view evaluation. (`perf-Glob.swift-de6`)
  Status: SKIPPED
  Suggested fix: Add a small prepared-pattern value (folded pattern array built once) that `ViewEvaluator.Context` builds per block, or memoise the folded pattern; keep the current entry points as thin wrappers.

- **P2** `Sources/Core/Query/ViewEvaluator.swift:92` — The sort comparator recomputes `key.field.value(of:in:)` for both operands on every comparison, i.e. O(n log n) derivations instead of n. Several derivations allocate (`.tags` sorts and maps, `.links`/`.linkedFrom` build arrays, `.deadlineNext` compactMaps every task), so a large result set pays repeated array allocations purely to compare. (`perf-ViewEvaluator.swift-203`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Decorate-sort-undecorate: precompute `[ViewField: ViewValue]` per row for the sort keys once, sort on the precomputed tuple, then drop it.

- **P2** `Sources/Core/Query/ViewEvaluator.swift:232` — `linksTo` and `linkedFrom` are called once per record but recompute work that does not depend on the record: `Set(resolve(title))` in `linksTo`, and in `linkedFrom` the entire `resolve(title).compactMap { byPath[$0] }` source set plus a re-resolution of every one of those sources' link targets. For a corpus of N records with S sources this is N×S×T resolutions where N×1 would do. The type's own doc comment states that per-evaluation facts belong in `Context` for exactly this reason. (`perf-ViewEvaluator.swift-97e`)
  Status: SKIPPED
  Suggested fix: Resolve the term's title once per evaluation (lazily memoised on `Context`) into a target path set / a set of paths linked-from, and have the per-record check be a single `Set.contains`.

- **P2** `Sources/Core/Search/SearchQuery+Matching.swift:47` — `matchesText` re-folds every needle (`SearchQuery.fold(needle)`) for every note in the vault-wide loop, though the folded needles are query-constant. `excerpt` (line 91) is worse: it folds every needle again for every line of the note. `Matcher` exists precisely to hold per-search precomputation — it already caches the compiled regexes but not the folded needles. (`perf-SearchQuery+Matching.swift-072`)
  Status: Fixed (commit fa67926)
  Suggested fix: Store `foldedWords`, `foldedPhrases`, `foldedNegated` as `let` properties computed once in `Matcher.init`, and read those in `matchesText`/`excerpt`.

- **P2** `Sources/Core/Search/SearchQuery.swift:274` — `SearchQuery.fold` allocates a new `Locale(identifier: "it_IT")` on every call. `fold` is the shared normalisation used by `SearchQuery.Matcher`, `Glob.matches`/`matchesTag`/`matchesPath`, `ViewEvaluator`'s `.text` term and `UnlinkedMentions`, i.e. it is called per needle, per note and per line during a vault-wide search or view evaluation. (`perf-SearchQuery.swift-fd9`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist the locale into a `private static let foldingLocale = Locale(identifier: "it_IT")` and pass that to `folding(options:locale:)`.

- **P2** `Sources/Core/Tasks/DateEntry.swift:168` — `Calendar.gregorianUTC` is a computed `static var`, so every access constructs a fresh `Calendar` plus a `TimeZone` and a `Locale`. It is the default argument of nine `DateEntry` functions and backs `CalendarDate.adding(days:)`, which runs inside loops (e.g. `CalendarService.bucketed`'s per-event day walk, task grouping headings). Calendar construction is one of Foundation's more expensive object initialisations. (`perf-DateEntry.swift-102`)
  Status: Fixed (commit 563083c)
  Suggested fix: Change to `static let gregorianUTC: Calendar = { var c = Calendar(identifier: .gregorian); ...; return c }()` — `Calendar` is `Sendable`, and the file already uses this shape for `uiLocale`/`hintFormatter`.

- **P2** `Sources/Core/Tasks/TaskListOptions.swift:207` — `TaskArrangement.sort` builds a fresh key String for both operands on every comparison. For `.text` that is a `lowercased()` allocation per comparison; for `.note` it is an `NSString` bridge, `lastPathComponent`, `NoteName.title(fromFileName:)` and a `lowercased()` per comparison. A list of n tasks pays 2·n·log n string allocations where 2n would do. (`perf-TaskListOptions.swift-145`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Map tasks to `(key, id, task)` once, sort that array, then map back — keeping the existing id tiebreak so the sort stays deterministic.

- **P2** `Sources/Features/Diary/DiaryView.swift:92` — Same defect as `EditorColumn+Text.swift:58`: `CanvasStore(root:).allBoards()` recursively enumerates the whole vault on disk and is called inline in the `editor` view builder, so a full filesystem walk happens on every body evaluation of the Diario pane (every keystroke in the diary editor). (`perf-DiaryView.swift-b3b`)
  Status: Fixed (commit ad8a2e3)
  Suggested fix: Cache the board list in `@State`, refreshed on `vault.scanGeneration`, and pass the cached value to `NoteTextView` instead of walking the vault in `body`.

- **P2** `Sources/Features/Editor/EditorColumn+Text.swift:57` — `vault.index.allNotes` is a computed property that sorts every note in the vault with `localizedStandardCompare` (`IndexSnapshot.swift:96`). Reading it just to build `.map(\.title)` in `editing(_:)` means a locale-aware full-vault sort plus two array allocations on every editor body evaluation, i.e. on every keystroke. `DiaryView.swift:91` has the identical line. (`perf-EditorColumn+Text.swift-add`)
  Status: Fixed (commit ad8a2e3)
  Suggested fix: Expose an unsorted `notes.values.map(\.title)` accessor on the index (order is irrelevant to completion ranking), or cache the title list in `@State` refreshed on `vault.scanGeneration`.

- **P2** `Sources/Features/Editor/MarkdownStyler.swift:704` — `listMarkerSpan` calls `ListNesting.level(in: text, ...)` for every list line, and that helper walks backward line by line through the whole enclosing list run to rebuild the ancestor stack. Since `spans(in:)` runs over the whole note on every keystroke, a note holding one long list costs O(listLength^2) line scans per keystroke. The same call is repeated at layout time by `EditorDecorationDelegate+ListRendering.swift:151`. (`perf-MarkdownStyler.swift-c80`)
  Status: SKIPPED
  Suggested fix: Compute the ancestor content-column stack once in a single forward pass inside `spans(in:)` and hand each list line its level, instead of re-deriving it per line with a backward walk.

- **P2** `Sources/Features/Editor/NoteTreeRow.swift:236` — `vault.index.allNotes.first(where: { $0.relativePath == node.id })` triggers a full locale-aware sort of every note in the vault (`allNotes` is computed and sorts with `localizedStandardCompare`) followed by a linear scan, purely to look up one record by path. `IndexSnapshot.note(at:)` is an O(1) dictionary lookup that already exists. (`perf-NoteTreeRow.swift-ee7`)
  Status: Fixed (commit fa67926)
  Suggested fix: Replace with `vault.index.note(at: node.id)`.

- **P2** `Sources/Features/Editor/QuickSwitcher.swift:150` — `groups` is a computed property evaluated at least twice per render: once by `list` (`groups.allSatisfy`) and again by `rows` (`ForEach(groups)`). Each evaluation can run `vault.index.search(...)` over the whole index, and in the heading branch `headingGroups` calls `vault.noteText(at:)` — which falls through to a synchronous `session.read` disk read for a note that is not an open tab — plus a full `NoteOutline.entries(in:)` parse. So a `#` query does two disk reads and two full parses per keystroke render. (`perf-QuickSwitcher.swift-a18`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Evaluate `groups` once into a `let` inside `body` and pass it to `list`/`rows`/`choose`, or cache it in `@State` updated `onChange(of: query)`.

- **P2** `Sources/Features/Editor/VaultBrowser.swift:252` — `vault.index.unresolvedLinks()` walks the entire backlink index, materialises every unresolved target with its source records, and sorts the whole result with `localizedStandardCompare` — and then only the first 10 are used. It sits in a view-builder property, so the full scan and locale sort re-run on every inspector body evaluation, which is every keystroke while the inspector is open. (`perf-VaultBrowser.swift-dd0`)
  Status: SKIPPED
  Suggested fix: Cache the unresolved-link list in `@State` refreshed on `vault.scanGeneration`, or add a limited variant on the index that avoids the whole-set locale sort.

- **P2** `Sources/Features/Pratiche/AttachmentChip.swift:33` — `body` triggers at least three synchronous `FileManager.fileExists` stat syscalls per chip per render: `symbol` (line 36), `isMissing` -> `previewURL` (line 39) and `helpText` -> `previewURL` (line 46) each call `fileExists` independently. In a pratica timeline with many messages and several attachments each, every SwiftUI re-render issues that many filesystem stats on the main thread. (`perf-AttachmentChip.swift-09a`)
  Status: SKIPPED
  Suggested fix: Resolve the existence check once per body into a `let exists = fileExists(...)` (or a single precomputed `AttachmentChipModel.State`) and derive symbol, missing flag, help text and targets from it.

- **P2** `Sources/Features/Pratiche/PraticaTimelineView.swift:41` — `entries` is a computed property re-running `PraticheController.filteredTimeline` (a full filter with a per-row `trimmingCharacters` allocation in `matchesText`) on every access. Besides `body` and `sections`, it is read from `following(_:)`, which is called while building each row's context menu and then does a linear `firstIndex` — making menu construction O(n²) in the number of timeline rows. (`perf-PraticaTimelineView.swift-c8b`)
  Status: SKIPPED
  Suggested fix: Compute the filtered array once per body (or cache it on the controller when `timeline`/`filter` change) and thread it into `sections`/`following(_:)`; hoist the needle trim out of `matchesText`.

- **P2** `Sources/Features/Recordings/RecordingsController.swift:562` — `saveDraft` is called from ReviewSheet on every checkbox toggle and every keystroke of a speaker-rename TextField (ReviewSheet.swift:342/360). Each call does a full read-modify-write of plaud-drafts.json: `store.loadDrafts()` reads and JSON-decodes the whole file, then `saveDrafts` re-encodes and atomically writes it — synchronous disk I/O on the main actor per character typed. (`perf-RecordingsController.swift-8f0`)
  Status: SKIPPED
  Suggested fix: Keep the decoded drafts dictionary in memory on the controller/store and write only the mutated entry; the per-keystroke `loadDrafts()` read is pure redundancy.

- **P2** `Sources/Features/Workspace/BoardContentLayer.swift:195` — `cardBody` passes `workspace.subfolder(for: node)` to every NodeCard; that helper performs a synchronous `FileManager.fileExists(atPath:isDirectory:)` stat. It runs for every visible node on every board redraw (pan, zoom, selection change), i.e. hundreds of main-thread stat syscalls per frame. `selectedFileURLs` documents exactly this cost and guards against it; this path does not. (`perf-BoardContentLayer.swift-85c`)
  Status: SKIPPED
  Suggested fix: Resolve the folder-ness of file nodes once per document load/scan into a cached `[nodeID: Bool]` on WorkspaceController and read that from the body.

- **P2** `Sources/Features/Workspace/WorkspaceBrowser+Tree.swift:58` — `rebuild()` calls `canvasStore.allBoards()` and then `canvasStore.allFolders()`; each delegates to the same private `walk()`, so the entire vault directory tree is enumerated twice per scan generation, despite CanvasStore's own comment stating "One walk, both answers, because they are the same walk". (`perf-WorkspaceBrowser+Tree.swift-17e`)
  Status: Fixed (commit ad8a2e3)
  Suggested fix: Expose a single combined accessor on CanvasStore (e.g. `foldersAndBoards() -> (folders: [String], boards: [String])` returning `walk()`) and call it once here.

- **P2** `Sources/Index/IndexSnapshot.swift:171` — `allTasks` is a computed property that sorts both `notes.values` and `boardTasks.values` and flatMaps every task on each access, and it is the single aggregation point every task query reads (tasks(for:on:), rolledOverTasks, dueTasks, dueDays, tasks(linkingTo:), tasks(assignedToWorkspace:)). View bodies call those queries several times per redraw (DayReferences reads it 4x, TodayView's dueDays once more, TaskViewSidebar 6x), so the whole vault's task list is rebuilt and re-sorted many times per frame. (`perf-IndexSnapshot.swift-2f0`)
  Status: SKIPPED
  Suggested fix: Materialise the sorted task list once as a stored property rebuilt in `replaceAll(with:)`/`update(_:at:)` beside `rebuildDerivedIndexes()`, and have `allTasks` return it.

- **P2** `Sources/Index/IndexSnapshot.swift:348` — `taskCounts(on:rolloverDays:)` calls `tasks(for:on:)` once per TaskView case plus `rolledOverTasks`, and each of those rebuilds `allTasks` and re-filters `state.isOpen` from scratch — six full passes over every task in the vault. It is called straight from `TaskViewSidebar.body` (TaskViewSidebar.swift:20), so this happens on every sidebar redraw. (`perf-IndexSnapshot.swift-c21`)
  Status: SKIPPED
  Suggested fix: Compute the open-task array once inside `taskCounts` and derive the five counts from that single array instead of calling `tasks(for:on:)` per case.

- **P2** `Sources/Index/IndexSnapshot.swift:358` — `daysBetween(_:_:)` constructs a fresh `Calendar(identifier: .gregorian)`, sets its time zone and builds two `DateComponents` dates on every call. It is invoked from inside the filter closures of `rolledOverTasks`, `dueTasks` and the `.upcoming` view, i.e. once per task in the vault per query, and those queries run per redraw. (`perf-IndexSnapshot.swift-d9e`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist the calendar to a `private static let gmtCalendar: Calendar` built once, and use it inside `daysBetween`.

- **P2** `Sources/Vault/NoteStore.swift:79` — `read(_:)` always derives the full `NoteRecord` (frontmatter parse, wikilink scan, embed scan, task scan, SHA-256 of the whole file), but many hot callers discard it and use only `text`: `VaultSession.search`, `unlinkedMentions`, `violations(forRecordAt:)`, `NoteFileOperations.rename`/`danglingLinks`/`trash`, `BoardFileOperations.renamePlan`, `tagRenamePreview`. A vault-wide search therefore hashes and parses every note for nothing. (`perf-NoteStore.swift-ce3`)
  Status: SKIPPED
  Suggested fix: Add a `func text(_ relativePath: String) throws -> String` on `NoteStore` (read + UTF-8 decode only) and point the `let (_, text) = try? read(...)` call sites at it.

- **P2** `Sources/Vault/NoteStore.swift:93` — `read(_:)` parses the note twice: `NoteDocument.parse(text)` for the frontmatter, then `linkTargets(in:)` parses the same text again. Each parse does `text.components(separatedBy: "\n")` plus a `joined` of the body, so every note read allocates two full line arrays and two body copies. This runs once per note on a cold scan and once per note on every full-text search. (`perf-NoteStore.swift-bf6`)
  Status: SKIPPED
  Suggested fix: Parse once: `let document = NoteDocument.parse(text)` and add `static func linkTargets(in document: NoteDocument)` so the record uses `document.frontmatter` and the same document for the link walk.

- **P2** `Sources/Vault/VaultScanner.swift:126` — `boardTaskRecord(at:...)` reads each `.canvas` file's bytes with `Data(contentsOf:)` and then calls `store.load(board:)`, which does a `fileExists` check and reads the same file again. Every board in the vault is read from disk twice on each scan that cannot reuse its cached board entry. (`perf-VaultScanner.swift-daa`)
  Status: Fixed (commit fa67926)
  Suggested fix: Read the bytes once and decode from them: `let document = try? CanvasDocument(data: data)` instead of the second `store.load(board:)` round-trip.

- **P2** `Sources/Vault/VaultSession+Move.swift:79` — A batch move dispatches one file operation per item, and each of `moveNote`/`moveBoard`/`moveFolder` calls its own `*Plan`, which calls `repointBoardsPlan` → `CanvasStore.allBoards()`: a full recursive vault enumeration plus `Data(contentsOf:)` and a JSON decode/encode of *every* `.canvas` in the vault. A drag of N rows costs N full vault walks and N × (board count) JSON round-trips. (`perf-VaultSession+Move.swift-2a6`)
  Status: Deferred — report-only
  Suggested fix: Needs design: the per-item plan re-reads disk because earlier moves changed it. Consider computing the board-repoint set once for the whole batch and applying prefix substitutions in memory, or caching `allBoards()` per batch and invalidating only on folder moves.

- **P2** `Sources/Vault/VaultSession+TagRename.swift:115` — `journal.entry(id:)` is called inside a loop over `ids`, and each call runs `WriteJournal.entries()`, which re-reads the whole `journal.jsonl` file and JSON-decodes every line. Undoing N journalled writes reads and decodes the entire journal N times. (`perf-VaultSession+TagRename.swift-c08`)
  Status: Fixed (commit fa67926)
  Suggested fix: Read once outside the loop: `let byID = Dictionary(journal.entries().map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })`, then look up `byID[id]`.

- **P3** `Sources/Connector/VaultPratiche.swift:299` — `isoString` builds a new `ISO8601DateFormatter` for every timeline row (every message file plus every manual entry of a pratica). The file's own comment ties the per-call construction to `ISO8601DateFormatter` lacking a `Sendable` conformance, so any shared-instance fix crosses the concurrency boundary and is reported rather than auto-fixed per the dimension guard. (`perf-VaultPratiche.swift-cf2`)
  Status: Deferred — report-only
  Suggested fix: Report only. If addressed, prefer hoisting one formatter into `timeline(...)` and threading it into the two row builders, rather than introducing a `nonisolated(unsafe)` static.

- **P3** `Sources/Core/Pratiche/MessageDocument.swift:185` — `isoString` (line 185) and `isoDate` (line 192) each construct an `ISO8601DateFormatter` per call; `parse` calls `isoDate` twice per message file and rendering calls `isoString` per date field. Sharing an instance would require a `nonisolated(unsafe)` static under strict concurrency, so this falls under the report-only guard. (`perf-MessageDocument.swift-9a2`)
  Status: Deferred — report-only
  Suggested fix: Report only. A safe fix is a per-call-site hoist (one formatter reused across the fields of a single parse) rather than a shared mutable static.

- **P3** `Sources/MCPServer/VaultHost.swift:45` — `call(_:)` performs `await session.rescan()` before every tool invocation, including read-only tools that only consult the in-memory index (`vault_stats`, `list_notes`, `note_backlinks`). Each call therefore pays a full vault enumeration plus a cache load/save, even when nothing changed. (`perf-VaultHost.swift-bbb`)
  Status: Deferred — report-only
  Suggested fix: Consider rescanning only for tools whose answer depends on disk freshness, or throttling by elapsed time — touches the async call path, so report only.

- **P3** `Tests/ReleasePipelineTests.swift:189` — `run(executable:arguments:currentDirectory:)` drains stdout and stderr only after `waitUntilExit` has returned. If a spawned script ever writes more than the ~64 KB pipe buffer the child blocks on write, the process never exits, and the suite stalls for the full 60 s watchdog before throwing — per subprocess, on a suite that runs every turn. The inline comment acknowledges the constraint but nothing enforces it as output grows (e.g. appcast.py --self-test gaining a verbose report). (`perf-ReleasePipelineTests.swift-2cd`)
  Status: Deferred — report-only
  Suggested fix: Drain both pipes concurrently while the process runs (readabilityHandler or a reader queue per pipe) before waiting on exit. Concurrency-sensitive: the helper already coordinates via DispatchQueue/DispatchSemaphore, so change it deliberately rather than as an optimisation.

- **P3** `Sources/Core/Email/HTMLTextReducer.swift:199` — `finished()` collapses blank runs with `while text.contains("\n\n\n") { text = text.replacingOccurrences(...) }`. Each iteration rescans and reallocates the whole document, and a run of k consecutive newlines needs roughly k/2 iterations — quadratic on a body with long blank stretches, which quoted email routinely has. (`perf-HTMLTextReducer.swift-2e5`)
  Status: Fixed (commit fa67926)
  Suggested fix: Collapse in one pass: split on newlines and rebuild, or use a single `replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)`.

- **P3** `Sources/Core/Email/QuoteSplitter.swift:67` — `attributionLine` calls `trimmed.lowercased()` inside the `endings.contains` closure, so a full-string lowercase copy is allocated up to five times for every line of the body. `separatorLine` additionally makes five independent full passes over the lines, each re-trimming every line, and `originalMessageLine` builds a `CharacterSet(charactersIn:)` per line. (`perf-QuoteSplitter.swift-2b8`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist `let lowered = trimmed.lowercased()` above the `endings.contains` closure; hoist the `CharacterSet` in `originalMessageLine` to a `static let`.

- **P3** `Sources/Core/Pratiche/MembershipRule.swift:89` — Inside rule 3's loop over `everyMessage(in: store)` (every message of every loaded conversation, followed or not), membership is tested with `dossier.conversations.contains(...)` and `autoFollowed.contains(...)`, both linear scans over `[Int]` arrays, the second over an array that grows as the loop runs. (`perf-MembershipRule.swift-1c6`)
  Status: Fixed (commit fa67926)
  Suggested fix: Build `let followed = Set(dossier.conversations)` before the loop and make `autoFollowed` accompanied by a `Set<Int>` for the membership test, appending to the array only for order.

- **P3** `Sources/Core/Pratiche/MessageDocument.swift:243` — `parse` calls `scalar(_:_:)` thirteen times (plus `list`, which calls it again), and each call is a full linear scan of the frontmatter lines that allocates two trimmed Strings per line examined. For every message file read during a sync dedup this is ~13×L scans and ~26×L String allocations where one pass would do. (`perf-MessageDocument.swift-938`)
  Status: SKIPPED
  Suggested fix: Build a `[String: String]` of top-level key→value in one pass over `lines`, then have `scalar`/`list` read from that dictionary.

- **P3** `Sources/Core/Search/SearchQuery+Matching.swift:64` — `matchesMetadata` builds the `noteTags` Set — lowercasing every frontmatter tag and every task tag of the note, twice over — unconditionally, even when `query.tags` and `query.negatedTags` are both empty, which is the common case for a plain word search across the whole vault. (`perf-SearchQuery+Matching.swift-296`)
  Status: Fixed (commit fa67926)
  Suggested fix: Guard the Set construction behind `if !query.tags.isEmpty || !query.negatedTags.isEmpty` before the two tag loops.

- **P3** `Sources/Core/Tasks/WorkspaceBoardResolver.swift:43` — `resolve` allocates a filtered array of every matching board just to branch on `hits.count`, scanning the full board list even after two hits are known, and `matches` re-lowercases `workspacePath` once per board examined. `TaskArrangement.byWorkspace` calls this once per task, so a list of T tasks over B boards pays T×B string lowercase allocations plus T array allocations. (`perf-WorkspaceBoardResolver.swift-de5`)
  Status: Fixed (commit fa67926)
  Suggested fix: Lowercase `workspacePath` once before the scan and short-circuit: iterate boards tracking the first hit, returning `.ambiguous` on the second.

- **P3** `Sources/Features/Editor/MarkdownAttributedText.swift:64` — The `.heading` case calls `ProseTypography.heading(level: level, theme)` twice for the same level (once for `.font`, once for the paragraph style's `font:`) and rebuilds the whole `base(theme:)` dictionary — itself another `prose(theme)` plus a fresh `NSParagraphStyle` — just to read `[.paragraphStyle]`. `attributes(for:theme:)` is invoked once per styled span by `applyStyling` on every keystroke, so these font-descriptor resolutions and `NSColor(Color)` conversions are re-done hundreds of times per pass. (`perf-MarkdownAttributedText.swift-64e`)
  Status: SKIPPED
  Suggested fix: Hoist the heading font into a single `let` reused by both `.font` and `paragraphStyle(font:)`, and pass the already-resolved base paragraph style in rather than rebuilding `base(theme:)` per span.

- **P3** `Sources/Features/Editor/MarkdownStyler.swift:737` — `taskMarker` builds `Array(after)` twice — allocating the whole remainder of the line as a `[Character]` array on each call — only to read indices 2 and 3. It also calls `line.count` and `after.count`, both O(n) on a `StringProtocol`. This runs once per line on every full styling pass, i.e. on every keystroke. (`perf-MarkdownStyler.swift-6fd`)
  Status: Fixed (commit fa67926)
  Suggested fix: Read the two characters without materialising an array, e.g. `let rest = after.dropFirst(2); guard let marker = rest.first, rest.dropFirst().first == "]"`, and replace the `count` comparisons with `dropFirst(n).isEmpty` checks.

- **P3** `Sources/Features/Editor/NoteHistorySheet.swift:82` — `HistoryGrouping.time(for:)` allocates a fresh `DateFormatter` on every call, and it is called from inside a row body (`NoteHistorySheet.swift:197`) inside a `ForEach`. `DateFormatter` construction is expensive relative to formatting, so this repeats per snapshot row per render. `title(for:...)` at line 72 has the same shape. (`perf-NoteHistorySheet.swift-502`)
  Status: No-op
  Suggested fix: Hoist the formatters into `static let` instances (one for `HH:mm`, one for `EEEE d MMMM`) and only mutate `calendar`/`locale` when they differ from the cached configuration.

- **P3** `Sources/Features/Editor/NoteListPane+FolderVerbs.swift:55` — `vault.index.allNotes.first { $0.relativePath == path }` sorts the entire vault with `localizedStandardCompare` and then scans it linearly, to fetch one record by path. The same pattern repeats at line 67 in `deleteSelection()`. `IndexSnapshot.note(at:)` is an O(1) dictionary lookup. (`perf-NoteListPane+FolderVerbs.swift-016`)
  Status: Fixed (commit fa67926)
  Suggested fix: Replace both occurrences with `vault.index.note(at: path)`.

- **P3** `Sources/Features/Editor/RankableEntry.swift:112` — `EntryRanking.aWord(of:startsWith:)` calls `text.lowercased()` and `split(whereSeparator:)` on every invocation, and `rank(startingWith:)` invokes it once for the title plus once per keyword of every catalogue entry — so a keystroke in the slash/emoji menu allocates roughly one lowercased copy and one split array per keyword across the whole catalogue. `fuzzyCloseness` additionally allocates `[rankingTitle] + keywords` per entry. (`perf-RankableEntry.swift-e05`)
  Status: SKIPPED
  Suggested fix: Precompute the lowercased word list per catalogue entry once (a stored `searchWords: [String]` on `EmojiEntry`/`EditorCommand`, or a lazily built static table) and match against it; iterate title and keywords without building a concatenated array.

- **P3** `Sources/Features/Pratiche/PraticaCommandActions.swift:649` — `contentsMatch` loads both attachment files fully into memory to compare them, which for large attachments is two full reads and two allocations even when the sizes differ and the answer is already known. (`perf-PraticaCommandActions.swift-e73`)
  Status: Fixed (commit fa67926)
  Suggested fix: Compare `resourceValues(forKeys: [.fileSizeKey])` first and return false on mismatch; fall back to the byte comparison only when sizes are equal (semantics unchanged).

- **P3** `Sources/Features/Pratiche/PraticheListColumn.swift:183` — `grouped` is a computed property performing the whole filter-plus-group-plus-two-sorts pipeline (`PraticheSidebarGrouping.grouped(filtered)`), and it is read four times per redraw: `grouped.open`, `grouped.closed.isEmpty`, `grouped.closed`, and `grouped.closed.count` in `closedRow`. (`perf-PraticheListColumn.swift-529`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Bind it once inside `list` (`let grouped = grouped`) and pass the halves down, the way TasksView+List.swift:12 already does for `rolled`.

- **P3** `Sources/Features/Recordings/PlaudQuote.swift:22` — `fingerprint(_:)` constructs `Locale(identifier: "en_US_POSIX")` on every call, and the function is called in loops: once per accepted task in `RecordingsController.fingerprints`, and once per task line of the note in `TranscriptNote.suppressionSet`. (`perf-PlaudQuote.swift-fd1`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist the locale to a `private static let posix = Locale(identifier: "en_US_POSIX")` and reference it in `folding(options:locale:)`.

- **P3** `Sources/Features/Tasks/LinkedTasksPanel.swift:23` — `body` calls `vault.index.tasks(linkingTo:)` directly, which rebuilds the whole-vault `allTasks` array and lowercases every task link on each redraw. The sibling surface, BoardTray, deliberately holds its result and refreshes it from `.task(id: vault.taskGeneration)` instead. (`perf-LinkedTasksPanel.swift-744`)
  Status: SKIPPED
  Suggested fix: Mirror BoardTray: hold the result in @State and refresh it from `.task(id: <taskGeneration, title>)` rather than querying per draw.

- **P3** `Sources/Features/Tasks/TasksView+List.swift:66` — `options` decodes the stored JSON preferences map on every read (`TaskListOptions.map(fromJSON:)` allocates a JSONDecoder and decodes the whole map), and it is read from `arrangedGroups`, from `optionsBinding`'s getter and from `list`'s controls on each redraw. (`perf-TasksView+List.swift-851`)
  Status: Fixed (commit ffd0a0e)
  Suggested fix: Decode once per body (`let options = options`) and pass it to `arrangedGroups`/`TaskListControls`, or cache the decoded map in @State keyed on `storedOptions`.

- **P3** `Sources/Features/Today/DayController.swift:136` — `span()` builds `Set(vault.index.allNotes.map(\.relativePath))` — `allNotes` localized-sorts the whole vault only for the sort to be discarded — and then passes the full task array to `WeekPlan.entries` for each of the 7 or 42 days, which filters all tasks twice per day (scheduled + due), i.e. up to 84 passes over every task in the vault per reload. (`perf-DayController.swift-eb2`)
  Status: Fixed (commit fa67926)
  Suggested fix: Look daily-note paths up with `vault.index.note(at:)` instead of building a Set from the sorted array, and bucket tasks by day once (`Dictionary(grouping:)`) before the per-day loop.

- **P3** `Sources/Features/Views/RenderedViewBlock.swift:52` — `block` is a computed property that runs the full `ViewBlock.parse(source)` grammar on every access, and it is read from `body` on each render as well as from `evaluate()`. In the editor-hosted attachment the body re-evaluates far more often than the fence text changes. (`perf-RenderedViewBlock.swift-8bc`)
  Status: SKIPPED
  Suggested fix: Cache the parse result in @State keyed on `source` (the same key `taskID` already uses) rather than re-parsing per render.

- **P3** `Sources/Features/Workspace/WorkspaceController+Gestures.swift:32` — `updateDrag(translation:)` rebuilds the snap-candidate array (`document.nodes.filter { !draggingIDs.contains($0.id) }.map(\.frame)`) on every drag tick, then `BoardGeometry.snapped` flatMaps it into 3n candidate edges. The document is explicitly not mutated during a gesture, so these frames are invariant for the whole drag. (`perf-WorkspaceController+Gestures.swift-4b4`)
  Status: SKIPPED
  Suggested fix: Compute the candidate frames once in `beginDrag` and store them in a transient property cleared by `endDrag`.

- **P3** `Sources/Index/IndexSnapshot+Search.swift:28` — `notes(carryingAll:)` allocates a fresh `Set` from every note's tag array inside the filter closure, so one full Set construction per note per call. The caller (TagBrowserView's `notes`) reads it several times per redraw. (`perf-IndexSnapshot+Search.swift-716`)
  Status: Fixed (commit fa67926)
  Suggested fix: Replace with `tags.allSatisfy { record.frontmatter.tags.contains($0) }` (tag lists are tiny) to avoid the per-record Set allocation.

- **P3** `Sources/Vault/NoteFileOperations.swift:34` — `CharacterSet(charactersIn: "/")` is constructed inside the per-board loop of `boardPaths()`. The same throwaway `CharacterSet` is also rebuilt on every call of `FolderFileOperations.normalized` (line 376), `BoardFileOperations.normalized` (line 300) and `VaultController.canOperateOnFolder` (line 22), all of which run in loops over notes or boards. (`perf-NoteFileOperations.swift-a48`)
  Status: Fixed (commit 563083c)
  Suggested fix: Declare one `private static let slashes = CharacterSet(charactersIn: "/")` (or trim with `hasPrefix`/`hasSuffix` on the string) and reuse it at all four sites.

- **P3** `Sources/Vault/NoteStore.swift:139` — `hash(_:)` formats each of the 32 digest bytes with `String(format: "%02x", $0)` and joins them, allocating 32 intermediate strings per hash. Hashing runs on every note read and every write. `ThumbnailStore.cacheKey` (ThumbnailStore.swift:126) uses the identical pattern per thumbnail lookup. (`perf-NoteStore.swift-026`)
  Status: Fixed (commit fa67926)
  Suggested fix: Build the hex string without per-byte `String(format:)`, e.g. reduce into a preallocated `String` using a static hex-digit table.

- **P3** `Sources/Vault/VaultController+Files.swift:19` — `canOperate(on:)` builds two intermediate arrays (`flatMap` over every column's tabs, then `filter`) only to test whether the result is empty. (`perf-VaultController+Files.swift-ab0`)
  Status: Fixed (commit fa67926)
  Suggested fix: Replace with a short-circuiting predicate: `guard !columns.contains(where: { $0.tabs.contains { $0.note.relativePath == relativePath && $0.note.hasUnsavedChanges } }) else { ... }`.

- **P3** `Sources/Vault/VaultController+Tabs.swift:136` — `show(_:)` calls `rememberTabs()` twice when it reuses the preview tab: once at the end of the `if` branch and again unconditionally after the `if/else`. Each call rebuilds the whole `OpenTabsStore.Session`, JSON-encodes it and writes it to `UserDefaults`, so the work is done twice on every single-click note open. (`perf-VaultController+Tabs.swift-b67`)
  Status: Fixed (commit fa67926)
  Suggested fix: Remove the `rememberTabs()` inside the `if` branch (line 127) and keep only the trailing one.

- **P3** `Sources/Vault/VaultScanner.swift:67` — `Set(keys)` is rebuilt inside the enumeration loop, once per file in the vault. The same pattern is repeated in `CanvasStore.walk()` (line 195) and `FolderFileOperations.walk(_:)` (line 112). (`perf-VaultScanner.swift-7f0`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist `let keySet = Set(keys)` above the `while` loop in all three walks and pass `keySet`.

- **P3** `Sources/Vault/VaultScanner.swift:178` — `relativePath(of:under:)` recomputes `root.standardizedFileURL.path(percentEncoded: false)` on every call, and it is called once per file during the vault scan, once per entry in `CanvasStore.walk()`, and once per path in `VaultWatcher.handle`. The root does not change during a walk. (`perf-VaultScanner.swift-a0b`)
  Status: SKIPPED
  Suggested fix: Add an overload taking a pre-computed `rootPath: String` and compute the standardized root once per walk, keeping the current signature as a thin wrapper.

- **P3** `Sources/Vault/VaultScanner.swift:196` — `isUnchanged(_:at:)` re-queries `url.resourceValues(forKeys:)` for size and modification date even though the scan loop already fetched both into `values` a few lines earlier, allocating a fresh `Set<URLResourceKey>` and `URLResourceValues` for every cached file in the vault. (`perf-VaultScanner.swift-a99`)
  Status: Fixed (commit fa67926)
  Suggested fix: Pass the already-read `values` into the check: call the static `isUnchanged(_:size:modifiedAt:)` with `values?.fileSize`/`values?.contentModificationDate` from the loop.

- **P3** `Sources/Vault/VaultSession+Files.swift:102` — The `folders` computed property rebuilds the whole folder set on every access, and for each path component it calls `accumulated.joined(separator: "/")`, re-allocating the prefix string from scratch at each depth level (quadratic in path depth). It is read through `VaultController.folders` by the folder pickers, so it can run repeatedly during view evaluation. (`perf-VaultSession+Files.swift-edc`)
  Status: Fixed (commit fa67926)
  Suggested fix: Accumulate the prefix incrementally (`prefix = prefix.isEmpty ? c : prefix + "/" + c`) instead of `joined` per component, and consider caching the result against `scanGeneration`.

- **P3** `Sources/Vault/VaultSession+Journal.swift:78` — `moveFile` reads the moved file twice: `Data(contentsOf: destination)` to compute the hash, then `store.read(newPath)` which reads the same bytes again, re-parses the note and hashes it a second time. This runs for every note carried by a rename or a batch move. (`perf-VaultSession+Journal.swift-462`)
  Status: SKIPPED
  Suggested fix: Derive the record from the single read (or reuse the hash already computed) instead of a second `store.read(newPath)` round-trip.

- **P3** `Sources/Vault/VaultSession+Starred.swift:37` — `moveStar` writes the whole starred-paths file (JSON encode + atomic write) once per moved note. It is called in a loop over `outcome.movedNotes` by `renameFolder` (VaultSession+Folders.swift:29) and by the batch move (VaultSession+Move.swift:102), so a folder holding many starred notes rewrites the same small file once per note. (`perf-VaultSession+Starred.swift-4d9`)
  Status: SKIPPED
  Suggested fix: Add a batch door (e.g. `moveStars(_ pairs: [MovedNote])`) that mutates the set for every pair and calls `starredStore.save` once.

- **P3** `Sources/Vault/VaultSession.swift:196` — `write(_:to:)` re-reads the file it has just written (`store.read(relativePath)`) to refresh the index, re-parsing the frontmatter, links, embeds and tasks and re-hashing bytes that are already in memory as `text` (the hash was even returned by `store.write`). This is a redundant disk read plus full parse on the main actor for every save. (`perf-VaultSession.swift-11e`)
  Status: Deferred — report-only
  Suggested fix: Build the record from `text` and the hash `store.write` returned, fetching only `modifiedAt` from the file attributes; verify the watcher's self-write hash contract still holds before applying.

- **P3** `Sources/Vault/VaultSession.swift:246` — `rescan()` constructs `IndexCache(url: cacheURL)` twice in consecutive statements, so the cache store is opened and read twice per scan (once for note entries, once for board-task entries), synchronously on the main actor before the detached scan starts. (`perf-VaultSession.swift-447`)
  Status: Fixed (commit fa67926)
  Suggested fix: `let cache = IndexCache(url: cacheURL)` once, then `cache.load()` and `cache.loadBoardTasks()`.

- **P3** `Sources/Vault/WriteJournal.swift:161` — `makeID(at:)` allocates a new `DateFormatter` on every call. It is called on every journalled write, on every `transaction`, and on every note-history snapshot (`NoteHistory.fileName`). `DateFormatter` construction is expensive and `NoteHistory` already caches one statically for the inverse parse. (`perf-WriteJournal.swift-842`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist a `private static let idFormatter: DateFormatter` (same `yyyyMMdd-HHmmss`, `.current` time zone) and reuse it, mirroring `NoteHistory.idDateFormatter`.

- **P3** `Tests/PraticheIsolationTests.swift:108` — `strippingCommentsAndStringLiterals` compiles three `NSRegularExpression` objects on every invocation, and the helper is called once per scanned .swift file (line 54-55 inside the enumerator loop). With 32 files under Sources/Connector, Sources/CLI and Sources/MCPServer that is ~96 regex compilations per run, repeated on every turn because the suite runs through `.claude/test-cmd`. Regex compilation is the classic hoistable allocation. (`perf-PraticheIsolationTests.swift-cbd`)
  Status: Fixed (commit 563083c)
  Suggested fix: Hoist the three patterns into a `private static let strippingRegexes: [NSRegularExpression]` compiled once, and iterate that array inside the helper.

- **P3** `Tests/SharedSourcesPurityTests.swift` — Both tests in this suite independently enumerate the tree and read every .swift file into a String: `noGuardedSharedSourceFileImportsSparkle` reads 195 files across seven directories, `noCoreOrConnectorFileImportsAppKitOrSwiftUI` re-reads 109 of those same files. Sources/Core and Sources/Connector are therefore fully read twice per run, and the sibling guards (PlaudIsolationTests reads all ~510 files / 4.1 MB of Sources, PraticheIsolationTests re-reads the connector dirs) repeat the walk again — all on every turn via `.claude/test-cmd`. (`perf-SharedSourcesPurityTests.swift-91f`)
  Status: SKIPPED
  Suggested fix: Introduce one `static let` cache of `[URL: String]` for the scanned Swift sources (thread-safe lazy init via swift_once) and have both tests — ideally the sibling isolation suites too — consult it instead of re-enumerating and re-reading.

- **P3** `Tests/SharedSourcesPurityTests.swift:84` — The AppKit/SwiftUI import check builds two full intermediate arrays per source file: `components(separatedBy:)` splits the whole file, `.map` allocates a second array of trimmed copies, `.filter` a third, and only then `.contains` short-circuits. Run over 109 files under Sources/Core and Sources/Connector (~760 KB), this allocates tens of thousands of throwaway String instances for a predicate that could stop at the first match. (`perf-SharedSourcesPurityTests.swift-21e`)
  Status: SKIPPED
  Suggested fix: Collapse the chain into one lazy pass: `contents.split(separator: "\n", omittingEmptySubsequences: false).contains { let t = $0.trimmingCharacters(in: .whitespaces); return !t.hasPrefix("//") && (t == "import AppKit" || t == "import SwiftUI") }`.

- **P3** `UITests/WorkspaceOpenStateUITests.swift:116` — Every row lookup builds a fresh `app.descendants(matching: .any)` query over the whole application hierarchy, and `tree`/`selectedRowsInTree` are computed properties so `assertExactlyOneRowSelected` re-resolves the `workspace-tree` query twice per call. Each unscoped `.any` descendants query forces a full accessibility-tree snapshot; with 13 tests and several lookups per test this is pure repeated work, not extra coverage. (`perf-WorkspaceOpenStateUITests.swift-846`)
  Status: SKIPPED
  Suggested fix: Cache `tree` in a stored lazy property and scope tree-row lookups to it (`tree.descendants(...)`) instead of `app.descendants(matching: .any)`; keep the app-wide query only for the `canvas-node-*` card lookups that live outside the tree.

- **P3** `docs/design/pratiche/support.js:380` — `encodeCase` compiles nine `new RegExp(...)` objects inside a loop over `RAW_WRAP` on every call, and it is called from `compileTemplate`, which re-runs on each `updateHtml` (i.e. per streaming chunk). The patterns are constant, so the regex compilation is redundant recomputation. (`perf-support.js-1e7`)
  Status: Deferred — report-only
  Suggested fix: Precompute the nine `[RegExp, replacement]` pairs once at module scope. Note the file header says it is generated from `dc-runtime/src/*.ts`, so the change belongs upstream, not here.

- **P3** `scripts/mcp-smoke.py:107` — The stderr drain thread uses a list comprehension, so it accumulates one `None` per line read for the whole life of the server process instead of discarding them. The allocation grows unbounded with however much the MCP server logs, for a value nobody reads. (`perf-mcp-smoke.py-a69`)
  Status: SKIPPED
  Suggested fix: Drain without building a list, e.g. a small named function with `for _ in self.process.stderr: pass`, or `collections.deque(self.process.stderr, maxlen=0)`.

### structure

Checkpoint: 944fca2

- **P1** `Sources/Features/Pratiche/PraticheController.swift` — 1575 lines — past the project's own SwiftLint *error* threshold of 1000 (`file_length` in .swiftlint.yml), the only file in the shard that reaches it. It holds five top-level types: `PraticheController` (class body 318 lines), `PraticaRowDetail`, `PraticaAttachmentRef`, `SyncRunQueue`, and a second @MainActor class `PraticaLiveSync` (lines 999-1506, body 337 lines) that is a complete sync driver unrelated to the pane's state. (`structure-PraticheController.swift-7e1`)
  Status: SKIPPED
  Suggested fix: Split into PraticheController.swift (class + its two pure extensions), PraticaRowModels.swift (PraticaRowDetail/PraticaAttachmentRef) and PraticaLiveSync.swift (SyncRunQueue + PraticaLiveSync).

- **P1** `UITests/WikilinkNavigationUITests.swift:47` — This UI-test file's launchArguments omit `-mailStoreRoot`, so `MailStoreLocation.resolve()` falls through to `~/Library/Mail/V10` and any pratiche sync a run triggers reads the operator's real Apple Mail store. CLAUDE.md states every UI-test file must pass the flag, not only the pratiche ones. It is the only one of the 21 UI-test files that misses it — a direct consequence of the setUp harness being copy-pasted per file rather than inherited. (`structure-WikilinkNavigationUITests.swift-db4`)
  Status: Fixed (commit 944fca2)
  Suggested fix: Add a per-test temporary `mailStoreRoot` directory (as ComposerUITests does) and pass `"-mailStoreRoot", mailStoreRoot.path(percentEncoded: false)` in launchArguments, removing it in tearDown.

- **P2** `Sources/Core/Conventions/NoteExport.swift:138` — `MarkdownHTML.render` is a second, independent markdown grammar in Core: a 68-line single function (SwiftLint function_body_length + cyclomatic 11) re-parsing fences, headings, tables, quotes, lists and paragraphs, plus its own inline pass, while `MarkdownBlockParser` and `MarkdownInlineParser` already parse the same dialect. The two have drifted: the exporter's `inline(_:)` handles `**`, `*`, code, links and wikilinks but not `~~strikethrough~~`, which MarkdownInlineParser supports. (`structure-NoteExport.swift-c0f`)
  Status: Deferred — high-risk
  Suggested fix: Render HTML from `MarkdownBlockParser.blocks(in:)` + `MarkdownInlineParser.spans(in:)` so one grammar feeds the reading view and the exporter; pin current output with a golden-file test first.

- **P2** `Sources/Features/Editor/NoteTextView+Coordinator.swift:12` — `NoteTextView.Coordinator` is a god object: 31 mutable state fields declared in the first 150 lines and behaviour spread over 13 files (~2,270 lines of extensions) covering embeds, embed resize, transclusion, folding, tables, view blocks, reveal, list editing, matches, checkbox click and two caret-rescue subsystems. Every feature added since ADR-0018 has landed on the same object. (`structure-NoteTextView+Coordinator.swift-d95`)
  Status: Deferred — report-only
  Suggested fix: Group the per-feature state into owned sub-controllers (EmbedDecorations, TableDecorations, ViewBlockDecorations) held by the Coordinator; do not attempt this mechanically — it crosses TextKit delegate dispatch.

- **P2** `Sources/Calendar/CalendarService.swift` — 552 lines, the largest breach of the project's own `file_length: warning: 400` rule in this shard, and it holds five unrelated concerns: the CalendarEvent/CalendarReminder value types, the `[CalendarEvent]` extension, the `CalendarStore` protocol with its default implementation, the `CalendarAccess`/`CalendarError` enums and the 400-line `EventKitStore` EventKit implementation. (`structure-CalendarService.swift-d72`)
  Status: SKIPPED
  Suggested fix: Split into CalendarModels.swift (events, reminders, access, error), CalendarStore.swift (protocol + default impl) and EventKitStore.swift; no call-site change needed.

- **P2** `Sources/Core/Editor/ListContinuation.swift:228` — ListContinuation duplicates five private primitives verbatim from LineFormat.swift: `struct Line` (228 vs 110), `lines(in:)` (238 vs 126), `indentLength(on:in:)` (289 vs 253), `matches(_:in:at:limit:)` (377 vs 263) and `isDigit(_:)` (385 vs 271) - about 60 identical lines in two files of the same directory. A fix to NSString line-boundary handling has to be made twice or the two silently diverge. (`structure-ListContinuation.swift-f19`)
  Status: SKIPPED
  Suggested fix: Extract the shared line primitives into one internal type under Sources/Core/Editor (e.g. `TextLines`) and have both LineFormat and ListContinuation call it.

- **P2** `Sources/Features/Editor/NoteListPane.swift` — 636-line view with 18 `@State` properties, already spilling into two extension files, and holding five separable concerns: header/filter, starred section, folder tree vs flat list rendering, the `SelectionOutcome` collapse rule (~80 lines of pure logic), and the whole drag-and-drop move machinery (beginDrag/references/dropOnRoot/performMove). (`structure-NoteListPane.swift-b4a`)
  Status: SKIPPED
  Suggested fix: Move `SelectionOutcome`/`opening(from:to:tree:currentlyOpen:isComposingNote:)` into its own pure file and the move helpers into `NoteListPane+Move.swift`, leaving the view with rendering state only.

- **P2** `Sources/Features/Editor/NoteTextView+ViewBlocks.swift:54` — `applyViewBlocks` (89 lines) and `applyTables` (NoteTextView+Tables.swift:42, 66 lines) are the same ~60-line skeleton twice: hidesMarkup guard + clear, `text as NSString`, run loop calling `EditorDecorationDelegate.<x>Run(in:atParagraphStart:)`, `getParagraphStart`, marker append, paragraph walk filling a `lines`/`rows` set plus an offset->opening map, store lookup, `decorations.apply(...)`, change-guard, caret rescue. Only the recogniser, marker kind and store differ. (`structure-NoteTextView+ViewBlocks.swift-00b`)
  Status: SKIPPED
  Suggested fix: Extract one generic multi-paragraph block scanner (recogniser closure + marker kind) returning (openings, hiddenLines, openingOfLine); have applyTables and applyViewBlocks call it and keep only their store-specific tails.

- **P2** `Sources/Features/Editor/NoteTextView.swift:321` — `updateNSView` is 123 lines (73 code) and handles eight unrelated concerns in one pass: input push-down, spell check, readable width, text/caret resync, five styling passes, text insertion plus an inline query-builder anchor resolution (~35 lines), focus, find, replacements, match jump and scroll requests. (`structure-NoteTextView.swift-c97`)
  Status: SKIPPED
  Suggested fix: Split into named private steps (`syncText`, `applyDecorations`, `applyInsertion`, `applyNavigationRequests`) and move the `insertion.opensQueryBuilder` block into its own method on the Coordinator.

- **P2** `Sources/Features/Editor/VaultBrowser.swift:270` — `ConformanceText` — a 102-line pure Italian-wording enum — lives at the bottom of a SwiftUI view file, yet it is consumed by six other modules (DayController+TaskDrop, WorkspaceFolderSheets, NoteRowMenu, ViewBoardRenderer, WorkspaceView+Creation, NewNoteComposer) and referenced by doc comments in Sources/Vault. A shared, testable utility is reachable only by importing an editor screen. (`structure-VaultBrowser.swift-8ae`)
  Status: SKIPPED
  Suggested fix: Move `ConformanceText` into its own file (e.g. Sources/Core/Conventions/ConformanceText.swift or Sources/DesignSystem) and leave VaultBrowser.swift as a view.

- **P2** `Sources/Features/Pratiche/NuovaPraticaWizard.swift` — 485-line SwiftUI view mixing four step views with ~180 lines of non-view orchestration: Mail selection via AppleScript, `MailSeedLoader` calls on detached tasks, state-directory/Mail-root resolution, proposal loading, pratica creation and tag derivation. A `WizardState.swift` model already exists next to it but holds only data. (`structure-NuovaPraticaWizard.swift-ec2`)
  Status: SKIPPED
  Suggested fix: Move seedFromMailSelection/resolveSeed/loadProposals/performLoadProposals/performCreate/tags(for:) onto an observable wizard model, and split the four step views into their own files.

- **P2** `Sources/Features/Pratiche/PraticaCommandActions.swift:21` — `PraticaCommandActions` has a 483-line struct body (SwiftLint error threshold 350) in a 786-line file. Two unrelated layers live in one type: command dispatch/applicability (lines 33-300) and raw filesystem plumbing (lines 313-652: trash/restore, moveFiles, copyFiles, copyAttachments, reservedBaseName, contentsMatch, attachment-reference rewriting), plus two menu-rendering enums at the end. (`structure-PraticaCommandActions.swift-7cd`)
  Status: SKIPPED
  Suggested fix: Move lines 313-652 into PraticaFileOperations.swift (mirroring the existing NoteFileOperations/FolderFileOperations split) and PraticaMenuItems/MessageMenuItems into PraticaMenus.swift.

- **P2** `Sources/Features/Pratiche/PraticaSyncEngine.swift:20` — The `PraticaSyncEngine` actor spans 549 body lines in an 860-line file — 1.6x the SwiftLint type_body error threshold (350) and 2x the file_length warning. It carries six distinct concerns in one type: progress channel, store opening, folder context, per-message decoding, regeneration preview/commit, and attachment placement, each already fenced off by its own MARK. (`structure-PraticaSyncEngine.swift-186`)
  Status: SKIPPED
  Suggested fix: Split along the existing MARKs into PraticaSyncEngine+Progress.swift, +Decoding.swift and +Regeneration.swift extensions, keeping `sync(_:)` and the request/outcome types in the base file.

- **P2** `Sources/Features/Pratiche/PraticaSyncEngine.swift:331` — `prepare(_:request:reader:folder:)` is 184 source lines (135 excluding comments, over the 100-line error) with cyclomatic complexity 16. The MIME-part loop (attachment threshold/placement, inline-image decorative filter, cid: rewriting) is a self-contained ~60-line unit inside it, followed by unrelated file-naming and frontmatter assembly. (`structure-PraticaSyncEngine.swift-6c9`)
  Status: SKIPPED
  Suggested fix: Extract the `for (ordinal, part) in parts.enumerated()` body into a `decodeParts(...) -> (body: String, writes: [PreparedAttachment], links: [String], storeReferences: [...])` helper, and the frontmatter assembly into `document(for:)`.

- **P2** `Sources/Features/Pratiche/PraticheController.swift:1168` — `PraticaLiveSync.runExclusive(praticaPath:)` is 151 source lines (113 excluding comments, over SwiftLint's 100-line error) with cyclomatic complexity 18. It sequentially does five separable jobs: main-actor precondition gathering, off-actor store preparation, conversation-remap write-back into pratica.md, two-pass membership evaluation, then engine run + tray refresh. (`structure-PraticheController.swift-95b`)
  Status: SKIPPED
  Suggested fix: Extract `applyConversationRemap(_:to:)`, `resolveCandidates(dossier:prepared:onDisk:)` and `refreshTray(...)` as private methods; leave runExclusive as the orchestration skeleton.

- **P2** `Sources/Features/Today/MonthView.swift:124` — `menu(for column: DayColumn)` is byte-for-byte identical (26 lines, comment included) to WeekView.swift:135 — verified with diff. This is exactly the duplication CalendarDayMenuItems.swift was written to prevent; its own header says "One view rather than three copies is the whole point", yet only the bottom two entries were extracted and the four surrounding buttons were copied instead. (`structure-MonthView.swift-db1`)
  Status: Fixed (commit 944fca2)
  Suggested fix: Move the whole menu into a `DayColumnMenu` view (or extend CalendarDayMenuItems with the four navigation buttons) and have MonthView and WeekView both call it.

- **P2** `Sources/Features/Views/ViewBoardRenderer.swift:38` — The whole drop-feedback machine is duplicated with the Today feature: an identical three-field `Drop` struct (vs DayController.swift:57), an identical outcome-decoding block at lines 125-143 (vs DayController+TaskDrop.swift:26-44, differing only in the Italian prefix "Non scritto:"/"Non spostato:") and a ~16-line identical banner HStack at 156-174 (vs TodayView.swift:78-92). (`structure-ViewBoardRenderer.swift-c3e`)
  Status: SKIPPED
  Suggested fix: Hoist one `WriteDropOutcome` model plus a shared `DropBanner` view into a common file and have both the board renderer and the Today views consume it.

- **P2** `Sources/Features/Workspace/WorkspaceView.swift:11` — `WorkspaceView`'s struct body is 358 lines — over SwiftLint's 350 error threshold — in a 568-line file, despite the file's own header claiming the type is already split across four files. The base still carries the toolbar (68 lines), the board, the grid, the background gestures, QuickLook plumbing and import confirmation. (`structure-WorkspaceView.swift-f8e`)
  Status: SKIPPED
  Suggested fix: Move `toolbar(previewURLs:)` into WorkspaceView+Toolbar.swift and `board`/`grid`/`boardBackground`/`backgroundGesture` into WorkspaceView+Board.swift, following the file's existing extension convention.

- **P2** `Sources/Index/IndexCache.swift:116` — `save(_:boardTasks:)` is 74 source lines (65 excluding comments, over the 50-line warning) with complexity 11, and its two halves are near-identical: the notes INSERT loop (lines 130-157) and the boardTasks INSERT loop (lines 159-188) differ only in table name, entry type and error prefix. Any fix to the rollback/binding path has to be applied twice. (`structure-IndexCache.swift-dc5`)
  Status: SKIPPED
  Suggested fix: Extract a private generic `insertAll<E: Encodable>(into table: String, rows: [(path: String, entry: E)], database:) -> String?` and call it twice.

- **P2** `Sources/Vault/NoteFileOperations.swift:312` — `repointBoards(from:to:titleChange:into:)` (l.312-352) is a verbatim copy of `repointBoardsPlan(from:to:titleChange:)` (l.165-213): same board enumeration, same node switch, same `.file`/`.text` rewrite rules and even the same `includeQuotedRelated: false` comment. Only the tail differs (write to disk vs collect a FileChange). Two copies of the canvas-repoint rule must be edited in lockstep or a rename silently repoints cards through one path and not the other. (`structure-NoteFileOperations.swift-292`)
  Status: Fixed (commit 944fca2)
  Suggested fix: Make `repointBoards` call `repointBoardsPlan` and then apply the returned changes/failures into the outcome, leaving one implementation of the node-rewrite rule.

- **P2** `Tests/MarkupHidingTests.swift` — 1386 lines, the largest file in the shard, holding 13 `@Suite` types across 8 unrelated marker families (heading, emphasis, list, checkbox, strikethrough, link, rule, inline spans) plus the coordinator-level suites. Three of the suites are not about markup hiding at all: `ListMarkerRenderingComposition`, `EditorDecorationDelegateProseFaces` and `FoldedHeadingFragmentBadgeFont` cover ADR-0030 typography and have natural homes in ProseTypographyTests.swift / TypographyResolutionTests.swift. (`structure-MarkupHidingTests.swift-7e8`)
  Status: SKIPPED
  Suggested fix: Split per marker family (MarkupHidingLists/Checkboxes/InlineSpans etc.) sharing the `Frame`/`frames(...)` helper via one support file, and relocate the three ADR-0030 typography suites to the existing typography test files.

- **P2** `Tests/SharedSourcesPurityTests.swift:101` — `resolvedRepoRoot()` and its companion `private enum RepoRootResolutionError` are declared four times across the suite: SharedSourcesPurityTests.swift:101, ReleasePipelineTests.swift:203, PraticheIsolationTests.swift:120 and (as `resolvedSourcesRoot()`) PlaudIsolationTests.swift:50. The copies have already diverged — PraticheIsolationTests' own doc comment records the bug of a variant that returned `Sources` instead of the repo root. This is test infrastructure, not a per-file fixture, so the repo's declared "each test file keeps its own fixture copy" convention does not cover it. (`structure-SharedSourcesPurityTests.swift-903`)
  Status: SKIPPED
  Suggested fix: Move one `RepoRoot.resolve()` plus `RepoRootResolutionError` into a shared Tests/RepoRootSupport.swift (same precedent as Tests/MailStoreFixture.swift) and have all four suites call it; derive Sources/ by appending, never by a second resolver.

- **P2** `Tests/VaultTests.swift` — 714 lines covering eight unrelated subject areas in one file — Store, Scanner, iCloud-Drive vault (principle 6), Index, Fuzzy matching, Controller, Note creation and ADR-0037's `revealsInlineSpans` setting. The last section in particular is an editor-setting test living in the vault store's test file. The suite already has dedicated files for several of these concerns (SearchTests, IndexCacheTests, VaultSessionTests). (`structure-VaultTests.swift-b6d`)
  Status: SKIPPED
  Suggested fix: Split by MARK section into VaultStoreTests / VaultScannerTests / VaultIndexTests / VaultControllerTests / NoteCreationTests, and move the `revealsInlineSpans` section beside the other ADR-0037 tests.

- **P2** `Tests/VaultTests.swift:8` — `TemporaryVault`, the shared non-copyable on-disk vault fixture, is declared at the top of VaultTests.swift, a topic-specific test file. 37 test files across the suite depend on it, so they all implicitly depend on a file whose purpose is testing the vault store. The repo already has the right home shape for this (Tests/MailStoreFixture.swift, Tests/EmbedEditorTestSupport.swift, Tests/DayTestSupport.swift). (`structure-VaultTests.swift-3ac`)
  Status: SKIPPED
  Suggested fix: Move `TemporaryVault` (and the `sampleNote` literal if shared) into a new Tests/VaultTestSupport.swift; leave VaultTests.swift as a consumer like the other 36 files.

- **P2** `UITests/ComposerUITests.swift:26` — The ~20-line setUpWithError/tearDownWithError launch harness (temporary stateBase + mailStoreRoot creation, the five-flag launchArguments array, the three removeItem calls) is duplicated verbatim in all 21 files under UITests/. Adding a sixth isolation flag means editing 21 files, and the two drift defects already present (missing -mailStoreRoot, missing -disablePlaud) are exactly that failure mode. ComposerUITests is cited as the representative; the duplication is file-wide across the directory. (`structure-ComposerUITests.swift-866`)
  Status: SKIPPED
  Suggested fix: Extract a `PergamenumUITestCase: XCTestCase` base (or a `UITestHarness` helper in a new UITests/UITestSupport.swift) owning stateBase/mailStoreRoot creation, the flag array and teardown; let each suite supply only its own fixture via an overridable `makeVault()`.

- **P2** `UITests/PraticheUITests.swift:58` — This UI-test file's launchArguments omit `-disablePlaud`, the only one of the 21 UI-test files that does. The app therefore starts its Plaud polling against 127.0.0.1:3777 during the pratiche run, making the suite depend on whether a local plaud-service happens to be listening. Same copy-paste drift as the missing `-mailStoreRoot` elsewhere. (`structure-PraticheUITests.swift-d06`)
  Status: SKIPPED
  Suggested fix: Add `"-disablePlaud", "YES"` to the launchArguments array, matching every other UI-test file.

- **P3** `scripts/release.sh:44` — The release pipeline is ~270 lines of linear top-level code with only two tiny helpers (`fail`, `step`, plus `sparkle_tool`). Eleven distinct phases (branch/tree guards, preflight, generate/archive/export, bundle verification, notarization, stapling, packaging, EdDSA signing, GitHub release, appcast regeneration, feed propagation check) share one flat scope, so no phase can be run, tested or reasoned about in isolation and every variable is global. (`structure-release.sh-fd5`)
  Status: Deferred — report-only
  Suggested fix: Wrap each phase in a named function (preflight, build_and_export, verify_bundle, notarize, package, publish_release, publish_appcast, confirm_feed) called from a short `main`. Given this script ships releases and cannot be dry-run, treat as report-only unless a manual end-to-end release is planned to validate the refactor.

- **P3** `Sources/App/RootView.swift:9` — RootView's struct body spans 279 lines, over the project's `type_body_length` warning of 250. The type mixes sidebar-selection derivation (`currentItem`, `choose`, `sidebarVisibility`), window-place/history wiring, four sheet presentations and the whole split-view layout. (`structure-RootView.swift-c0b`)
  Status: SKIPPED
  Suggested fix: Extract the sidebar column and the sheet stack into their own small views (RootSidebar, RootSheets) or move the selection derivation into an extension file.

- **P3** `Sources/Connector/VaultWrites.swift:123` — `moveNote` (123) repeats `renameNote`'s (100) body almost exactly: the same empty-path guard, the same `FileMoveSummary` construction from the outcome's four fields, and the same `catch let refusal as FileOperationError { throw ConnectorError("\(refusal)") }` wrapper. Only the session call differs. (`structure-VaultWrites.swift-dd6`)
  Status: SKIPPED
  Suggested fix: Extract a private `fileMove(_ path: String, _ operation: () throws -> MoveOutcome) throws -> FileMoveSummary` and have both call it with their own session closure.

- **P3** `Sources/Core/Email/HTMLTextReducer.swift` — 442 lines over the 400 `file_length` rule, and four functions over the complexity threshold (96 = 11, 207 = 15, 250 = 13, 388 = 18). Four independent private types (HTMLToken, HTMLTokenizer, HTMLWalk, HTMLEntities) plus a String extension share one file. (`structure-HTMLTextReducer.swift-abe`)
  Status: SKIPPED
  Suggested fix: Move HTMLTokenizer, HTMLWalk and HTMLEntities into their own files under Sources/Core/Email, leaving HTMLTextReducer as the entry point.

- **P3** `Sources/Core/Email/HTMLTextReducer.swift:388` — `replacement(for:)` reaches cyclomatic complexity 18 purely because fifteen named HTML entities are spelled as switch arms before the numeric-reference fallback. The branching carries no logic, only data. (`structure-HTMLTextReducer.swift-6ef`)
  Status: SKIPPED
  Suggested fix: Replace the named-entity arms with a `static let named: [String: String]` lookup, keeping only the `#`/`#x` numeric fallback as control flow.

- **P3** `Sources/Core/Email/MailStoreReader.swift:365` — 412 lines, over the 400 `file_length` rule, because the SQLite reader also owns ~90 lines of filesystem path derivation: `emlxPath(forRow:)` (279) plus `mailRoot`, `mailboxDirectory`, `storeDirectory` and `fanOut` (365-412). That is EMLXLocator's concern - EMLXLocator.swift (119 lines) already documents itself as consuming this rule from here. (`structure-MailStoreReader.swift-27d`)
  Status: SKIPPED
  Suggested fix: Move the four private path helpers and `emlxPath(forRow:)` next to EMLXLocator (or into an EMLXPathRule type), leaving MailStoreReader to the queries.

- **P3** `Sources/Core/Pratiche/MessageDocument.swift` — 448 lines with a 314-line struct body, breaching both `file_length` (400) and `type_body_length` (250). One type carries three separable responsibilities: the frontmatter/body renderer (81-201), the parser and its hand-rolled YAML-flow codec (203-412), and the direction/counterpart rules (414-448). (`structure-MessageDocument.swift-3ab`)
  Status: SKIPPED
  Suggested fix: Split into MessageDocument.swift (the value type + direction/counterpart) plus MessageDocument+Render.swift and MessageDocument+Parse.swift extensions.

- **P3** `Sources/Core/Pratiche/MessageDocument.swift:264` — `splitTopLevel(_:)` (264) and `splitOutsideQuotes(_:on:)` (332) are the same quote-and-backslash-aware splitter written twice in one file; the first simply hard-codes `,` as the separator the second takes as a parameter. Two copies of one escaping rule that the comments already say must stay in step with `quoted(_:)`. (`structure-MessageDocument.swift-27f`)
  Status: SKIPPED
  Suggested fix: Delete `splitTopLevel` and call `splitOutsideQuotes(value, on: ",")` at its single call site.

- **P3** `Sources/Core/Pratiche/PraticaNaming.swift:64` — `PraticaNaming.truncated(_:toFit:)` is a verbatim copy of `ImportNaming.truncatedAtWordBoundary(_:toFit:)` (ImportNaming.swift:162) - 13 identical lines. Its own doc comment states it is "the same rule ImportNaming.recordingNoteTitle already applies", so the duplication is known but unresolved; both feed file names that are protected interfaces. (`structure-PraticaNaming.swift-942`)
  Status: SKIPPED
  Suggested fix: Move the word-boundary truncation into one shared helper (NoteName is the natural home) and have both naming types call it.

- **P3** `Sources/Core/URLScheme/PergamenumURL.swift:33` — `PergamenumRoute.init?(URL)` reaches cyclomatic complexity 17 - eight host cases each with their own nested query-validation branches in one initializer. The project keeps complexity rules on deliberately as a debt signal. (`structure-PergamenumURL.swift-ab3`)
  Status: SKIPPED
  Suggested fix: Give each host its own `private static func` returning `PergamenumRoute?` and let the init be a flat dispatch table over `host`.

- **P3** `Sources/DesignSystem/Theme.swift:318` — `Int.asFontWeight` (line 321) and `Int.asNSFontWeight` (line 338) duplicate the same nine-stop DTCG weight threshold table (..<150 … default) in two private extensions, differing only in the returned type. The two ladders can drift silently, giving SwiftUI and AppKit different weights for the same token. (`structure-Theme.swift-d64`)
  Status: SKIPPED
  Suggested fix: Map the Int to one canonical stop enum once, then translate that stop to Font.Weight and NSFont.Weight — one threshold table instead of two.

- **P3** `Sources/Features/DesignGallery/MockupScreens.swift` — 515-line file holding four unrelated full-screen mockups (EditorMockup M1, WorkspaceMockup M2/M3, TodayMockup M5, TasksMockup M4) — WorkspaceMockup alone spans lines 129-329. The rest of the DesignGallery directory uses one file per mockup, so this file breaks its own neighbourhood's convention. (`structure-MockupScreens.swift-4d0`)
  Status: SKIPPED
  Suggested fix: Split into EditorMockup.swift, WorkspaceMockup.swift, TodayMockup.swift and TasksMockup.swift, matching the sibling mockup files.

- **P3** `Sources/Features/DesignGallery/TabBarMockup.swift:77` — The private `scene(_ caption:_ content:)` caption-plus-content helper is copy-declared in 17 of the 23 DesignGallery files, and each mockup repeats the same page shell (ScrollView + VStack + .padding(theme.spacing(.l)) + .frame(maxWidth:alignment:.leading) + .background(theme.color(.backgroundPrimary))). (`structure-TabBarMockup.swift-dcb`)
  Status: SKIPPED
  Suggested fix: Add one `MockupPage` container view and a single shared `scene(_:_:)` (or a `.mockupScene(caption:)` modifier) in MockupGalleryView.swift, and delete the 17 private copies.

- **P3** `Sources/Features/Editor/CompletionPanel.swift:191` — `CompletionPanel` and `FormatBarPanel` each declare their own private `NeverKeyPanel: NSPanel` (identical two-override body) and their own `makePanel()` with the same eight-line configuration block (isFloatingPanel, level, backgroundColor, isOpaque, hidesOnDeactivate, animationBehavior, isReleasedWhenClosed, ignoresMouseEvents) and an identical `hide()`. (`structure-CompletionPanel.swift-602`)
  Status: SKIPPED
  Suggested fix: Extract one `NeverKeyPanel` type plus a `makeFloatingPanel(contentRect:hasShadow:)` factory (and a shared `hide()`), and have both panel hosts use it.

- **P3** `Sources/Features/Editor/EditorDecorationDelegate+CheckboxRendering.swift:28` — `checkboxParagraph`, `listParagraph` (ListRendering.swift:25) and `quoteParagraph` (QuoteRendering.swift:20) repeat the same ~10-line preamble: marker lookup by kind, `NSMaxRange(marker.range) <= range.length` guard, absolute markerRange arithmetic, a `stillSpells…` re-read against live text, then `NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))`. (`structure-EditorDecorationDelegate+CheckboxRendering.swift-552`)
  Status: SKIPPED
  Suggested fix: Extract a `markerCopy(at:storage:kind:)` helper returning (marker, markerRange, mutable copy) or nil, and let the three branches start from it.

- **P3** `Sources/Features/Editor/EditorDecorationDelegate+TableRendering.swift:30` — `tableParagraph(at:storage:)` and `viewBlockParagraph(at:storage:)` (EditorDecorationDelegate+ViewBlockRendering.swift:39) repeat the same ~20-line attachment substitution: marker lookup, live-text re-read via the run recogniser, mutable copy, `attachmentRange`/`restRange` arithmetic, replace with U+FFFC, attach, collapse the rest. Only the attachment type and recogniser differ, so the length arithmetic lives in two places. (`structure-EditorDecorationDelegate+TableRendering.swift-a75`)
  Status: SKIPPED
  Suggested fix: Extract a shared `attachmentParagraph(at:storage:markerKind:recognises:makeAttachment:)` helper and let both branches supply only the recogniser and the attachment factory.

- **P3** `Sources/Features/Editor/NoteTextView+Tables.swift:130` — `tableCaretRescue(in:rows:headers:)` and `viewBlockCaretRescue(in:lines:openings:)` (NoteTextView+ViewBlocks.swift:264) are byte-for-byte identical bodies differing only in parameter names — the doc comment itself calls them "twins" of `rescueCaret(in:from:)`, so the concept now has three copies. (`structure-NoteTextView+Tables.swift-a5b`)
  Status: SKIPPED
  Suggested fix: Extract one `caretRescue(in textView: NSTextView, hiddenLines: Set<Int>, anchors: [Int: Int]) -> Int?` on the Coordinator and call it from both sites.

- **P3** `Sources/Features/Editor/NoteTextView.swift:9` — `NoteTextView` exposes 37 stored inputs (bindings, values and 15 closure callbacks) on one NSViewRepresentable. The cost is visible at the single call site: `EditorColumn+Text.swift:46` `editing(_:)` is an 83-line initializer that does nothing but fill them in. (`structure-NoteTextView.swift-e7a`)
  Status: Deferred — report-only
  Suggested fix: Group related inputs into value structs (e.g. `FindInputs`, `OutlineInputs`, `EmbedInputs`) so the representable takes a handful of parameters instead of 37.

- **P3** `Sources/Features/Pratiche/PraticaCommandActions.swift:661` — `praticaNotePath(of:)` is a pure two-line naming rule but lives as a static member of a @MainActor SwiftUI command struct, so four unrelated layers reach up into the UI for it: DossierWriter.swift:24 (pure writer), PraticaEntryComposer.swift:43, NuovaPraticaWizard.swift:450 and PraticheController.swift:1214 (inside the detached sync path). `PraticaNaming` already exists in Sources/Core/Pratiche/ and is where this belongs. (`structure-PraticaCommandActions.swift-697`)
  Status: SKIPPED
  Suggested fix: Move `praticaNotePath` (and the `praticaFileName` constant it reads off PraticheController) into Sources/Core/Pratiche/PraticaNaming.swift and update the four call sites.

- **P3** `Sources/Features/Pratiche/PraticheController.swift:1438` — The "publish a Mail-store generation, open the Envelope Index, report one of three Italian failure sentences" block (17 lines) is duplicated verbatim in MailSeedPicker.swift:149-163, including the two error strings. The comments in both files acknowledge the twin without sharing the code, so a wording or recovery change has to be made in two places. (`structure-PraticheController.swift-bea`)
  Status: SKIPPED
  Suggested fix: Extract one `MailStoreAccess.openReader(mailRoot:stateDirectory:) -> Result<MailStoreReader, String>` helper beside MailStoreCopy and call it from both.

- **P3** `Sources/Features/Pratiche/PratichePane.swift:14` — The pane's struct body spans 293 lines (over the 250-line type_body warning) in a 382-line file, with a 76-line `body` at line 35 that inlines the three-column layout, the sheets and the toolbar wiring together. (`structure-PratichePane.swift-bb8`)
  Status: SKIPPED
  Suggested fix: Split the column layout and the sheet/dialog stack into computed properties or a PratichePane+Sheets.swift extension, mirroring the Workspace pane's shape.

- **P3** `Sources/Features/Recordings/RecordingsController.swift` — 612 lines, over the 400-line file_length warning. The type already uses two extensions but the base still combines loading, the polling/processing state machine (lines 163-282), the two-phase import (283-395) and delete (396-424) — four independently testable subjects in one file. (`structure-RecordingsController.swift-bef`)
  Status: SKIPPED
  Suggested fix: Move the polling/processing section and the two-phase import into RecordingsController+Processing.swift and +Import.swift, following the existing extension seams.

- **P3** `Sources/Features/Settings/EditorSettings.swift:47` — `body` is a single 110-line Form holding five unrelated settings groups (prose font picker, marker concealment, inline-span reveal, readable width, spell check with its language picker), each with its own binding and explanatory paragraph. Adding a sixth setting means editing the same 110-line expression. (`structure-EditorSettings.swift-11d`)
  Status: SKIPPED
  Suggested fix: Split into computed section properties (`fontSection`, `markupSection`, `widthSection`, `spellCheckSection`) and have `body` compose them.

- **P3** `Sources/Features/Workspace/BoardHandles.swift:22` — `ResizeHandleView`'s grip geometry (`visualSize`/`targetSize`) and its whole drawn body (RoundedRectangle + strokeBorder overlay + double frame + contentShape + cursor onHover) are duplicated in BoardCropEditor.swift:150-176 by `CropHandleView`, which differs only in the gesture attached and the missing onDisappear cursor pop. (`structure-BoardHandles.swift-5b2`)
  Status: SKIPPED
  Suggested fix: Extract a shared `BoardGripShape` view taking the gesture and position as parameters; have both handle views wrap it.

- **P3** `Sources/Features/Workspace/BoardTray.swift:89` — `traySection` takes 7 parameters (title, badge, accessibilityLabel, identifier, isEmpty, emptyText, rows), over the project's 5-parameter SwiftLint rule. Six of them are one section's static configuration. (`structure-BoardTray.swift-0f2`)
  Status: SKIPPED
  Suggested fix: Bundle the six non-builder parameters into a small `TraySectionStyle` struct, leaving `traySection(_ style:, @ViewBuilder rows:)`.

- **P3** `Sources/Features/Workspace/CardTextView.swift` — 508 lines, over the 400-line file_length warning, despite four +Fold/+ListEditing/+Reveal/+Teardown extension files already peeled off. The base still holds the representable, the full Coordinator and the styling pass. (`structure-CardTextView.swift-05d`)
  Status: SKIPPED
  Suggested fix: Move the Coordinator's styling pass into a CardTextView+Styling.swift extension, keeping makeNSView/updateNSView in the base file.

- **P3** `Sources/Features/Workspace/CardTextView.swift:359` — `Coordinator.applyStyling(to:)` is 66 lines with cyclomatic complexity 13 — it decides the span switch, the marker map, the reveal set and the paragraph styles in one pass, which is the routine most likely to need a targeted edit when a new marker kind is added. (`structure-CardTextView.swift-d6d`)
  Status: SKIPPED
  Suggested fix: Extract the marker-to-substitution mapping and the paragraph-style construction into two private helpers so the branch count drops below the project's complexity-10 rule.

- **P3** `Sources/Features/Workspace/FormattingTextView.swift:14` — 582-line file, 279-line class body (over the 250 warning). One NSTextView subclass carries six unrelated responsibilities: selection frames, inline/line format toggling, Return-inside-a-list, click-to-unfold, checkbox hit-testing, and the whole wikilink completion panel (lines 406-534). (`structure-FormattingTextView.swift-fd1`)
  Status: SKIPPED
  Suggested fix: Split into FormattingTextView+Wikilink.swift, +Clicks.swift (fold badge + checkbox hit-testing) and +Formatting.swift, mirroring the CardTextView+Fold/+ListEditing/+Reveal convention already used in this folder.

- **P3** `Sources/Features/Workspace/WorkspaceBrowser.swift:109` — `body` is 114 lines: the actual layout is 12 lines, the other ~100 are three inline presentation blocks (the create sheet, the rename sheet, the delete confirmationDialog) plus the move-conflict alert, each with its own closures. WorkspaceFolderSheets.swift already exists as the natural home for them. (`structure-WorkspaceBrowser.swift-ac5`)
  Status: SKIPPED
  Suggested fix: Extract the four presentation blocks into a `.workspaceBrowserPresentations(...)` ViewModifier or into WorkspaceFolderSheets, leaving body as layout plus one modifier.

- **P3** `Sources/Features/Workspace/WorkspaceController.swift:12` — 607-line file with a 273-line class body (over the 250 warning) even though ten +Extension files already exist for this controller. The remaining base still mixes the Tool enum (lines 12-165), navigation (166-370), editing (371-571) and saving (572-607). (`structure-WorkspaceController.swift-52b`)
  Status: SKIPPED
  Suggested fix: Move `Tool` into its own WorkspaceTool.swift and the Editing/Saving MARK sections into WorkspaceController+Editing.swift / +Saving.swift, matching the ten sibling extension files.

- **P3** `Sources/Vault/CanvasStore.swift:178` — Three copies of the same vault traversal skeleton exist (this `walk()`, FolderFileOperations.walk l.91-127, VaultScanner.scan l.56-108): same resource keys, same `skipsPackageDescendants` enumerator, same `values?.name ?? url.lastPathComponent` fallback, same `isExcludedDirectory` + `skipDescendants`, same relativePath call. The doc comments acknowledge the copying ("mirrors VaultScanner.scan()"), so an exclusion or path-normalisation fix has to land in three places. (`structure-CanvasStore.swift-5cb`)
  Status: SKIPPED
  Suggested fix: Extract one `VaultWalk.enumerate(root:) { url, isDirectory, relativePath in ... }` helper carrying the exclusion/skip rule, and have the three walks supply only their per-entry filter.

- **P3** `Sources/Vault/FolderFileOperations.swift:310` — The "apply a plan's noteChanges/boardChanges, collecting rewrittenPaths and failures" loop is copy-pasted six times: here (l.310, l.318), FolderFileOperations+Move.swift:119, BoardFileOperations.swift:160/170/284 and VaultSession+Files.swift:26/34/61. The copies have already drifted - the BoardFileOperations ones record failures but never append to rewrittenPaths. (`structure-FolderFileOperations.swift-895`)
  Status: SKIPPED
  Suggested fix: Extract one `apply(_ changes:[NoteFileOperations.FileChange], writer:)` helper returning (rewrittenPaths, failures) and call it from all six sites.

- **P3** `Sources/Vault/NoteFileOperations.swift:226` — `rename` (l.226-277) re-implements `renamePlan` (l.88-126): identical `NoteName.validate` guard, oldTitle/folder/fileName/newPath derivation, existence and collision guards, and knownPaths rewrite loop. Likewise `trash`'s tail (l.371-376) repeats `danglingLinks` (l.147-154) line for line, as its own doc comment admits. (`structure-NoteFileOperations.swift-97f`)
  Status: SKIPPED
  Suggested fix: Have `rename` compute `renamePlan` first and perform it (move file, then apply noteChanges/boardChanges); call `danglingLinks` from `trash` instead of repeating the filter.

- **P3** `Sources/Vault/VaultController.swift:4` — `import SwiftUI` in the vault layer with no SwiftUI symbol used anywhere in the file (only `Foundation`, `Observation` and `OSLog` types appear; the one `@State` occurrence is inside a comment). A UI-framework import under Sources/Vault is the exact dependency CLAUDE.md/ADR-0001 §D1 warns about: if this file were ever added to `sharedSources` it would break both the perg and pergamenum-mcp builds. (`structure-VaultController.swift-9c5`)
  Status: SKIPPED
  Suggested fix: Remove the `import SwiftUI` line; `Observation` already provides `@Observable`.

- **P3** `Sources/Vault/VaultScanner.swift:44` — `scan()` is 71 lines (64 non-comment) and mixes four concerns in one loop body: directory exclusion, `.canvas` board-task extraction with its own cache lookup, the iCloud-evicted-placeholder failure report, and the `.md` record read with its cache lookup. (`structure-VaultScanner.swift-c2e`)
  Status: SKIPPED
  Suggested fix: Split the per-entry work into `boardTaskRecord(for:)`, `evictionFailure(for:)` and `noteRecord(for:)` private helpers so `scan()` stays the enumeration plus three dispatches.

- **P3** `Sources/Vault/VaultSession+BoardDrop.swift:66` — The journal borrow-and-return block (capture `journalOnDisk`, snapshot entry ids, save/restore `journal` and `journalCommand` in a `defer`, then diff the ids to find the new entry) is duplicated verbatim in three places: here l.66-75, VaultSession+TaskDrop.swift:74-82 and VaultSession+TagRename.swift:67-76. `VaultSession+Journal.transaction` already exists as the gesture wrapper but arms only the command, not the on-disk journal. (`structure-VaultSession+BoardDrop.swift-ac4`)
  Status: SKIPPED
  Suggested fix: Add a `withJournalOnDisk(_ command: String, _ body:) -> [String]` helper beside `transaction` in VaultSession+Journal.swift and route all three call sites through it.

- **P3** `Tests/ConventionsTests.swift` — 810 lines and 72 top-level tests covering at least eight unrelated subjects in one file: tag validation/ordering, vocabulary closed families, ISO dates, frontmatter parse/round-trip/foreign keys, wikilink parsing and rendering, structural links, note-name validation and slugging, import naming, and the harness vocabulary importer. The largest file in the shard and the hardest to navigate when one convention changes. (`structure-ConventionsTests.swift-4b8`)
  Status: SKIPPED
  Suggested fix: Split by subject into TagConventionTests, FrontmatterTests, WikilinkTests, NoteNameTests, ImportNamingTests and VocabularyImportTests.

- **P3** `Tests/EmbedDrawingTests.swift:156` — Test-fixture duplication despite a shared support file existing for exactly this. `makeTempVaultRoot` appears twice inside this file (l.156 and l.247, differing only by the temp-dir prefix) and again in Tests/EmbedEditorTestSupport.swift:15 and Tests/EmbedResolutionTests.swift:28; `writeImage` is byte-identical across all three files, and three variants of `editor(text:root:thumbnails:)` exist. EmbedEditorTestSupport's own header says a copy in each suite is a copy that drifts. (`structure-EmbedDrawingTests.swift-048`)
  Status: SKIPPED
  Suggested fix: Delete the local copies and call `EmbedEditorFixtures.makeTempVaultRoot()` / `.writeImage(named:in:)` / `.editor(...)`, widening the shared fixture where a suite needs a variant.

- **P3** `Tests/MarkdownStylerTests.swift` — 662 lines across six independent construct families (heading marker, emphasis marker, fenced code blocks, embed run, list markers, ADR-0029 constructs), each accreted by a different ADR. Cohesive by type-under-test but well past the 400-line threshold, and the sections share no fixture that would be broken by a split. (`structure-MarkdownStylerTests.swift-ee1`)
  Status: SKIPPED
  Suggested fix: Split along the existing MARK boundaries into per-construct files (MarkdownStylerEmphasisTests, MarkdownStylerListTests, MarkdownStylerCodeFenceTests, ...).

- **P3** `Tests/PraticaSyncTests.swift:77` — 768-line file whose `PraticaSyncEngineTests` suite alone spans lines 77-633 (~557 lines), and which declares `makeEngine` twice (lines 88 and 649) because the second suite could not reach the first one's copy. A suite that long makes the fixture reuse invisible and forces exactly that kind of local re-declaration. (`structure-PraticaSyncTests.swift-53d`)
  Status: SKIPPED
  Suggested fix: Extract the shared engine/store fixture to file scope (or a PraticaSyncFixtures support file) and split PraticaSyncEngineTests into the per-concern suites its internal MARKs already imply.

- **P3** `Tests/TaskTests.swift` — 524 lines mixing parsing, task state, on-disk rewriting and the five task views in one file, while the shard already carries six sibling task test files (TaskMarkerTests, TaskMarkerWriteTests, TaskArrangementTests, TaskComposerTests, TaskCommandTests, TaskDropTests). The rewriting-on-disk section in particular duplicates the concern TaskMarkerWriteTests owns. (`structure-TaskTests.swift-6f0`)
  Status: SKIPPED
  Suggested fix: Move the "Rewriting" and "Task views and rewriting on disk" sections into TaskMarkerWriteTests / a new TaskViewTests, leaving TaskTests.swift for parsing and state.

- **P3** `docs/design/pratiche/support.js` — A 1911-line generated JavaScript bundle is committed under docs/, and its own header points the rebuild at `cd dc-runtime && bun run build` — a directory that does not exist anywhere in this repository. The artifact is therefore unmaintainable in-tree: it cannot be regenerated, reviewed or patched from this checkout, yet it is loaded by the mockup at `docs/design/pratiche/Pergamenum Pratiche.dc.html:6`. (`structure-support.js-0ab`)
  Status: Deferred — report-only
  Suggested fix: Either record the upstream source/version of `dc-runtime` beside the file (or vendor it under a `vendor/` path with a pinned version), or drop the local copy and load the runtime the mockup needs from its documented origin. No in-place refactor of the bundle itself.

- **P3** `scripts/appcast.py:141` — The eight appcast item fields (version, short_version, min_system, download_url, signature, length, notes_link, pub_date) are spelled out as a positional/keyword parameter list four separate times: `make_item`, `build_feed`, the `main` call site and the `_feed` self-test helper. Adding or renaming one field means four coordinated edits, and `build_feed` takes 10 parameters. (`structure-appcast.py-d86`)
  Status: SKIPPED
  Suggested fix: Introduce a small `@dataclass AppcastItem` (or NamedTuple) holding the eight fields; have `make_item(item)` and `build_feed(raw, feed_url, item)` take it, and build it once in `main`/`_feed`.

- **P3** `scripts/appcast.py:224` — `self_test()` is 63 lines holding five independent scenarios inline, two of which repeat the same try/except/else-to-capture-the-message idiom (cases 4 and 5) verbatim. It also mixes the assertions with tempfile writing and report printing in the same body. (`structure-appcast.py-0a8`)
  Status: SKIPPED
  Suggested fix: Extract a `_message_of(call)` helper for the two error cases and split each numbered scenario into its own `_case_N(report)` function, leaving `self_test()` as the sequence plus the printing.

- **P3** `scripts/install-cli.sh:25` — The same bootstrap prologue is copy-pasted across the shell scripts in this shard: the `REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` resolution plus identical `fail()`/`step()` helpers appear in install-cli.sh, release.sh and fetch-sparkle-tools.sh (uitests.sh carries its own third variant of `fail`). Four copies of the same three primitives, each with its own hardcoded message prefix. (`structure-install-cli.sh-11b`)
  Status: SKIPPED
  Suggested fix: Extract a `scripts/lib/common.sh` defining `REPO`, `fail` (prefix from `$(basename "$0")`) and `step`, sourced by each script; keep per-script behaviour identical.

- **P3** `scripts/mcp-smoke.py:167` — `writing()` is 70 lines and bundles six unrelated verification scenarios (tool listing, dryRun default, apply, journal + undo, time-block collision, non-conformant title refusal, capture with its three sub-cases). A failure anywhere leaves the rest of the stage unrun, and the function is the only one in the file over the 60-line limit. (`structure-mcp-smoke.py-314`)
  Status: SKIPPED
  Suggested fix: Split into focused helpers taking the already-open `Server` (e.g. `_write_and_undo(server, path)`, `_time_block(server)`, `_capture(server, vault)`) and have `writing()` call them in sequence inside the existing try/finally.

- **P3** `scripts/mcp-smoke.py:336` — The driver runs as bare module-level statements (binary lookup, per-stage temp vault loop, failure report, `sys.exit`) with no `main()` and no `if __name__ == "__main__"` guard, and results accumulate in a module-global `failures` list mutated by `check()`. The module cannot be imported or a single stage invoked without executing the whole smoke run. (`structure-mcp-smoke.py-6f1`)
  Status: SKIPPED
  Suggested fix: Move lines 336-354 into `def main(argv=None) -> int` guarded by `if __name__ == "__main__": sys.exit(main())`, and have `check()` append to a passed-in list (or return a bool collected by the caller) instead of a module global.

- **P3** `scripts/release.sh:272` — The appcast publish call is written twice, the two branches differing only by the presence of `-f sha="$appcast_sha"`. Message text, endpoint, base64 body and error handling are duplicated, so any change to the publish call has to be made in two places or silently drift between the first-upload and replacement paths. (`structure-release.sh-627`)
  Status: SKIPPED
  Suggested fix: Build the argument list once (`args=(-f message=... -f content=...); [ -n "$appcast_sha" ] && args+=(-f sha="$appcast_sha")`) and issue a single `gh api -X PUT ... "${args[@]}"`.

- **P3** `scripts/uitests.sh:75` — The kill-stale-instances loop is duplicated verbatim: lines 73-79 (before the run) and 135-141 (after the run) both pipe `running_instances` output through the same `while IFS=tab read -r pid _; kill "$pid"` construct with only the printed message differing. The pre-run copy also sleeps 2s, so the two can drift apart unnoticed. (`structure-uitests.sh-2fa`)
  Status: SKIPPED
  Suggested fix: Add a `kill_instances "<message>" "$list"` helper used by both sites, keeping the pre-run `sleep 2` as an explicit argument or a separate call.

## Security findings

- **P2** (risk: high) `Sources/Features/Pratiche/AttachmentChip.swift:130` — «Apri»/double-click passes an email attachment copied into allegati/ straight to NSWorkspace.shared.open with no type restriction. Nothing in the repo sets com.apple.quarantine on the files it extracts from Mail's store (no occurrence of "quarantine" in Sources), so an executable, .command, or .app attachment authored by a third party launches without Gatekeeper's first-run warning that the same file would get from Mail or a browser. (`security-AttachmentChip.swift-4ce`)
  Suggested fix: Set the com.apple.quarantine extended attribute on attachments when they are written into allegati/ (in the sync engine), or refuse to open executable/bundle UTIs from the chip and reveal them in the Finder instead.
  Evidence: `private func openWithDefaultApp() {
    guard let openURL else { return }
    NSWorkspace.shared.open(openURL)
}`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: high) `Sources/Features/Pratiche/PraticheController.swift:775` — The attachment file name is parsed out of a [[wikilink]] read from a message note's frontmatter and appended to the allegati directory with no path-component stripping; attachmentFileName(fromWikilink:) only removes brackets and the alias suffix. A value such as [[../../../secret.pdf]] in a hand-edited or externally synced note yields a URL outside the pratica folder that the row then previews with Quick Look, opens in the default app and reveals in Finder. (`security-PraticheController.swift-96d`)
  Suggested fix: Reduce the parsed name to its last path component before building the URL, and drop the reference when the resolved URL is not inside the pratica's allegati directory.
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: high) `Sources/Features/Workspace/BoardCardMenu.swift:184` — A .link canvas node's URL string is opened via NSWorkspace.shared.open with no scheme allow-list, so any scheme stored in an externally authored .canvas file (file://, or a third-party app scheme that performs an action) is launched on double-click or «Apri». The editor/card link path deliberately gates on http/https in MarkdownAttributedText.clickTarget(for:); this surface diverges from that rule. (`security-BoardCardMenu.swift-b8d`)
  Suggested fix: Route the link-card open through the same gate as MarkdownAttributedText.clickTarget (allow http/https plus the app's known schemes), refusing anything else instead of opening it.
  Evidence: `case .link(let url): if let target = URL(string: url) { NSWorkspace.shared.open(target) }`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: high) `Sources/Vault/ThumbnailStore.swift:43` — thumbnail(for:width:) joins a caller-supplied relative path onto root with no containment check. The path is a .canvas node file value, which is untrusted input (a board can be authored by Obsidian or arrive with a shared vault), so a node path of ../../../ causes PDFKit/QuickLook to open a file outside the vault and cache a rendered preview of it under the vault state directory. (`security-ThumbnailStore.swift-411`)
  Suggested fix: Reject a relativePath that does not standardize to a location under root before building fileURL, reusing the same boundary helper as NoteStore.
  Evidence: `let fileURL = root.appending(path: relativePath, directoryHint: .notDirectory)`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: high) `Sources/Vault/VaultController+Routes.swift:24` — The whole PergamenumRoute is logged to the unified system log with privacy: .public. For .capture(text:) and .search(query) that value is user-authored note content, and for .note(path:) it is a vault file path, so private vault data is persisted in a system-wide log store readable outside the app - at odds with the project's no-telemetry posture even though no network is involved. (`security-VaultController+Routes.swift-07d`)
  Suggested fix: Log only the route case name (or the payload with the default .private annotation) and keep privacy: .public for non-content fields, e.g. routeLog.notice("route: \(routeKind, privacy: .public)").
  Evidence: `routeLog.notice("route ricevuta: \(String(describing: route), privacy: .public)")`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: high) `Tests/PlaudHTTPClientTests.swift:36` — No test covers a recording or proposal id that is not a bare token. PlaudHTTPClient builds endpoints with Self.base.appending(path: id), which preserves "/" and ".." in the component, so an id taken from the service's own JSON response can reshape the request path (e.g. /recordings/../../admin/process). Host and port stay pinned to loopback, so impact is limited, but the construction is unvalidated and uncovered. (`security-PlaudHTTPClientTests.swift-431`)
  Suggested fix: Add a test asserting an id containing "/" or ".." is rejected or percent-encoded, and validate ids against a token charset in PlaudHTTPClient before interpolating them into the path.
  Evidence: `_ = try await client.process(id: "r1", force: false)
#expect(request.url?.path == "/recordings/r1/process")`
  ACTION REQUIRED — not auto-fixed

- **P1** (risk: low) `Tests/URLSchemeTests.swift:46` — The route-refusal argument list and theCanvasRouteIsHandedToTheWorkspace (line 219) contain no path-traversal case. The canvas path is asserted to pass through verbatim to WorkspaceController.open(board:) -> CanvasStore.load/save, and CanvasStore has no vault-containment guard at all (NoteStore.swift:126-134 has StoreError.outsideVault; CanvasStore.swift has only .alreadyExists/.missing). pergamenum:// is an externally invokable scheme, so a crafted link can read and write a .canvas outside the vault. (`security-URLSchemeTests.swift-868`)
  Suggested fix: Add traversal cases (pergamenum://canvas?file=../../x.canvas, pergamenum://note?file=../../etc/passwd) to the refusal list, and give CanvasStore the same standardizedFileURL/hasPrefix containment guard NoteStore already has.
  Evidence: `#expect(route("pergamenum://canvas?file=Area/Area.canvas") == .canvas(path: "Area/Area.canvas", nodeID: nil))`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Core/Conventions/NoteExport.swift:273` — The markdown link URL is interpolated raw into an href attribute, and NoteExport.escape (line 75) only replaces &, < and > — never the double quote. A note containing [x](" onclick="…) therefore produces an anchor with an attacker-chosen extra attribute in the exported .html/.pdf, and a javascript:/data: URL passes through unchecked since no scheme allow-list exists. Note bodies are not all hand-typed: the Pratiche importer writes links taken from received email into notes. (`security-NoteExport.swift-154`)
  Suggested fix: Escape " (and ') in NoteExport.escape, and validate the link scheme against an allow-list (http/https/mailto/message/pergamenum) before emitting href, dropping the anchor otherwise.
  Evidence: `result += "<a href=\"\(url)\">\(label)</a>"`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Features/Editor/MarkdownBlocksView.swift:252` — Links are built from the raw markdown target with no scheme allow-list, then handed to SwiftUI's default openURL (system action). This view renders pratiche email bodies, whose targets come verbatim from an attacker-controlled HTML href (HTMLTextReducer emits `[text](href)`), so a crafted message can offer a clickable `file://`, `x-apple.systempreferences:` or third-party app scheme. The editor's own path (MarkdownAttributedText.targetURL, line 211) already restricts external links to http/https; this surface diverges. (`security-MarkdownBlocksView.swift-3cb`)
  Suggested fix: Mirror MarkdownAttributedText.targetURL: only attach `piece.link` when the parsed URL's scheme is http/https, otherwise render the label as plain text (or route through an OpenURLAction that validates the scheme).
  Evidence: `case .url(let target):
    piece.link = URL(string: target)`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Features/Pratiche/PraticaSyncEngine.swift:758` — storePath(of:at:rowID:part:) appends a raw MIME attachment filename (fully attacker-controlled: it arrives in the email) to Mail's attachments directory with no containment check. A filename containing ../ escapes that directory, and the resulting absolute path is persisted into the note's pergamenum-mail-store-references frontmatter and later handed to NSWorkspace.open / reveal-in-Finder by AttachmentChipModel.targetURL, which only checks existence, never containment. (`security-PraticaSyncEngine.swift-ce5`)
  Suggested fix: Sanitise the part name with (name as NSString).lastPathComponent (as PraticaNaming.attachmentFileName already does) before appending, and reject any resolved path not under the message's own attachments directory.
  Evidence: `EMLXReader.attachmentsDirectory(...).appending(path: name, directoryHint: .notDirectory)`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Vault/CanvasStore.swift:25` — CanvasStore has no vault-boundary check at all: url(forBoard:) joins a caller-supplied relative path onto root and load/save/createBoard/createFolder use it unguarded. The board path is attacker-influenced end to end: PergamenumURL parses pergamenum://canvas?file=<path> verbatim, VaultController+Routes stores it in routeState.pendingCanvas, WorkspaceView.openPendingCanvas opens it and WorkspaceController.save() writes the document back via store.save(document:board:). A file= of ../../.. therefore reads and later writes outside the vault (the app is not sandboxed). (`security-CanvasStore.swift-a6f`)
  Suggested fix: Apply the same standardized-path prefix check NoteStore.assertInsideVault performs (ideally a shared helper) inside CanvasStore.url(forBoard:) / load / save / createBoard / createFolder, and reject a route path that escapes the vault before it reaches routeState.pendingCanvas.
  Evidence: `func url(forBoard board: String) -> URL { root.appending(path: board, directoryHint: .notDirectory) }`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Vault/VaultSession+Journal.swift:58` — moveFile(from:to:) and writeFile(_:to:) (line 151) both build destinations with store.url(for:) and then createDirectory/moveItem/Data.write without any vault-boundary check. The MCP move_note tool passes its folder argument through unvalidated (VaultHost: arguments.string("folder") ?? ""), so a folder of ../../tmp moves a note out of the vault and creates directories outside it; writeFile can likewise write arbitrary bytes to an escaped path. (`security-VaultSession+Journal.swift-077`)
  Suggested fix: Run the vault-boundary assertion on both oldPath and newPath in moveFile, and on relativePath in writeFile, before any FileManager mutation; reject rather than normalise silently.
  Evidence: `let destination = store.url(for: newPath) ... try FileManager.default.moveItem(at: store.url(for: oldPath), to: destination)`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Sources/Vault/VaultSession+Journal.swift:106` — trashFile(at:) sends store.url(for: relativePath) to FileManager.trashItem with no vault-boundary check. The path comes straight from the MCP trash_note tool (VaultHost.write -> VaultAPI.trashNote -> VaultSession.trashNote), whose only validation is a non-empty string, so a path containing ../ deletes a file outside the vault on an unsandboxed app. NoteStore guards read/write against exactly this (its doc comment names pergamenum://note?file=../../), but the guard is not reached here. (`security-VaultSession+Journal.swift-9b5`)
  Suggested fix: Validate relativePath against the vault root (reuse NoteStore's boundary check, exposed as a non-private throwing helper) before the exists() probe and before trashItem.
  Evidence: `try FileManager.default.trashItem(at: store.url(for: relativePath), resultingItemURL: nil)`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Tests/PraticheControllerTests.swift:289` — Three tests write MailStoreLocation.overrideKey into UserDefaults.standard and undo it only in a defer. The unit suite is hosted inside the real Pergamenum.app bundle, so UserDefaults.standard is the shipping it.stefer.pergamenum persistent domain: an aborted, crashed or terminated run (this suite runs every turn via .claude/test-cmd) leaves the installed app permanently resolving its Mail store to a deleted temp fixture. SparkleUpdateControllerTests.swift:33 in the same shard documents the opposite discipline ("never .standard"). (`security-PraticheControllerTests.swift-ce3`)
  Suggested fix: Inject a throwaway UserDefaults(suiteName:) per test as SparkleUpdateControllerTests does, or thread the fixture root into MailStoreLocation explicitly rather than through the shared standard domain.
  Evidence: `UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `Tests/SharedSourcesPurityTests.swift:35` — Both purity guards silently `continue` when FileManager's enumerator returns nil, and neither asserts a positive scanned-file count. A renamed or mistyped entry in guardedDirectories turns the Sparkle-isolation guard (ADR-0031 D2) and the AppKit/SwiftUI purity guard (ADR-0036 R-38) into unconditional passes with no signal. PraticheIsolationTests.swift:62-65, in this same shard, documents that this exact bug shipped there and fixes it with a scannedAnyFile assertion. (`security-SharedSourcesPurityTests.swift-e19`)
  Suggested fix: Record an Issue on a nil enumerator and add a `#expect(scannedAnyFile, ...)` assertion to both tests, mirroring PraticheIsolationTests.
  Evidence: `guard let enumerator = FileManager.default.enumerator(...) else {
    continue
}`
  ACTION REQUIRED — not auto-fixed

- **P2** (risk: low) `UITests/WikilinkNavigationUITests.swift:47` — This UI-test file launches the app without -mailStoreRoot, the only launch argument that keeps MailStoreLocation.resolve() off the real ~/Library/Mail/V10 for a launched app (the xctest fixture-root fallback applies to the host process, not to the app a UI test launches). It is the single UITests file of 21 missing the flag, against the explicit CLAUDE.md / ADR-0036 rule that every one passes it. A pratiche sync triggered during a run reads the person's actual mail, and an existing Full Disk Access grant makes that succeed silently. (`security-WikilinkNavigationUITests.swift-6d4`)
  Suggested fix: Add "-mailStoreRoot", <per-test temporary fixture path> to app.launchArguments beside -disableCalendar/-disableUpdater, matching every other UITests file.
  Evidence: `app.launchArguments = ["-recentVaults", ..., "-disableCalendar", "YES", "-disablePlaud", "YES", "-disableUpdater", "YES", "-stateBase", ...]`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Sources/App/NoteExporter.swift:62` — PDF export parses note-derived HTML with NSAttributedString(html:options:), the WebKit-backed importer, which can fetch subresources declared in the document (for example a style with a remote url) during parsing. Combined with the attribute injection at NoteExport.swift:273, exporting a note whose content came from an imported email can produce an outbound request, which CLAUDE.md principle 2 allows only for the Sparkle updater and the Plaud loopback. (`security-NoteExporter.swift-403`)
  Suggested fix: Render the PDF from the app's own markdown blocks instead of the HTML importer, or fix the href escaping upstream so no attacker-controlled attribute can reach this parser.
  Evidence: `NSAttributedString(html: data, options: [.documentType: .html], documentAttributes: nil)`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Sources/Core/Email/HTMLTextReducer.swift:268` — The href read from untrusted email HTML is written into the vault markdown as [text](href) with no scheme validation and no escaping of parentheses. A javascript:, data: or file: link from a received message becomes an ordinary clickable link in a note, and an href containing ')' breaks the markdown link boundary. This is also the upstream source feeding the HTML-export injection in NoteExport.swift:273. (`security-HTMLTextReducer.swift-b63`)
  Suggested fix: Filter hrefs to an allow-list of schemes (http, https, mailto, message) and percent-encode or angle-bracket-wrap URLs containing parentheses before writing the markdown link.
  Evidence: `append("[\(text)](\(href))")`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Sources/Features/Pratiche/PraticaSyncEngine.swift:714` — Attachment bytes decoded from an email are written into the vault with Data.write(to:options:.atomic) and no com.apple.quarantine attribute is ever set (no quarantine handling exists anywhere in Sources/). The extension of the sender-supplied name is preserved by PraticaNaming.attachmentFileName, so a hostile .command/.app/.dmg attachment lands as an unquarantined file that the attachment chip opens in one double-click through NSWorkspace, with none of the origin warnings Finder shows for a downloaded file. (`security-PraticaSyncEngine.swift-a15`)
  Suggested fix: Set the com.apple.quarantine extended attribute on files written from email content (or refuse to open executable types from the chip), so Gatekeeper still prompts for attachments of foreign origin.
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Sources/Features/Workspace/WorkspaceController+Files.swift:12` — fileURL(for:) builds an absolute URL by appending a canvas node's stored file path to the vault root with no containment check. .canvas files are external, round-tripped documents (JSON Canvas, Obsidian-compatible), so a node path containing ../ resolves outside the vault; the URL then feeds Quick Look (selectedFileURLs) and BoardCardMenu.open, which calls NSWorkspace.shared.open on it. NoteStore.assertInsideVault exists for exactly this class of input but is not on this path. (`security-WorkspaceController+Files.swift-8c7`)
  Suggested fix: Standardise the resolved URL and verify it is under store.root (same guard as NoteStore.assertInsideVault) before returning it or opening it.
  Evidence: `return store.root.appending(path: path, directoryHint: .notDirectory)`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Sources/Vault/NoteStore.swift:74` — The traversal guard assertInsideVault is private and is invoked only by read(_:) and write(_:to:), while url(for:) vends an unchecked URL to roughly a dozen call sites that mutate the file system (VaultSession+Journal move/trash/write, BoardFileOperations rename writes, FolderFileOperations rename/trash, NoteFileOperations). The containment invariant the tests pin for read/write therefore does not hold for the vault as a whole. (`security-NoteStore.swift-63e`)
  Suggested fix: Either perform the boundary check inside url(for:) (returning an optional/throwing variant) or expose assertInsideVault as an internal checkedURL(for:) that every FileManager mutation in Sources/Vault must go through; add traversal tests for move/trash/canvas alongside the existing read/write ones.
  Evidence: `func url(for relativePath: String) -> URL { root.appending(path: relativePath, directoryHint: .notDirectory) }`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Tests/MessageDocumentTests.swift:35` — No test pins MessageDocument.quoted()'s YAML escaping of attacker-controlled mail headers. That helper exists precisely because "a header value is somebody else's text: a quote or a line break in it would close the scalar early and let the rest be read as new frontmatter keys", yet every fixture here uses benign subjects, senders and attachment names. A regression in the escaping would let a crafted Subject or attachment file name inject arbitrary frontmatter into a generated message .md. Note also that a bare CR is not escaped, only CRLF and LF. (`security-MessageDocumentTests.swift-7cc`)
  Suggested fix: Add render tests with a subject/from/storePath containing a double quote, a newline, a bare CR and a leading "---", asserting the value stays inside one quoted scalar and parse round-trips it.
  Evidence: `subject: "Richiesta offerta staffe antivibranti"  // no hostile-header fixture anywhere in this suite`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `Tests/PlaudIsolationTests.swift:27` — The mechanical enforcement of CLAUDE.md Principle 2 ("fully offline") greps Sources/ for the literal string "URLSession" only. Network access via Network.framework (NWConnection/NWBrowser), NSURLConnection, CFSocket/BSD sockets, or a Process launching curl would all pass this guard unnoticed, so the test claims a stronger invariant than it actually checks. (`security-PlaudIsolationTests.swift-7a1`)
  Suggested fix: Extend the forbidden-symbol list to NWConnection, NWBrowser, NSURLConnection, CFSocket, "import Network", Process/NSTask, keeping the single-file allowance for PlaudHTTPClient.swift.
  Evidence: `if contents.contains("URLSession") { filesMentioningURLSession.append(fileURL.path) }`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `UITests/PraticheUITests.swift:58` — This UI-test file omits -disablePlaud YES, which every other UITests file in the repo passes. RecordingsController.isIsolated reads defaults.bool(forKey: "disablePlaud") || isTestHost, and isTestHost is false for the app a UI test launches, so the app under test is free to issue real loopback HTTP requests to 127.0.0.1:3777 during the run. (`security-PraticheUITests.swift-29d`)
  Suggested fix: Add "-disablePlaud", "YES" to app.launchArguments beside -disableCalendar/-disableUpdater/-mailStoreRoot.
  Evidence: `app.launchArguments = ["-recentVaults", ..., "-disableCalendar", "YES", "-disableUpdater", "YES", "-mailStoreRoot", ..., "-stateBase", ...]`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `docs/design/pratiche/support.js:1218` — The generated design-mockup runtime executes code fetched at runtime through the Function constructor (both the inline x-dc logic at line 844 and modules fetched over the network at line 1206/1218, which unlike the React/Babel CDN loads carry no integrity hash), and broadcasts runtime metadata to any embedding parent with postMessage targetOrigin "*" (lines 1387 and 1858). The file is vendored and marked "GENERATED ... do not edit", so this is informational: opening the mockup also pulls React/Babel from unpkg.com, i.e. it is not an offline artifact. (`security-support.js-9c6`)
  Suggested fix: Leave the vendored file untouched; if the mockup is ever hosted or embedded, open it only from trusted content and treat the unpkg fetches as a known network dependency of docs/, not of the app.
  Evidence: `new Function("React", "module", "exports", "require", code)(...) / window.parent.postMessage({...}, "*")`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `scripts/appcast.py:67` — default_fetch opens whatever --feed-url it is given with urllib without checking the scheme, and build_feed copies every pre-existing <item> of the fetched feed verbatim into the appcast that is then republished. A tampered or substituted feed response therefore gets rebroadcast under the project's own URL; Sparkle's EdDSA verification keeps that from installing arbitrary code, but downgrade/metadata items would survive the round trip. (`security-appcast.py-3f6`)
  Suggested fix: Reject a --feed-url whose scheme is not https before fetching, and validate that each preserved item's enclosure URL points at the expected releases host before republishing.
  Evidence: `request = urllib.request.Request(url, headers={"User-Agent": "pergamenum-appcast"})`
  ACTION REQUIRED — not auto-fixed

- **P3** (risk: low) `scripts/install-cli.sh:62` — The binary copied into a PATH directory (default /usr/local/bin) is picked with `find ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/.../Release -name "$tool" | head -1`, which resolves in shell glob order, not by build time. Stale DerivedData folders accumulate after every `tuist generate`, so the install can silently put an older binary of unknown provenance on the PATH while reporting success. (`security-install-cli.sh-105`)
  Suggested fix: Select the most recently built artifact explicitly (e.g. `find ... -newer`/`ls -dt` ordering) and fail when more than one candidate matches, instead of taking the first glob hit.
  Evidence: `built="$(find ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Release -maxdepth 1 -name "$tool" -type f 2>/dev/null | head -1)"`
  ACTION REQUIRED — not auto-fixed

## Deferred findings (not auto-fixed)

- `dead-code-PraticaLedger.swift-df3` `Sources/Core/Pratiche/PraticaLedger.swift:142` — SKIPPED
- `dead-code-AttachmentChipModel.swift-580` `Sources/Features/Pratiche/AttachmentChipModel.swift:57` — SKIPPED
- `dead-code-PraticaSyncEngine.swift-e75` `Sources/Features/Pratiche/PraticaSyncEngine.swift:537` — Deferred — report-only
- `dead-code-VaultController+Routes.swift-6be` `Sources/Vault/VaultController+Routes.swift:155` — SKIPPED
- `dead-code-ReminderScheduler.swift-b9e` `Sources/Calendar/ReminderScheduler.swift:30` — Deferred — report-only
- `dead-code-VaultSettings.swift-e71` `Sources/Vault/VaultSettings.swift:68` — Deferred — report-only
- `dead-code-ShortcutStore.swift-35f` `Sources/App/ShortcutStore.swift:73` — SKIPPED
- `dead-code-AppInfo.swift-7c7` `Sources/Core/AppInfo.swift:7` — SKIPPED
- `dead-code-NoteName.swift-a42` `Sources/Core/Conventions/NoteName.swift:67` — Deferred — report-only
- `dead-code-MailLink.swift-f00` `Sources/Core/Email/MailLink.swift:3` — Deferred — report-only
- `dead-code-PergamenumURL.swift-af1` `Sources/Core/URLScheme/PergamenumURL.swift:90` — Deferred — report-only
- `dead-code-MarkdownReadingView.swift-8fa` `Sources/Features/Editor/MarkdownReadingView.swift:25` — Deferred — report-only
- `dead-code-PraticaCommand.swift-1b0` `Sources/Features/Pratiche/PraticaCommand.swift:49` — Deferred — report-only
- `dead-code-PraticaSyncEngine.swift-666` `Sources/Features/Pratiche/PraticaSyncEngine.swift:296` — SKIPPED
- `dead-code-CalendarDayCommand.swift-522` `Sources/Features/Today/CalendarDayCommand.swift:52` — Deferred — report-only
- `dead-code-BoardFormatBar.swift-e0a` `Sources/Features/Workspace/BoardFormatBar.swift:81` — Deferred — report-only
- `dead-code-BoardWikilinkCompletionLayer.swift-887` `Sources/Features/Workspace/BoardWikilinkCompletionLayer.swift:42` — Deferred — report-only
- `dead-code-WorkspaceBrowser+Tree.swift-5e1` `Sources/Features/Workspace/WorkspaceBrowser+Tree.swift:219` — SKIPPED
- `dead-code-OpenTabsStore.swift-775` `Sources/Vault/OpenTabsStore.swift:72` — SKIPPED
- `dead-code-ThumbnailStore.swift-bdd` `Sources/Vault/ThumbnailStore.swift:54` — Deferred — report-only
- `dead-code-ThumbnailStore.swift-3b0` `Sources/Vault/ThumbnailStore.swift:58` — Deferred — report-only
- `dead-code-VaultSession+Tasks.swift-610` `Sources/Vault/VaultSession+Tasks.swift:15` — Deferred — report-only
- `dead-code-VaultSession.swift-0f8` `Sources/Vault/VaultSession.swift:234` — Deferred — report-only
- `dead-code-FakePlaudService.swift-0dd` `Tests/FakePlaudService.swift:67` — Deferred — report-only
- `dead-code-PergamenumTests.swift-f31` `Tests/PergamenumTests.swift:4` — SKIPPED
- `dead-code-appcast.py-b96` `scripts/appcast.py:81` — SKIPPED
- `perf-PraticheController.swift-c6e` `Sources/Features/Pratiche/PraticheController.swift:325` — Deferred — report-only
- `perf-VaultSession.swift-fc1` `Sources/Vault/VaultSession.swift:218` — Deferred — report-only
- `perf-HTMLTextReducer.swift-b66` `Sources/Core/Email/HTMLTextReducer.swift:148` — SKIPPED
- `perf-HTMLTextReducer.swift-0d5` `Sources/Core/Email/HTMLTextReducer.swift:352` — SKIPPED
- `perf-MIMEDecoder.swift-33c` `Sources/Core/Email/MIMEDecoder.swift:116` — SKIPPED
- `perf-MailStoreReader.swift-53f` `Sources/Core/Email/MailStoreReader.swift:150` — SKIPPED
- `perf-MailStoreReader.swift-495` `Sources/Core/Email/MailStoreReader.swift:281` — SKIPPED
- `perf-Glob.swift-de6` `Sources/Core/Query/Glob.swift:19` — SKIPPED
- `perf-ViewEvaluator.swift-97e` `Sources/Core/Query/ViewEvaluator.swift:232` — SKIPPED
- `perf-MarkdownStyler.swift-c80` `Sources/Features/Editor/MarkdownStyler.swift:704` — SKIPPED
- `perf-VaultBrowser.swift-dd0` `Sources/Features/Editor/VaultBrowser.swift:252` — SKIPPED
- `perf-AttachmentChip.swift-09a` `Sources/Features/Pratiche/AttachmentChip.swift:33` — SKIPPED
- `perf-PraticaTimelineView.swift-c8b` `Sources/Features/Pratiche/PraticaTimelineView.swift:41` — SKIPPED
- `perf-RecordingsController.swift-8f0` `Sources/Features/Recordings/RecordingsController.swift:562` — SKIPPED
- `perf-BoardContentLayer.swift-85c` `Sources/Features/Workspace/BoardContentLayer.swift:195` — SKIPPED
- `perf-IndexSnapshot.swift-2f0` `Sources/Index/IndexSnapshot.swift:171` — SKIPPED
- `perf-IndexSnapshot.swift-c21` `Sources/Index/IndexSnapshot.swift:348` — SKIPPED
- `perf-NoteStore.swift-ce3` `Sources/Vault/NoteStore.swift:79` — SKIPPED
- `perf-NoteStore.swift-bf6` `Sources/Vault/NoteStore.swift:93` — SKIPPED
- `perf-VaultSession+Move.swift-2a6` `Sources/Vault/VaultSession+Move.swift:79` — Deferred — report-only
- `perf-VaultPratiche.swift-cf2` `Sources/Connector/VaultPratiche.swift:299` — Deferred — report-only
- `perf-MessageDocument.swift-9a2` `Sources/Core/Pratiche/MessageDocument.swift:185` — Deferred — report-only
- `perf-VaultHost.swift-bbb` `Sources/MCPServer/VaultHost.swift:45` — Deferred — report-only
- `perf-ReleasePipelineTests.swift-2cd` `Tests/ReleasePipelineTests.swift:189` — Deferred — report-only
- `perf-MessageDocument.swift-938` `Sources/Core/Pratiche/MessageDocument.swift:243` — SKIPPED
- `perf-MarkdownAttributedText.swift-64e` `Sources/Features/Editor/MarkdownAttributedText.swift:64` — SKIPPED
- `perf-RankableEntry.swift-e05` `Sources/Features/Editor/RankableEntry.swift:112` — SKIPPED
- `perf-LinkedTasksPanel.swift-744` `Sources/Features/Tasks/LinkedTasksPanel.swift:23` — SKIPPED
- `perf-RenderedViewBlock.swift-8bc` `Sources/Features/Views/RenderedViewBlock.swift:52` — SKIPPED
- `perf-WorkspaceController+Gestures.swift-4b4` `Sources/Features/Workspace/WorkspaceController+Gestures.swift:32` — SKIPPED
- `perf-VaultScanner.swift-a0b` `Sources/Vault/VaultScanner.swift:178` — SKIPPED
- `perf-VaultSession+Journal.swift-462` `Sources/Vault/VaultSession+Journal.swift:78` — SKIPPED
- `perf-VaultSession+Starred.swift-4d9` `Sources/Vault/VaultSession+Starred.swift:37` — SKIPPED
- `perf-VaultSession.swift-11e` `Sources/Vault/VaultSession.swift:196` — Deferred — report-only
- `perf-SharedSourcesPurityTests.swift-91f` `Tests/SharedSourcesPurityTests.swift` — SKIPPED
- `perf-SharedSourcesPurityTests.swift-21e` `Tests/SharedSourcesPurityTests.swift:84` — SKIPPED
- `perf-WorkspaceOpenStateUITests.swift-846` `UITests/WorkspaceOpenStateUITests.swift:116` — SKIPPED
- `perf-support.js-1e7` `docs/design/pratiche/support.js:380` — Deferred — report-only
- `perf-mcp-smoke.py-a69` `scripts/mcp-smoke.py:107` — SKIPPED
- `structure-PraticheController.swift-7e1` `Sources/Features/Pratiche/PraticheController.swift` — SKIPPED
- `structure-NoteExport.swift-c0f` `Sources/Core/Conventions/NoteExport.swift:138` — Deferred — high-risk
- `structure-NoteTextView+Coordinator.swift-d95` `Sources/Features/Editor/NoteTextView+Coordinator.swift:12` — Deferred — report-only
- `structure-CalendarService.swift-d72` `Sources/Calendar/CalendarService.swift` — SKIPPED
- `structure-ListContinuation.swift-f19` `Sources/Core/Editor/ListContinuation.swift:228` — SKIPPED
- `structure-NoteListPane.swift-b4a` `Sources/Features/Editor/NoteListPane.swift` — SKIPPED
- `structure-NoteTextView+ViewBlocks.swift-00b` `Sources/Features/Editor/NoteTextView+ViewBlocks.swift:54` — SKIPPED
- `structure-NoteTextView.swift-c97` `Sources/Features/Editor/NoteTextView.swift:321` — SKIPPED
- `structure-VaultBrowser.swift-8ae` `Sources/Features/Editor/VaultBrowser.swift:270` — SKIPPED
- `structure-NuovaPraticaWizard.swift-ec2` `Sources/Features/Pratiche/NuovaPraticaWizard.swift` — SKIPPED
- `structure-PraticaCommandActions.swift-7cd` `Sources/Features/Pratiche/PraticaCommandActions.swift:21` — SKIPPED
- `structure-PraticaSyncEngine.swift-186` `Sources/Features/Pratiche/PraticaSyncEngine.swift:20` — SKIPPED
- `structure-PraticaSyncEngine.swift-6c9` `Sources/Features/Pratiche/PraticaSyncEngine.swift:331` — SKIPPED
- `structure-PraticheController.swift-95b` `Sources/Features/Pratiche/PraticheController.swift:1168` — SKIPPED
- `structure-ViewBoardRenderer.swift-c3e` `Sources/Features/Views/ViewBoardRenderer.swift:38` — SKIPPED
- `structure-WorkspaceView.swift-f8e` `Sources/Features/Workspace/WorkspaceView.swift:11` — SKIPPED
- `structure-IndexCache.swift-dc5` `Sources/Index/IndexCache.swift:116` — SKIPPED
- `structure-MarkupHidingTests.swift-7e8` `Tests/MarkupHidingTests.swift` — SKIPPED
- `structure-SharedSourcesPurityTests.swift-903` `Tests/SharedSourcesPurityTests.swift:101` — SKIPPED
- `structure-VaultTests.swift-b6d` `Tests/VaultTests.swift` — SKIPPED
- `structure-VaultTests.swift-3ac` `Tests/VaultTests.swift:8` — SKIPPED
- `structure-ComposerUITests.swift-866` `UITests/ComposerUITests.swift:26` — SKIPPED
- `structure-PraticheUITests.swift-d06` `UITests/PraticheUITests.swift:58` — SKIPPED
- `structure-release.sh-fd5` `scripts/release.sh:44` — Deferred — report-only
- `structure-RootView.swift-c0b` `Sources/App/RootView.swift:9` — SKIPPED
- `structure-VaultWrites.swift-dd6` `Sources/Connector/VaultWrites.swift:123` — SKIPPED
- `structure-HTMLTextReducer.swift-abe` `Sources/Core/Email/HTMLTextReducer.swift` — SKIPPED
- `structure-HTMLTextReducer.swift-6ef` `Sources/Core/Email/HTMLTextReducer.swift:388` — SKIPPED
- `structure-MailStoreReader.swift-27d` `Sources/Core/Email/MailStoreReader.swift:365` — SKIPPED
- `structure-MessageDocument.swift-3ab` `Sources/Core/Pratiche/MessageDocument.swift` — SKIPPED
- `structure-MessageDocument.swift-27f` `Sources/Core/Pratiche/MessageDocument.swift:264` — SKIPPED
- `structure-PraticaNaming.swift-942` `Sources/Core/Pratiche/PraticaNaming.swift:64` — SKIPPED
- `structure-PergamenumURL.swift-ab3` `Sources/Core/URLScheme/PergamenumURL.swift:33` — SKIPPED
- `structure-Theme.swift-d64` `Sources/DesignSystem/Theme.swift:318` — SKIPPED
- `structure-MockupScreens.swift-4d0` `Sources/Features/DesignGallery/MockupScreens.swift` — SKIPPED
- `structure-TabBarMockup.swift-dcb` `Sources/Features/DesignGallery/TabBarMockup.swift:77` — SKIPPED
- `structure-CompletionPanel.swift-602` `Sources/Features/Editor/CompletionPanel.swift:191` — SKIPPED
- `structure-EditorDecorationDelegate+CheckboxRendering.swift-552` `Sources/Features/Editor/EditorDecorationDelegate+CheckboxRendering.swift:28` — SKIPPED
- `structure-EditorDecorationDelegate+TableRendering.swift-a75` `Sources/Features/Editor/EditorDecorationDelegate+TableRendering.swift:30` — SKIPPED
- `structure-NoteTextView+Tables.swift-a5b` `Sources/Features/Editor/NoteTextView+Tables.swift:130` — SKIPPED
- `structure-NoteTextView.swift-e7a` `Sources/Features/Editor/NoteTextView.swift:9` — Deferred — report-only
- `structure-PraticaCommandActions.swift-697` `Sources/Features/Pratiche/PraticaCommandActions.swift:661` — SKIPPED
- `structure-PraticheController.swift-bea` `Sources/Features/Pratiche/PraticheController.swift:1438` — SKIPPED
- `structure-PratichePane.swift-bb8` `Sources/Features/Pratiche/PratichePane.swift:14` — SKIPPED
- `structure-RecordingsController.swift-bef` `Sources/Features/Recordings/RecordingsController.swift` — SKIPPED
- `structure-EditorSettings.swift-11d` `Sources/Features/Settings/EditorSettings.swift:47` — SKIPPED
- `structure-BoardHandles.swift-5b2` `Sources/Features/Workspace/BoardHandles.swift:22` — SKIPPED
- `structure-BoardTray.swift-0f2` `Sources/Features/Workspace/BoardTray.swift:89` — SKIPPED
- `structure-CardTextView.swift-05d` `Sources/Features/Workspace/CardTextView.swift` — SKIPPED
- `structure-CardTextView.swift-d6d` `Sources/Features/Workspace/CardTextView.swift:359` — SKIPPED
- `structure-FormattingTextView.swift-fd1` `Sources/Features/Workspace/FormattingTextView.swift:14` — SKIPPED
- `structure-WorkspaceBrowser.swift-ac5` `Sources/Features/Workspace/WorkspaceBrowser.swift:109` — SKIPPED
- `structure-WorkspaceController.swift-52b` `Sources/Features/Workspace/WorkspaceController.swift:12` — SKIPPED
- `structure-CanvasStore.swift-5cb` `Sources/Vault/CanvasStore.swift:178` — SKIPPED
- `structure-FolderFileOperations.swift-895` `Sources/Vault/FolderFileOperations.swift:310` — SKIPPED
- `structure-NoteFileOperations.swift-97f` `Sources/Vault/NoteFileOperations.swift:226` — SKIPPED
- `structure-VaultController.swift-9c5` `Sources/Vault/VaultController.swift:4` — SKIPPED
- `structure-VaultScanner.swift-c2e` `Sources/Vault/VaultScanner.swift:44` — SKIPPED
- `structure-VaultSession+BoardDrop.swift-ac4` `Sources/Vault/VaultSession+BoardDrop.swift:66` — SKIPPED
- `structure-ConventionsTests.swift-4b8` `Tests/ConventionsTests.swift` — SKIPPED
- `structure-EmbedDrawingTests.swift-048` `Tests/EmbedDrawingTests.swift:156` — SKIPPED
- `structure-MarkdownStylerTests.swift-ee1` `Tests/MarkdownStylerTests.swift` — SKIPPED
- `structure-PraticaSyncTests.swift-53d` `Tests/PraticaSyncTests.swift:77` — SKIPPED
- `structure-TaskTests.swift-6f0` `Tests/TaskTests.swift` — SKIPPED
- `structure-support.js-0ab` `docs/design/pratiche/support.js` — Deferred — report-only
- `structure-appcast.py-d86` `scripts/appcast.py:141` — SKIPPED
- `structure-appcast.py-0a8` `scripts/appcast.py:224` — SKIPPED
- `structure-install-cli.sh-11b` `scripts/install-cli.sh:25` — SKIPPED
- `structure-mcp-smoke.py-314` `scripts/mcp-smoke.py:167` — SKIPPED
- `structure-mcp-smoke.py-6f1` `scripts/mcp-smoke.py:336` — SKIPPED
- `structure-release.sh-627` `scripts/release.sh:272` — SKIPPED
- `structure-uitests.sh-2fa` `scripts/uitests.sh:75` — SKIPPED

## Run log

### Phase timings

| Phase | Seconds |
| --- | --- |
| phase2 | 6122 |

- Agents dispatched: 33
- Fix records: 208

### Test runs

| Label | Exit | Duration (s) | Passed | Failed | Timeout |
| --- | --- | --- | --- | --- | --- |
| baseline | 65 | 180 | 0 | 0 | no |
| baseline-retry | 65 | 181 | 0 | 0 | no |
| dead-code | 0 | 143 | 0 | 0 | no |
| perf | 0 | 80 | 0 | 0 | no |
| structure | 65 | 172 | 0 | 0 | no |
| structure-retry | 65 | 75 | 0 | 0 | no |

- Timeouts: 0
- Test command: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`
- Baseline commit: 7381877
- Run id: 2026-09-11-2300

## Orchestrator notes (deviations and triage, hand-written)

Everything above this heading is produced by `render-report.py` from the run state. This section
records the judgement calls the orchestrator made during the run so a reader can audit them.

### How to read the Summary counters

- **Baseline: RED / Post-fix: RED / Regressions caught: 3.** The test runner's parser does not
  read Swift Testing output (`PASSED=0/FAILED=0` on every row), so exit codes are the only signal
  it records. The baseline itself was RED on one known, pre-existing test,
  `ReleasePipelineTests.appcastSelfTestExitsZeroWithOutput()` (GCD QoS priority inversion, fix
  pending on `origin/fix/release-pipeline-test-qos-priority-inversion`). The baseline was
  therefore treated as GREEN modulo that one test, and each dimension was judged by diffing its
  snapshot against the baseline snapshot: any new failing test or build error would have been RED.
  The three non-zero rows are, in order:
  - `baseline-retry`: the same known test, 2798/2799 passed.
  - `structure`: the same known test, 2798/2799 passed, nothing new.
  - `structure-retry`: the test host received an external SIGTERM mid-run (xcresult:
    `Test crashed with signal term`, `aFailedProcessCallSurfacesOnTheRowRatherThanCrashing()`),
    caused by a concurrent `xcodebuild test` from another session on the shared
    `DerivedData` (result bundle `Test-Pergamenum-2026.09.12_01-00-32`). The host was restarted
    by xcodebuild, 2798/2799 passed, no assertion failed, and the known test passed on that run.
    Not a regression: the same test passed in the baseline, in every dimension run and in the
    first `structure` run, and no file under `Sources/Features/Recordings` other than
    `PlaudQuote.swift`/`ReviewSheet.swift` (dead-code removals) changed in this run.
  - `dead-code` and `perf` runs were fully green (2799/2799).
- **Fixed: 100** across dead-code, perf and structure; 1 finding recorded as No-op
  (`perf-NoteHistorySheet.swift-502`: the formatter is configured from a caller-supplied
  calendar/locale, so there is no concurrency-safe shared shape to hoist it to).
- **Deferred: 137** = 29 report-only + 1 high-risk (renderer defaults) + 107 `SKIPPED` by
  orchestrator triage (reasons below; each id's reason is also stored in the run state under
  `fixes.<id>.note`).
- **Reverted: 0.** The circuit breaker never fired.

### Deviations from the skill's reference procedure

1. **Audit Workflow used the object-root JSON schema variant** (`{"findings": [...]}`) instead of
   the array form, because the Workflow runtime rejects an array-root schema. `merge-findings.py`
   consumed the unwrapped arrays unchanged.
2. **Cluster dispatch.** Fix agents were dispatched per cluster of related findings (one worktree
   and one merge per cluster, 9 clusters) instead of one agent per finding. Every finding in a
   cluster is recorded individually with the cluster's merge sha. Each agent's brief carried the
   full list of ids, the PATTERN pre-flight contract, the `.claude/protected-interfaces` list, and
   an explicit ban on writing under `.claude/`.
3. **Files under edit by other sessions were excluded** (the user asked this run not to conflict
   with concurrent work). Diffed `main` against the baseline and read the other sessions'
   branches; every finding touching those files is `SKIPPED` with the reason
   "file under edit by another session".
4. **Baseline treated as GREEN modulo the known failing test** (see above). This is the
   reason the Summary shows RED/RED.
5. **Runner parser limitation.** `run-test-cmd.sh` reports `PASSED=0/FAILED=0` for Swift
   Testing output; the per-dimension verdicts were computed from the snapshots
   (`Test run with N tests in M suites`, `✘ Test …` lines) instead.
6. **Fix agents used a worktree-local derived-data path** when the shared `DerivedData`
   `build.db` was locked by other sessions' builds; the shared path was used for every recorded
   dimension test run.

### Triage: why 107 routable findings were SKIPPED

- **File under edit by another session** (9): `dead-code-PraticaLedger.swift-df3`,
  `dead-code-AttachmentChipModel.swift-580`, `dead-code-PraticaSyncEngine.swift-666`,
  `perf-AttachmentChip.swift-09a`, `perf-MessageDocument.swift-938`,
  `perf-PraticaTimelineView.swift-c8b`, `structure-PraticheController.swift-7e1`,
  `dead-code-appcast.py-b96`, `perf-mcp-smoke.py-a69`.
- **Fix would delete or weaken an existing test** (3): `dead-code-ShortcutStore.swift-35f`
  (`hasConflicts` is asserted by `ShortcutTests`), `dead-code-AppInfo.swift-7c7` and
  `dead-code-PergamenumTests.swift-f31` (the tagline is asserted by `PergamenumTests`).
- **Design decision, not a mechanical fix** (3): `dead-code-VaultController+Routes.swift-6be`
  (see the defect below), `dead-code-OpenTabsStore.swift-775` (the finding proposes wiring
  `forget(_:)` into recents removal, a behaviour change), `dead-code-WorkspaceBrowser+Tree.swift-5e1`
  (the `old` parameter is documented as deliberately unread and the fix asks to change tests).
- **Behaviour-sensitive perf rewrites or new caching layers with no test net** (23): the
  `NoteStore`, `MailStoreReader`, `MIMEDecoder`, `HTMLTextReducer` tokenizer, `IndexSnapshot`
  materialised task list, `RecordingsController` drafts cache, `@State` caches inside
  attachment-hosted views, `BoardContentLayer` cached map, gesture state, `VaultSession`
  starred/journal batch APIs, and the `Glob`/`ViewEvaluator`/`MarkdownStyler`/`RankableEntry`/
  `MarkdownAttributedText` algorithmic restructures. Each is a candidate for its own reviewed
  change, not for an unattended fix loop.
- **Test-only perf** (3): `perf-SharedSourcesPurityTests.swift-91f`/`-21e`,
  `perf-WorkspaceOpenStateUITests.swift-846`.
- **Structure file-split / oversize findings** (66): multi-file moves are not regression-safe
  without a dedicated review; only the three structure findings with a contained, testable shape
  were fixed (`WikilinkNavigationUITests` `-mailStoreRoot`, `NoteFileOperations` repoint dedupe,
  the shared `DayColumnMenu` for `MonthView`/`WeekView`).

### Real defect found, reported and not fixed

`RouteState.noteIDs` (`Sources/Vault/VaultController+Routes.swift`) is never populated, so a
`pergamenum://note?id=<id>` route always fails. No stable note id exists anywhere in the index
(`IndexSnapshot`/`IndexCache` have no id column); the SPEC's URL-scheme table says the id is
"registrato nell'indice", which was never implemented on the producer side. A fix needs an index
field and a `schemaVersion` bump (a protected interface), so it is a design decision for a
dedicated chain, not a refactor.

### Follow-ups worth a look

- `RenderedViewBlock.notePath` became write-only after `dead-code-NoteTextView+Transclusion-8dd`;
  either read it or remove it in a later pass.
- The 27 security findings above, six of them `risk: high`, are the most valuable output of the
  run and are all still open.
- Run `scripts/uitests.sh` before merging the run branch into `main` (CLAUDE.md rule); this run
  executed only `PergamenumTests`.
- Eight `worktree-agent-*` worktrees and ~50 `worktree-agent-*` branches are left under
  `.claude/worktrees/` by the merge script; prune them once the run branch is merged.
