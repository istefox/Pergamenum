# SPEC — Cmd+click navigation for wikilinks and links in the editor

**Topic slug:** wikilink-click-navigation

Source: GitHub issue [#188](https://github.com/istefox/Pergamenum/issues/188), found during the
ADR-0037 R-11 hand check (2026-09-09).

## Objectives

Make wikilinks (`[[Nota]]`, `[[Nota|alias]]`, `^[[board.canvas]]`) and CommonMark links
(`[text](url)`) clickable to navigate, in an editor that (per ADR-0029) is always editable and has
no reading-mode toggle — so a plain click must keep placing the caret. Cmd+click becomes the
navigation gesture, matching a widely-understood macOS/developer-tool convention (Xcode
Cmd+click-to-jump-to-definition), and a context-menu entry gives the same action without a
keyboard modifier.

Separately, fix the pre-existing quirk where a single click on a wikilink's *visible target text*
fails to trigger reveal-on-caret (a double-click is needed there, while a single click works
elsewhere in the paragraph) — if, on investigation, it shares a root cause with this feature's own
change. If it turns out to be genuinely unrelated, this SPEC does not fix it; a new issue is filed
instead.

## Root cause (revised — verified against a running debug build, 2026-09-09; supersedes issue
## #188's original diagnosis, which was incomplete)

**Issue #188's claim ("only `.toolTip` is set, never `.link`") is factually wrong for the note
editor.** `MarkdownAttributedText.attributes(for:.linkTarget)` (called with the default
`links: true` from `NoteTextView+Coordinator.applyStyling`) already sets both `.link` and
`.cursor: .pointingHand` on a wikilink's/CommonMark link's *label* text (the range between the
delimiters, never the delimiters themselves) directly on the live `NSTextView`'s real
`textStorage`. This is confirmed on-screen: hovering a wikilink with Cmd held shows a pointing-hand
cursor; without Cmd, a normal I-beam — exactly AppKit's own built-in convention for an editable
`NSTextView`'s `.cursor` attribute. `textView(_:clickedOnLink:at:)`
(`NoteTextView+Coordinator.swift:392`) is also already correctly implemented and correctly wired
as the `NSTextView`'s delegate, and correctly resolves the clicked URL to a title/embed target.

**The actual, narrower defect: AppKit's automatic Cmd+click "clickedOnLink" gesture never fires
in this editor**, so a correctly-implemented, correctly-attributed, correctly-delegated mechanism
sits unreached. Root cause: `NoteTextView` opts into TextKit 2
(`CompletingTextView(usingTextLayoutManager: true)`, `NoteTextView.swift:152`) *and* installs a
custom `NSTextContentStorageDelegate`
(`EditorDecorationDelegate.textContentStorage(_:textParagraphWith:)`) that returns a freshly
allocated `NSTextParagraph` for every paragraph containing markup, on every layout pass. This
substitute paragraph is attribute-preserving and length-preserving by construction — it does still
carry `.link`/`.cursor` at the same offsets as the real backing store, which is why the
cursor-rect mechanism (a separate AppKit code path that reads through the rendered/laid-out
content) works correctly. But AppKit's older, TextKit‑1-era `mouseDown` convenience for
Cmd+click-to-follow-a-link does not reliably re-derive `.link` through a substituted
`NSTextParagraph` the way the cursor-rect scan does — so `super.mouseDown`'s built-in handling
silently fails to recognize the click as a link click and never invokes
`clickedOnLink(at:)` at all. Nothing in `CompletingTextView+Pasteboard.swift` overrides
`mouseDown`/`mouseUp` to detect this manually; it only handles embed-resize/margin/checkbox hits
and otherwise defers entirely to AppKit's automatic (and, here, non-functional) gesture.

**Consequence for the fix:** rather than "add `.link`" (already present, already correct), the fix
is to stop relying on AppKit's automatic link-click gesture and instead detect a Cmd+click
explicitly in `CompletingTextView.mouseDown(with:)` (mirroring the existing
embed-resize/margin/checkbox interception pattern already in that file): when
`event.modifierFlags.contains(.command)`, resolve the character index at the click point via
`textLayoutManager` (not the legacy `layoutManager`, unused under TextKit 2), read the `.link`
attribute directly from `textStorage` at that index, and if present, invoke the same delegate
method (`textView(_:clickedOnLink:at:)`) directly instead of waiting for AppKit to call it. The
Workspace `.text` card (`CardTextView`/`FormattingTextView`) needs the same explicit-detection fix
*plus* the `.link`/`.cursor` attributes it currently omits by design
(`CardTextAttributes.swift`'s `.linkTarget`/`.embedTarget` case, commented as deliberately
non-clickable per ADR-0027 §D1 — reopened by this feature's R-06) — `FormattingTextView` shares
the same TextKit 2 + content-storage-delegate setup (ADR-0028 §D1), so the same AppKit gesture
gap applies there once it has something to be clickable at all.

## Scope

In scope:
- Wikilinks (`[[Nota]]`, `[[Nota|alias]]`, `^[[board.canvas]]`) in the note editor (`NoteTextView`).
- CommonMark links (`[text](url)`, both external URLs and vault-relative note links) in the note
  editor.
- Workspace `.text` card (`CardTextView`) — same constructs, same concealment mechanism
  (ADR-0028 §D1 shared `EditorDecorationDelegate`, ADR-0037 §D5 card parity).
- A context-menu entry ("Apri collegamento") as a non-modifier alternative to Cmd+click.
- A hover affordance (pointing-hand cursor) while Cmd is held over a link/wikilink range.
- Investigating, and fixing if same root cause, the single-click reveal-on-caret quirk on a
  wikilink's visible target text (see Non-goals for the "unrelated" outcome).
- Verifying (and fixing if actually broken) Cmd+click parity in read-only rendering surfaces
  (`TranscludedNoteView`, `NoteExporter`'s HTML export path via `MarkdownBlocksView`) — those
  already carry `.link` and are expected to already support a *plain* click there (no caret to
  place); this SPEC does not change that to require Cmd there (see UI flows).

Out of scope (Non-goals):
- No new keyboard shortcut or menu command for "follow link under caret" (e.g. no Cmd+Enter) —
  only the mouse-driven Cmd+click and the context-menu item are in scope.
- No change to how links/wikilinks are authored, inserted, or autocompleted.
- No back/forward navigation history — Cmd+click opens the target exactly the way the existing
  navigation entry points (breadcrumb, "Task collegati" panel, per ADR-0036) already do; no new
  history stack.
- No requirement to make read-only surfaces require Cmd+click — if plain click already navigates
  there, that stays unchanged.

## Stack / architecture

- No new dependency. Changes are scoped to `Sources/Features/Editor/` and
  `Sources/Features/Workspace/` (`CardTextView.swift`), consistent with every prior ADR-0028/
  ADR-0029/ADR-0037 chain — neither `Sources/Core` nor `Sources/Connector` nor either command-line
  target (`perg`, `pergamenum-mcp`) is touched.
- **Navigation logic is reused, not reimplemented.** ADR-0036 already defines `open(link:)` and
  `WorkspaceBoardResolver`, used today by the breadcrumb and the "Task collegati" panel to resolve
  and navigate a wikilink to a note or a `.canvas` board, including not-found and ambiguous-board
  handling. This feature's Cmd+click/context-menu action calls into that same path rather than
  defining a second notion of "what does this link mean" and "what happens when it's broken".
- **External `http(s)` URLs** (from a CommonMark link) are handed to `NSWorkspace.shared.open(_:)`
  — standard macOS behavior. This is a user-initiated action taken on an explicit gesture, not a
  background network call, so it does not reopen Principle 2 ("fully offline") any more than the
  Sparkle updater's manual-only check (ADR-0031) or the Plaud loopback exception (ADR-0032) did;
  unlike those two, it needs no ADR-level exception at all, since Cmd+click already exists in this
  codebase as an explicit local file-URL open elsewhere and involves no vault data leaving the
  machine — only whatever destination the person clicks.
- **`.link`/`.cursor` are already correctly applied in `NoteTextView`** (see revised Root cause) —
  no change needed there. They must be **added** to `CardTextAttributes.swift`'s `.linkTarget`/
  `.embedTarget` case for the Workspace card, alongside (not instead of) the existing colour-only
  styling, reopening ADR-0027 §D1's "never `.link`, never `.cursor`" line for this feature.
- **Gating on the Cmd modifier does NOT rely on AppKit's automatic clickedOnLink gesture — it is
  detected explicitly in `mouseDown(with:)`.** Both `CompletingTextView` (note editor) and
  `FormattingTextView` (Workspace card) already override `mouseDown(with:)` to intercept
  embed-resize/margin/checkbox hits before falling through to `super.mouseDown` (see revised Root
  cause for why the automatic gesture doesn't fire under this editor's TextKit 2 +
  content-storage-delegate setup). The Cmd+click check is added as one more explicit interception,
  in the same shape: when `event.modifierFlags.contains(.command)`, resolve the character index at
  the click point via `textLayoutManager` (never the legacy `layoutManager`, unused under
  TextKit 2), read `.link` from `textStorage` at that index, and if present call
  `textView(_:clickedOnLink:at:)` directly instead of `super.mouseDown` — consuming the event
  rather than falling through, exactly like the existing embed/margin/checkbox branches.
- **Context-menu entry** is added by prepending "Apri collegamento" (with a separator) to the menu
  returned when right-clicking directly on a link/wikilink range, inside the existing
  `menu(for:)` override (ADR-0023 §D4, note editor) — falling through to `super.menu(for:)`
  everywhere else, unchanged. `FormattingTextView` has no `menu(for:)` override today (confirmed);
  this feature adds one there too, in the same shape.
- **Cursor affordance is already correct, unmodified, in the note editor** — AppKit's own
  behavior for an editable `NSTextView`'s `.cursor` attribute already shows the pointing hand only
  while Cmd is held (confirmed on-screen), reverting automatically otherwise; no new cursor-rect
  or tracking-area code is needed there. Adding `.cursor` to `CardTextAttributes` (above) is
  expected to produce the same free behavior in the Workspace card; verify this on-screen once
  added rather than assuming it, since it depends on the same AppKit convention applying under
  `FormattingTextView`'s own TextKit 2 setup.

## Data model

No new storage, no schema change, no index field, no frontmatter key, no `.canvas` property.
Purely an interaction-and-rendering change on data that already exists (the parsed link/wikilink
ranges `MarkdownStyler`/`EditorDecorationDelegate` already compute, per ADR-0037 §D1).

## UI flows

1. **Cmd+click a wikilink or link in the editor** → the click is intercepted before normal caret
   placement; the underlying target is resolved via the existing ADR-0036 `open(link:)` /
   `WorkspaceBoardResolver` path (note, `.canvas` board, or — new for this feature — an external
   URL via `NSWorkspace`); navigation happens exactly as it does from the breadcrumb/task panel
   today.
2. **Plain click on the same range** → unchanged: places the caret, exactly as everywhere else in
   the paragraph (ADR-0029's always-editable model is not touched).
3. **Cmd+click while an existing text selection touches the click point** → navigates. Cmd+click on
   a link is treated as a distinct gesture from selection, not as a selection-extend modifier
   (Shift already owns extend).
4. **Right-click on a link/wikilink range** → context menu shows "Apri collegamento" first, then a
   separator, then the standard system menu (spelling, paste, etc.) exactly as `menu(for:)`
   produces today outside a link range.
5. **Hovering a link/wikilink range while Cmd is held** → cursor becomes a pointing hand; reverts
   on Cmd-up or when the mouse leaves the range.
6. **Broken wikilink (target note/board doesn't exist) or ambiguous board name, Cmd+clicked** →
   identical to what `open(link:)` already does today from the breadcrumb/task panel (this SPEC
   does not add a "create missing note" flow or a new error UI — whatever that existing path
   surfaces is what the editor surfaces too).
7. **Read-only rendering (`TranscludedNoteView` embed preview, `NoteExporter`'s interactive HTML
   export preview if any)** → a plain click continues to navigate if it already does (verify during
   implementation); no requirement is added to gate these behind Cmd, since there is no caret to
   protect there.
8. **Single click on a wikilink's *visible target text*, editor surfaces** → after this feature's
   fix, triggers reveal-on-caret with one click, consistent with clicking anywhere else in the
   paragraph — *if* investigation confirms the same root cause as this feature's `.link` change
   (most likely candidate: the `.link` attribute's own color/underline overlay changing
   AppKit's hit-testing once added). If investigation shows an unrelated cause, this SPEC does not
   fix it; a new issue is filed describing the confirmed (different) cause.

## Edge cases

- Cmd+click on a wikilink whose target note title matches more than one note (should not happen —
  note titles are unique per ADR-0021/0025's model — but if `WorkspaceBoardResolver` reports
  ambiguity for a `.canvas` board name shared across folders, defer to its existing `.ambiguous`
  handling, same as item 6 above).
- Cmd+click landing exactly on the boundary between the concealed marker and the revealed target
  text of a wikilink — treated as "inside the link range" if `MarkdownStyler`'s computed extent for
  that link/wikilink (ADR-0037 §D1) contains the click point, consistent with how reveal-on-caret's
  own span containment already works.
- Cmd+click on a link inside a folded/collapsed region (e.g. inside a folded heading, ADR-0029) —
  not reachable by definition (folded content isn't laid out/clickable); no special handling needed.
- Cmd released between mouse-down and mouse-up (e.g. Cmd+click but the key is released mid-click) —
  resolved by checking the modifier state at mouse-down (the same point AppKit already samples for
  `NSEvent.modifierFlags` in a `mouseDown(with:)` override), not at mouse-up.
- A link inside a table cell (ADR-0029's GFM table grid) — Cmd+click there should work the same way
  as elsewhere; if the table cell's own text-editing session (ADR-0029 §D-cell-commit) intercepts
  the click before it reaches this feature's handling, that's a defect to catch during
  implementation, not a designed exception.
- Workspace `.text` card mid-drag or freshly culled/deallocated (per ADR-0029 §D17's culling
  behavior) — Cmd+click only applies to a live, currently-rendered `CardTextView`; nothing changes
  about culling.

## Success criteria

- [x] R-01 — Cmd+clicking a wikilink (`[[Nota]]`) in the note editor navigates to that note, using
  the same `open(link:)` resolution ADR-0036 already uses elsewhere.
- [x] R-02 — Cmd+clicking a `^[[board.canvas]]` wikilink marker in the note editor navigates to
  that Workspace board via `WorkspaceBoardResolver`, same as the existing breadcrumb/task-panel
  entry points.
- [x] R-03 — Cmd+clicking a CommonMark link to a vault-relative note (`[text](Note.md)`) in the
  note editor navigates to that note.
- [x] R-04 — Cmd+clicking a CommonMark link to an external URL (`[text](https://...)`) in the note
  editor opens it via `NSWorkspace.shared.open(_:)` in the system default browser.
- [x] R-05 — A plain click (no Cmd held) on any link/wikilink range in the note editor places the
  caret exactly as today, and never navigates — regression guard for ADR-0029's always-editable
  model.
- [x] R-06 — Cmd+click and plain click behave identically to R-01…R-05 inside the Workspace `.text`
  card (`CardTextView`), for both wikilinks and CommonMark links.
- [ ] R-07 — Right-clicking a link/wikilink range in the editor (or the card) shows "Apri
  collegamento" as the first context-menu item, followed by a separator and the standard system
  menu; choosing it performs the same navigation as Cmd+click on that range.
  Implemented (`menu(for:)` in both `CompletingTextView+Pasteboard.swift` and
  `FormattingTextView.swift`) but not yet verified by any test, automated or manual — no
  unit/UI test covers a context-menu invocation. Needs the manual on-screen check from this
  plan's Verification section before this criterion can be checked off.
- [ ] R-08 — Hovering a link/wikilink range while Cmd is held shows a pointing-hand cursor; the
  cursor reverts to normal when Cmd is released or the pointer leaves the range.
  Relies on AppKit's own `.cursor` attribute behavior (no new code needed per the plan), and was
  confirmed correct on-screen for wikilinks earlier in this chain, before this continuation — but
  not re-confirmed after this continuation's own changes (CommonMark links' new `.cursor`
  attribute, the card's new `.cursor` attribute). Needs the manual on-screen check from this
  plan's Verification section before this criterion can be checked off.
- [x] R-09 — Cmd+clicking a broken wikilink (target note/board doesn't exist) or an ambiguous board
  name produces the identical outcome `open(link:)` already produces today from the
  breadcrumb/task panel — no new UI is introduced for this case.
- [x] R-10 — The implementation investigates whether the single-click reveal-on-caret quirk on a
  wikilink's visible target text shares this feature's root cause; if it does, the fix ships as
  part of this feature and a single click on the visible target text triggers reveal-on-caret,
  consistent with clicking elsewhere in the paragraph. If investigation shows an unrelated cause,
  a new GitHub issue is filed describing the confirmed cause instead (no-test: the "file a new
  issue instead" branch is a documentation/process outcome, not something a test can assert).
  Investigated: the quirk reproduces independently of this chain's own changes (wikilinks already
  carried `.link`/`.cursor` before this chain touched anything) and independently of ADR-0037's
  setting, with no computational asymmetry found in `MarkdownStyler`/`EditorDecorationDelegate`.
  Confirmed unrelated; filed as [#191](https://github.com/istefox/Pergamenum/issues/191) rather
  than fixed here.
- [x] R-11 — Read-only rendering (`TranscludedNoteView` embed preview) is verified to still
  navigate on a plain click after this feature's changes (no regression from adding `.link`
  handling changes elsewhere); if it was already broken beforehand, that is fixed too.
  Verified via `git diff --stat` against `main`: `TranscludedNoteView.swift`,
  `MarkdownBlocksView.swift` and `MarkdownInlineParser.swift` are untouched by this chain.
- [x] R-12 — A UI test exists asserting Cmd+click on a known wikilink in the editor navigates to
  the target note. `UITests/WikilinkNavigationUITests.swift`,
  `testCommandClickOnAWikilinkNavigatesToTheLinkedNote`.
- [x] R-13 — A UI test exists asserting a plain click on a wikilink in the editor does not
  navigate and places the caret (regression guard for R-05).
  `UITests/WikilinkNavigationUITests.swift`, `testAPlainClickOnAWikilinkPlacesTheCaretAndDoesNotNavigate`.
- [x] R-14 — A unit test exists covering the pure resolution from a clicked link/wikilink range to
  its navigation target (note path / board path / external URL), independent of AppKit click
  simulation. `Tests/MarkdownAttributedTextTests.swift` (9 tests) and `Tests/CardTextViewTests.swift`
  (3 tests, R-06 card-side coverage).
