---
name: pergamenum-standard-menu-items-are-english
description: Pergamenum's system-provided menu items render in English ("About Pergamenum", "Settings…") despite the Italian UI, because the bundle is en-only — a UI test asserting the Italian title of a standard item fails.
metadata:
  type: project
---

The app's own strings are Italian, but every menu item macOS supplies itself (About, Settings,
Services, Hide, Quit) renders in **English**: `CFBundleDevelopmentRegion` is `en` and the built
bundle has no `.lproj` at all, so AppKit localizes the standard app menu to English. Measured
2026-09-04 from a UI-test accessibility snapshot:
`MenuItem, identifier: 'orderFrontStandardAboutPanel:', title: 'About Pergamenum'`, followed by
`title: 'Settings…'`.

**Why:** `UITests/UpdateMenuUITests.swift` (ADR-0031, Sparkle) asserted
`app.menuBars.menuItems["Informazioni su Pergamenum"]` as a precondition before looking for
«Cerca Aggiornamenti…», and failed on it in 11 s — not a defect in the feature, which was
present and correctly disabled one row below.

**How to apply:** a UI test that reaches for a *system-provided* menu item must use the English
title. The Italian titles in this repo's UI tests are correct only for items the app declares
itself (`Nuovo task rapido`, `Apri nel Workspace`, `Rinomina…`). CLAUDE.md's
"never find a control by the words on it" rule still applies to app-authored controls; a
`CommandGroup` button has no `accessibilityIdentifier`, so its title is the contract, and for a
standard item that title comes from the system's English, not from the app.
