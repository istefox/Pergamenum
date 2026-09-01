import SwiftUI

/// The text of one column: the editor, the find bar, the reading view, and what a click on
/// an embedded file does.
///
/// In a file of its own so `EditorColumnView` stays inside SwiftLint's type body length. It
/// extended `VaultBrowser` until the split view (ADR-0012 D4) moved the editor's state down a
/// level, into the column it describes.
extension EditorColumnView {
    /// Writes a pasted picture into the vault beside the note, returning the name the
    /// embed should carry.
    ///
    /// Through a temporary file and `importFileIntoVault` rather than a second copy of
    /// the same logic: that is what already picks a free name and copies into the note's
    /// folder, for a dropped file and now for a pasted one.
    func save(pastedImage data: Data, in note: VaultController.OpenNote) -> String? {
        vault.importPastedImage(data, near: note.relativePath)
    }

    /// Opens the Quick Look panel on an embedded file.
    ///
    /// Reached by clicking the file name inside `![[foto.png]]` while its raw syntax is
    /// still on screen - `hidesMarkup` off, or the run not yet collapsed into a picture
    /// (still rendering, or not an image/PDF). Once ADR-0018 slice 3 draws the picture
    /// in the run's place, a click there selects the run instead
    /// (`selectEmbed(at:in:)`) - and, unlike a heading or emphasis marker, the caret
    /// reaching that line does not bring the raw text back (D5's deliberate exception
    /// to D2). A name the vault cannot place is reported rather than swallowed: a
    /// broken embed is worth knowing about.
    func preview(embed name: String, in note: VaultController.OpenNote) {
        guard let root = vault.root else { return }
        guard let relative = Attachment.resolve(name, nearNoteAt: note.relativePath, inVaultAt: root)
        else {
            vault.recordProblem("file non trovato nel vault: \(name)")
            return
        }
        previewURLs = [root.appending(path: relative, directoryHint: .notDirectory)]
        isPreviewingEmbed = true
    }

    /// The editor itself, with everything the text view needs wired to it.
    ///
    /// Here rather than inline in the column's `body` for the reason this file exists at
    /// all: the browser is the widest view in the app, and M8 gave the text view two more
    /// inputs.
    func editing(_ note: VaultController.OpenNote) -> some View {
        NoteTextView(
            text: Binding(
                // This column's note, and not the facade: the facade answers for whichever
                // column has the focus, so both halves would show the same text.
                get: { tab?.note.text ?? "" },
                // The focus first, inside the setter: a keystroke in the column that does not
                // have it would otherwise be typed into the other column's note.
                set: { text in focused { vault.updateOpenNoteText(text) } }
            ),
            theme: theme,
            noteTitles: vault.index.allNotes.map(\.title),
            tagSuggestions: tagSuggestions,
            spellCheck: vault.settings.spellCheck,
            hidesMarkup: vault.settings.hidesMarkup,
            editorCommands: slashCommands,
            onRunCommand: commandActions.run,
            onFollowLink: follow(title:),
            onOpenEmbed: { name in preview(embed: name, in: note) },
            vaultRoot: vault.root, notePath: note.relativePath, thumbnails: vault.thumbnails,
            onDropFile: { url in vault.importFileIntoVault(url, near: note.relativePath) },
            onPasteImage: { data in save(pastedImage: data, in: note) },
            insertion: pendingInsertion,
            onInsertionApplied: { pendingInsertion = nil },
            findRequest: findRequest,
            onFindApplied: { selection in
                // The flags are cleared first: `open` bumps a focus request, and leaving them
                // set would re-open the bar on the next update and bump it again, taking the
                // caret back out of the note on every keystroke.
                let replacing = navigation.isReplaceRequested
                navigation.isFindRequested = false
                navigation.isReplaceRequested = false
                find.open(replacing: replacing, over: selection, in: note.text)
            },
            matches: find.matches,
            currentMatch: find.matches.isEmpty ? nil : find.current,
            replacements: pendingReplacements,
            onReplacementsApplied: replacementsApplied,
            matchJump: find.currentMatch,
            focusRequest: focusRequest,
            scrollRequest: pendingJump,
            onScrollApplied: { pendingJump = nil },
            // Computed here, once per rebuild, from the same `NoteOutline` the sidebar
            // draws: the text view needs the ranges only to say which one the caret is
            // in, and it must be the same list or the highlight lands a row off.
            outlineRanges: NoteOutline.entries(in: note.text).map {
                NSRange($0.range, in: note.text)
            },
            onOutlineEntryChanged: { entry in focused { vault.currentOutlineEntry = entry } },
            foldedEntries: tab?.foldedEntries ?? [],
            // The same source Lettura uses, so the two surfaces cannot resolve the same
            // `![[nota]]` to two different notes (ADR-0010 §D3).
            transclusions: transclusionSource,
            onToggleFold: { entry in focused { vault.toggleFold(entry) } },
            // Clicking into the text is how a person says which half they are working in, and
            // the column's own tap gesture never sees that click: the text view takes it.
            onTakeFocus: { vault.focusColumn(columnIndex) }
        )
        .modifier(FindKeeping(
            find: find,
            navigation: navigation,
            text: note.text,
            isFocused: isFocused
        ))
    }

