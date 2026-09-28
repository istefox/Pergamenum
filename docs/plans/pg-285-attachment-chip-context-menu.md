# Fix: right-clicking an attachment chip opens the chip's own menu (PG-285)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to ADR-0065's chain (format-edge
hardening), which has already merged, and is not this chain's input. The brief is the `PG-285`
entry in `TODO.md`. The acceptance criteria it came with are declared here as six requirement ids:

- **R-01** A right-click (or Ctrl+click) on an attachment chip in the pratica timeline opens the
  chip's own menu. The menu has «Anteprima», «Apri», then `AttachmentChipModel.contextMenuTitles`
  («Mostra nel Finder», «Copia»), each enabled by today's rule and doing today's action. The
  message row's menu does not open.
- **R-02** A right-click anywhere else on the message row still opens the message menu unchanged.
  That covers the header text, the footer, the gaps and the note slot, and the menu still includes
  «Inserisci qui». (Corrected 2026-09-28: the expanded body's text view answers a right-click with
  its own text menu, and did so before this change too; ADR-0069 §D4.) A left click, a double-click, the tooltip and the pending popover
  on the chip behave as today.
- **R-03** `UITests/AttachmentChipContextMenuUITests.swift` goes green through
  `scripts/uitests.sh`. It is not disabled, skipped or weakened. It may be strengthened.
- **R-04** An in-process regression in `PergamenumTests`, the merge gate, observes the chip menu's
  catalogue through the production AppKit `menu(for:)`: titles, order, enablement and routing.
  A drift or a revert then fails without the GUI suite.
- **R-05** `scripts/uitests.sh --affected` selects `AttachmentChipContextMenuUITests` for a
  change under `Sources/Features/Pratiche/`.
- **R-06** Every other surface that hosts an `AttachmentChip` is checked and named, and the trap
  is recorded where the next reader looks. (no-test: documentation and audit obligation)

The plan was read at `1e09448e` (`main`, equal to `origin/main`, clean tree). Every line number
below was checked against that tree.

## ADR outcome: new ADR

**`docs/adr/0069-attachment-chip-menu-is-hosted-by-appkit.md`** (status: proposed).

On the three-part test, the decision is surprising without context and is a real trade-off (six
alternatives were weighed). "Hard to reverse" alone is weak: the shim is local. Two overrides
apply regardless, and two project rules require the record:

- **A deliberate deviation from the obvious approach.** SwiftUI's `.contextMenu` is exactly what
  was there, and it silently never worked. A future reader who meets an `NSView` overlay with a
  gated `hitTest` would "fix" it back.
- **A constraint invisible in the code.** Nothing greppable says that a `List` row's menu takes
  every right-click inside the row.
- **CLAUDE.md requires a GUI test to be justified in its feature's ADR.** This chain adds one.
- **The rule for the next nested menu goes into CLAUDE.md** (ADR §D7), and it needs a record to
  point to.

## What the code says (facts, with sources)

