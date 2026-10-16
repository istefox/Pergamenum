import AppKit
import Foundation
import SwiftUI
@testable import Pergamenum

// ADR-0096 "Measured" and G-ceiling-406 (PG-406 follow-up).
//
// `UpdatePathFixture` hosts `EditorColumnView` alone, so the top bar, the sidebar's `NoteListPane` with its
// outline footer and the inspector (`categoryLink`, backlinks...) are outside its measurement, and the person's
// window costs about 7, 28 and 150 ms more per key at 50 KB, 200 KB and 1 MB (2026-10-14). This is the other host:
// the real `VaultBrowser`, typed into through the same `keystroke()` and forced the same way.

extension UpdatePathFixture {
    /// What the hosted window holds around the note's text view.
    enum Host: Sendable {
        /// `EditorColumnView` alone, 900x700: what PR #1006's printed row measures.
        case editorColumn
        /// `VaultBrowser`, 1500x900: the top bar, the note list pane, the editor and the inspector.
        case window
    }

    /// A frontmatter block in the closed schema plus the category key, so the inspector's `categoryLink`
    /// reads a real block on every update instead of finding none (`RestyleBudget.syntheticNote` has none).
    static let frontmatter = "---\ndate: 2026-10-14\ntags: [type-note]\npergamenum-category: presse\n---\n"

    /// The case's synthetic note, prefixed with `frontmatter` (nil for none), open in the whole window.
    convenience init(window c: RestyleBudget.Case, frontmatter: String? = UpdatePathFixture.frontmatter) async throws {
        let note = (frontmatter ?? "") + RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        try await self.init(c, note: note, host: .window)
    }

    /// The host of `Host.window`, with the two environment objects `VaultBrowser` reads that the column does not.
    ///
    /// The three panes are pinned rather than left to `Navigation`'s initial values: the note list shows
    /// unless the notes are focused or the tree collapsed, the inspector only while `isShowingInspector`.
    /// `NoteListPane` also reads `@AppStorage("noteListShowsFolders")` and `("noteListShowsStarred")`, which
    /// would come from the test host's standard defaults, the app's own domain; `defaults` (the fixture's
    /// throwaway suite, removed at `tearDown()`) is made the subtree's app storage with both set to true,
    /// their shipped values, so no setting of the person's reaches the measurement and nothing leaks out.
    static func window(
        vault: VaultController, navigation: Navigation, actions: CommandActions, shortcuts: ShortcutStore,
        defaults: UserDefaults
    ) -> HostedView<AnyView> {
        navigation.isNotesFocused = false
        navigation.isNoteTreeCollapsed = false
        navigation.isShowingInspector = true
        defaults.set(true, forKey: "noteListShowsFolders")
        defaults.set(true, forKey: "noteListShowsStarred")
        return HostedView(
            AnyView(
                VaultBrowser()
                    .environment(\.theme, .emergency)
                    .environment(vault)
                    .environment(navigation)
                    .environment(actions)
                    .environment(shortcuts)
                    .environment(ThemeEngine())
                    .environment(PraticheController(probe: { .granted }, performSync: { _, _ in }))
                    .defaultAppStorage(defaults)
            ),
            size: CGSize(width: 1500, height: 900)
        )
    }
}
