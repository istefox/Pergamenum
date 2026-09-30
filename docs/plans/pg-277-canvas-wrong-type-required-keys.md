# Fix: a JSON Canvas required key with a wrong JSON type is kept, not defaulted (PG-277)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to `PG-257`'s chain, which has
already merged, and is not this chain's input. The brief is the `PG-277` entry in `TODO.md` (#616,
P2, kind:fix), which ADR-0065 §D13.4 names and leaves open. The acceptance criteria are declared
here as eleven requirement ids.

The plan was read at `f8fead16` (`HEAD`). `origin/main` is at `f916dac7`, and the two differ in no
file this plan reads or touches (`git diff --stat f8fead16 origin/main` over `Sources/Core/Canvas`,
`Tests/Canvas*`, `Tests/FormatEdgeCorpus*`, ADR-0065 and `BoardEdgeLayer.swift` is empty). Every
line number below was read from that tree.

## What is already settled, and not reopened

ADR-0065 (accepted) governs. Registered as it stands:

- **§D0: opaque-first by default** (a SPEC decision the ADR registered). What the codec cannot read
  is carried through untouched. Refusal is only for what cannot be carried.
- **§D5.4: the opaque mechanism.** An unreadable element of `nodes`/`edges` is kept as a
  `JSONValue` in `CanvasDocument.opaqueNodes`/`opaqueEdges`, with its original index, and is
  re-inserted there on encode (`JSONCanvas.swift:79-96`, `:117-133`).
- **§D5.5: refusal is reserved** for `nodes`/`edges` present and not an array. Such a file cannot
  be written back consistently. A malformed element can be.
- **§D5.3: an optional key is consumed only when understood.** A wrong-typed optional key
  (`color`, `label`, `subpath`, the sides and ends) stays in `unknown`, and its element stays
  readable. This plan does not change that.
- **§D6.3: a reconciliation diverges on an opaque difference.** It is not changed. R-09 pins the
  case this fix makes newly reachable.
- **§Context: what "round-trips" means for `.canvas`.** The file must equal the codec's canonical
  encoding of the same JSON value (`FormatEdgeCorpus.canonicalCanvas`). Layout is not preserved.
  Values are.

§D13.4 names the defect: "A canvas's required keys with a wrong JSON type (`"x": "12"`,
`"text": 42`) are replaced by their defaults." This plan closes it by applying §D5.4's rule to one
more input class. It changes no rule.

## The defect, as the code has it

`CanvasNode.init?(_:)` (`JSONCanvas.swift:238-272`):

- `x`, `y`, `width` and `height` are read as `(object[k] as? NSNumber)?.doubleValue ?? default`
  (`:242-245`). A string, an array, an object or a null fails the cast, so the key takes its
  default (0, 0, 260, 120). The key is always consumed (`:250`), so `rawValue` writes the default
  over the file's value (`:278-281`).
- A JSON boolean passes the cast. `JSONSerialization` hands back a `CFBoolean`, which is an
  `NSNumber`, so `"width": true` reads as 1 and is written back as `1`. That is a coercion, not a
  default, and it is the same loss.
- `text`, `file` and `url` read `as? String ?? ""`, and the key is always consumed (`:254-263`).
  So `"text": 42` is written back as `"text": ""`.

The following already behave correctly and are only pinned by this plan:

- A node's `id`/`type` with a wrong type fails the `guard ... as? String` (`:239`), and the node
  becomes opaque.
- An edge's `id`/`fromNode`/`toNode` with a wrong type does the same (`:346-349`). The ticket's
  `"fromNode": 3` example is therefore already kept verbatim today.

## What counts as a wrong type

Taken from JSON Canvas 1.0, read live at <https://jsoncanvas.org/spec/1.0/> on 2026-09-28:

- `id`, `type`, `x`, `y`, `width` and `height` are required on every node, `x` to `height` typed
  "integer";
- `text` (text node), `file` (file node) and `url` (link node) are required strings;
- `id`, `fromNode` and `toNode` are required strings on an edge;
- everything else is optional.

"Present" means that `object[key] != nil` after `JSONSerialization`. A JSON `null` is present, as
`NSNull`. The expected type is judged through `JSONValue(_:)` (`JSONValue.swift:17-33`), which
already separates a `CFBoolean` from a number.

