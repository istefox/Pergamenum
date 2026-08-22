import AppKit
import SwiftUI

/// The Diario pane: the day written in markdown on the left, the hours of the day on
/// the right.
///
/// Two halves of one record. The text is an ordinary markdown editor, with the rendered
/// note beside it live rather than behind a mode switch - reading mode elsewhere in the
/// app replaces the editor, and a diary is written and reread in the same minute.
///
/// SPEC §14 rules out a live preview *inside* the editor, one that hides syntax while
/// typing. This is not that: the source keeps its syntax and its styling, and the
/// rendering is a second view of the same text (ADR-0005).
struct DiaryView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(DiaryController.self) private var controller

    var body: some View {
        HSplitView {
            writingColumn
                .frame(minWidth: 420)
            DiaryTimeline(controller: controller)
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 640)
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { DiaryToolbar(controller: controller) }
        .task { controller.load() }
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
            Divider()
            body(for: controller.layout)
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

    @ViewBuilder
    private func body(for layout: DiaryController.Layout) -> some View {
        switch layout {
        case .editor:
            editor
        case .preview:
            preview
        case .both:
            HSplitView {
                editor.frame(minWidth: 220)
                preview.frame(minWidth: 220)
            }
        }
    }

    private var editor: some View {
        NoteTextView(
            text: Bindable(controller).prose,
            theme: theme,
            noteTitles: vault.index.allNotes.map(\.title),
            tagSuggestions: vault.tagSuggestions,
            spellCheck: vault.settings.spellCheck,
            hidesMarkup: vault.settings.hidesMarkup,
            onFollowLink: follow,
            onDropFile: { url in vault.importFileIntoVault(url, near: fileLabel) },
            onPasteImage: { data in vault.importPastedImage(data, near: fileLabel) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("diary-editor")
    }

    private var preview: some View {
        MarkdownReadingView(
            text: controller.prose,
            onFollowLink: follow,
            notePath: fileLabel,
            vaultRoot: vault.root,
            thumbnails: vault.thumbnails,
            takesFocus: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("diary-preview")
    }

    /// A wikilink in the diary goes to the note it names, in the pane that shows notes.
    private func follow(_ title: String) {
        guard let path = vault.index.resolve(title: title).first else { return }
        controller.flush()
        vault.openNote(at: path)
        navigation.pane = .notes
    }
}
