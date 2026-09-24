# PG-225: `Theme.emergency.colors` is missing the three calendar tokens

## Context

`TokenKeys.swift:65-67` declares `ColorToken.calendarPrefestive`, `.calendarFestive` and
`.calendarHoliday`. Both bundled theme JSON files define all three under `color.calendar.*`
(`Resources/Themes/pergamenum-{dark,light}.json:50-54`) — confirmed by grep, zero hits for
`calendar`/`Prefestive`/`Festive`/`Holiday` anywhere in `Theme.swift`. But
`Theme.emergency.colors` (`Theme.swift:242-287`), the hardcoded fallback dictionary, has no
entry for any of the three.

`Theme.rawColor(_:)` (`Theme.swift:37-39`) and `Theme.hexValue(_:)` (`Theme.swift:212-220`)
both do `colors[token] ?? Theme.emergency.colors[token]!` — a force-unwrap. A token present
in the active theme never reaches the `!`, but any test or code path that resolves one of
these three tokens against a *partial* theme (one built with `inheriting: .emergency` before
the bundled JSON is read, e.g. `Theme(document:, id:, inheriting: .emergency)` the way
`Tests/DesignSystemTests.swift:94` already does for other tokens) crashes the whole xctest
process instead of falling back. The `.surfaceReceived` comment at `Theme.swift:253-256`
documents this exact hazard for a different token family — this is the same trap, unfixed
for calendar.

Found while exploring the PG-225/#465 category-colour change (unrelated to that change,
pre-existing). No architecture decision, one file plus its test: no ADR.

## Fix

**`Sources/DesignSystem/Theme.swift`**, inside `Theme.emergency.colors` (after the
`.stickyGrey`/`.category*` block added by #465, or wherever the dictionary literal currently
ends before `],`): three entries, using the same light-theme values already in
`Resources/Themes/pergamenum-light.json:50-54`.

```swift
.calendarPrefestive: RGBA(hex: "#C98B84")!,
.calendarFestive: RGBA(hex: "#B3261E")!,
.calendarHoliday: RGBA(hex: "#D62828")!,
```

No other file changes: `TokenKeys.swift` and both theme JSON files are already correct, and
no call site needs to change — this only fills the fallback dictionary so the existing
force-unwrap has something to find.

## Verification

Add a test to `Tests/DesignSystemTests.swift` that resolves all three tokens against
`Theme.emergency` directly (`Theme.emergency.rawColor(.calendarPrefestive)` etc., or
`Theme.emergency.color(_:)` if that reads better against the file's existing style) and
asserts each one does not crash and returns a non-nil colour — the shape that would have
caught this before it shipped. Place it near `bundledThemesDefineEveryToken()`
(`Tests/DesignSystemTests.swift:85`), since it is testing the same fallback contract from
the other side (the emergency dict, not the bundled JSON).

Run the project's approved test command. `tuist generate --no-open` is not needed first —
no `Project.swift` change.
