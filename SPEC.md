# SPEC — Word-grained markdown reveal-on-caret in the editor

**Topic slug:** word-grained-markdown-reveal-on-caret-in

## Objectives

Today's reveal-on-caret mechanism (ADR-0018 §D2, extended by ADR-0029) conceals markdown
delimiters everywhere except the caret's own paragraph, tracked as `revealedParagraphs: Set<Int>`
in `EditorDecorationDelegate`. Revealing an entire paragraph is coarser than necessary for inline
emphasis and link constructs: a long paragraph with several bold/italic runs and a wikilink shows
all of their markers at once whenever the caret sits anywhere in that paragraph.

This feature narrows the reveal unit for emphasis and link constructs from "the whole paragraph"
to "the delimited span itself" (bold/italic/strikethrough run, or link/wikilink syntax), so only
the construct the caret (or an active selection) actually touches shows its markdown, while the
rest of the paragraph stays rendered. The feature ships behind a new, separate, off-by-default
setting — it does not change default behavior for anyone who does not opt in.

## Scope

**In scope:**
- Span-level reveal for inline emphasis: `**bold**`, `*italic*`, `~~strikethrough~~`.
- Span-level reveal for links: `[[wikilink]]`, `[[wikilink|alias]]`, `[text](url)`.
- A new, dedicated, off-by-default setting controlling this behavior, alongside the existing
  `hidesMarkup` setting.
- Applies identically to the note editor and to Workspace `.text` cards (both consume
  `EditorDecorationDelegate`, ADR-0028 §D1).
- Selection-range reveal: every span intersected by a non-empty selection reveals its markers, not
  only the span containing the caret.
- Nested emphasis (e.g. bold containing italic): only the innermost span containing the caret
  reveals; outer spans stay concealed until the caret also leaves the outer span's range.

**Out of scope (unchanged, stays paragraph/line-level as today):**
- Blockquote `>`, heading `#`, horizontal rule.
- List markers (bulleted/ordered) and checkboxes.
- Tables (`NSTextAttachmentViewProvider`-hosted grid).
- `pergamenum-view` fences.

## Stack

No new dependency. Swift 6, SwiftUI/AppKit (TextKit 2 via `NSTextView`), same as the rest of the
editor. Implementation lives in `Sources/Features/Editor/EditorDecorationDelegate*.swift` and the
settings surface in the existing Impostazioni editor section, following the design-token binding
rule (no hardcoded colors/fonts).

## Architecture

- **New span model.** `EditorDecorationDelegate` currently tracks only
  `revealedParagraphs: Set<Int>` (paragraph-granularity). This feature adds a per-paragraph scan
  that locates emphasis/link spans and their character ranges within the paragraph currently being
  styled, independent of (and additive to) `revealedParagraphs`. The exact recompute strategy
  (per-styling-pass rescExpectations vs a lighter cache) is left to the architect, constrained only
  by "no perceptible typing lag" — the interview surfaced no fixed performance budget beyond that.
- **Reveal predicate.** A span reveals its delimiters when the caret (collapsed) falls anywhere
  inside its full range (including the delimiter characters themselves), or when it intersects a
  non-empty selection range. For nested spans, the reveal predicate matches the innermost span
  whose range contains the caret; an outer span reveals only once the caret is also outside every
  inner span nested within it.
- **New setting.** A new boolean setting (name/wording left to the architect/design pass, sits next
  to `hidesMarkup` in the existing editor settings section) gates the span-level mechanism.
  Default `false`. When `false`, behavior is byte-for-byte identical to today
  (`revealedParagraphs`-only, paragraph granularity) — zero regression for existing users. This
  follows the same persistence path as `hidesMarkup` (`VaultSettings`).
- **Shared delegate, shared toggle.** Because `EditorDecorationDelegate` is shared between the note
  editor and Workspace `.text` cards (ADR-0028 §D1), the new setting applies to both surfaces
  identically — no card-specific override, no reopening of ADR-0029's card exclusion boundary
  beyond what ADR-0028 already crossed.

## Data model

No persisted data model changes. No new frontmatter key, no index field, no `.canvas` property, no
migration, no `schemaVersion` bump. The new setting is a `Bool` in the same settings storage
`hidesMarkup` already uses.

## API

No connector-facing API change. `Sources/Core`, `Sources/Connector`, `perg`, and
`pergamenum-mcp` are untouched — this is a pure `NSTextView`/AppKit rendering concern local to
`Sources/Features/Editor` (and, via the shared delegate, `Sources/Features/Workspace`).

## UI flows

