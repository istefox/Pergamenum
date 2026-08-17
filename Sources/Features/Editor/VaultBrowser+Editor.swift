import SwiftUI

/// The editor pane's own parts: its header, the reading view, and what a click on an
/// embedded file does.
///
/// In a file of its own so `VaultBrowser` stays inside SwiftLint's type body length. It
/// is already the widest view in the app, holding three panes and their sheets.
extension VaultBrowser {
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
    /// The editor shows `![[foto.png]]` as text and always will (SPEC §5 rules out a
    /// preview that hides the syntax), so this is how the picture behind the line is
    /// seen without leaving the note. A name the vault cannot place is reported rather
    /// than swallowed: a broken embed is worth knowing about.
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
    /// Here rather than inline in `VaultBrowser.body` for the reason this file exists at
    /// all: the browser is the widest view in the app, and M8 gave the text view two more
    /// inputs.
    func editing(_ note: VaultController.OpenNote) -> some View {
        NoteTextView(
            text: Binding(
                get: { vault.openNote?.text ?? "" },
                set: { vault.updateOpenNoteText($0) }
            ),
            theme: theme,
            noteTitles: vault.index.allNotes.map(\.title),
            tagSuggestions: tagSuggestions,
            // Filtered here, once per rebuild: a command the app cannot run right now is
            // not offered, rather than offered and inert.
            editorCommands: EditorCommand.all(
                canRun: commandActions.canRun,
                // The user's binding and never the default: a menu that taught a shortcut
                // the user had changed would be teaching one that does nothing.
                caption: { command in
                    let binding = shortcuts.binding(for: command)
                    return binding.isValid ? binding.displayString : nil
                }
            ),
            onRunCommand: commandActions.run,
            onFollowLink: follow(title:),
            onOpenEmbed: { name in preview(embed: name, in: note) },
            onDropFile: { url in vault.importFileIntoVault(url, near: note.relativePath) },
            onPasteImage: { data in save(pastedImage: data, in: note) },
            insertion: pendingInsertion,
            onInsertionApplied: { pendingInsertion = nil },
            findRequest: findRequest,
            onFindApplied: {
                navigation.isFindRequested = false
                navigation.isReplaceRequested = false
            },
            focusRequest: focusRequest,
            scrollRequest: pendingJump,
            onScrollApplied: { pendingJump = nil },
            // Computed here, once per rebuild, from the same `NoteOutline` the sidebar
            // draws: the text view needs the ranges only to say which one the caret is
            // in, and it must be the same list or the highlight lands a row off.
            outlineRanges: NoteOutline.entries(in: note.text).map {
                NSRange($0.range, in: note.text)
            },
            onOutlineEntryChanged: { navigation.currentOutlineEntry = $0 },
            foldedEntries: navigation.foldedEntries,
            // The same source Lettura uses, so the two surfaces cannot resolve the same
            // `![[nota]]` to two different notes (ADR-0010 §D3).
            transclusions: transclusionSource,
            onToggleFold: navigation.toggleFold
        )
    }

    var findRequest: NoteTextView.FindRequest? {
        if navigation.isReplaceRequested { return .replace }
        if navigation.isFindRequested { return .find }
        return nil
    }

    func editorHeader(_ note: VaultController.OpenNote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(note.title).themedText(.heading)
                Text(note.relativePath).themedText(.caption, color: .textTertiary)
            }
            Spacer()
            // Modifica / Lettura, the toggle SPEC §10 puts on Cmd+Shift+E. Reading
            // mode renders the note; the editor keeps showing the source with style
            // applied, which is what §7.1 asks for and what §14 keeps a live preview
            // out of.
            Picker("", selection: Bindable(navigation).isReadingMode) {
                Text("Modifica").tag(false)
                Text("Lettura").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if note.hasUnsavedChanges {
                // No shortcut of its own: File > Salva already carries one, and the
                // user may have moved it.
                Button("Salva", action: vault.saveOpenNote)
            } else {
                Label("Salvato", systemImage: "checkmark.circle")
                    .themedText(.caption, color: .textSecondary)
            }
        }
        .padding(theme.spacing(.s))
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
            scrollToEntry: pendingJump?.ordinal,
            onScrollApplied: { pendingJump = nil }
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