| # | Finding | Source |
|---|---|---|
| F1 | The chip declares its own menu: «Anteprima», «Apri», then `contextMenuTitles[0]`/`[1]`, with `.disabled` rules on the first three. | `Sources/Features/Pratiche/AttachmentChip.swift:60-68` |
| F2 | The whole timeline row, the chip included, carries the message menu. | `Sources/Features/Pratiche/PraticaTimelineView.swift:167`, `:175-183` |
| F3 | The chip's only host is `PraticaMessageRow.attachments`. `PraticaMessageRow` is built only by `PraticaTimelineView.row(_:)`. No inspector, message detail or editor surface builds a chip. | `rg 'AttachmentChip\(' Sources/`; `PraticaMessageRow.swift:135-164`; `PraticaTimelineView.swift:124` |
| F4 | In the failed run the right-click landed on the chip (`Check for interrupting elements affecting "pratiche-attachment-4b96b80a3b5fce56-0" Button`), and «Mostra nel Finder» never appeared. | `$TMPDIR/pergamenum-uitests-20260926-193441.log`; verdict `.git/uitests-verdicts/322b578….partial.verdict` (`red`) |
| F5 | Both menus date from 2026-09-10 (`530e29cc` for the chip, `dddd1401` for the row). The chip's menu has never opened in the timeline. | `git log -S` |
| F6 | `--affected` maps Pratiche sources to `PraticheUITests` only, so a chip change never selects the chip's own UI class. | `scripts/uitests.sh:147-148` |
| F7 | A context menu can be tested in-process by calling `menu(for:)` directly with a synthesized right-mouse event. No `sendEvent` is involved. | `Tests/WikilinkClickNavigationTests.swift:190-279` |
| F8 | The in-process harness delivers no pointer event to SwiftUI. No test in `Tests/` has ever found a representable's `NSView` inside a `HostedView`. | `Tests/HostedViewSupport.swift:75-79`; ADR-0053 Context |
| F9 | Precedents for an AppKit context menu and a pass-through overlay: `rightMouseDown` plus `menu(for:)` plus `NSMenu.popUpContextMenu`, and `hitTest` returning `nil`. | `FormattingTextView.swift:194-243`; `CompletingTextView+Pasteboard.swift:135,262`; `EmbedResizeOverlay.swift:68` |
| F10 | Apple's documentation states no precedence between nested context menus. Third-party reports, and the `ViewBoundContextMenu` package, describe a `List` row's menu applying to the whole row. | Context7 `/websites/developer_apple_swiftui`, read 2026-09-26; github.com/MrAsterisco/ViewBoundContextMenu |
| F11 | No GUI test clicks a chip, so left-click behaviour on the chip has no automated witness. | `rg 'pratiche-attachment' UITests/` |

## Root cause

**Fact:** in the running app, a right-click on the chip inside the timeline's `List` row opens
the row's menu (F4). The chip's nested `.contextMenu` never receives the event.

**Assumption, not needed by the fix:** SwiftUI lifts the row's menu into the backing table row, so
a menu nested in the row is never consulted. Apple does not document this (F10).

The design does not rely on it. An AppKit view over the chip takes the right-click at `hitTest`,
before SwiftUI resolves any menu.

## Design (summary; the ADR has the reasoning)

- **AppKit owns the chip's context click** (ADR §D1). `AttachmentChipMenuView`, an `NSView`, is
  laid over the chip through `AttachmentChipMenuHost`, an `NSViewRepresentable`, as the last
  modifier in the chip's chain and `.accessibilityHidden(true)`. The chip's SwiftUI `.contextMenu`
  is deleted.
- **The overlay claims only the context click** (ADR §D2). `hitTest` returns `self` only for
  `.rightMouseDown`, or `.leftMouseDown` with `.control`, read from `NSApp.currentEvent` through a
  pure static `claimsContextClick(type:modifierFlags:)`. Every other event sees no overlay.
- **The view shows the menu itself** (ADR §D2). `rightMouseDown` and the Control-click
  `mouseDown` pop `menu(for:)` through `NSMenu.popUpContextMenu`. The menu has
  `autoenablesItems = false`, and its entries are read when it opens.
- **One catalogue** (ADR §D3). `AttachmentChipModel.Command`, `.MenuEntry` and
  `.menuEntries(for:state:)` carry today's rules. `contextMenuTitles` is unchanged and supplies
  the reveal and copy titles by identity.
- **Row menu untouched** (ADR §D4).
- **`.accessibilityActions` from the same entries** (ADR §D5), so the commands keep a route that
  does not need the pointer.
- **Fallback, authorised in advance** (ADR §D2): if the overlay does not win the right-click, or
  does not let a left click through, use the container shape (the chip's label hosted inside the
  AppKit view), and record the change in the ADR's implementation notes.

## Tasks

### Task 1: Declarations and red in-process tests (tester) (R-01, R-04, R-02)

The tester owns every signature below. The coder owns the bodies. The target must build at the
end of this task: every test fails on an assertion, never on a build error (ADR-0053 §D1).

**Files, declarations:**

- **`Sources/Features/Pratiche/AttachmentChipModel.swift`**, three declarations:
  - `enum Command: String, CaseIterable, Sendable { case preview, open, reveal, copy }`, with
    `var title: String` and `var identifier: String`, both returning placeholders;
  - `struct MenuEntry: Equatable, Sendable { let command: Command; let title: String; let isEnabled: Bool }`;
  - `static func menuEntries(for content: AttachmentChip.Content, state: (URL) -> FileState) -> [MenuEntry]`,
    returning `[]`.
- **`Sources/Features/Pratiche/AttachmentChipMenuHost.swift`** (new):
  - `@MainActor final class AttachmentChipMenuView: NSView`, with:
    - `var entries: () -> [AttachmentChipModel.MenuEntry]` and
      `var perform: (AttachmentChipModel.Command) -> Void`, defaulting to empty closures;
    - `override func menu(for event: NSEvent) -> NSMenu?`, returning `nil`;
    - `static func claimsContextClick(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) -> Bool`,
      returning `false`.
  - `struct AttachmentChipMenuHost: NSViewRepresentable`, holding the same two closures, with
    `makeNSView`/`updateNSView` that assign them. The body of this glue is written here, because
    no test targets it directly.

**Files, tests:**

- **`Tests/AttachmentChipTests.swift`**: tests for `menuEntries`.
  - The titles in order equal `["Anteprima", "Apri"] + AttachmentChipModel.contextMenuTitles`,
    and the identifiers are distinct.
  - Enablement per case:

    | Case | Enabled |
    |---|---|
    | usable `.file` | all four |
    | missing `.file` | copy only |
    | unusable `.file` | copy only |
    | usable `.storeReference` | open, reveal, copy |
    | missing `.storeReference` | copy only |
    | `.pending` | copy only; `state` is never called |
    | usable `.sh` file (PG-123) | preview, reveal, copy; not open |

    The existing test `theContextMenuOffersExactlyMostraNelFinderAndCopia` (`:171-173`) stays
    unchanged.
- **`Tests/AttachmentChipMenuTests.swift`** (new, `@MainActor`), in four groups:
  1. **`menu(for:)`.** Build an `AttachmentChipMenuView` directly, set `entries` to a fixed list
     that includes one disabled entry, and set `perform` to record what it receives. Call
     `menu(for:)` with `NSEvent.mouseEvent(with: .rightMouseDown, …)`, the
     `WikilinkContextMenu` shape (F7), with no window event and no `sendEvent`. Assert:
     - the titles and their order match the entries;
     - each `isEnabled` matches its entry;
     - `autoenablesItems == false`;
     - each item's `identifier` is its command's identifier;
     - performing each item's action on its target delivers exactly its command to `perform`.
  2. **`claimsContextClick` truth table.** It answers true for `.rightMouseDown`, and for
     `.leftMouseDown` with `[.control]`. It answers false for `.leftMouseDown` with `[]` or
     `[.command]`, and for `.mouseMoved`, `.otherMouseDown`, `.rightMouseUp`, `.leftMouseDragged`
     and `.scrollWheel`.
  3. **Hosted chip, measured first.** Host `AttachmentChip(content: .file(ref), …)` in
     `HostedView`, with a real temporary `.txt` file and `settle()`. Then walk
     `host.hosting`'s subview tree for an `AttachmentChipMenuView`.
     - **If the harness instantiates it:** assert exactly one is found, that its `menu(for:)`
       titles and enabled flags equal `menuEntries` for that file, and that performing
       «Anteprima» hands the file's URL to the chip's `onQuickLook`. This is the test that fails
       if a SwiftUI `.contextMenu` replaces the AppKit one.
     - **If the harness does not:** write neither this group nor group 4. Record the measurement
       in ADR-0069's implementation notes. Never write a test that asserts the harness cannot do
       something (ADR-0053).
  4. **Hosted row, the R-02 guard.** Only if group 3's measurement is positive. Host a
     `PraticaMessageRow` whose `PraticaRowDetail` carries one attachment, one store reference and
     one pending name (fixture shape: `Tests/PraticaLinkAggregationTests.swift:22`), with a width
     of 800. Assert:
     - exactly three `AttachmentChipMenuView`s are found;
     - each is narrower than half the row's width, so the overlay stays on its chip and does not
       cover the row.

**Red:** groups 1 and 2 and the `menuEntries` tests fail on assertions. Group 3 fails because
the chip has no AppKit view yet; Task 3 adds it.

### Task 2: Catalogue and AppKit menu view bodies (coder) (R-01, R-04)

Files: `Sources/Features/Pratiche/AttachmentChipModel.swift`,
`Sources/Features/Pratiche/AttachmentChipMenuHost.swift`.

`AttachmentChipModel`:

- **`Command.title`**:
  - `preview` → «Anteprima»
  - `open` → «Apri»
  - `reveal` → `contextMenuTitles[0]`
  - `copy` → `contextMenuTitles[1]`
- **`Command.identifier`** is `pratiche-attachment-command-<rawValue>`.
- **`menuEntries`** carries the rules of `AttachmentChip.swift:61-67` verbatim, through
  `previewURL`/`openURL`/`revealURL`, with copy always enabled. The `.pending` case never calls
  `state` (ADR-0040 §D8).

`AttachmentChipMenuView`:

- **`menu(for:)`** builds an `NSMenu` with `autoenablesItems = false`. Each item has:
  - `target = self` and action `@objc performEntry(_:)`;
  - `representedObject` set to the command's raw value;
  - `identifier` set to the command's identifier;
  - `isEnabled` taken from the entry.
- **`performEntry(_:)`** maps the raw value back to its command and calls `perform`.
- **`hitTest(_:)`** calls `super.hitTest` only when
  `claimsContextClick(type:modifierFlags:)` holds for `NSApp.currentEvent`, and returns `nil`
  otherwise (no current event included).
- **Showing the menu.** `rightMouseDown(with:)`, and `mouseDown(with:)` when `.control` is held,
  show `menu(for:)` through `NSMenu.popUpContextMenu(_:with:for:)`. `mouseDown` without Control
  calls `super`.
- **Accessibility.** `isAccessibilityElement()` returns `false`.

Swift 6: the class is `@MainActor`. `claimsContextClick` is `nonisolated static`, which needs no
state. The stored closures are main-actor.

Green: Task 1's groups 1 and 2 and the `menuEntries` tests.

### Task 3: Wire the chip (coder) (R-01, R-02)

File: `Sources/Features/Pratiche/AttachmentChip.swift`.

1. **Delete the chip's `.contextMenu { … }`** (`:60-68`).
2. **Add `private func run(_ command: AttachmentChipModel.Command)`.** It switches to the existing
   `preview()`, `openWithDefaultApp()`, `showInFinder()` and `copy()`. No action changes.
3. **Append the overlay as the last modifier of `body`**, after `.popover` and therefore after
   `.accessibilityIdentifier(identifier)`:
   `.overlay { AttachmentChipMenuHost(entries: { AttachmentChipModel.menuEntries(for: content, state: state) }, perform: run).accessibilityHidden(true) }`.
4. **Add `.accessibilityActions`**, iterating the enabled `menuEntries`: one action per entry,
   titled by the entry, running `run(entry.command)` (ADR §D5).
5. **Update the header comment.** It points to ADR-0069: why the menu is AppKit's, and why the
   overlay must stay last in the chain.

`PraticaTimelineView.swift` and `PraticaMessageRow.swift` are **not** edited (ADR §D4).

Green: Task 1's group 3, and group 4 if written.

**Hand checks** (plan M1, M2, M3, M5) run on a Debug build before Task 4's GUI run. If M1 fails
(the overlay does not win the right-click), or M2, M3 or M5 fails (a left click no longer reaches
the chip), switch to ADR-0069 §D2's container fallback in this same task. Then note the switch in
the ADR's implementation notes.

### Task 4: GUI test, strengthened, plus the R-02 witness (tester) (R-01, R-02, R-03)

File: `UITests/AttachmentChipContextMenuUITests.swift`.

**`testAttachmentChipContextMenuShowsBothCatalogueEntries`.** Keep every assertion and timeout
it has. After the two existing ones, add:

- «Anteprima» and «Apri» exist as `app.menuItems`;
- `XCTAssertFalse(app.menuItems["Escludi dalla pratica"].exists, …)`, which proves the message menu
  did not open in its place;
- then dismiss the menu with Esc.

**New `testRightClickBesideTheChipStillOpensTheMessageMenu`.**

- Right-click the element whose identifier `BEGINSWITH "pratiche-message-subject-"`. The fixture
  has one message, and the subject sits in the same header line as the chip
  (`PraticaMessageRow.swift:68-93`).
- Assert «Escludi dalla pratica» appears within 5 s and «Mostra nel Finder» does not exist.

The literal titles follow the file's own convention (no `@testable import` in UI tests). The
launch flags are unchanged (`-disableCalendar`, `-disableUpdater`, `-mailStoreRoot`,
`-stateBase`).

Update the header comment. PG-285: the menu was unreachable. It should say what each test
witnesses and cite the ADR-0069 §D6 justification for the second GUI test.

No `XCTSkip`, no relaxed timeout, no removed assertion. An agent never runs this file; Task 7 runs
it under a gate.

### Task 5: `--affected` selects the witness (coder) (R-05)

File: `scripts/uitests.sh`.

- Change the arm at `:147-148` to `echo "PraticheUITests AttachmentChipContextMenuUITests"`.
- Add one comment line saying why: the chip's own class must run on a Pratiche change, and PG-285
  stayed red because it did not.
- Then run `scripts/uitests.sh --self-test`. It is offline and touches no real verdict, and it
  must stay green.

### Task 6: Records (coder, one step behind a human approval) (R-06)

Files: `docs/adr/0069-attachment-chip-menu-is-hosted-by-appkit.md`, `CLAUDE.md`, `TODO.md`,
`ROADMAP.md`.

- **ADR-0069 implementation notes:** which shape shipped (overlay or fallback), Task 1's
  measurement about hosting a representable offscreen, and any line drift. The status stays
  `proposed` until the merge, then flips to `accepted` with the PR and the merge hash
  (`docs/adr/README.md` §2).
- **`CLAUDE.md`, gate G2:**
  - a working-agreement bullet next to the `DisclosureGroup` one: "A view inside a `List` row that
    carries its own `.contextMenu` cannot have a working SwiftUI `.contextMenu` of its own: the
    row's menu takes every right-click in the row. Host its menu through AppKit, the
    `AttachmentChipMenuHost` shape (ADR-0069)";
  - a Chain decision index entry for ADR-0069.
- **`TODO.md`:**
  - close `PG-285` in the file's closing format, which cites the PR and the merge hash (at ship
    time);
  - file one P3 follow-up: "audit the remaining `.contextMenu` sites for a menu nested inside a
    `List` row that carries its own". Name the files ADR §D7 did not spot-check: `TasksView+Row`,
    `CategorySidebarSection`, `RecordingRow`, `MiniCalendar`, `MonthView`, `TimelineBlockBox`,
    `WeekView`, `WorkspaceRow`, `WorkspaceBrowser+Rows`, `BoardContentLayer`, `TagBrowserView`,
    `DiaryEntryCard`, `NoteTreeRow`, `StarredPane`.
