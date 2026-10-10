import AppKit
import SwiftUI

/// The markdown editor: an `NSTextView` on TextKit 2, wrapped for SwiftUI.
///
/// SwiftUI's `TextEditor` cannot style ranges, place a completion list, or make a
/// wikilink clickable, all three of which M1 needs, so this is the AppKit bridge
/// SPEC §3 anticipates.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    /// Titles offered when completing after `[[`.
    let noteTitles: [String]
    /// Workspace boards offered alongside notes when completing after `[[`, by vault-relative
    /// path (`CanvasStore.allBoards()`) - defaults empty so a text view built without a vault
    /// behind it behaves exactly as before (the `spellCheck`/`hidesMarkup` contrast above
    /// documents the same convention).
    var boardTitles: [String] = []
    /// The aliases each note answers to, by title, offered through `[[` completion (n1-seams
    /// R-08). Defaulted empty for the same reason `boardTitles` is. Built with `aliasesByTitle`.
    var noteAliases: [String: [String]] = [:]
    /// Tags offered when completing after `#`, most used first.
    let tagSuggestions: [String]
    /// Whether misspellings are underlined, and in which language (M8, SPEC §12). Off by
    /// default so a text view built without a vault behind it behaves as it always did.
    var spellCheck: SpellCheck = .off
    /// Whether a heading's `#` marker is hidden until the caret's paragraph, a selection,
    /// an IME composition or the find bar's current match touches it (ADR-0018 §D1).
    /// **`false` here, `true` in `VaultSettings`, deliberately** - the same contrast as
    /// `spellCheck`'s default: a text view with no vault behind it behaves exactly as
    /// before, and the vault's own default is what a real note editor reads through.
    var hidesMarkup = false
    /// Whether emphasis/strikethrough/link markers are revealed span by span rather than
    /// paragraph by paragraph (ADR-0037 §D2). **`false` here, `true` in `VaultSettings`,
    /// deliberately** - the same contrast `hidesMarkup` above documents: a text view with
    /// no vault behind it behaves exactly as before, and the vault's own default is what a
    /// real note editor reads through.
    var revealsInlineSpans = false
    /// Whether the text column is capped to a readable width and centred, rather than
    /// filling the whole pane (ADR-0030 §D6). **`false` here, `true` in `VaultSettings`,
    /// deliberately** - the same contrast `hidesMarkup` above documents: a text view with
    /// no vault behind it behaves exactly as before, and the vault's own default is what a
    /// real note editor reads through.
    var readableWidth = false
    /// The slash menu's catalogue, already filtered to what can run (M8). Passed in
    /// rather than built here: whether a command can run is a fact about the app, and
    /// the editor is not the place that knows it.
    var editorCommands: [EditorCommand] = []
    var onRunCommand: ((ShortcutCommand) -> Void)?
    let onFollowLink: (String) -> Void
    /// What the vault behind the editor provides: where embeds, transclusions and view
    /// fences resolve, and the drop, paste, embed-click and "Modifica query" callbacks
    /// (`NoteTextView+Inputs.swift`). Empty by default, so a text view with no vault behind
    /// it behaves exactly as before.
    var vault = VaultInputs()
    /// Text the Inserisci menu asked for, applied at the cursor and then reported as
    /// applied so it is not inserted twice on the next view update (SPEC §10). Carries
    /// `opensQueryBuilder` for the insert-view command (R-04, ADR-0034 §D10): true only
    /// for the stub it writes, applied alongside the ordinary insertion
    /// (`NoteTextView+Update.swift`'s `consumeInsertion`).
    var insertion: Navigation.Insertion?
    var onInsertionApplied: () -> Void = {}
    /// The find bar's request, matches, replacements and match jump
    /// (`NoteTextView+Inputs.swift`).
    var find = FindInputs()
    /// Bumped when the cursor should move into the editor, which is what makes a note
    /// created in the composer open ready to be typed into.
    var focusRequest = 0
    /// The outline's entry ranges, its jump request and the folded sections
    /// (`NoteTextView+Inputs.swift`).
    var outline = OutlineInputs()
    /// Called when the editor takes the keyboard. The split view uses it to move the focus
    /// to the column that was clicked into (ADR-0012 D4).
    var onTakeFocus: (() -> Void)?

    enum FindRequest { case find, replace }

    /// `noteAliases` from the index's notes: a title with no alias has no entry, and two notes
    /// sharing a title pool theirs, as the title pool itself does not tell them apart.
    static func aliasesByTitle(_ notes: [NoteRecord]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for note in notes where !note.frontmatter.aliases.isEmpty {
            result[note.title, default: []] += note.frontmatter.aliases
        }
        return result
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // Smart substitutions would rewrite `- [ ]`, `>2026-08-15` and `--` into
        // characters the task and frontmatter parsers do not accept, silently making
        // a conformant note non-conformant as the user types. Autocorrection is one of
        // them and stays off whatever the spell-check setting says: underlining a word is
        // an opinion, replacing it is an edit.
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        apply(spellCheck, to: textView)
        // The horizontal half is recomputed from the pane's width as soon as there is one
        // (ADR-0030 §D6); this is its floor, which is the value the editor has always had
        // and the value it keeps when the setting is off or the pane is narrow, less the gutter
        // every paragraph carries as its own indent (ADR-0081 §D1).
        textView.textContainerInset = NSSize(
            width: EditorGutter.containerInset(
                readableInset: Coordinator.minimumHorizontalInset, gutter: theme.spacing(.gutter)
            ),
            height: Coordinator.verticalInset
        )
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [:]
        textView.onPasteURL = { [weak textView] pasted in
            guard let textView, let selectionRange = textView.selectedRanges.first as? NSRange,
                  selectionRange.length > 0
            else { return false }
            let selected = (textView.string as NSString).substring(with: selectionRange)
            guard let replacement = EditorEdits.markdownLink(pasting: pasted, over: selected) else {
                return false
            }
            textView.insertText(replacement, replacementRange: selectionRange)
            return true
        }
        wire(textView, to: context.coordinator)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        // After the text view is the scroll view's document view, so the coordinator can
        // reach the clip view whose width it reads (ADR-0030 §D6). `updateNSView` does not
        // run on a window resize, so this observation is the only thing that keeps the
        // column centred as the pane grows.
        context.coordinator.observeWidthChanges(of: scrollView)
        context.coordinator.applyReadableWidth(to: textView)
        textView.textContentStorage?.delegate = context.coordinator.decorations
        textView.textLayoutManager?.delegate = context.coordinator.decorations
        textView.string = text
        context.coordinator.applyStyling(to: textView, theme: theme)
        context.coordinator.applyEmbeds(to: textView)
        context.coordinator.applyTransclusions(to: textView, theme: theme)
        context.coordinator.applyMatches(
            to: textView, matches: find.matches, current: find.currentMatch, theme: theme
        )
        return scrollView
    }

    /// Turns the spell checker on or off, and tells it which language to read in.
    ///
    /// The language is a property of `NSSpellChecker.shared` and not of the text view, so it
    /// is set here rather than on the view: there is one checker per process, and the three
    /// panes that draw this view all read the same vault.
    ///
    /// Grammar checking follows the same switch instead of getting one of its own. It is the
    /// same underline in the same places, and a second toggle for it would be a setting
    /// nobody could describe.
    ///
    /// Not private because `NoteTextView+Update.swift`'s `pushInputs` re-applies it on every update.
    func apply(_ spellCheck: SpellCheck, to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = spellCheck.isEnabled
        textView.isGrammarCheckingEnabled = spellCheck.isEnabled
        guard spellCheck.isEnabled else { return }
        let checker = NSSpellChecker.shared
        if let language = spellCheck.fixedLanguage {
            checker.automaticallyIdentifiesLanguages = false
            checker.setLanguage(language)
        } else {
            checker.automaticallyIdentifiesLanguages = true
        }
    }

    /// The closures the text view calls back through.
    ///
    /// All of them go through the coordinator rather than capturing `self`: the closure is
    /// read when the event happens, so it is the current one and not the one this view was
    /// built with. In a method of its own because `makeNSView` is otherwise past the length
    /// SwiftLint warns at, and a text view with eight callbacks earns the separation.
    ///
    /// **Internal rather than private so a test can wire a text view the way the app does.**
    /// `Tests/NoteListEditingTests.swift` drives Return through a real `CompletingTextView`,
    /// and the behaviour it asserts lives in `claimsCommand` below; a fixture that assigned
    /// that closure itself would be asserting against its own copy of the wiring rather than
    /// against this one, and would go stale the moment this method changed
    /// (`Tests/EmbedEditorTestSupport.swift` holds exactly such a copy). Nothing else about
    /// the method changes: it is still called only from `makeNSView`.
    func wire(_ textView: CompletingTextView, to coordinator: Coordinator) {
        // The headings of a note, for `[[Nota#`. Through the same source the two surfaces
        // resolve a transclusion with, so the completion cannot offer a section the
        // rendition would fail to find - `NoteOutline` strips the markdown from a heading,
        // which is exactly the form `Transclusion.excerpt` matches against.
        textView.noteSections = { reference in
            guard let resolved = coordinator.parent.vault.transclusions?.resolve(reference) else { return [] }
            return NoteOutline.entries(in: resolved.text).compactMap { entry in
                guard case .heading = entry.kind else { return nil }
                return entry.title
            }
        }
        textView.onDropFile = { url in coordinator.parent.vault.onDropFile?(url) }
        textView.onPasteImage = { data in coordinator.parent.vault.onPasteImage?(data) }
        textView.onRunCommand = { command in coordinator.parent.onRunCommand?(command) }
        textView.onTakeFocus = { coordinator.parent.onTakeFocus?() }
        // Three claimants, asked in turn the way the `onClickInMargin` chain below is:
        // the caret and Backspace/Delete crossing a drawn embed's run in one step
        // (ADR-0018 slice 3, Step 4, D5), then Return inside a list item (ADR-0028 §D6,
        // R-07/R-08), then Return/forward-Delete redirected around a table's own hidden
        // delimiter/body rows (ADR-0029 §D5, `NoteTextView+TableCaret.swift`). They cannot
        // all claim one command - the embed's half answers only to the four arrows and the
        // two delete keys, and the table claimant only to Return and forward Delete.
        // Closed over `textView` the same way the click handler below is, since all three
        // need the live selection.
        textView.claimsCommand = { [weak textView] selector in
            guard let textView else { return false }
            return coordinator.claimsEmbedCommand(selector, in: textView)
                || coordinator.claimsListCommand(selector, in: textView)
                || coordinator.claimsTableCommand(selector, in: textView)
        }
        // A drag on a drawn embed's resize handle (ADR-0019 §D6) - closed over `textView`
        // weakly, exactly as `claimsCommand` above is, and for the same reason: the
        // gesture needs the live layout, which only the view has, and the closure outlives
        // nothing it holds. Offered the press *before* the chain below, which
        // `CompletingTextView.mouseDown(with:)` is where it is decided.
        textView.onEmbedResize = { [weak textView] phase in
            guard let textView else { return false }
            return coordinator.resizeEmbed(phase, in: textView)
        }
        // A secondary click on a drawn embed (ADR-0023 §D9) - closed over `textView`
        // weakly for the reason the two above are, and answering nil where there is no
        // view left, which is what `CompletingTextView.menu(for:)` turns into the editor's
        // ordinary contextual menu instead of no menu at all.
        textView.onEmbedMenu = { [weak textView] point in
            guard let textView else { return nil }
            return coordinator.embedMenu(at: point, in: textView)
        }
        // Three decorations, asked in turn: whoever claims the click keeps it. They
        // cannot both claim one - a folded heading's line is not a transclusion's line,
        // and neither is a drawn embed's.
        textView.onClickInMargin = { [weak textView] point in
            guard let textView else { return false }
            return coordinator.openTransclusion(at: point, in: textView)
                || coordinator.unfold(at: point, in: textView)
                || coordinator.selectEmbed(at: point, in: textView)
        }
        // A click on a task line's checkbox glyph (PG-101-adjacent, checkbox size + click
        // chain): asked in `mouseDown` after the margin claimants above and before `super`,
        // so it never places the caret and never triggers `NoteTextView+Reveal`'s
        // reveal-on-caret for that paragraph.
        textView.onToggleCheckbox = { [weak textView] point in
            guard let textView else { return false }
            return coordinator.toggleCheckbox(at: point, in: textView)
        }
    }

    /// Four steps, in this order and no other (`NoteTextView+Update.swift`): the text sync
    /// before every pass, the passes before the insertion (which must not be overwritten by the
    /// model value that predates it), and the insertion before the one-shots.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CompletingTextView else { return }
        let coordinator = context.coordinator
        pushInputs(to: textView, coordinator: coordinator)
        runPasses(on: textView, coordinator: coordinator)
        consumeInsertion(in: textView, coordinator: coordinator)
        consumeOneShots(in: textView, coordinator: coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Purges this text view's pending undo actions before SwiftUI releases it.
    ///
    /// The typing undo `allowsUndo = true` registers is on the **window's** `undoManager`
    /// (ADR-0026 §D8 shares that stack with the sidebar's move-undo, deliberately). Leaving
    /// the pane this editor is in - the Note/Workspace switch is a full rebuild, not a
    /// hide (`RootView.swift`'s pane switch) - deallocates this text view while that action
    /// is still on the stack, targeting it. The next Cmd+Z that reaches it then invokes a
    /// dangling target and crashes: `EXC_BAD_ACCESS` in `-[_NSUndoStack popAndInvoke]`,
    /// reproduced 2026-08-28 by typing in a note, moving a board via the sidebar drag
    /// (ADR-0026), and pressing Cmd+Z twice. Removing every action still targeting this view
    /// or its storage - where `NSTextView` actually registers typing undo - drops the
    /// now-meaningless "redo my typing" step instead of leaving it to crash on.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.undoManager?.removeAllActions(withTarget: textView)
        if let textStorage = textView.textStorage {
            coordinator.undoManager?.removeAllActions(withTarget: textStorage)
        }
    }
}
