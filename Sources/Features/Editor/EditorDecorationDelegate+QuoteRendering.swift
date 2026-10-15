import AppKit

/// The blockquote-rendering half of `EditorDecorationDelegate`'s substitution mechanism
/// (ADR-0029 §D1; plan `2026-09-02-editor-wysiwyg-unification`, Task 2), split out on its
/// own the way `+ListRendering.swift` and `+CheckboxRendering.swift` already are - one
/// self-contained concern, one `extension` file (`type_body_length`).
extension EditorDecorationDelegate {
    /// The blockquote branch of the substitution in `textContentStorage(_:textParagraphWith:)`.
    /// `Self.survivors(among:of:in:)` collapses any other marker sharing the paragraph (a bold run
    /// inside a quote, the SPEC's coexistence case), the reuse `listParagraph(at:storage:)` makes.
    ///
    /// At a gutter (the note editor) the concealed `>` run is collapsed and the content hangs at
    /// `EditorGutter.quoteColumn`, one `QuoteGeometry` step per level, while `QuoteBarFragment` draws
    /// the bars (ADR-0087 §D7). Revealed, the file's `>` run hangs from that same column, so the
    /// content does not move when the caret enters the line (ADR-0081 §D3). Without a gutter (a
    /// card, §D6) the run is still drawn one `▏` per `>`, character for character, with no style,
    /// and a revealed quote is nil.
    ///
    /// A callout's title line carries no blockquote marker: it is handed to
    /// `calloutTitleParagraph(at:storage:)`. Nil - leaving the raw source on screen - whenever there
    /// is nothing to draw: no marker at this offset, the paragraph revealed with no gutter to hang
    /// in, the setting off, or the marker gone stale against the real characters.
    func quoteParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        // Its own guard rather than the caller's: `textContentStorage(_:textParagraphWith:)`
        // already refuses at its first line without the setting, but this branch is reached
        // directly too, and ADR-0018 §D10's switch has to mean off wherever it is asked.
        let revealed = revealedParagraphs.contains(range.location)
        guard hidesMarkup, !revealed || gutter > 0 else { return nil }
        guard let marker = marker(of: .blockquote, at: range) else {
            return calloutTitleParagraph(at: range, storage: storage)
        }

        let text = storage.string as NSString
        let markerRange = NSRange(
            location: range.location + marker.range.location, length: marker.range.length
        )
        guard let level = Self.stillSpellsABlockquoteMarker(text, at: markerRange) else { return nil }