- **`ROADMAP.md:830-832`** (item 6): note that the chip's catalogue is now one naming site
  (ADR-0069 §D3). The wording question («Anteprima» against «Anteprima allegato») stays open
  there.

### Task 7: Verification and gates (orchestrator, then Stefano) (R-01, R-02, R-03)

1. SwiftLint on the changed Swift files.
2. `tuist generate --no-open` for the new source file, then the full unit suite (the TEST-CMD
   below). Every test must pass, not just the new ones.
3. `scripts/uitests.sh --status`, then, **at gate G3**,
   `scripts/uitests.sh AttachmentChipContextMenuUITests`. The argument replaces the selection, so
   both methods run and nothing else does.
   - The run takes the pointer for about one to two minutes.
   - A red is diagnosed from the `.xcresult`
     (`xcrun xcresulttool get test-results summary --path <bundle>`) before anything is rerun.
   - A `contaminated` verdict is rerun, not acted on.
4. Hand checks on a Debug build. Find the build with `ls -dt …/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`,
   then `open -n "$APP" --args -recentVaults '("<throwaway vault>")' -disableUpdater YES`. The
   throwaway vault holds the UI test's fixture pratica plus a store-reference chip and a pending
   chip.

   | Check | Action | Expected |
   |---|---|---|
   | M1 | Right-click a usable chip | The chip's menu: four entries, all enabled |
   | M1b | Right-click a pending chip | Only «Copia» enabled |
   | M1c | Right-click a store-reference chip whose `storePath` is gone | Only «Copia» enabled |
   | M2 | Click a chip | Quick Look opens |
   | M3 | Double-click a chip | The default app opens it |
   | M4 | Hover a chip | The tooltip appears |
   | M5 | Click a pending chip | The popover appears |
   | M6 | Right-click the subject, the sender, a gap in the footer, the note slot | The message menu, «Inserisci qui» included (the expanded body shows its text view's own menu, pre-existing, ADR-0069 §D4) |
   | M7 | Ctrl+click a chip | The chip's menu |
   | M8 | VoiceOver on a chip | Its actions list the enabled commands |
   | M9 | Click the row outside the chips, then press Backspace | The row is still selected, and Backspace still offers «Escludi» |

5. **At merge:** `scripts/uitests.sh --affected`. It now selects both Pratiche classes, and it
   does not block the merge (CLAUDE.md merge-gate rule).

## Observable-contract staleness

Changed contract: the chip's context menu becomes an AppKit `NSMenu` with item identifiers, and
its SwiftUI `.contextMenu` disappears. The titles, the order, the enablement and the actions are
unchanged. `rg 'contextMenuTitles|AttachmentChipContextMenuUITests|pratiche-attachment-'` over the
repo finds these call sites:

| Call site | What happens to it |
|---|---|
| `Sources/Features/Pratiche/AttachmentChip.swift:60-68` | The old rendering; replaced in Task 3 |
| `Tests/AttachmentChipTests.swift:171-173` | Still valid; unchanged |
| `UITests/AttachmentChipContextMenuUITests.swift:3-14, 57-73` | Strengthened and re-commented in Task 4 |
| `Sources/Features/Pratiche/PraticaMessageRow.swift:142-158` | The chip identifiers; unchanged |
| `UX-BLUEPRINT.md:157` | The chip identifiers; unchanged |
| `ROADMAP.md:830-832` | Its line reference goes stale; updated in Task 6 |
| `scripts/uitests.sh:147-148` | The class mapping; changed in Task 5, and asserted by no test |

`CLAUDE.md:484` matches only by coincidence, inside ADR-0040's index line, and needs nothing.

Run the **full** unit suite after Task 3, not only the new tests: the hosted tests share a machine
and a run loop with every other suite.

## Risks and HITL gates

**Risks:**

- **Left-click pass-through is the one mechanism that is not verified in advance.** The risk is
  that SwiftUI's handling of an overlay representable absorbs a left click even though `hitTest`
  returns `nil`. Only M2, M3 and M5 detect it (F11); no GUI test clicks a chip. Mitigation: the
  ADR §D2 fallback.
- **The overlay may not win the right-click** (for example, if the hosting view intercepts
  `rightMouseDown` above its subviews). M1 and the GUI test detect it. Mitigation: the same
  fallback.
- **`hitTest` gated on `NSApp.currentEvent`.** AppKit sets the current event for every event it
  dispatches, synthesized XCUITest events included. An accessibility "show menu" produces no
  mouse event, which is why §D5 adds explicit accessibility actions.
- **The hosted harness may not instantiate a representable offscreen** (F8). Tests 3 and 4 are
  then not written. R-04 still holds through groups 1 and 2 and the `menuEntries` tests, but a
  revert to a SwiftUI `.contextMenu` would then be caught only by the GUI class. The ADR records
  the result either way.
- **Swift 6 strict concurrency** on an `NSView` subclass with stored closures: keep the closures
  main-actor, and the predicate `nonisolated` and pure.
- **Cost:** every Pratiche change now runs a second UI class at merge, two more launches. This is
  accepted: it is the class that witnesses the behaviour.
- **Parallel chains.** A `TODO.md` conflict is resolved by merging `origin/main` into the branch,
  never by force. Re-check that the ADR number 0066 is still free immediately before the merge
  (`docs/adr/README.md` §1).

**HITL gates:**

- **G1, before Task 2:** Stefano accepts ADR-0069's approach. In particular:
  - the §D2 fallback, authorised in advance;
  - the §D5 accessibility actions, which Stefano may drop;
  - the §D6 second GUI test.
- **G2, Task 6:** approval of the `CLAUDE.md` diff (the working agreement and the index entry).
- **G3, Task 7 step 3:** the go-ahead to run the GUI class, which takes over the pointer.
- **Commit, push, PR, merge:** the standard gates. Branch: `fix/attachment-chip-context-menu`.
  Nothing is deleted except nine lines of view code. There is no schema change and no
  external resource.

## Open for Stefano

1. **§D5 accessibility actions.** Keep them (recommended: one modifier, the same catalogue, no
   regression for VoiceOver), or drop them and accept that the chip's commands are pointer-only.
2. **The two GUI tests (§D6).** Both halves of the precedence can only be observed in a live
   `List`. The recommendation is to keep both. The alternative is one method with two phases in
   one launch, which is cheaper but gives a less precise failure attribution.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