| Key | Where | Expected | Absent | Present, expected type | Present, anything else (null included) |
|---|---|---|---|---|---|
| `id`, `type` | node | string | opaque (today) | read | opaque (today) |
| `x`, `y`, `width`, `height` | every node, `.unknown` kinds included | a JSON number: integer or fractional, any sign, exponent form allowed; **not** a boolean | default 0/0/260/120 (**today, kept**) | read as `Double` | **opaque (new)** |
| `text` | `"type": "text"` | string | `""` (**today, kept**) | read | **opaque (new)** |
| `file` | `"type": "file"` | string | `""` (**today, kept**) | read | **opaque (new)** |
| `url` | `"type": "link"` | string | `""` (**today, kept**) | read | **opaque (new)** |
| `id`, `fromNode`, `toNode` | edge | string | opaque (today) | read | opaque (today) |
| any optional key, `pergamenum-*` included | node, edge | — | — | consumed | left in `unknown`; the element stays readable (§D5.3, today) |
| another kind's payload key (`file` on a text node) | node | — | — | — | left in `unknown`, whatever its type (§D5.1, today) |

Three boundary choices, each deliberate:

- **"Integer" is not enforced.** No rounding of node geometry exists anywhere in
  `Sources/Features/Workspace` (`rg -n "rounded|round\(" Sources/Features/Workspace` finds none on
  geometry). `rawValue` writes `Double(x)` (`:278`), so this app's own boards can carry fractional
  geometry. Enforcing the spec's integer would turn the app's own cards opaque.
- **A boolean is not a number,** although `NSNumber` carries both. The codec already makes this
  distinction for foreign keys (`CanvasTests.distinguishesBooleanFromNumberOnRoundTrip`). A required
  key gets the same treatment.
- **An absent required key keeps its default.** An absent key has no value that a save could
  overwrite, so nothing is lost. Tools that generate canvases can omit geometry, and turning such
  boards opaque would empty them on screen. The encode then adds the key with the default the card
  was drawn with. That is a repair, and no value is lost. It stays outside the round-trip corpus for
  that reason (Task 1).

## Acceptance criteria

- **R-01** A node whose required key is present with a wrong JSON type, per the table above, is
  kept as an opaque element at its original index. Every other element of the board still decodes.
  Decode followed by encode reproduces the element's JSON value, which is the canonical round-trip.
  The cases that must hold include:
  - `"x": "12"`, `"y": []`, `"width": true`, `"height": null`, and `"x": {}` on an `.unknown`-kind
    node;
  - `"text": 42` and `"text": null`;
  - `"file": 7`;
  - `"url": []`.
- **R-02** After an open and a save that do not touch the malformed element, its JSON value on
  disk is unchanged, and the rest of the board changes as the app meant it to. This holds on both
  write paths a board has:
  - the Workspace's own autosave (`WorkspaceController.move` of another node, then
    `flushPendingSave()`);
  - a background board writer the person never opened: a note rename's board repoint
    (`VaultSession.renameNote`).
- **R-03** A node's `id`/`type` and an edge's `id`/`fromNode`/`toNode` with a wrong type stay
  opaque, as today. Pinned cases: edge `"fromNode": 3`, `"toNode": null`, `"id": 5`; node
  `"id": 7`, `"type": 1`.
- **R-04** Every well-typed element decodes exactly as today. `CanvasTests`,
  `CanvasRoundTripTests`, `CanvasReconciliationTests`, `FormatEdgeCorpusTests` and every other
  existing test stay green, **unmodified**.
- **R-05** `x`/`y`/`width`/`height` accept any JSON number: `12.5`, `-3`, `1e2` and `0` decode as
  a readable node with that frame and re-encode canonically. A JSON boolean is not a number, which
  R-01 covers.
- **R-06** An absent required key keeps today's behaviour. The node stays readable, with no opaque
  entry, and its geometry defaults to (0, 0, 260, 120). An absent `text`, `file` or `url` reads as
  `""`.
- **R-07** An edge whose `fromNode` or `toNode` names a node that is opaque behaves as follows:
  - it stays a readable `CanvasEdge` in `edges`;
  - it is not drawn (`BoardEdgeLayer.swift:31-32` resolves both endpoints with `if let`);
  - an edit elsewhere on the board does not remove it, it is written back unchanged, and nothing
    traps;
  - deleting its other endpoint, a readable node, removes it as today
    (`WorkspaceController+Nodes.swift:155`).
