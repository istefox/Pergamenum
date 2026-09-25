import AppKit
import SwiftUI

/// The Diario pane: the day written in markdown on the left, the hours of the day on
/// the right.
///
/// Two halves of one record, and the left one is the app's single editor - always
/// editable, always styled, markup concealed until the caret reaches it. A diary is
/// written and reread in the same minute, which used to buy it a second view of its own
/// text beside the source and a picker to choose between them; it now buys nothing,
/// because there is no second, non-editable view of the note being written left to
/// switch to - here or in the Note pane.
///
/// ADR-0029 supersedes ADR-0005 §D2 on exactly that point and on nothing else here:
/// §D1's "Diario is its own pane" and §D3-§D8 - the ten-minute grid, overlapping blocks,
/// the hour window, the `## Diario` section, the pane saving itself, the key it takes -
/// all stand as written, `DiaryTimeline` included.
struct DiaryView: View {
    // Internal, not private: read by `DiaryView+Conflict.swift`.
    @Environment(\.theme) var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    // Internal, not private: read by `DiaryView+Conflict.swift`.
    @Environment(DiaryController.self) var controller
    @Environment(ThemeEngine.self) private var themeEngine

    /// Every board's vault-relative path, for the editor's `[[` completion.
    ///
    /// Fetched once per scan rather than in `editor`, which `body` calls:
    /// `CanvasStore.allBoards()` is an uncached walk of the whole vault on disk, and
    /// computed there it ran on every keystroke. `TasksView.boards` and
    /// `WorkspacePicker` make the same trade for the same reason.
    @State private var boardTitles: [String] = []

    var body: some View {
        HSplitView {
            writingColumn
                .frame(minWidth: 420)
            DiaryTimeline(controller: controller)
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 640)
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { DiaryToolbar(controller: controller, themeEngine: themeEngine) }
        // Keyed on the vault so a vault switch with the pane on screen reloads at the
        // switch rather than at the next keystroke (ADR-0057 §D7).
        .task(id: vault.root) { controller.load() }
        .task(id: vault.scanGeneration) {
            boardTitles = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        }
        // Every way out of this pane writes the day: switching pane takes the view
        // away, and quitting or clicking on another app does not go through here at
        // all. A diary that loses the last sentence typed is not a diary.
        .onDisappear { controller.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            controller.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            controller.flush()
        }
        .sheet(isPresented: Bindable(controller).isChoosingDate) {
            GoToDateSheet(
                day: controller.day,
                onGo: { controller.show($0) },
                onCancel: { controller.isChoosingDate = false }
            )
        }
        .sheet(isPresented: Binding(
            get: { controller.draft != nil },
            set: { if !$0 { controller.cancelDraft() } }
        )) {
            DiaryEntrySheet(controller: controller)
        }
    }

    // MARK: The writing column

    private var writingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case .conflicted = controller.saveState {
                conflictBanner
            }
            Divider()
            editor
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            Text(controller.day.italianForm).themedText(.title)
            Text(DateEntry.weekdayName(of: controller.day))
                .themedText(.body, color: .textSecondary)
            Spacer()
            Text(fileLabel)
                .themedText(.caption, color: .textTertiary)
                .help("Il diario è un file markdown nella cartella note")
        }
        .padding(.horizontal, theme.spacing(.l))
        .padding(.vertical, theme.spacing(.s))
        .accessibilityIdentifier("diary-header")
    }

    private var fileLabel: String { vault.diaryNotePath(for: controller.day) }

    private var editor: some View {
        NoteTextView(
            text: Bindable(controller).prose,
            theme: theme,
            noteTitles: vault.index.allNotes.map(\.title),
            boardTitles: boardTitles,
            tagSuggestions: vault.tagSuggestions,
            spellCheck: vault.settings.spellCheck,
            hidesMarkup: vault.settings.hidesMarkup,
            revealsInlineSpans: vault.settings.revealsInlineSpans,
            readableWidth: vault.settings.readableWidth,
            onFollowLink: follow,
            vaultRoot: vault.root,
            notePath: fileLabel,
            thumbnails: vault.thumbnails,
            onDropFile: { url in vault.importFileIntoVault(url, near: fileLabel) },
            onPasteImage: { data in vault.importPastedImage(data, near: fileLabel) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("diary-editor")
    }

    /// A wikilink in the diary goes to the note it names, in the pane that shows notes.
    private func follow(_ title: String) {
        guard let path = vault.index.resolve(title: title).first else { return }
        controller.flush()
        vault.openNote(at: path)
        navigation.pane = .notes
    }
}
