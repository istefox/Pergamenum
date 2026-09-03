---
name: textkit2-attachment-view-accessibility
description: An NSTextAttachmentViewProvider-hosted view is drawn but invisible to XCUITest/VoiceOver unless the NSTextView hands it to accessibilityChildren, and no offscreen unit test can observe the hosting.
metadata:
  type: project
---

A real `NSView` hosted by `NSTextAttachmentViewProvider` in this app's editor (the ADR-0029
GFM table grid) renders correctly and is still absent from the accessibility tree:
`NSTextView` answers `accessibilityChildren()` from its **text**, not from its subviews, and
the hosted view lives inside the private `_NSTextViewportElementView` TextKit 2 makes per
laid-out fragment. Measured 2026-09-03: grid on screen at 286x96 with a real superview and
window, `super.accessibilityChildren()` = 0, XCUITest's snapshot showed the whole `TextView`
node as a leaf.

**Why:** the same class of gap `CompletingTextView+Accessibility.swift` was already written
for drawn embeds (an orphan `NSAccessibilityElement` that never reached VoiceOver). A real
view is not exempt from it — being in the view hierarchy is not being in the AX hierarchy.

**How to apply:** anything the editor draws through TextKit 2 that a UI test or VoiceOver
must reach has to be offered from `CompletingTextView.accessibilityChildren()` explicitly.
And it cannot be proved offscreen: a window never ordered in has an empty visible rect, so
`NSTextViewportLayoutController` builds no rendering surfaces and never hosts the attachment
view — `ensureLayout` plus an explicit `layoutViewport()` still leave `superview` nil. A unit
test can only assert the offering rule; the hosting half belongs to the XCUITest suite.
