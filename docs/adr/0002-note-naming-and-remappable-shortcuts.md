# ADR-0002: "Note" in the interface, and shortcuts the user can move

- **Status**: Accepted
- **Date**: 2026-08-13
- **Context**: SPEC v2.2 (`docs/20260811_Pergamenum_SpecApp.md`) §10 and §12, post-M6

## Context

Three requests arrived together, and they turn out to be one subject: what the app
calls things, and what happens when the user presses a key.

The sidebar pane holding the editor was labelled "Vault". SPEC §10 calls the same pane
"Editor". Neither word says what is in it, and "vault" is an Obsidian term of art that
means nothing to someone who has not used Obsidian. The pane holds notes.

That pane showed one flat list of every note in the vault, with the containing folder
printed underneath each row as a caption. It says where a note is and never says what
the vault looks like: SPEC §4.1 is explicit that the app respects a structure it does
not impose, and the sidebar was the one place that structure could have been visible
and was not.

The shortcuts were literals spread across four `Commands` structs. Two consequences.
First, nobody could change one. Second, nothing could see them all at once, and they
had already collided: `Navigation.Pane.today` put the Vista menu's "Oggi" on Cmd+T and
the File menu's daily note was already there. Two menu items on one key means one of
them never fires, silently, and no test could have caught it because there was nothing
to ask.

## Decision

### D1 - The interface says "Note"; the code and the specification keep "vault"

Every user-visible string. The pane is "Note", the folder is "la cartella note", the
File menu opens "Apri cartella note…" and lists "Cartelle recenti".

The Swift identifiers do not follow: `VaultController`, `RecentVaults`, `VaultScanner`
stay as they are. "Vault" is the word SPEC §4 uses for the concept throughout, it is
the word the `harness-system` conventions use, and renaming the domain to match a
label would leave the code unable to be read against the document that specifies it.
The one case renamed is `Navigation.Pane.vault` → `.notes`, because that case *is* the
pane and nothing else.

The specification is not edited. It says "Editor" where the app now says "Note", and
recording the divergence here is honest in a way that quietly rewriting §10 would not
be: the spec is the older document and it is allowed to be older.

### D2 - The sidebar shows the folder tree

`NoteTree` builds the structure from the index's note paths. Folders before notes at
every level, both groups in `localizedStandardCompare` order so `9` sorts before `10`
the way the Finder does. The identity of a row is its relative path, so two notes with
the same title in different folders stay two rows.

Expansion state lives in the view, not in the tree, because it has to be reachable
from outside: "Espandi tutto", and a note opened from a backlink, a wikilink or the
quick switcher, whose folders the sidebar opens so the selected row is visible rather
than merely selected.

Only markdown, because the index holds only markdown. A folder containing nothing but
PDFs does not appear. This is a real limit and it is written down rather than hidden;
lifting it means indexing attachments, which is a larger change than this one.

The flat list is kept and is what a filter falls back to: a match three folders down is
easier to see in a list than as a tree opened around it.

### D3 - One catalogue of commands, and the menus read their keys from it

`ShortcutCommand` lists every remappable command with its title, its menu and its
default binding. `ShortcutStore` holds the user's changes over that, persisted in
`UserDefaults` as one JSON string. Every `.keyboardShortcut` in the menu bar is now
`shortcuts.shortcut(for: .someCommand)`.

`KeyBinding` is this app's own type rather than SwiftUI's `KeyboardShortcut`, which is
neither `Equatable` nor `Codable` - and all three properties are needed to store a
binding, show it, and tell whether two commands ended up on the same keys. Its modifier
bits are its own too, so what is written to disk does not depend on a framework
constant.

Consequences that fall out of having a catalogue at all:

- A test asserts no two shipped defaults share a binding. It found the Cmd+T collision
  described above, which is now resolved: the panes moved to Control-Command-digit,
  which §10 leaves unassigned, and Cmd+T stays with the daily note.
- Conflicts between *user* bindings are reported, not prevented. macOS itself allows
  two menu items on one key, and refusing the second would make swapping two shortcuts
  impossible - the intermediate state is always a collision.
- A command may have no shortcut at all. That is stored as an empty binding rather than
  as a missing entry, because a missing entry is what "never changed" looks like and
  the default would come straight back.

### D4 - The recorder takes keys with a local event monitor

While recording, the combination being typed is usually a menu shortcut, and the menu
bar claims those before any view in the window sees them - so neither `onKeyPress` nor
a first-responder `NSView` can be the mechanism. A local monitor runs inside
`NSApplication.sendEvent`, ahead of that dispatch, and returning nil from it swallows
the event so the menu does not also fire.

### D5 - Test overrides arrive as a property list, and are never persisted

`-shortcutOverrides` reaches the app through the argument domain, exactly as
`-recentVaults` does, and `ShortcutStore` refuses to persist a map that arrived that
way - the same guard, for the same reason: a UI test must not leave its throwaway
bindings in the user's real preferences.

The value has to be written as an old-style property list, not as JSON. `UserDefaults`
runs an argument whose value begins with `{` through the old-style plist reader, and a
value that reader cannot parse is **dropped entirely** rather than kept as text, so a
JSON literal never reaches the app at all. This was found by measurement, after a test
that should have failed loudly instead passed with the default binding still in place.
The store therefore also accepts modifiers written as digits, because an old-style
plist has no number type.

## Alternatives considered

**Renaming the domain types to `Notes…`.** Rejected, see D1: the code would stop
matching the specification it implements.

**`OutlineGroup` for the tree.** Rejected: it owns its expansion state privately, and
this tree has to be opened from outside.

**Scanning the disk for folders so empty ones appear.** Rejected for now: it introduces
a second source of truth beside the index for the sake of folders with nothing in them.

**Preventing conflicting bindings.** Rejected, see D3.

## Consequences

- The menu bar is now driven by data. A command added to `ShortcutCommand` appears in
  the settings pane automatically; one that is not in the catalogue has no shortcut,
  which is visible, rather than an unchangeable one.
- SwiftUI `Commands` do observe an `@Observable` store: a shortcut changed in Settings
  is live in the menu bar without a relaunch. Verified by a UI test that presses the
  new key and then checks the old one no longer works.
- `VaultBrowser` lost the note list to `NoteListPane` and went from 646 lines to 493.
  Still over the 400-line warning, so the debt SwiftLint records against it is smaller
  and not paid off.
