---
name: textkit2-custom-fragment-injection
description: How to get a real instance of a custom NSTextLayoutFragment subclass (TranscludedLineFragment, HorizontalRuleFragment, FoldedHeadingFragment) into a real TextKit 2 layout pass for a unit test, without NoteTextView.
metadata:
  type: project
---

Pergamenum's editor decorates specific paragraphs by returning a custom
`NSTextLayoutFragment` subclass from
`EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`
(`EditorDecorationDelegate.swift:255-270`). That delegate callback is the *only* supported
way to get such a subclass into a real layout pass — there is no
`NSTextLayoutManager.replaceTextLayoutFragment` or similar API to splice one in after the
fact (confirmed by grep: no such symbol appears anywhere in AppKit usage in this repo).

**Pattern for testing one of these fragments' geometry logic directly, offscreen** (used for
`TranscludedLineFragmentWidthTests.swift`, mirrors `TransclusionLayoutTests.swift`'s existing
low-level `NSTextContentStorage`/`NSTextLayoutManager`/`NSTextContainer` fixture style rather
than going through `NoteTextView`):

1. Build a real `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, same as
   `TransclusionLayoutTests.swift`'s `frames(...)` helper.
2. Write a tiny private `NSTextLayoutManagerDelegate` conformer whose
   `textLayoutManager(_:textLayoutFragmentFor:in:)` constructs and returns the custom
   fragment subclass (`TranscludedLineFragment(textElement:range:)` etc.), capturing it in a
   `nonisolated(unsafe) var made: SubclassType?`.
3. Set `layout.delegate = delegate` **before** setting `content.textStorage`'s string /
   calling `layout.ensureLayout(for:)` — the delegate hook only fires during layout.
4. Return the fragment **together with** the content storage, layout manager and delegate
   from the fixture helper, all four in one tuple. `NSTextLayoutManager.delegate`,
   `.textContainer`, and the content storage's layout-manager list are weak/unowned on
   AppKit's side. If only the fragment is returned, everything else is deallocated on
   return and `fragment.textLayoutManager` reads `nil` — a property that should read the
   container silently falls back to a wrong-but-plausible value, which reads as "the fix
   didn't work" when the real bug is fixture lifetime, not the code under test.

Reference the existing correctly-fixed sibling class first when writing a red test for this
bug shape: `HorizontalRuleFragment.ruleWidth` (`HorizontalRuleFragment.swift:31-34`) is the
canonical "read `textLayoutManager?.textContainer.size.width`, never
`layoutFragmentFrame.width`" fix, with a comment explaining why
(`layoutFragmentFrame.width` is the *text's own* width, near-zero for a short/collapsed
line, not the column width). The same defect recurred in `TranscludedLineFragment.draw(at:in:)`
(2026-09-04) despite the sibling fix already existing in the same file family — grep for other
`layoutFragmentFrame.width` reads in `Sources/Features/Editor/*Fragment*.swift` when auditing
for this class of bug again.

See also [[swift-testing-only-testing-gap]] (the `@Suite struct` name, not the file's base
name, is what `-only-testing:PergamenumTests/<Name>` must match — held again here:
`TranscludedLineFragmentWidthTests.swift` declares `@Suite struct TranscludedLineFragmentWidth`).