1. User opens Impostazioni → Editor section, sees the new toggle next to the existing "nascondi
   markup" (`hidesMarkup`) option, off by default.
2. User enables the toggle. In the note editor (and in any open Workspace `.text` card):
   - Typing `**bold**` outside the caret's own span still renders as bold with markers concealed,
     exactly as it looks under paragraph-level reveal.
   - Caret moves into the bold span (anywhere between and including the `**` delimiters): only
     that span's `**` markers reveal; any other emphasis/link span in the same paragraph stays
     concealed.
   - Caret moves out of the span (into plain text or into a different span): the span re-conceals,
     rendering as styled bold text again.
   - Selecting a range spanning two spans reveals both simultaneously; collapsing the selection
     back to a caret re-evaluates against the single span (or none) the caret now sits in.
   - Caret inside `[[Nota reale|testo mostrato]]`: the whole link syntax (target, pipe, alias,
     brackets) reveals together, never just the alias half.
   - Caret inside the italic portion of `**bold con *italic* dentro**`: only the `*...*` markers
     reveal; the outer `**...**` stays concealed.
3. User disables the toggle: editor reverts immediately to today's paragraph-level reveal, no
   further action needed.

## Edge cases

- Caret exactly adjacent to a delimiter character (e.g. right before the opening `**` or right
  after the closing `**`) is treated as inside the span — delimiter characters are part of the
  span's range for the reveal predicate.
- A paragraph containing only out-of-scope constructs (heading, list, blockquote, table, view
  fence) with no emphasis/link spans behaves exactly as it does today regardless of the new
  toggle's state.
- A paragraph mixing an out-of-scope construct (e.g. a heading) with an in-scope span (e.g. a bold
  run inside the heading text) reveals the heading `#` marker under the existing paragraph rule and
  the bold span under the new span rule, independently — the two mechanisms are additive, not
  mutually exclusive.
- Mid-typing a new delimiter pair (e.g. typing `**` to start a bold run before any closing `**`
  exists) has no closed span yet, so nothing reveals under the new mechanism until the pair closes;
  behavior in that interval is unaffected by this feature (governed by existing unclosed-fence /
  unclosed-emphasis handling already in the codebase).
- Multi-cursor input is not a feature of this editor; only a single caret or a single contiguous
  selection is in scope, consistent with the rest of the editor.

## Success criteria

- [ ] R-01 — With the new setting enabled, moving the caret into a `**bold**`, `*italic*`, or
      `~~strikethrough~~` span reveals only that span's own delimiters; other emphasis spans in the
      same paragraph remain concealed.
- [ ] R-02 — With the new setting enabled, moving the caret into a `[[wikilink]]` or
      `[text](url)` construct reveals the construct's full syntax (brackets/parens/pipe/alias
      included); other link/emphasis spans in the same paragraph remain concealed.
- [ ] R-03 — Moving the caret out of a revealed span re-conceals it back to its rendered form.
- [ ] R-04 — A non-empty selection intersecting two or more spans reveals every intersected span
      simultaneously.
- [ ] R-05 — For nested emphasis (e.g. bold containing italic), only the innermost span containing
      the caret reveals; the outer span stays concealed until the caret also leaves the inner span's
      range.
- [ ] R-06 — Blockquote, heading, list/checkbox, table, and `pergamenum-view` fence constructs are
      unaffected by this feature at any setting value — they keep today's paragraph/line-level
      reveal behavior exactly as-is.
- [ ] R-07 — The new setting defaults to off; with it off, editor behavior is unchanged from
      today's paragraph-level `revealedParagraphs` mechanism (byte-for-byte, no regression).
- [ ] R-08 — The setting lives in the existing editor settings section, next to `hidesMarkup`, and
      persists the same way `hidesMarkup` does.
- [ ] R-09 — The new behavior applies identically in the note editor and in Workspace `.text`
      cards, since both share `EditorDecorationDelegate`.
- [ ] R-10 — Unit test coverage exists for the span-range computation and the reveal/conceal
      predicate (mirroring `Tests/MarkupHidingTests.swift`'s existing structure), covering: single
      span reveal, multi-span paragraph with only one revealed, selection spanning multiple spans,
      and nested emphasis innermost-only reveal.
- [ ] R-11 — Manual verification in a Debug build of: typing and moving the caret through
      `**bold**`, `[[wikilink]]`, and `[[target|alias]]`, with the setting on and off, in both the
      note editor and a Workspace `.text` card (no dedicated XCUITest required, per repo
      convention on hand-written UI test additions).
