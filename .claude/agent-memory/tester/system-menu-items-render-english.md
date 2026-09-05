---
name: system-menu-items-render-english
description: Pergamenum's own strings are Italian, but macOS-supplied app-menu items (About, Settings, Services, Hide, Quit) render in English in this bundle — a UI test must not look them up by an Italian title.
metadata:
  type: project
---

`CFBundleDevelopmentRegion` is `en` and the built bundle ships no `.lproj`, so AppKit
localizes every *system-provided* app-menu item to English regardless of the app's own
Italian UI. Measured 2026-09-04 (`UpdateMenuUITests.swift`, ADR-0031/Sparkle chain, batch 2):
a precondition asserting `app.menuBars.menuItems["Informazioni su Pergamenum"]` failed even
though the feature under test (a sibling item, «Cerca Aggiornamenti…») was present and
correctly placed.

**Why:** cost a full test-run cycle to diagnose from an xcresult accessibility snapshot before
attributing the failure correctly (not a feature defect).

**How to apply:** for a *system-supplied* item (About, Settings/Preferences, Hide, Quit,
Services submenu) prefer its `accessibilityIdentifier` where AppKit gives one stable regardless
of locale — About is `orderFrontStandardAboutPanel:`, Settings is `menuAction:` (shared with
other actions, so title is the only handle there) — and fall back to the **English** title, not
the Italian one, only if the identifier does not resolve. This does not relax CLAUDE.md's
"never find a control by its title" working agreement: that rule is scoped to app-authored
controls, which always carry an identifier the app sets itself. A system-provided item outside
the app's control is the one legitimate exception, and even then the identifier (where one
exists) is preferable to any title. Every *app-authored* command in the same menu (e.g. «Cerca
Aggiornamenti…») keeps its normal Italian title — this gotcha applies only to items AppKit
itself supplies.