- **R-08** A wrong-typed optional key never makes an element opaque (§D5.3, unchanged):
  - a file node with `"subpath": 3` stays readable, with `subpath == nil` and the value kept in
    `unknown`;
  - so does a node with `"pergamenum-crop": 5`, ADR-0020's key;
  - so does a text node carrying `"file": 7`.
- **R-09** Take a node that `base` reads and `theirs` has made malformed. `reconcile(mine:base:theirs:)`
  diverges. Its reasons name the node's id and the opaque index (`nodes[i]`), and it never adopts
  `mine` over the external value.
- **R-10** Nothing changes in the on-disk format, in `IndexCache.schemaVersion` or in any entry of
  `.claude/protected-interfaces`. `perg` and `pergamenum-mcp` build unchanged: they compile
  `JSONCanvas.swift` through `sharedSources`. (no-test: checked by `git diff --stat`, the
  protected-interface hook and the three builds in Task 4)
- **R-11** The record follows the code:
  - ADR-0065 gains a dated cross-reference under §D13.4 and an implementation-notes follow-up. They
    name the widened §D5.4 set, the wrong-type definition and the consequences below.
  - The `CanvasDocument.opaqueNodes` doc comment (`JSONCanvas.swift:16-18`) and the `CanvasNode.init?`
    comment (`:248-249`) state the new rule.
  (no-test: documentation obligation)

## ADR outcome: existing ADR, ADR-0065, with a dated follow-up note

**ADR-0065 governs, unchanged in its decisions.** §D5.4 states the rule: an element the codec
cannot read is kept opaque at its index. §D0 registers opaque-first as the default. §D13.4 names
this exact defect as out of that chain's scope. This fix extends §D5.4's list of unreadable inputs
with one class. The mechanism, the encode and the reconciliation are unchanged.

**No new ADR.** The significance test fails on "hard to reverse". The change is one initializer's
body in one file, with no on-disk format, schema or interface change, so reverting it takes a few
lines. None of the override conditions applies either:

- no security boundary is involved;
- no constraint is invisible in the code, because the table above goes into the ADR-0065 note and
  into the doc comments;
- there is no deviation from the governing ADR's approach, since this is its approach.

The one explicit "no" a future reader might undo is "do not coerce `"12"` to 12". It is recorded
in the ADR-0065 note, where a reader of §D5.4 or §D13.4 will look.

