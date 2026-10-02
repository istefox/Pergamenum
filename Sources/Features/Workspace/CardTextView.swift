import AppKit
import SwiftUI

/// A `.text` canvas card's text, drawn and edited by one component (ADR-0027 §D3).
///
/// `isEditable` is the only difference between the two states: the same `FormattingTextView`
/// draws the same source with the same `CardTextAttributes`, so a card cannot look one way at
/// rest and another way while it is being written into (R-08). That is what the pair it replaces
/// could not promise - a SwiftUI `TextEditor` while editing and a static `Text` otherwise were
/// two renderers of one string.
///
/// Always inside an `NSScrollView`, built by `FormattingTextView.scrollableTextView()`: whether
/// the card can be scrolled changes with `isEditable`, what is drawn does not. Dropping the
/// scroll view would have been simpler and would have regressed today's `TextEditor`, which
/// scrolls when a card's text overflows its frame.
struct CardTextView: NSViewRepresentable {
    /// While editing this is `WorkspaceController.editingTextDraft`; at rest it is the node's
    /// stored text and nothing ever writes back through it. The document is mutated once, at
    /// `endTextEdit(commit:)`, never per keystroke.
    @Binding var text: String
    let theme: Theme
    /// The whole-card text colour and alignment (ADR-0027 §D4), read from the node's own
    /// `pergamenum-*` keys. They are properties of the card rather than of a selection, so they
    /// arrive here as one value and are applied under every span.
    let style: CardTextStyle
    let isEditable: Bool
    /// The vault's `hidesMarkup` setting (ADR-0028 §D10), travelling the route the board's own
    /// settings already travel: `WorkspaceView.applyBoardSettings()` reads it from
    /// `vault.settings`, `WorkspaceController` holds it, `StickyTextCard` hands it here. Never a
    /// second switch of the card's own, and never an `@Environment(VaultController.self)` read
    /// inside the card - a card built in a preview or a test has no such environment and would
    /// crash on it.
    let hidesMarkup: Bool
    /// The vault's note titles and boards, offered as `[[` completion candidates - the same
    /// `hidesMarkup`-style route, off `WorkspaceController.wikilinkNoteTitles`/
    /// `.wikilinkBoardTitles`. Defaulted, like `foldedEntries` below: a card in a preview or
    /// a test offers no completion rather than crashing.
    var wikilinkNoteTitles: [String] = []
    var wikilinkBoardTitles: [String] = []
    /// Whether reveal-on-caret narrows from paragraph to span for this card's emphasis,
    /// strikethrough and link runs (ADR-0037 §D8), travelling the same route `hidesMarkup`
    /// above already does: `WorkspaceView.applyBoardSettings()` →
    /// `WorkspaceController.revealsInlineSpans` → `StickyTextCard`. A defaulted `var`, not a
    /// `let`: the six preview/test construction sites that predate this property must keep
    /// compiling unmodified. Since ADR-0037's §D8 amendment, `Coordinator.hiddenKind(for:)`
    /// maps `.strikethrough` and `.link` the way the note editor's table does.
    var revealsInlineSpans: Bool = false
    /// Which of this card's headings are folded (ADR-0028 §D8), as ordinals into
    /// `NoteOutline.entries(in:)` over this card's own text - the numbers `NoteTab.foldedEntries`
    /// holds for a note, down the route `hidesMarkup` above already travels. Defaulted like the
    /// closures below: a card in a preview or a test folds nothing.
    var foldedEntries: Set<Int> = []
    /// The card's selection moved or its text changed while it was editable, with the live view
    /// so the caller can read where the selection is and act on it (ADR-0027 §D5).
    ///
    /// A closure rather than a reference to `CardTextSelection` for the same reason
    /// `onEndEditing` below is one: this view knows nothing about the board it floats on, only
    /// that something out there asked to be told. Both `nil`-safe by default, so a card built
    /// without a board behind it - a preview, a test - publishes to nobody.
    var onSelectionChange: (FormattingTextView) -> Void = { _ in }
    /// The card's `[[` completion popup changed - opened, moved its highlight, or closed -
    /// with the live view so the caller can read its state and act on it. Same shape as
    /// `onSelectionChange` above, and for the same reason: this view knows nothing about the
    /// board it floats on.
    var onWikilinkCompletionChange: (FormattingTextView) -> Void = { _ in }
    /// Esc, a click outside, or the keyboard going anywhere else. One closure for all three
    /// because today all three do the same thing - `endTextEdit(commit: true)` - and a second
    /// one would only record a distinction the card does not make.
    var onEndEditing: () -> Void = {}
    /// A click landed on a folded heading's badge, naming the entry ordinal it stands for
    /// (ADR-0028 §D8) - the card's half of `NoteTextView.onToggleFold`. Reported rather than acted
    /// on for the reason the two above are: this view does not know which node id the fold is for.
    var onToggleFold: (Int) -> Void = { _ in }
    /// A click landed on a task line's checkbox glyph, naming the zero-based line it toggled
    /// (SPEC §7.1, PG-074) - reported for the same reason `onToggleFold` above is: this view
    /// does not know which node id, or which of the two write paths (at rest / while editing),
    /// the toggle has to go through.
    var onToggleTask: (Int) -> Void = { _ in }
    /// A wikilink or CommonMark link was Cmd+clicked (or "Apri collegamento" chosen), naming
    /// the resolved title/href to navigate to (issue #188, R-06) - reported rather than acted
    /// on for the same reason the closures above are: this view knows nothing about the
    /// board or the vault, only that something out there asked to be told.
    var onFollowLink: (String) -> Void = { _ in }
    /// The embed half of the same click (`![[foto.png]]`'s target), naming the file. No card
    /// surface previews an embed today, so the default is a no-op rather than a required
    /// wiring - out of this feature's scope (SPEC scope is wikilinks/CommonMark links).
    var onOpenEmbed: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        // Apple's own wiring rather than a hand-assembled pair: it returns an instance of the
        // receiving class (verified - `FormattingTextView.scrollableTextView()` hands back a
        // `FormattingTextView`), already on TextKit 2, already vertically resizable, with the
        // text container tracking the view's width. Each of those is a way a hand-built
        // scroll-view/text-view pair goes subtly wrong.
        let scrollView = FormattingTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? FormattingTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        // Smart substitutions would rewrite `- [ ]` and `>2026-08-15` into characters the task
        // parser rejects, silently making a conformant To Do card non-conformant as it is typed -
        // the same reason `NoteTextView` turns all four of them off.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // A card's links are styled and never navigable (ADR-0027 §D1). Detection off, and no
        // attributes for a `.link` that this table never writes anyway.
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [:]
        // The card draws its own background - the sticky colour, or nothing at all for a plain
        // Testo card - so neither the scroll view nor the text view may paint one over it.
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        textView.textContainerInset = NSSize(width: 2, height: 2)

