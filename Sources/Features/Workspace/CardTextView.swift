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
    /// Whether reveal-on-caret narrows from paragraph to span for this card's bold/italic runs
    /// (ADR-0037 §D8), travelling the same route `hidesMarkup` above already does:
    /// `WorkspaceView.applyBoardSettings()` → `WorkspaceController.revealsInlineSpans` →
    /// `StickyTextCard`. A defaulted `var`, not a `let`: the six preview/test construction
    /// sites that predate this property must keep compiling unmodified. A card's `hiddenKind`
    /// switch has no `.strikethrough`/`.link` case (ADR-0029 §D17, not widened by this chain),
    /// so this setting only ever narrows the card's bold/italic reveal.
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

        // The rendering rule, handed over in the two lines that carry it - the same pair
        // `NoteTextView.swift:148-149` assigns, to the same class rather than to a fork of it
        // (ADR-0028 §D1): the delegate *is* what a `# `, a `- ` and a `**` look like, so a
        // second copy of it is how a card and a note would quietly stop agreeing.
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CardTextView
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
        private(set) var hiddenMarkers: [Int: [HiddenMarker]] = [:]
        /// The revealed set already published, so an unchanged one invalidates nothing - the
        /// same restraint `NoteTextView.Coordinator.lastRevealed` keeps, and for the same
        /// reason: `applyReveal` runs on every arrow key. Not private for that type's other
        /// reason too - its mutator lives in `CardTextView+Reveal.swift`.
        var lastRevealed: Set<Int> = []
        /// The revealed-span table already handed to `decorations`, beside `lastRevealed` for
        /// the same reason (ADR-0037 §D6): both must be unchanged for `applyReveal` to skip
        /// work, or a caret held still while only the setting flips would never redraw. Its
        /// mutator lives in `CardTextView+Reveal.swift`.
        var lastRevealedSpans: [Int: [NSRange]] = [:]
        /// The fold layout already handed to the delegate, so an unchanged one re-reads nothing -
        /// `NoteTextView.Coordinator.lastFoldLayout`'s restraint, mattering more here because
        /// `applyFolding` runs in every SwiftUI update of every card. Not private, like
        /// `lastRevealed` above: its mutator lives in `CardTextView+Fold.swift`.
        var lastFoldLayout = NoteFolding.Layout()
        /// Guards the delegate callback from re-entering while styling rewrites attributes.
        private var isStyling = false
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

        /// The two states, and the single property that separates them (ADR-0027 §D3).
        ///
        /// `isSelectable` follows `isEditable` rather than staying on: at rest the card's own
        /// tap, drag and double-click gestures need the pointer, which is the same condition
        /// `BoardContentLayer.selectionGestures(enabled:)` already switches on.
        func configure(_ textView: FormattingTextView, editable: Bool) {
            textView.isEditable = editable
            textView.isSelectable = editable
            textView.typingAttributes = baseAttributes
        }

        /// Restyles the live storage in place - attributes only, never a character, so the caret
        /// and the selection stay where the typist left them.
        ///
        /// Two readings of the same spans, and only the second is about hiding:
        /// `CardTextAttributes.apply` writes what the card looks like, from the card's own table
        /// (ADR-0027 §D1), and the walk below records what the card conceals, in the note
        /// editor's key space (ADR-0018 §D1). They are kept apart rather than fused because those
        /// two tables are deliberately different objects - the attribute one is the card's, the
        /// marker one is shared - and `MarkdownStyler.spans(in:)` is cheap enough to ask twice
        /// for a card's worth of text.
        func applyStyling(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }
            let text = textView.string
            let nsText = text as NSString
            var markers: [Int: [HiddenMarker]] = [:]
            storage.beginEditing()
            CardTextAttributes.apply(to: storage, theme: parent.theme, base: baseAttributes)
            for styled in MarkdownStyler.spans(in: text) {
                let kind: HiddenMarker.Kind? = switch styled.span {
                case .headingMarker: .heading
                case .emphasisMarker: .emphasis
                case .embedRun: .embed
                case .listMarker: .list
                case .taskMarker: .checkbox
                default: nil
                }
                guard let kind else { continue }
                let nsRange = NSRange(styled.range, in: text)
                guard nsRange.location != NSNotFound, NSMaxRange(nsRange) <= nsText.length else { continue }
                let paragraphStart = nsText.paragraphRange(
                    for: NSRange(location: nsRange.location, length: 0)
                ).location
                markers[paragraphStart, default: []].append(
                    // The note editor's own mapping, called rather than copied: a `.list` marker's
                    // range starts at its paragraph and not at its marker character, so that the
                    // indentation is inside it (ADR-0028 §D4), and a second spelling of that one
                    // asymmetry is exactly how the two surfaces would start drawing nested items
                    // differently.
                    NoteTextView.Coordinator.hiddenMarker(kind, at: nsRange, paragraphStart: paragraphStart)
                )
            }
            hiddenMarkers = markers
            // The badge a folded heading draws over itself, from the two tokens the note editor's
            // `applyFolding` reads (`NoteTextView+Coordinator.swift:154-155`). Here rather than
            // beside a fold pass the card does not have yet: the delegate is shared, and it must
            // never be left drawing a badge in its `.secondaryLabelColor` default on a themed card.
            decorations.badgeColor = NSColor(parent.theme.color(.textTertiary))
            decorations.badgeBackground = NSColor(parent.theme.color(.backgroundTertiary))
            // Before `endEditing()`, not after: that call is what fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so the table
            // has to already be current when it does (ADR-0018 §D1). The setting travels beside
            // the table rather than switching the walk off, so turning it back on redraws without
            // a styling pass of its own (ADR-0028 §D10).
            decorations.apply(hiddenMarkers: markers, hidingMarkup: parent.hidesMarkup)
            // Pushed here rather than only from `applyReveal` (ADR-0037 §D7/F6, the same
            // placement `NoteTextView+Coordinator.applyStyling` uses): that pass early-returns
            // when the computed reveal already matches what it last applied, so a toggle flip
            // with a stationary caret would otherwise never reach the delegate. `applyStyling`
            // runs unconditionally on every `updateNSView`.
            decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)
            storage.endEditing()
        }

        /// Lets go of everything the shared delegate is holding on this card's behalf (R-11).
        ///
        /// All three tables, not only the markers: they are read together at layout time, and a
        /// revealed-paragraph offset or a folded heading's offset surviving its text is the same
        /// stale-offset bug as a marker surviving it. `hidingMarkup: false` alongside, which makes
        /// the substitution hook a no-op outright rather than leaving it to find an empty table.
        ///
        /// The fold is the one with teeth: its offsets keep a paragraph out of the layout rather
        /// than styling it. `lastFoldLayout` empties with it, or the next pass would compare
        /// against a layout the delegate no longer holds and skip re-applying it.
        func releaseDecorations() {
            hiddenMarkers = [:]
            lastRevealed = []
            lastRevealedSpans = [:]
            lastFoldLayout = NoteFolding.Layout()
            decorations.apply(hiddenMarkers: [:], hidingMarkup: false)
            decorations.apply(revealsInlineSpans: false)
            _ = decorations.apply(revealedParagraphs: [])
            _ = decorations.apply(revealedSpans: [:])
            decorations.apply(hiddenLines: [], foldedHeadings: [:])
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

        /// `CardTextAttributes.base(theme:)` with the card's own colour and alignment written
        /// over it (ADR-0027 §D4). Under the spans rather than over them, so a coloured card
        /// still draws its links and its task markers in their own colours.
        private var baseAttributes: [NSAttributedString.Key: Any] {
            var attributes = CardTextAttributes.base(theme: parent.theme)
            if let rgba = parent.style.color.flatMap(CardTextStyle.rgba(for:)) {
                attributes[.foregroundColor] = NSColor(
                    srgbRed: CGFloat(rgba.red),
                    green: CGFloat(rgba.green),
                    blue: CGFloat(rgba.blue),
                    alpha: CGFloat(rgba.alpha)
                )
            }
            if let alignment = parent.style.alignment {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment.textAlignment
                attributes[.paragraphStyle] = paragraph
            }
            return attributes
        }
    }
}

private extension CardTextStyle.Alignment {
    /// AppKit's alignment for each of the four values ADR-0027 §D4 spells out in the file. There
    /// is no case for "absent": a node with no `pergamenum-textAlign` key reads as `nil` and
    /// never reaches this, which is what keeps natural alignment distinct from an explicit left.
    var textAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justify: .justified
        }
    }
}