    /// Clears the applied replacements, and - for an outline move (PG-019) only - saves right
    /// after: the buffer already carries the move by the time this fires, so the save persists
    /// it and any pre-existing unsaved edits in one journalled write.
    func replacementsApplied() {
        pendingReplacements = nil
        guard pendingReplacementsIsMove else { return }
        pendingReplacementsIsMove = false
        vault.saveOpenNote()
    }

    /// The slash menu's catalogue, filtered to what can run right now.
    ///
    /// Built once per rebuild: a command the app cannot perform is not offered, rather than
    /// offered and inert. The caption is the user's own binding and never the default - a menu
    /// teaching a shortcut that has been remapped is teaching one that does nothing.
    var slashCommands: [EditorCommand] {
        EditorCommand.all(
            canRun: commandActions.canRun,
            caption: { command in
                let binding = shortcuts.binding(for: command)
                return binding.isValid ? binding.displayString : nil
            }
        )
    }

    /// The find bar and everything it can ask for (SPEC §10, M8).
    func findBar(_ note: VaultController.OpenNote) -> some View {
        FindBar(
            session: find,
            onStep: { offset in find.step(by: offset) },
            onReplaceOne: {
                guard let match = find.currentMatch else { return }
                pendingReplacements = [(match, NoteFind.replacement(
                    for: find.currentQuery, matching: match, in: note.text,
                    template: find.replacement
                ))]
            },
            // Already ordered last match first by the session, which is what keeps the ranges
            // of the ones still to come valid as the text moves.
            onReplaceAll: { pendingReplacements = find.replacements(in: note.text) },
            onClose: {
                find.close()
                focusRequest += 1
            }
        )
    }

    /// Cmd+F and Cmd+Alt+F, for this column only.
    ///
    /// **The guard is the whole point.** The request is a flag on `Navigation`, which is the
    /// window; without asking whose it is, both columns' text views consume it and the one
    /// that clears the flag first decides where the bar opened - on screen, always the right
    /// hand column, whichever half the caret was in. Same rule as `pendingInsertion` and the
    /// index jump, which the column already checks the focus for.
    var findRequest: NoteTextView.FindRequest? {
        guard isFocused else { return nil }
        if navigation.isReplaceRequested { return .replace }
        if navigation.isFindRequested { return .find }
        return nil
    }
    /// An external edit arrived while this note had unsaved changes. Neither side is
    /// discarded without the user choosing (ADR-0001 §D3.4).

