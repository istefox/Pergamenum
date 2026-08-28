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
    /// Esc, a click outside, or the keyboard going anywhere else. One closure for all three
    /// because today all three do the same thing - `endTextEdit(commit: true)` - and a second
    /// one would only record a distinction the card does not make.
    var onEndEditing: () -> Void = {}

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

        textView.string = text
        coordinator.configure(textView, editable: isEditable)
        coordinator.applyStyling(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FormattingTextView else { return }
        context.coordinator.parent = self

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
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Purges this text view's pending undo actions before SwiftUI releases it.
    ///
    /// Redundant given that the coordinator hands out an `UndoManager` of its own, which dies
    /// with it (ADR-0027 §D2) - and kept anyway, because the cost of being wrong about that is
    /// the `EXC_BAD_ACCESS` in `-[_NSUndoStack popAndInvoke]` that `a853e8e` fixed for the note
    /// editor. A card's text view is deallocated far more often than the editor's: once per card,
    /// and again every time a card crosses `BoardContentLayer.visibleNodes`' culling rect.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.undoManager.removeAllActions(withTarget: textView)
        if let textStorage = textView.textStorage {
            coordinator.undoManager.removeAllActions(withTarget: textStorage)
        }
    }

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
        /// Guards the delegate callback from re-entering while styling rewrites attributes.
        private var isStyling = false

        init(parent: CardTextView) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? FormattingTextView else { return }
            parent.text = textView.string
            applyStyling(to: textView)
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
        func applyStyling(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }
            storage.beginEditing()
            CardTextAttributes.apply(to: storage, theme: parent.theme, base: baseAttributes)
            storage.endEditing()
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