**The note (Task 5, behind G2)** follows the precedent of ADR-0043's dated "Cross-reference,
2026-09-20 (PG-168, #313)" blockquote and ADR-0026's dated amendments. It has two parts:

- a blockquote under §D13.4: "Closed by PG-277 (#616), PR #N, `<merge hash>`: see Implementation
  notes, Follow-up PG-277";
- a short `### Follow-up: PG-277` subsection under «Implementation notes», holding the wrong-type
  table's substance, the three boundary choices, the rejected alternatives below and the
  consequences under G1.

It is not a supersession. No decision of ADR-0065 is reversed.

**Alternatives weighed, for the note:**

- **Refuse the open**, `DecodingError` style. Rejected, for two reasons:
  - §D5.5 reserves refusal for a shape that cannot be written back, and a malformed element can be,
    verbatim, through the existing opaque path.
  - Every background reader decodes with `try?`: `VaultScanner.swift:132`,
    `FolderFileOperations.swift:218,287` and `NoteFileOperations.swift:179`. A refusal there skips
    the **whole** board, so one bad key would stop every other file node on it from being
    repointed on a rename, and would drop every board task on it from the index.
- **Keep the element readable and carry only the bad key.** The card would be drawn at a default
  frame, and the wrong-typed value written back until the app changes that property. Rejected, for
  three reasons:
  - it draws a position, a size or a text the file never had, as if they were real, which is the
    guess ADR-0065 exists to remove;
  - it needs per-property provenance on `CanvasNode`, a value type that the whole Workspace mutates
    and compares with `==` (`filePathRepoint`, `CanvasReconciliation.swift:122-131`), which makes
    a third carrying tier beside §D5.3 and §D5.4;
  - the first move, resize or keystroke on the card then replaces the value anyway, so the loss is
    only deferred to a gesture made on invented geometry.
- **Coerce leniently** (`"12"` → 12, `true` → 1). Rejected: it is a guess, and it changes the
  value's JSON type on write, which fails the canonical round-trip. `true` → 1 is today's defect.

## Tasks

Order: the tester writes Tasks 1 and 2 and the coder writes Task 3. Tasks 4 and 5 close the chain.
**No new declaration is needed by any test.** Every test drives existing internal API:

- `CanvasDocument(data:)`, `encoded()`, `nodes`, `edges`, `opaqueNodes`, `opaqueEdges`;
- `CanvasDocument.reconcile`;
- `WorkspaceController.open(board:)`, `move(nodeIDs:by:)`, `flushPendingSave()`;
- `VaultSession.renameNote(at:to:)`.

The target builds at the end of Tasks 1 and 2, so red is an assertion failure, never a build
break. Zero GUI tests: everything is in-process in `PergamenumTests`.

### Task 1 — Codec-level tests, red where the defect lives (tester) (R-01, R-03, R-05, R-06, R-07, R-08, R-09, R-04)

Files:

- **new** `Tests/CanvasRequiredKeyTypeTests.swift`, with a header comment citing ADR-0065 §D5.4,
  §D13.4 and this plan;
- **extend** `Tests/FormatEdgeCorpus.swift` (`canvases`, `:116-153`).

Then run `tuist generate --no-open`, because a new file under `Tests/**` must reach the generated
project.

Tests in the new file. Each one names its R-id in a comment, and "Today" is the predicted state
before Task 3:

| Test | Asserts | Today |
|---|---|---|
| `aWrongTypedRequiredKeyKeepsTheNodeOpaque` (`@Test(arguments:)`, one case per R-01 value; fixture `[nodeA, malformed, nodeB]`) | `nodes.map(\.id) == ["a", "b"]`, `opaqueNodes.map(\.index) == [1]`, `encoded() == canonicalCanvas(json)` | red |
| `aMalformedNodeSurvivesAnEditElsewhere` | decode, remove `b`, append `c`, encode: the element with `id == "m"` in the output equals the fixture's object, compared as `JSONValue` | red |
| `aWrongTypedIdentityKeyWasAlreadyOpaque` (R-03 cases, nodes and edges) | opaque indices as expected, round-trip | green, pin |
| `everyJSONNumberFormIsReadableGeometry` (`12.5`, `-3`, `1e2`, `0`) | readable, `frame == CGRect(x: 12.5, y: -3, width: 100, height: 0)`, no opaque entry, round-trip | green, pin |
| `aBooleanIsNotANumber` (`"width": true`) | opaque at index 1, the encoded value is still the boolean `true` (`CFBoolean` check) | red |
| `anAbsentRequiredKeyKeepsItsDefault` (`{"id":"n","type":"text"}`, plus a file node and a link node without payload) | readable, `frame == CGRect(x: 0, y: 0, width: 260, height: 120)`, `kind == .text("")` / `.file(path: "", subpath: nil)` / `.link(url: "")`, `opaqueNodes.isEmpty`. **Not** a round-trip assertion (see the boundary choices above) | green, pin |
| `aWrongTypedOptionalKeyStaysReadable` (`"subpath": 3` on a file node, `"pergamenum-crop": 5`, `"file": 7` on a text node) | readable, the value is in `unknown`, round-trip | green, pin |
| `anEdgeToAnOpaqueNodeIsKeptAndWrittenBack` (nodes `[nodeA, m with "x": "12"]`, edge `a → m`) | `edges.map(\.id) == ["e"]`; after `nodes[0].x += 10` and encode, the edge object is unchanged and `m`'s object is unchanged | red, because `m` is read with x 0 today |
| `aNodeMadeMalformedByTheirsDiverges` (`base` has `m` readable at x 40, `theirs` has `"x": "12"`, `mine` = `base` plus one node) | `.diverged(reasons)` with `reasons.contains("m")` **and** `reasons.contains("nodes[1]")`; never `.adopted` | red, because it diverges today on `m` alone |

Corpus additions to `FormatEdgeCorpus.canvases`. `everyCorpusCaseRoundTripsOrIsRefused` then
covers them with no change to `FormatEdgeCorpusTests.swift`:

- `wrongTypeGeometry` (`"x": "12"`, `"width": true`, `"height": null` on three nodes), red;
- `wrongTypePayload` (`"text": 42`, `"file": 7`, `"url": []`), red;
- `wrongTypeEdgeEndpoint` (`"fromNode": 3`), green, pin;
- `numericGeometryForms` (`12.5`, `-3`, `1e2`, `0`), green, pin.

No absent-key case is added to the corpus: a repair is not a round-trip.

The existing canvas tests are not touched (R-04). The tester runs the new file and
`FormatEdgeCorpusTests`, and reports the red and green counts against the "Today" column.

### Task 2 — The two write paths, red (tester) (R-02, R-07)

File: `Tests/CanvasRequiredKeyTypeTests.swift`, a second `// MARK:` section.

- `aWorkspaceSaveOfAnotherEditKeepsTheMalformedNode` (`@MainActor`):
  - setup: `CanvasTemporaryRoot`, `makeFile("Board.canvas", json)` with `nodeA`, `m`
    (`"type": "text"`, `"x": "12"`) and edge `a → m`, then
    `WorkspaceController().attach(to: CanvasStore(root:))` and `open(board: "Board.canvas")`;
  - act: `move(nodeIDs: ["a"], by: CGSize(width: 10, height: 0))`, then `flushPendingSave()`;
  - on disk: `a.x == 10`, `m`'s object equals the fixture's, and edge `e` is present with
    `fromNode "a"` and `toNode "m"`;
  - in memory: `controller.document.opaqueNodes.count == 1` and `saveState == .saved`;
  - `detach()` at the end, as the existing controller tests do.
  - Today: red, because `m` is written back with `"x": 0`.
- `aNoteRenameRepointsABoardWithoutRewritingItsMalformedNode` (`@MainActor`, `async`):
  - setup: a `TemporaryVault` holding `Vecchio titolo.md` and `Labs.canvas`, the board carrying a
    file node for the note and a text node `m` with `"text": 42`, built in the shape of
    `VaultSessionFileOperationsTests.swift:15-18,33-51`;
  - act: `session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")`;
  - on disk: the file node points at `Nuovo titolo.md`, and `m`'s object still has `"text": 42`.
  - Today: red, because the repoint's decode and encode write `"text": ""`.

### Task 3 — The fix (coder) (R-01, R-02, R-05, R-06, R-07, R-08)

File: `Sources/Core/Canvas/JSONCanvas.swift`, and nothing else in `Sources/`.

- `CanvasNode.init?(_ object: [String: Any])` keeps its signature. Only the set of inputs for which
  it answers `nil` widens. `CanvasDocument.elements(of:in:read:)` already turns `nil` into an
  opaque element, so the opaque path needs no change.
- Every required key is read through one private reader with three outcomes:
  - absent: the default;
  - expected type: the value;
  - anything else: the initializer answers `nil`.
- Geometry is judged through `JSONValue(_:)` and `.doubleValue`, so a boolean is refused. `text`,
  `file` and `url` are judged through `.stringValue`, and only inside their own kind's case.
- An `.unknown` kind checks geometry only.
- `CanvasEdge.init?` is untouched, because its guards already refuse a non-string identity key.
- Correct the two comments that become incomplete: the `opaqueNodes` doc (`:16-18`) and the
  §D5.1/§D5.3 comment in the initializer (`:248-249`). Both now name "a required key present with
  a wrong JSON type" and cite §D13.4's closure.
- Size limits: the file is 386 lines and SwiftLint warns at 400 (`.swiftlint.yml:45-47`). If the
  change crosses 400, or pushes the initializer over the cyclomatic-complexity warning, move the
  reader into a new Foundation-only file, `Sources/Core/Canvas/CanvasRequiredKey.swift`. It must
  not import SwiftUI, or the `perg` and `pergamenum-mcp` builds break (ADR-0001 §D1). The file is
  picked up by the `Sources/Core/**` glob and needs no manifest edit. Run
  `tuist generate --no-open` after it.
- Done when Task 1 and Task 2 are green and no existing test changed.

### Task 4 — Staleness sweep, full suite, three builds (coder, then orchestrator) (R-04, R-10)

**Observable contract that changes:** what `CanvasDocument(data:)` returns for a node with a
wrong-typed required key. Such a node moves from `nodes`, where it carried defaults, to
`opaqueNodes`. Nothing else changes: no signature, no file shape, no JSON the connectors emit.

Call sites and tests asserting the old behaviour, grepped for this plan:

- `rg -n "CanvasNode\.init|read: CanvasNode|read: CanvasEdge" Sources Tests` finds one caller,
  `JSONCanvas.swift:69-70`. The two other hits, `LinkCardTitle.swift:6` and `CardTextStyle.swift:6`,
  are comments about `unknown` keys and stay true.
- `rg -n --pcre2` for a required key followed by a string, boolean, null, array, object or number
  of the wrong kind, over `Tests UITests Sources`, finds **no** fixture that feeds a wrong-typed
  required key, once the MCP tool schemas and design-token JSON are excluded. So no existing test
  asserts the defaulted value, and none needs updating. The coder re-runs both greps after Task 3,
  and any new hit is updated here with its reason, never deleted.
- The decode readers whose view of a malformed node changes (from "interpreted with defaults" to
  "not seen"):
  - `VaultScanner.swift:132` (board tasks);
  - `NoteFileOperations.swift:179,218` and `FolderFileOperations.swift:218,223,287,292` (repoints);
  - `CanvasStore.swift:141-144` (tray "placed" set);
  - `WorkspaceReferences.swift:31-39`;
  - `BoardEdgeLayer.swift:31-32`.

  None asserts a count that includes such a node. The consequences are listed under G1.

Verification:

- The **full** unit suite, not only the canvas files:
  `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
  -only-testing:PergamenumTests test`. The codec is read by the scanner, the rename passes, the
  Workspace, reconciliation and the Pratiche board links.
- `xcodebuild ... -scheme perg ... build` and `-scheme pergamenum-mcp ... build`, because both
  compile `JSONCanvas.swift`.
- SwiftLint on the touched files.
- `git diff --stat origin/main` touches no `IndexCache.swift`, no file named in
  `.claude/protected-interfaces` and no `.canvas` fixture on disk (R-10).
- `scripts/uitests.sh --status`, then `--affected` at merge per CLAUDE.md. This change reaches no
  GUI class, so `--affected` should select nothing. The merge gate is the unit suite.

### Task 5 — Records (coder; the ADR-0065 wording behind G2) (R-11)

Files:

- `docs/adr/0065-format-round-trip-faithful-or-refused.md`:
  - under §D13.4, a dated blockquote in ADR-0043's cross-reference form;
  - under «Implementation notes», a `### Follow-up: PG-277` subsection with the table's substance,
    the three boundary choices, the three rejected alternatives and the G1 consequences.

  Neither the decision text nor the Acceptance table is edited. The PR number and merge hash are
  filled in after the merge, the same way ADR status flips work (`docs/adr/README.md` rule 2). If
  the wording lands before the merge, it reads "PR #N" until then.
- This plan: a closing «Implementation notes» section, with departures, if any.
- Not edited:
  - `CLAUDE.md`: its ADR-0065 index entry ("keeps unreadable elements at their index") stays true;
  - `ROADMAP.md` §Chain 1: its "residuals are filed" sentence stays true.

  `TODO.md` and issue #616 are closed by `/ship`, not here.

Run `scripts/check-adr-references.py` after the ADR edit, following `git fetch origin`.

## Risks and HITL gates

- **A malformed node vanishes from the board.** Today it is drawn at a wrong or default place, and
  it is damaged on the next save. After the fix it is carried and not drawn. This is ADR-0065's
  own trade (fate 1 over a silent fate 4), but it is visible to the person. G1 asks for
  acknowledgment.
- **The opaque index can go stale after an edit (`PG-281`, #605, open).** Deleting or inserting a
  readable node before an opaque one shifts its relative position on the next save. Only order
  changes, and no content is lost. This fix makes more elements opaque, so `PG-281` becomes more
  reachable. It is named and not folded in.
- **A generated id can collide with an opaque node's id.**
  `WorkspaceController+Duplicate.swift:32` builds `taken` from readable nodes and edges only. A
  generated 16-hex id colliding with an opaque id is a 2^-64 event. This is pre-existing for every
  §D5.4 element and is not addressed.
- **Not examined:** a number outside `Double`'s range (for example `1e999`), and what
  `JSONSerialization` hands back for it. Precision beyond 2^53 is ADR-0065 §D13.6, pre-existing.
- **SwiftLint limits on `JSONCanvas.swift`** (386 lines, warning at 400). Task 3's fallback file
  handles it.
- **Working tree state:** `.claude/test-cmd` is modified to `NONE`, uncommitted, in this worktree.
  So the `Stop` hook currently runs no tests here. Do not commit that change: ADR-0062's landing
  check has already flagged `.claude/test-cmd` toggles twice. Restore it before `/build`, or run
  the suite explicitly, as the orchestrator decides.
- **Gates:**
  - G1 before Task 3 (consequence acknowledgment);
  - G2 at Task 5 (the ADR-0065 note's wording);
  - commit, push, PR and merge are Stefano's.

  There is no schema change, no deletion and no release.
- No externally provisioned resource is needed: no network, no service, no credential, no port.

## Open for Stefano

- **G1: accept the consequence of "carried, not interpreted" for a newly opaque node.** A node
  made opaque by this fix:
  - is not drawn, and neither are its edges;
  - keeps its old path when the file it names is renamed or moved;
  - does not reach the Tasks views, when it holds a task line;
  - leaves its file offered again in the board's tray;
  - is not listed among the board's referenced notes.

  Today the same node is interpreted with a default value, and that value is destroyed on the next
  write. **Recommended: accept.** It is the §D5.4 behaviour every other unreadable element already
  has.
- **G1b, a product question this plan does not decide:** whether a board holding opaque elements
  should say so, for example with one recorded problem on open. ADR-0065 §D5.4 decided silence for
  its elements, and this plan inherits that decision. **Recommended: not in this chain.** If wanted,
  file it as its own ticket, because it applies to every §D5.4 element and not only to this class.
- **G2:** the wording of the ADR-0065 follow-up note (Task 5).

## Test command

`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

This is the unit suite only, and CLAUDE.md records why the `Stop` hook must stay restricted to
`PergamenumTests`. The GUI suite runs only through `scripts/uitests.sh`.

## Implementation notes

Written after the implementation, 2026-09-28. G1 taken as recommended (accept); G1b not in this
chain; the G2 wording is in ADR-0065 «Follow-up: PG-277», for review before commit.

**Red before the fix, measured.** Every test marked red was red, every pin was green: in the new
file, all nine `aWrongTypedRequiredKeyKeepsTheNodeOpaque` cases, `aMalformedNodeSurvivesAnEditElsewhere`,
`aBooleanIsNotANumber`, `anEdgeToAnOpaqueNodeIsKeptAndWrittenBack`, `aNodeMadeMalformedByTheirsDiverges`
and both write-path tests failed; the four pins passed. In the corpus, `wrongTypeGeometry` and
`wrongTypePayload` failed and `wrongTypeEdgeEndpoint` and `numericGeometryForms` passed.

**Departures.**

1. **The reader lives in its own file from the start.** With the reader inline and a `guard` per
   payload case, `CanvasNode.init?` reached cyclomatic complexity 12 (warning at 10) and
   `JSONCanvas.swift` 397 lines. `Sources/Core/Canvas/CanvasRequiredKey.swift` (Foundation only)
   holds `number(_:in:absent:)` and `payload(ofType:in:)`. The payload is read once, in the
   initializer's leading `guard`, keyed by the node's type (`""` for `group` and any unknown type,
   which check geometry only), so the `switch` gains no branch. The initializer is back under the
   warning, and `JSONCanvas.swift` is 395 lines.
2. **Two extra assertions in one test.** `aMalformedNodeSurvivesAnEditElsewhere`
   also checks that `b` is gone and `c` present in the output, so the edit is shown to have
   happened. No assertion from the table was dropped.

**Staleness sweep, re-run after Task 3.** `rg -n "CanvasNode\.init|read: CanvasNode|read: CanvasEdge"`
finds the same one caller (`JSONCanvas.swift:70-71`), the two comments named above, and the new
file's own doc comment. The wrong-typed-required-key grep over `Tests UITests Sources` (MCP schemas
excluded) finds only the new tests, the corpus additions, one design-token fixture
(`DesignSystemTests.swift:38`, a `"text"` key inside a DTCG token group, not a canvas) and the new
doc comment. No existing test needed updating.
