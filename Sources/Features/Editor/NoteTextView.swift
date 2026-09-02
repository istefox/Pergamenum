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
    /// The slash menu's catalogue, already filtered to what can run (M8). Passed in
    /// rather than built here: whether a command can run is a fact about the app, and
    /// the editor is not the place that knows it.
    var editorCommands: [EditorCommand] = []
    var onRunCommand: ((ShortcutCommand) -> Void)?
    let onFollowLink: (String) -> Void
    /// Called with the file name inside `![[foto.png]]` when its raw syntax is clicked -
    /// `hidesMarkup` off, or the run not yet collapsed into a picture. Once ADR-0018
    /// slice 3 draws the picture in the run's place, a click there selects it instead
    /// (`selectEmbed(at:in:)`) and never reaches this callback; unlike a heading or
    /// emphasis marker, the caret alone never brings the raw text back (D5).
    var onOpenEmbed: ((String) -> Void)?
    /// The vault an embed's target is resolved in (ADR-0018 slice 3). Nil where there is
    /// no vault behind the editor - the same permissive default `spellCheck` and
    /// `hidesMarkup` take - and then `![[foto.png]]` stays unresolved, exactly today's
    /// behaviour.
    var vaultRoot: URL?
    /// The open note's own path, so a relative embed target is looked up beside it
    /// first, the same as `Attachment.resolve` already does for reading mode
    /// (`MarkdownReadingView.notePath`).
    var notePath = ""
    /// The vault's render cache for embedded files - the same `ThumbnailStore` reading
    /// mode's `EmbeddedFileView` reads, so a picture is rendered once and shared between
    /// the two surfaces rather than duplicated.
    var thumbnails: ThumbnailStore?
    /// Where a dropped file should be copied to, returning its file name for the
    /// embed (SPEC §5). Nil disables dropping.
    var onDropFile: ((URL) -> String?)?
    /// Called with the PNG bytes of an image pasted from the clipboard, returning the
    /// name it was written into the vault under. A screenshot has no file to drop, so
    /// without this it could not enter a note at all.
    var onPasteImage: ((Data) -> String?)?
    /// Text the Inserisci menu asked for, applied at the cursor and then reported as
    /// applied so it is not inserted twice on the next view update (SPEC §10).
    var insertion: (text: String, cursorBack: Int)?
    var onInsertionApplied: () -> Void = {}
    /// Raised by the Modifica menu; opens the find bar (SPEC §10, M8). Answered with the
    /// selection there was at that moment, which is the search's scope - captured once, the
    /// way AppKit's own bar did it, rather than followed: a scope tracking the caret would
    /// shrink to nothing as soon as the search moved the selection onto a match.
    var findRequest: FindRequest?
    var onFindApplied: (NSRange) -> Void = { _ in }
    /// What the find bar found, and which one the stepper is on. Drawn as a colour on the
    /// layout manager rather than on the text - see `NoteTextView+Matches`.
    var matches: [NSRange] = []
    var currentMatch: Int?
    /// Replacements to perform, and then report as performed. The one-shot shape `insertion`
    /// already has. **Ordered last match first** by whoever builds them, so that applying one
    /// does not move the ranges of those still to come.
    var replacements: [(range: NSRange, text: String)]?
    var onReplacementsApplied: () -> Void = {}
    /// The match the stepper moved onto, to be brought into view. Its own input rather than
    /// the index's `scrollRequest`: that one carries an `ordinal` the reading view counts
    /// blocks by, and a find match has no position in the index to report. Borrowing the type
    /// would mean filling that field with a number that means nothing.
    var matchJump: NSRange?
    /// Bumped when the cursor should move into the editor, which is what makes a note
    /// created in the composer open ready to be typed into.
    var focusRequest = 0
    /// A line the index asked to be taken to (M8). The fourth one-shot input, and it
    /// follows the same shape as the other three: consumed once, then reported as applied.
    var scrollRequest: Navigation.OutlineJump?
    var onScrollApplied: () -> Void = {}
    /// The index's entries, as line ranges. Handed to the text view so it can say which
    /// one the caret is in without the caret's position having to travel up on every
    /// arrow key.
    var outlineRanges: [NSRange] = []
    var onOutlineEntryChanged: ((Int?) -> Void)?
    /// The index entries whose sections are folded (M8). Held by ordinal and not by
    /// character offset: an edit above a fold moves every offset, and a fold anchored to a
    /// number would end up somewhere else on the next keystroke.
    var foldedEntries: Set<Int> = []
    /// How a `![[nota]]` reaches the note it names (ADR-0010). Nil where there is no vault
    /// behind the editor, and then the line stays the plain link it was.
    var transclusions: TransclusionSource?
    /// Called with an index entry whose fold badge was clicked (PG-021). The same call the
    /// index's chevron makes, so a section opened from the editor and one opened from the
    /// sidebar are one gesture with two doors.
    var onToggleFold: ((Int) -> Void)?
    /// Called when the editor takes the keyboard. The split view uses it to move the focus
    /// to the column that was clicked into (ADR-0012 D4).
    var onTakeFocus: (() -> Void)?

    enum FindRequest { case find, replace }

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
        textView.textContainerInset = NSSize(width: 24, height: 20)
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
        textView.textContentStorage?.delegate = context.coordinator.decorations
        textView.textLayoutManager?.delegate = context.coordinator.decorations
        textView.string = text
        context.coordinator.applyStyling(to: textView, theme: theme)
        context.coordinator.applyEmbeds(to: textView)
        context.coordinator.applyTransclusions(to: textView, theme: theme)
        context.coordinator.applyMatches(
            to: textView, matches: matches, current: currentMatch, theme: theme
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
    private func apply(_ spellCheck: SpellCheck, to textView: NSTextView) {
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
            guard let resolved = coordinator.parent.transclusions?.resolve(reference) else { return [] }
            return NoteOutline.entries(in: resolved.text).compactMap { entry in
                guard case .heading = entry.kind else { return nil }
                return entry.title
            }
        }
        textView.onDropFile = { url in coordinator.parent.onDropFile?(url) }
        textView.onPasteImage = { data in coordinator.parent.onPasteImage?(data) }
        textView.onRunCommand = { command in coordinator.parent.onRunCommand?(command) }
        textView.onTakeFocus = { coordinator.parent.onTakeFocus?() }
        // Two claimants, asked in turn the way the `onClickInMargin` chain below is:
        // the caret and Backspace/Delete crossing a drawn embed's run in one step
        // (ADR-0018 slice 3, Step 4, D5), then Return inside a list item (ADR-0028 §D6,
        // R-07/R-08). They cannot both claim one command - the embed's half answers only
        // to the four arrows and the two delete keys. Closed over `textView` the same way
        // the click handler below is, since both need the live selection.
        textView.claimsCommand = { [weak textView] selector in
            guard let textView else { return false }
            return coordinator.claimsEmbedCommand(selector, in: textView)
                || coordinator.claimsListCommand(selector, in: textView)
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
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CompletingTextView else { return }
        context.coordinator.parent = self
        context.coordinator.undoManager = textView.window?.undoManager
        textView.noteTitles = noteTitles
        textView.tagSuggestions = tagSuggestions
        textView.editorCommands = editorCommands
        // Re-applied on every update rather than only at build time: turning the checker on
        // in Impostazioni has to reach the note already open, not the next one.
        apply(spellCheck, to: textView)

        // Only touch the text when the model diverges from what is on screen:
        // reassigning it unconditionally would reset the cursor on every keystroke.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
        context.coordinator.applyStyling(to: textView, theme: theme)
        context.coordinator.applyEmbeds(to: textView)
        context.coordinator.applyTransclusions(to: textView, theme: theme)
        context.coordinator.applyFolding(to: textView, folded: foldedEntries, theme: theme)
        // After the styling, always: `applyStyling` rewrites every attribute in the storage
        // and invalidates the layout with them, so a highlight painted before it would be
        // gone by the time anything was drawn.
        context.coordinator.applyMatches(
            to: textView, matches: matches, current: currentMatch, theme: theme
        )
        // After the matches, so the find bar's current match is a reveal trigger too
        // (ADR-0018 §D2), and before growing the view so a reveal's height change is
        // already accounted for.
        context.coordinator.applyReveal(to: textView)
        context.coordinator.growToFitTheText(textView)

        if let insertion {
            // After the text sync above, so the insertion is not overwritten by the
            // model value that predates it.
            textView.insertText(insertion.text, replacementRange: textView.selectedRange())
            let cursor = textView.selectedRange().location - insertion.cursorBack
            textView.setSelectedRange(NSRange(location: max(0, cursor), length: 0))
            onInsertionApplied()
        }

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            context.coordinator.takeFocus()
        }

        if findRequest != nil {
            // The selection as it is *now*, before anything else in this pass moves it. This
            // is the whole of the scope: `FindSession.open` decides whether it is wide enough
            // to be one.
            onFindApplied(textView.selectedRange())
        }

        if let replacements, !context.coordinator.alreadyApplied(replacements) {
            context.coordinator.apply(replacements, to: textView)
            onReplacementsApplied()
        }

        // Consumed by location, so stepping onto a different match scrolls and every other
        // view update does not - the same guard `lastFocusRequest` and `lastScrollRequest`
        // are. Cleared when the bar closes, so reopening on the same match scrolls again.
        if matchJump?.location != context.coordinator.lastMatchLocation {
            context.coordinator.lastMatchLocation = matchJump?.location
            if let matchJump { context.coordinator.scroll(textView, to: matchJump, takingFocus: false) }
        }

        if let scrollRequest, scrollRequest.id != context.coordinator.lastScrollRequest {
            context.coordinator.lastScrollRequest = scrollRequest.id
            context.coordinator.scroll(textView, to: scrollRequest.range)
            onScrollApplied()
        }
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