    /// The note as reading mode draws it, pictures and transcluded notes included.
    func reading(_ note: VaultController.OpenNote) -> some View {
        MarkdownReadingView(
            text: note.text,
            onFollowLink: follow(title:),
            notePath: note.relativePath,
            vaultRoot: vault.root,
            thumbnails: vault.thumbnails,
            transclusions: transclusionSource,
            queries: viewQuerySource,
            scrollToEntry: pendingJump?.ordinal,
            onScrollApplied: { pendingJump = nil }
        )
    }

    /// Where a `pergamenum-view` block gets its rows (ADR-0009 §D4).
    ///
    /// The index answers everything but `text()`, which reads the files - the same work the
    /// global search does, and the reason §D7 states the cost as a rule rather than a number.
    /// `scanGeneration` rides along so a view is re-evaluated when the vault is rescanned and
    /// not when a key is pressed.
    var viewQuerySource: ViewQuerySource {
        ViewQuerySource(
            evaluate: { block in
                ViewEvaluator.evaluate(block, over: vault.index) { record in
                    try? vault.session?.read(record.relativePath).text
                }
            },
            generation: vault.scanGeneration,
            // The one write a view makes (§D5). Offered here, where there is a vault and a
            // person looking at it; a note card on the canvas passes no source and its board
            // never invites the drag.
            move: { path, old, new in vault.moveOnBoard(path, from: old, to: new) },
            undo: { id in vault.undoJournalledWrites([id]).failures.isEmpty }
        )
    }

    /// Where a `![[nota]]` gets the note it names (ADR-0010 §D1: read fresh, never copied).
    ///
    /// Two lookups, in the order §D2 gives them: a reference ending in `.md` is a path, and
    /// anything else is a title through the index - the same lookup a `[[wikilink]]` uses,
    /// so the two cannot disagree about which note a name means.
    ///
    /// `scanGeneration` rides along so a target edited outside the app is redrawn on the
    /// next scan, and only then: the id it feeds changes when the vault changes, not when a
    /// key is pressed.
    var transclusionSource: TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard let session = vault.session else { return nil }
                let paths = reference.lowercased().hasSuffix(".md")
                    ? [reference]
                    : vault.index.resolve(title: reference)
                for path in paths {
                    guard let read = try? session.read(path) else { continue }
                    return TransclusionSource.Resolved(
                        title: read.record.title,
                        relativePath: path,
                        text: read.text
                    )
                }
                return nil
            },
            generation: vault.scanGeneration
        )
    }
}

/// Keeps the search in step with the note and with the two keys that move it.
///
/// A modifier rather than five `onChange`s inline, because `editing(_:)` is already the
/// longest function in the widest view in the app and this is a separate concern from wiring
/// the text view.
private struct FindKeeping: ViewModifier {
    let find: FindSession
    let navigation: Navigation
    let text: String
    /// Cmd+G is the window's key and this column's search: the one without the focus has to
    /// let it pass, or it steps its own matches and clears the counter the other was reading.
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            // Recomputed when the note changes as well as when the query does: with the bar
            // open, typing in the note moves every match after the caret.
            .onChange(of: text) { find.update(in: text) }
            .onChange(of: find.query) { find.update(in: text) }
            .onChange(of: find.isRegex) { find.update(in: text) }
            .onChange(of: find.isCaseSensitive) { find.update(in: text) }
            // Cmd+G and Cmd+Shift+G arrive as a running total, so the same key pressed twice
            // is two steps where a Bool set twice would be one. Consumed by taking the
            // difference and writing back what was taken.
            .onChange(of: navigation.findStep) { previous, current in
                guard isFocused, let current else { return }
                guard find.isOpen else {
                    // Cmd+G with no bar open is «cerca di nuovo»: open it on the query that
                    // is already there rather than doing nothing at all.
                    navigation.isFindRequested = true
                    return
                }
                find.step(by: current - (previous ?? 0))
                navigation.findStep = nil
            }
    }
}
