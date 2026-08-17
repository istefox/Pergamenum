# ADR-0008: Capture is a global panel, and the write behind it is not the panel's

- Status: accepted
- Date: 2026-08-16, accepted 2026-08-17 with the panel's mockup (PR #39)
- Supersedes: nothing. Adds M7 of `docs/20260816_Pergamenum_Roadmap.md`, which SPEC v2.2
  does not describe. SPEC §7.4 already calls quick capture "globale"; it is not.

## Context

Quick capture exists (`Cmd+Shift+N`, ADR-0003) and is presented by the window, so it
works only while Pergamenum is the frontmost app. That is the one moment capture is not
needed. The thought that has to be written down arrives while reading a PDF, while on a
call, while in Mail - and by the time the app is in front, the reason to capture has been
replaced by whatever was on screen.

Craft's answer is Quick Entry on `Ctrl+Space` from any app, with four destinations. It is
the feature the whole roadmap starts with, because everything downstream of capture is
worth nothing if nothing gets captured.

Two constraints, and both were checked rather than remembered.

**A global hotkey has two implementations and they differ in what they cost the user.**
`NSEvent.addGlobalMonitorForEventsMatchingMask` is the modern-looking one, and
`NSEvent.h` in `MacOSX26.5.sdk` says of it, verbatim: *"Key-related events may only be
monitored if accessibility is enabled or if your application is trusted for accessibility
access."* `RegisterEventHotKey` is Carbon, is still in the same SDK, is **not** marked
deprecated (`AVAILABLE_MAC_OS_X_VERSION_10_0_AND_LATER`), needs no grant of any kind, and
delivers one event for one registered combination rather than a copy of every keystroke
the user types anywhere.

**TCC has already bitten this project once.** `CODE_SIGN_IDENTITY` defaulted to `-`, so
every rebuild threw away the Calendar and Reminders grants and it was twice mistaken for a
broken read. Adding a second permission - one that lets the app observe every keystroke in
every application - to buy a keyboard shortcut is the wrong trade at any exchange rate.

## Decision

**D1. The hotkey is `RegisterEventHotKey`, not a global `NSEvent` monitor.**

The app asks for no new permission, and the OS hands it exactly one event: the
registered combination was pressed. A user who inspects what Pergamenum can see finds that
it cannot see anything it was not given.

This is a Carbon API in a Swift 6 app and that looks like a smell. It is not: the SDK
shipping with Xcode 26 carries it unannotated, every serious Mac app that offers a global
shortcut uses it, and the alternative is not "more modern" but "requires Accessibility".
When Apple ships a replacement that needs no grant, this decision is worth reopening; until
then the choice is between an entitlement-free Carbon call and a keylogger-shaped
permission prompt.

**D2. Registration can fail, and the failure is visible.**

Registration uses `kEventHotKeyExclusive`, which returns `eventHotKeyExistsErr` when
another process already holds that combination exclusively. That return value is the only
honest source of truth about whether the shortcut works.

The default is `Ctrl+Space`, the same as Craft. On this machine it is free:
`com.apple.symbolichotkeys` has id 60 (previous input source, `Ctrl+Space`) at
`enabled = 0`, as are 61 and 64. That table covers **system** shortcuts only - a
third-party launcher holding the same keys does not appear in it - so the runtime return
value, not the table, is what the UI reports.

Impostazioni › Scorciatoie shows the **registered** state, not the configured one. A
shortcut that could not be taken reads as unavailable with the reason, and offers to pick
another. A settings pane that shows an intention while the feature silently does nothing is
the failure mode this project has already paid for once: `@remind` was wired to nothing,
and five green tests covered the request builder.

**D3. The panel does not activate the app.**

A non-activating `NSPanel` at `.floating`, so the app the user is in keeps its focus and
gets it back untouched when the panel closes. Three consequences that are not obvious and
are all in `.claude/rules/swift.md`:

- `.nonactivatingPanel` does not fire `windowDidBecomeKey`, so key status is taken
  explicitly with `makeKeyAndOrderFront` plus `orderFrontRegardless`.
- `NSApp.activate(ignoringOtherApps:)` is called only on the explicit user trigger - the
  hotkey press - and never on launch or on a programmatic show.
- `NSHostingView` inside the panel is created on the main actor, never off it.