        if revealed {
            // The generic path's copy, so an inline span inside a revealed quote follows
            // ADR-0037's reveal exactly as it did when this paragraph fell through to it.
            let copy = collapsedCopy(at: range, storage: storage)
                ?? NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            hangQuote(copy, level: level, displayedRun: text.substring(with: markerRange))
            return NSTextParagraph(attributedString: copy)
        }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        if gutter > 0 {
            // At a gutter the run is collapsed and `QuoteBarFragment` draws the bars, one per level
            // over the fragment's full height (ADR-0087 §D7, amending ADR-0029 §D1's bullet): a glyph
            // per `>` cannot span a wrapped paragraph.
            copy.addAttribute(.font, value: Self.collapsedFont, range: marker.range)
        } else {
            // A card (gutter 0, ADR-0081 §D6) keeps the bars it always drew: one `▏` per `>`,
            // character for character, the substitution the same length as what it replaces
            // (`NSTextContentManager.h:120`), which is why nesting is unbounded (R-03).
            copy.replaceCharacters(
                in: NSRange(location: marker.range.location, length: level),
                with: String(repeating: Self.quoteBar, count: level)
            )
            // The single space after the last `>`, when the line wrote one: collapsed rather
            // than kept, so the quoted text sits against its bars (ADR-0029 §D1).
            if marker.range.length > level {
                copy.addAttribute(
                    .font, value: Self.collapsedFont,
                    range: NSRange(location: marker.range.location + level, length: marker.range.length - level)
                )
            }
        }
        // The paragraph's other markers, collapsed exactly as the generic path in the main
        // file would have collapsed them: this branch returns early, and a quoted line whose
        // text is bold has to render both its bars and its hidden `**` in the one paragraph
        // the hook is allowed to hand back - the reuse `listParagraph` already makes.
        let markers = hiddenMarkers[range.location] ?? []
        for other in Self.survivors(among: markers.filter { $0.kind != .blockquote }, of: range, in: text) {
            collapse(other, in: copy)
        }
        for tooltip in Self.linkTooltips(
            among: Self.survivors(among: markers, of: range, in: text), of: range, in: text
        ) {
            copy.addAttribute(.toolTip, value: tooltip.target, range: tooltip.range)
        }
        // Nothing is displayed before the content: it starts at the column, as the revealed run's does.
        if gutter > 0 { hangQuote(copy, level: level, displayedRun: "") }
        return NSTextParagraph(attributedString: copy)
    }

    /// Hangs `displayedRun` from the quote's column over the whole displayed paragraph (ADR-0081
    /// §D3): wrapped lines at `quoteColumn`, the first line `w` before it, clamped at zero. Composed
    /// on the style the paragraph already carries, so the page's line height, the gutter's tail
    /// indent and the paragraph gap survive. `inset` moves the content further in, past what a
    /// fragment draws before it (a callout title's symbol).
    func hangQuote(_ copy: NSMutableAttributedString, level: Int, displayedRun: String, inset: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        if let base = Self.bodyParagraphStyle(of: copy) { style.setParagraphStyle(base) }
        let column = EditorGutter.quoteColumn(level: level, font: proseFont, gutter: gutter) + inset
        style.headIndent = column
        style.firstLineHeadIndent = max(0, column - markerWidths.width(of: displayedRun, in: proseFont))
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
    }

    /// Colours a quote line's text, from the end of its `>` run to the end of its line, in `color`
    /// (`color.text.secondary`, ADR-0087 §D7). Called by the styling pass at the marker's span, so
    /// the spans after it on the line (a link, a tag) keep their own colours.
    static func colourQuoteText(after marker: NSRange, in storage: NSTextStorage, color: NSColor) {
        let text = storage.string as NSString
        let line = text.paragraphRange(for: NSRange(location: marker.location, length: 0))
        let start = NSMaxRange(marker)
        let length = NSMaxRange(line) - start
        guard length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: length))
    }

    /// U+258F LEFT ONE EIGHTH BLOCK - the bar a `>` is drawn as. One character wide, which
    /// is what lets the substitution be one-for-one at any nesting depth.
    static var quoteBar: Character { "▏" }

    /// How many `>` a blockquote marker's range still spells, read from the text as it is
    /// right now, or nil when it no longer spells one at all.
    ///
    /// Returns the level rather than a `Bool`, the way `stillSpellsAListMarker` does and
    /// unlike the heading and emphasis re-checks: those say *whether* to collapse a range,
    /// this one also says *what* to draw over it. The level is derived here, from the
    /// characters, and never carried on the marker - a table entry can go stale between a
    /// styling pass and a layout pass, and a depth read one pass late would draw the wrong
    /// number of bars.
    ///
    /// The run is the `>`s and at most the single space after the last one, which is
    /// the quote marker grammar of `MarkdownBlockParser.lineTokens(in:readsFrontmatter:endsLine:listSeed:)`: a range covering
    /// more than that is not the run the styling pass recorded.
    static func stillSpellsABlockquoteMarker(_ text: NSString, at range: NSRange) -> Int? {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let candidate = text.substring(with: range)
        let carets = candidate.prefix(while: { $0 == ">" }).count
        guard carets > 0 else { return nil }
        let rest = candidate.dropFirst(carets)
        guard rest.isEmpty || rest == " " else { return nil }
        return carets
    }
}
