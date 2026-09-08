# ADR-0035: A view block's attachment measures its own content, capped at 320pt

- Status: accepted
- Date: 2026-09-08. Found by Stefano during hand-check of the query-builder chain (ADR-0034):
  a `pergamenum-view` fence with a small result set (a one-row table, an empty board) reserved
  the same fixed 320pt attachment as a forty-card one, leaving a visible empty area below sparse
  content.
- Supersedes: nothing. **Amends ADR-0033 §D8**, whose fixed 320pt height is replaced by a
  content-adaptive height capped at 320pt, scrolling internally past the cap exactly as the
  fixed height already did.
- Depends on: ADR-0033 §D8 (the cap value and the "`ScrollView` at the host site, never inside
  `RenderedViewBlock`" rule both survive unchanged — this ADR's own measurement depends on the
  latter), the `.onGeometryChange`/`CappedContent` precedent already in `TranscludedNoteView.swift`.

## Context

`ViewBlockAttachment.height` was a constant: every drawn `pergamenum-view` fence reserved exactly
320pt regardless of its result set, so the note's layout below the block never moved as the
result set grew or shrank (ADR-0033 §D8, R-06). That trade was deliberate and the reasoning still
holds for a *large* result set — nobody wants a forty-card board pushing a screen and a half of
text down the page. But it also means a fence with one matching note draws a mostly-empty 320pt
box, which reads as broken rather than as a deliberate design choice.

The fix has one real complication: `RenderedViewBlock`'s content height is not known when TextKit
first asks `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)`. The
query result arrives asynchronously, inside a SwiftUI `.task`, and there was no channel from that
SwiftUI state back into the `nonisolated` TextKit attachment code that answers the question.

## Decision

**D1. The height is adaptive, clamped between a 24pt floor and the original 320pt ceiling — never
unbounded.** `ViewBlockAttachment.height` becomes three constants: `minimumHeight = 24`,
`maximumHeight = 320` (R-06's original cap, unchanged value), and `unmeasuredHeight = 120` (see
D4). `attachmentBounds` returns `min(max(measured ?? unmeasuredHeight, minimumHeight),
maximumHeight)` at the proposed line fragment's own width, exactly as before. The rejection this
ADR does *not* reopen: an unbounded, purely intrinsic height is still wrong for the reason
ADR-0033 §D8 gave it — a forty-card board would still be a screen and a half of attachment, and
the height would still move under the reader on every vault change. Past the cap, the host's own
`ScrollView` still takes over, unchanged.

**D2. The measurement crosses from SwiftUI's main-actor layout into TextKit's `nonisolated`
`attachmentBounds` through a small lock-guarded box on the host, not a shared `@MainActor`
property.** `NSHostingView` is `@MainActor`; `attachmentBounds` is not. `ViewBlockHeightBox` (an
`@unchecked Sendable` class wrapping an `NSLock`-guarded `CGFloat?`) is the one value both sides
touch. `ViewBlockHostView`, a small `NSHostingView<AnyView>` subclass, carries it as `nonisolated
let measuredHeight`. The box lives on the host, not the attachment, because the attachment is
rebuilt fresh on every styling pass (`EditorDecorationDelegate+ViewBlockRendering.swift`) while
the host survives across passes (`ViewBlockHostStore`, keyed by ordinal, ADR-0033 §D3) — so the
measurement has to live where it survives, or every keystroke would re-measure from scratch.

**D3. The measurement point is inside the existing `ScrollView`, and that placement is
load-bearing.** `ViewBlockHostStore.rootView(...)` wires `.onGeometryChange(for: CGSize.self)` on
`RenderedViewBlock`, *inside* the `ScrollView` that already wraps it. A vertical `ScrollView`
proposes `nil` height to its content, so what's measured is `RenderedViewBlock`'s true ideal
height — never the capped height the attachment ends up reserving for it. This is what keeps the
cap from feeding back into what's measured: moving the `ScrollView` relative to the measurement,
or moving the measurement inside `RenderedViewBlock` itself, would make a capped block's own
measured height equal to the cap forever, and it could never report growing past its own first
measurement. `RenderedViewBlock` still gets no `ScrollView` of its own (ADR-0033 §D8's other
rule, unchanged) — the transclusion and export paths still draw the block at its natural,
unbounded height (R-10, R-11).

**D4. Before any measurement arrives, the attachment reserves `unmeasuredHeight = 120`, not the
320pt cap.** TextKit 2 lays out lazily — an attachment below the viewport is never instantiated
and therefore never measured until scrolled into view. A 320pt default would mean every fence
visibly collapses from 320 to its usually-smaller real height the first time it's scrolled past,
which is a worse first impression than the box this ADR is fixing. 120pt approximates the
"header, no result yet" placeholder height, so the common case is the block growing as results
fill in, not a layout collapsing. The measurement persists on the host across styling passes, so
this placeholder jump happens at most once per fence per note session, not on every scroll-past.

**D5. A height-change callback never invalidates TextKit synchronously.** `onGeometryChange`'s
action runs on the main thread during SwiftUI's own layout of a view TextKit is laying out;
calling `NSTextLayoutManager.invalidateLayout` from there would re-enter it. The callback instead
stores the new height (via `storableHeight(measured:current:)`, D6) and schedules one `Task {
@MainActor }`-deferred relayout, coalesced per Coordinator turn via a `pendingViewBlockRelayout`
flag so several fences reporting in one pass buy a single relayout. The deferred body calls
`manager.invalidateLayout(for: manager.documentRange)` — the same call `applyFolding` and
`applyTransclusion` already make in production — followed by the existing `growToFitTheText`,
which never sets a frame directly (the one operation this codebase has a documented regression
from, in `NoteTextView+Coordinator.swift`'s comment on `growToFitTheText`). No
`storage.edited(.editedAttributes, ...)` call is added: nothing about a paragraph's *content*
changes, only the size its attachment provider reports, and `edited` would mint a fresh
`ViewBlockAttachment`/provider on the next pass and reset the SwiftUI host's internal scroll
position.

**D6. `storableHeight(measured:current:)` clamps before it compares, which is what makes the
cycle terminate.** A pure static function on `ViewBlockAttachment`: clamps the raw measurement
into `[minimumHeight, maximumHeight]` first, then compares the clamped value against the
currently stored one with a `0.5pt` epsilon (matching `growToFitTheText`'s own tolerance),
returning `nil` (no relayout owed) when they don't differ meaningfully. Clamping before comparing
is what stops an over-cap board's height jittering between measurements (5000pt, then 5003pt) from
scheduling a relayout forever — both clamp to the same `maximumHeight`, so the second measurement
stores nothing. `RenderedViewBlock`'s ideal height is not itself a function of the attachment's
reserved height (D3 breaks that loop), so the sequence measure → clamp-and-compare → store →
invalidate → relayout → re-measure at the same width always terminates in one bounce.

## Consequences

- A fence with a small result set no longer reserves visibly empty space; a large one behaves
  exactly as before, scrolling internally past 320pt.
- `Tests/ViewBlockHostStoreTests.swift`'s prior assertion of content-*independence* is replaced —
  that property is precisely what this ADR removes — with assertions of the new clamp behaviour
  (unmeasured, below-cap, above-cap, below-floor, width still independent of height) and a new
  `storableHeight` convergence suite covering the anti-oscillation case directly.
- No index field, no frontmatter key, no `.canvas` property, no migration, no protected interface
  touched — the whole change is `Sources/Features/Editor/`, entirely below ADR-0033's existing
  attachment/host-store mechanism.
