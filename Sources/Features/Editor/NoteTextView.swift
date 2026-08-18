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
    /// The slash menu's catalogue, already filtered to what can run (M8). Passed in
    /// rather than built here: whether a command can run is a fact about the app, and
    /// the editor is not the place that knows it.
    var editorCommands: [EditorCommand] = []
    var onRunCommand: ((ShortcutCommand) -> Void)?
    let onFollowLink: (String) -> Void
    /// Called with the file name inside `![[foto.png]]` when the embed is clicked. The
    /// editor shows the syntax, not the picture (SPEC §5), so this is how the file
    /// itself is reached from here.
    var onOpenEmbed: ((String) -> Void)?
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
    /// Raised by the Modifica menu; opens AppKit's own find bar.
    var findRequest: FindRequest?
    var onFindApplied: () -> Void = {}
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
        // Trova e Sostituisci of SPEC §10: AppKit's find bar already does incremental
        // search, replace-all and the scope of the current text view.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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
        context.coordinator.applyTransclusions(to: textView, theme: theme)
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
    private func wire(_ textView: CompletingTextView, to coordinator: Coordinator) {
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
        // Two decorations, asked in turn: whoever claims the click keeps it. They cannot
        // both claim one - a folded heading's line is not a transclusion's line.
        textView.onClickInMargin = { [weak textView] point in
            guard let textView else { return false }
            return coordinator.openTransclusion(at: point, in: textView)
                || coordinator.unfold(at: point, in: textView)
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CompletingTextView else { return }
        context.coordinator.parent = self
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
        context.coordinator.applyTransclusions(to: textView, theme: theme)
        context.coordinator.applyFolding(to: textView, folded: foldedEntries, theme: theme)
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

        if let findRequest {
            textView.window?.makeFirstResponder(textView)
            textView.performTextFinderAction(
                NSMenuItem(title: "", action: nil, keyEquivalent: "").withFinderTag(
                    findRequest == .find ? .showFindInterface : .showReplaceInterface
                )
            )
            onFindApplied()
        }

        if let scrollRequest, scrollRequest.id != context.coordinator.lastScrollRequest {
            context.coordinator.lastScrollRequest = scrollRequest.id
            context.coordinator.scroll(textView, to: scrollRequest.range)
            onScrollApplied()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

}

private extension NSMenuItem {
    /// `performTextFinderAction` reads the sender's tag, so the action has to arrive
    /// wearing one.
    func withFinderTag(_ action: NSTextFinder.Action) -> NSMenuItem {
        tag = action.rawValue
        return self
    }
}