The text field is `ComposerTextField`, the `NSTextField` of ADR-0003 §D5, for the reason
recorded there: SwiftUI returns focus to a `TextField` by selecting all of it, so coming
back from the Programma or Scadenza popover would make the next keystroke replace
everything typed so far.

Unsent text survives a dismiss for sixty seconds. Capture that loses what was typed is
worse than no capture, because it is trusted once.

**D4. The write lives in `Sources/Connector/`, not in the panel.**

`VaultAPI` gains a capture operation; the panel and `perg capture` and the MCP tool are
three front ends onto it. This is ADR-0007 §D2 applied rather than restated: a capture
implemented in the panel is a capture the CLI does not have, and the two would grow
different ideas of which folder an inbox note lives in and what frontmatter it gets.

The write goes through `VaultSession.write` like every other, so it is journalled and
undoable, and the guardrails of ADR-0007 §D6 arm themselves for the connector callers
without the panel having to know.

**D5. `pergamenum://capture` is the same code path.**

The route of SPEC §9 takes `dest`, `text`, `schedule` and `deadline`. A Shortcut, a
bookmarklet in any browser, a Mail rule and a Back Tap all reach capture through it, and
none of them needs an extension, a native messaging host, or a port. The web clipper of the
roadmap is therefore not an app to write: it is a URL to build.

**D6. Four destinations, and the inbox is a real file.**

New note · task to the inbox · append to today's daily note · append to a chosen note. The
destination is remembered between invocations, because the same one is used twenty times in
a row and then never again.

The inbox is `00 Inbox/Capture.md`, a note like any other, and it already exists:
`VaultSession.TaskDestination.inboxPath` has pointed there since M4, and the implementation
uses that rather than inventing a second inbox. *(This paragraph named `Inbox.md` when the
ADR was written, from memory rather than from the code. Corrected on implementing it.)*
SPEC §7.4 defines the Inbox *view* as tasks with no date and no project, and that stays
exactly as it is - this does not replace it, it gives a captured task somewhere to live on
disk from the first second.
Craft's inbox holds tasks attached to no document, which is a state this vault cannot
represent and should not learn to.

**D7. What the panel deliberately does not do.**

- **It does not convert markdown into blocks.** Craft's Quick Entry turns each line into a
  block because Craft has blocks. Here the lines are written as they were typed, and a
  heading is a heading because `#` means one.
- **It does not stay resident as an accessory app.** Pergamenum keeps its normal activation
  policy and its Dock icon; the panel needs the app running, not hidden. A menu-bar item
  (`NSStatusItem`, hideable in settings) covers capture, today, inbox and last note for the
  times the hotkey is not the right gesture.
- **It does not capture the frontmost app's selection by itself.** Reading another app's
  selection is Accessibility again, by a different door. The Shortcut of D5 can pass a
  selection in, because there the user chose to.

## Consequences

- **Testing stops at the seam, and this ADR says so rather than leaving a gap in the
  coverage.** A global hotkey cannot be exercised from XCUITest: the runner drives
  Pergamenum, and the whole point is that Pergamenum is not frontmost. The capture write and
  the URL route are unit-testable and will be; the hotkey registration, the panel appearing
  over another app, and focus returning to it are a manual check, listed in the M7
  acceptance criterion. This project's own record is unambiguous about which of the two
  finds defects.
- **A hotkey conflict will look like a broken app.** Raycast lives on this machine and does
  not appear in `com.apple.symbolichotkeys`. If it or anything else holds `Ctrl+Space`,
  D2's return value is what turns a mystery into a sentence.
- **A panel over a full-screen app is a known risk, not a verified behaviour.** Craft's own
  documentation says its panel does not appear over full-screen applications and the user
  has to leave full screen. Whether that is a Craft choice or a platform rule is not
  established here, and it is the first thing to try by hand rather than to assume.
- **The signing identity matters more than before.** Nothing in D1 needs a TCC grant, which
  is the point - but the app's existing Calendar and Reminders grants still key on the
  signature, so the `Apple Development` identity rule in `Project.swift` stays load-bearing.
- **`perg capture` arrives for free**, and with it the ability for an assistant to put
  something in the inbox with the same guardrails a person gets. That was not the goal and
  is the second time ADR-0007's shape has paid for itself.
