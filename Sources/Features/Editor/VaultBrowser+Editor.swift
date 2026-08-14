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
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: ImportNaming.pastedImageFileName(on: .today), directoryHint: .notDirectory)
        do {
            try data.write(to: temporary, options: .atomic)
        } catch {
            vault.recordProblem("immagine incollata: \(error.localizedDescription)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        return vault.importFileIntoVault(temporary, near: note.relativePath)
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

    /// The note as reading mode draws it, pictures included.
    func reading(_ note: VaultController.OpenNote) -> some View {
        MarkdownReadingView(
            text: note.text,
            onFollowLink: follow(title:),
            notePath: note.relativePath,
            vaultRoot: vault.root,
            thumbnails: vault.thumbnails
        )
    }
}