        let coordinator = context.coordinator
        textView.onCancel = { [weak coordinator] in coordinator?.parent.onEndEditing() }
        // A click on a folded heading's badge (ADR-0028 §D8), reported the way Esc above is and
        // through the same weak coordinator - reading `parent` at call time is what makes it
        // follow the card as SwiftUI replaces the struct.
        textView.onToggleFold = { [weak coordinator] entry in coordinator?.parent.onToggleFold(entry) }
        // A click on a task line's checkbox glyph (PG-074), reported the same way.
        textView.onToggleTask = { [weak coordinator] lineIndex in coordinator?.parent.onToggleTask(lineIndex) }
        // The `[[` completion popup changed, reported the same way.
        textView.onWikilinkCompletionChange = { [weak coordinator] view in
            coordinator?.parent.onWikilinkCompletionChange(view)
        }

        // The rendering rule, handed over in the two lines that carry it - the same pair
        // `NoteTextView.swift:148-149` assigns, to the same class rather than to a fork of it
        // (ADR-0028 §D1): the delegate *is* what a `# `, a `- ` and a `**` look like, so a
        // second copy of it is how a card and a note would quietly stop agreeing.
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.wikilinkNoteTitles = wikilinkNoteTitles
        textView.wikilinkBoardTitles = wikilinkBoardTitles
        textView.string = text
        coordinator.configure(textView, editable: isEditable)
        coordinator.applyStyling(to: textView)
        // After the styling, which fills the table the fold's re-read walks over. A card rebuilt
        // on a node that is already folded draws folded straight away - see `applyFolding`.
        coordinator.applyFolding(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FormattingTextView else { return }
        context.coordinator.parent = self

        // Everything below runs inside SwiftUI's own update pass, and two of these calls -
        // `setSelectedRange` and `makeFirstResponder` - make AppKit deliver
        // `textViewDidChangeSelection` synchronously. Publishing the selection from in there
        // would be a state mutation during a view update, so the coordinator holds the
        // publication back for the length of the pass (ADR-0027 §D5).
        textView.wikilinkNoteTitles = wikilinkNoteTitles
        textView.wikilinkBoardTitles = wikilinkBoardTitles
        context.coordinator.duringViewUpdate {
            // Only touch the text when the model diverges from what is on screen: reassigning it
            // unconditionally would reset the caret on every keystroke (`NoteTextView`'s own guard).
            if textView.string != text {
                let selection = textView.selectedRange()
                textView.string = text
                textView.setSelectedRange(NSRange(
                    location: min(selection.location, (text as NSString).length),
                    length: 0
                ))
            }
            context.coordinator.configure(textView, editable: isEditable)
            context.coordinator.applyStyling(to: textView)
            context.coordinator.matchFocus(textView, editable: isEditable)
            // Last, and after `configure` above in particular: `isEditable` is what decides
            // whether anything is revealed at all (R-04), so a card that has just stopped being
            // edited has to be asked again here - nothing else will ask, because AppKit sends no
            // selection change when a view merely becomes uneditable.
            context.coordinator.applyReveal(to: textView)
            // Last, so the fold's document-wide re-read is the one that reaches the layout manager
            // (`NoteTextView.swift:275`'s own placement) - see `CardTextView+Fold.swift`.
            context.coordinator.applyFolding(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, LinkNavigatingDelegate {
        var parent: CardTextView
        /// Read live, at the moment `textView(_:clickedOnLink:at:)` runs, never captured at
        /// init - `NoteTextView.Coordinator.modifierFlags`'s twin (ADR-0053 §D2 seam #4,
        /// PG-361). A test injects a fixed value here instead of driving a real `NSEvent`;
        /// production never overrides the default.
        var modifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
        /// The card's own undo stack (ADR-0027 §D2), never the window's.
        ///
        /// The board's Annulla is `BoardHistory` through `workspace.undo()`, a third stack that
        /// has never been the window's; pushing "restore the letter I typed into a card" onto the
        /// window's manager would put a step the user cannot see between them and the board undo
        /// they meant. It also means no action targeting this view can outlive it on a stack
        /// somebody else owns.
        let undoManager = UndoManager()
        /// The rendering rule the two surfaces share, reused rather than forked (ADR-0028 §D1):
        /// the same object the note editor hands its own content storage and layout manager to
        /// (`NoteTextView.swift:148-149`), because the delegate *is* the rule and a fork of it
        /// would let a card and a note quietly disagree about what a `- ` looks like.
        let decorations = EditorDecorationDelegate()
        /// The hidden-marker table the last styling pass handed `decorations`: paragraph-start
        /// offset to the markers inside it, each range relative to its own paragraph - the key
        /// space `EditorDecorationDelegate` reads at layout time (ADR-0018 §D1), and the same one
        /// `NoteTextView+Coordinator.applyStyling` fills for the note editor.
        ///
        /// Kept on the coordinator rather than left as a local of the walk because the delegate's
        /// own copy is private: this is where a test reads back the kinds and the ranges the
        /// card's walk produced, and "the card's table has the same shape as the note's" is
        /// R-04's precondition.
        ///
        /// Setter not `private`: its two writers, `applyStyling(to:)` and `releaseDecorations()`,
        /// are in `CardTextView+Styling.swift`, and nothing else writes it.
        var hiddenMarkers: [Int: [HiddenMarker]] = [:]
        /// The revealed set already published, so an unchanged one invalidates nothing - the
        /// same restraint the note editor's `RevealController.lastRevealed` keeps, and for the same
        /// reason: `applyReveal` runs on every arrow key. Not private for that type's other
        /// reason too - its mutator lives in `CardTextView+Reveal.swift`.
        var lastRevealed: Set<Int> = []
        /// The revealed-span table already handed to `decorations`, beside `lastRevealed` for
        /// the same reason (ADR-0037 §D6): both must be unchanged for `applyReveal` to skip
        /// work, or a caret held still while only the setting flips would never redraw. Its
        /// mutator lives in `CardTextView+Reveal.swift`.
        var lastRevealedSpans: [Int: [NSRange]] = [:]
        /// The fold layout already handed to the delegate, so an unchanged one re-reads nothing -
        /// the note editor's `FoldController.lastFoldLayout` restraint, mattering more here because
        /// `applyFolding` runs in every SwiftUI update of every card. Not private, like
        /// `lastRevealed` above: its mutator lives in `CardTextView+Fold.swift`.
        var lastFoldLayout = NoteFolding.Layout()
        /// Guards the delegate callback from re-entering while styling rewrites attributes.
        ///
        /// Not `private`: `applyStyling(to:)` in `CardTextView+Styling.swift` raises it, and
        /// `textDidChange` here reads it.
        var isStyling = false
        /// Set for the length of `updateNSView`, the same shape as `isStyling` above and for a
        /// neighbouring reason: what happens in there is SwiftUI's, not the typist's.
        private var isUpdatingView = false

        init(parent: CardTextView) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? FormattingTextView else { return }
            parent.text = textView.string
            // Before the styling, so the passes below measure the text this one leaves behind
            // rather than one it is about to rewrite (ADR-0028 §D6, R-08). A no-op on every
            // keystroke outside an ordered run - see `CardTextView+ListEditing.swift`.
            renumberLists(in: textView)
            applyStyling(to: textView)
            // After the restyle: a keystroke moves every offset below it, so the revealed set has
            // to be recomputed against the text the pass above has just measured (ADR-0018 §D2).
            applyReveal(to: textView)
            // After both, not before: the frame published below comes from the laid-out text, and
            // a selection measured against the previous layout is a bar a few points off the words
            // it labels.
            publishSelection(textView)
            // Also after the restyle, for the same reason: the trigger and its candidates are
            // read against the text the pass above has just measured.
            textView.refreshWikilinkCompletion()
        }

        /// Every arrow key, every drag, and the `setSelectedRange` that ends a format action land
        /// here - the same callback `refreshFormatBar` hangs the note editor's own bar off
        /// (`CompletingTextView+FormatBar.swift:11`).
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? FormattingTextView else { return }
            // Before the publication and unconditionally: this is the only callback an arrow key
            // reaches, and it is arrows that carry the caret from one paragraph to the next
            // (R-03). `publishSelection` below returns early for a card at rest; this must not.
            applyReveal(to: textView)
            publishSelection(textView)
            // Arrow keys carry the caret in and out of a `[[...]]` span with no text change of
            // their own - the note editor's own `refreshCompletion` has the identical second
            // call site, via `refreshFormatBar`'s neighbouring hook.
            textView.refreshWikilinkCompletion()
        }

        /// Hands the board this card's current selection, but **only while this card is the one
        /// being written into**.
        ///
        /// The guard is the whole point: a card at rest that published its own empty selection
        /// would overwrite what the card actually being edited had just reported, and the bar
        /// would blink out from under the person using it. `isEditable` is the property that
        /// separates the two states (ADR-0027 §D3), so it is the one asked.
        ///
        /// Called from AppKit's own callbacks and never from `updateNSView`: publishing there
        /// would mutate observable state during a SwiftUI update pass. Nothing is lost by not
        /// doing so - a card that has just been opened for editing has an empty selection, which
        /// shows no bar anyway, and the first selection the person makes arrives here.
        private func publishSelection(_ textView: FormattingTextView) {
            guard !isUpdatingView, textView.isEditable else { return }
            parent.onSelectionChange(textView)
        }

        /// Runs `body` with every selection publication suppressed - see `publishSelection`.
        func duringViewUpdate(_ body: () -> Void) {
            isUpdatingView = true
            defer { isUpdatingView = false }
            body()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        /// Like `NoteTextView.Coordinator`'s twin (issue #191, `.editorLink`'s doc comment has
        /// the full history): AppKit can no longer invoke this delegate method on its own -
        /// clickable spans carry the app's own `.editorLink` attribute, never the standard
        /// `.link` that used to make AppKit's own unreliable click-navigation gesture engage.
        /// Reachable only from this app's own explicit call site in `followLinkIfPresent(at:)`,
        /// already Cmd-gated before calling in; the live modifier check here is defense in
        /// depth, not a live necessity. "Apri collegamento" bypasses this gate on purpose,
        /// through `performLinkNavigation(_:)` directly (see `LinkNavigatingDelegate`).
        ///
        /// `false`/`true` are back to their plain `NSTextViewDelegate` meaning ("did this
        /// navigate") - nothing depends any more on the refusal path returning `true`.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard modifierFlags().contains(.command) else { return false }
            return performLinkNavigation(link)
        }

        /// Same decode as `NoteTextView+Coordinator`'s own `performLinkNavigation` (issue #188,
        /// R-06) - through `MarkdownAttributedText.clickTarget(for:)` rather than a second copy
        /// of the URL parsing, so the two surfaces can never disagree about what a clicked URL
        /// means.
        @discardableResult
        func performLinkNavigation(_ link: Any) -> Bool {
            guard let url = link as? URL,
                  let target = MarkdownAttributedText.clickTarget(for: url)
            else { return false }

            switch target {
            case .external(let url):
                NSWorkspace.shared.open(url)
            case .embed(let name):
                parent.onOpenEmbed(name)
            case .note(let title):
                parent.onFollowLink(title)
            }
            return true
        }

        /// Not `private`: `applyStyling(to:)` in `CardTextView+Styling.swift` calls it. Kept in
        /// this file because `InlineSpanRevealFenceTests` reads this switch out of it (ADR-0037
        /// §D8 amendment), and kept the card's own because its `default: nil` is ADR-0029 §D17's
        /// seam. The `linkDelimiters` split the comment inside the switch refers to is in
        /// `applyStyling(to:)`, `CardTextView+Styling.swift`.
        static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind? {
            let kind: HiddenMarker.Kind? = switch styled.span {
            case .headingMarker: .heading
            case .emphasisMarker: .emphasis
            case .embedRun: .embed
            case .listMarker: .list
            case .taskMarker: .checkbox
            // ADR-0037 amendment to §D8: the card now conceals strikethrough and
            // link/wikilink syntax identically to the note editor, at the user's explicit
            // request (2026-09-09 hand check). `.link`'s whole run is never one marker -
            // see the `linkDelimiters` split below, the same reason the note editor splits
            // it.
            case .strikethroughMarker: .strikethrough
            case .linkSyntax: .link
            default: nil
            }
            return kind
        }

        /// Puts the keyboard where the model says editing is happening.
        ///
        /// SwiftUI's `@FocusState` reaches a SwiftUI view; the first responder inside an
        /// `NSViewRepresentable` is AppKit's to hand out, so the card asks for it here. Resigning
        /// on the way out matters just as much: a text view left holding the keyboard after
        /// editing ends swallows every board shortcut aimed past it.
        func matchFocus(_ textView: FormattingTextView, editable: Bool) {
            guard let window = textView.window else {
                guard editable else { return }
                // No window yet - the very first update after a card is created. Ask again once
                // the view is in one, the retry `NoteTextView.takeFocus` makes for the same reason.
                Task { @MainActor [weak textView] in
                    guard let textView, textView.isEditable else { return }
                    textView.window?.makeFirstResponder(textView)
                }
                return
            }
            let isFirstResponder = window.firstResponder === textView
            if editable, !isFirstResponder {
                window.makeFirstResponder(textView)
            } else if !editable, isFirstResponder {
                window.makeFirstResponder(nil)
            }
        }
    }
}
