import AppKit

/// The card's styling pass: what its text looks like (`configure`, `applyStyling`), what it lets
/// go of (`releaseDecorations`), and the base attributes both start from.
///
/// An extension file of `CardTextView.Coordinator` (ADR-0045 §D2), for the reason
/// `CardTextView+Reveal.swift` and `CardTextView+Fold.swift` are: `CardTextView.swift` reaches
/// SwiftLint's file length with every concern that arrives. Two members widen for it (§D3), each
/// with its comment where it is declared: `hiddenMarkers`' setter and `isStyling`.
///
/// The hidden-kind switch is not here. It stays in `CardTextView.swift` as
/// `Coordinator.hiddenKind(for:)`, because `InlineSpanRevealFenceTests` reads it out of that file.
extension CardTextView.Coordinator {
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
            let kind = Self.hiddenKind(for: styled)
            guard let kind else { continue }
            let nsRange = NSRange(styled.range, in: text)
            guard nsRange.location != NSNotFound, NSMaxRange(nsRange) <= nsText.length else { continue }
            let paragraphStart = nsText.paragraphRange(
                for: NSRange(location: nsRange.location, length: 0)
            ).location
            let spans = kind == .link
                ? NoteTextView.Coordinator.linkDelimiters(in: nsRange, of: nsText)
                : [nsRange]
            for span in spans {
                markers[paragraphStart, default: []].append(
                    // The note editor's own mapping, called rather than copied: a `.list` marker's
                    // range starts at its paragraph and not at its marker character, so that the
                    // indentation is inside it (ADR-0028 §D4), and a second spelling of that one
                    // asymmetry is exactly how the two surfaces would start drawing nested items
                    // differently.
                    NoteTextView.Coordinator.hiddenMarker(kind, at: span, paragraphStart: paragraphStart)
                )
            }
        }
        hiddenMarkers = markers
        // The badge a folded heading draws over itself, from the two tokens the note editor's
        // fold pass reads (`FoldController.apply`, `NoteTextView+Folding.swift`). Here rather than
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
