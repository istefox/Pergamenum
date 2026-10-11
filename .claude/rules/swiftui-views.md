---
paths:
  - "Sources/**/*.swift"
---

# SwiftUI and AppKit view traps

Moved verbatim from the `## Working agreements` section of `CLAUDE.md` on 2026-10-07; loaded only
when a file matching `paths:` is read.

- **A `SwiftUI` tree that must participate in `List(selection:)` cannot use `DisclosureGroup`.** A
  `DisclosureGroup`'s label is not a row of the enclosing `List`, so a `.tag` on it satisfies no
  binding — the list lights nothing and swallows every click, and it fails silently (`RootView.swift`
  §D-noted trap: a `.badge` applied after `.tag` drops the tag the same way). Use flat recursive rows
  instead (`NoteListPane.swift`'s shape: a `@ViewBuilder` row plus, as a sibling, `if isExpanded {
  ForEach(children) {...} }`, chevron and depth drawn by hand) — see ADR-0024.
- **A view inside a `List` row that carries its own `.contextMenu` cannot have a working SwiftUI
  `.contextMenu` of its own:** the row's menu takes every right-click in the row, and the nested one
  silently never opens (PG-285 — the attachment chip's menu had never opened since it was added).
  Host the nested menu through AppKit instead, the `AttachmentChipMenuHost` shape: an `NSView`
  overlay whose `hitTest` claims only the context click and lets every other event through — see
  ADR-0069.
- **A Quick Look host with the default claim takes the keyboard from every `List` beside it.**
  `quickLook(urls:isPresented:)` makes its host first responder when the view appears and again on
  every update while it has files, and a click on a row of a `List` next to it never takes the
  keyboard back: in the pratica timeline Backspace beeped and excluded nothing from the first launch
  on (PG-298, measured in ADR-0070's implementation notes). A host that shares a surface with a
  `List` passes `claimsFocus: false`, so it takes first responder only to present the panel and
  hands it back when its control of the panel ends. The Workspace board keeps the default on
  purpose: its bare-spacebar preview depends on the claim.
- **On a macOS `List`, a row click does not give the list the keyboard, and Backspace is not a key
  press.** Measured in PG-298 (ADR-0070): a click changes the selection but leaves the window itself
  first responder, so nothing in the list sees a key; and once the list's table is first responder,
  it sends Backspace down AppKit's Delete command, where `.onKeyPress(.delete)` never runs. Bind the
  list's `@FocusState` with `.focused(_:)` and set it on selection change (`.onChange(of: selection)
  { _, new in if new != nil { isFocused = true } }`), and answer the key with `.onDeleteCommand`,
  which also takes forward delete and enables Modifica ▸ Elimina while the list has focus
  (`PraticaTimelineView.swift`). Do not keep the `@FocusState` as a guard in front of the handler:
  it read false after every click, and `.onDeleteCommand` already runs only while focus is inside
  the list.
- **A text view's pointer is set after `NSTextView`'s own, never from SwiftUI.** `NSTextView`'s
  `mouseMoved(with:)` puts its I-beam back after anything set earlier, so a cursor set only from
  `cursorUpdate(with:)`, from cursor rects, from `push()`/`pop()` or from a SwiftUI `.pointerStyle`
  over the view shows for an instant, or while the mouse is still, and is gone at the first move
  (PG-219, measured with a real mouse). The view decides in its own file (`pointer(at:)`) and calls
  `EditorPointer.apply()` from `cursorUpdate(with:)` and again after `super.mouseMoved(with:)`
  (ADR-0090). `EditorPointer.swift` is the one file that names an `NSCursor` for a text view; a
  synthetic mouse event does not reproduce the reset, so the visible pointer is checked by hand.
- **The opposite failure of the rule above: a `@State` a confirmation dialog nils on its own
  dismissal cannot be read back inside the confirm button's `Task`.** `NoteListPane`'s
  «Sposta nel Cestino» button did `Task { if let note = deleting, ... }` — pressing the button
  dismisses the dialog first, which runs the `isPresented` binding's setter and nils `deleting`,
  so by the time the `Task` body ran it always saw `nil` and silently skipped the trash call: the
  note reappeared in the sidebar with no alert and no file in the Finder Trash. Capture the value
  before the `Task`, or receive it as the closure's own parameter via `.confirmationDialog(...,
  presenting: state) { value in ... }` — the shape `WorkspaceBrowser`'s own delete dialog and
  `NoteListPane+FolderVerbs`'s folder-delete dialog already used, and the one this fix adopted.
- **`firstRect(forCharacterRange:)` returns a zero rectangle for a text range TextKit 2 has
  not laid out yet** — reliably true at the end of a long note, since TextKit 2 lays out
  lazily. A zero rectangle handed to a popover or panel's placement clamps it to the screen's
  bottom-left corner instead of failing loudly, so a UI test asserting on a popup's position
  can pass by accident there. Anything anchoring UI to a character range must confirm layout
  has reached that range first, not assume `firstRect` always returns something meaningful.
