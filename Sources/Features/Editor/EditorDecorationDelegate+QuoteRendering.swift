import AppKit

/// The blockquote-rendering half of `EditorDecorationDelegate`'s substitution mechanism
/// (ADR-0029 §D1; plan `2026-09-02-editor-wysiwyg-unification`, Task 2), split out on its
/// own the way `+ListRendering.swift` and `+CheckboxRendering.swift` already are - one
/// self-contained concern, one `extension` file (`type_body_length`).
extension EditorDecorationDelegate {
    /// The blockquote branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// meant to draw a `>`/`>>`/`>>>` run as one `▏` per nesting level, character for
    /// character - the file's own `>` count *is* the depth (R-03, unbounded), so a bar is a
    /// straight one-for-one substitution and never a computed indent the way `.list`'s glyph
    /// is. `Self.survivors(among:of:in:)` is what the coder reuses here to collapse any other
    /// marker sharing the same paragraph (a bold run inside a quote, the SPEC's coexistence
    /// case) - the same reuse `listParagraph(at:storage:)` already makes.
    ///
    /// At a gutter (ADR-0081 §D3, the note editor only) the quote also hangs: its content sits
    /// at `EditorGutter.quoteColumn`, and the run displayed before it - the bars concealed, the
    /// file's `>` run revealed - hangs from that column, so the content does not move when the
    /// caret enters the line. The revealed paragraph is then the source with that style and no
    /// substitution. Without a gutter (a card, §D6) nothing changes: no style concealed, nil
    /// revealed.
    ///
    /// Nil - leaving the raw `>` source on screen exactly as today - whenever there is
    /// nothing to draw: no blockquote marker at this offset, the paragraph revealed because
    /// the caret is in it (ADR-0018 §D2) with no gutter to hang in, the setting off, or the
    /// marker gone stale against the real characters since the last styling pass.
    func quoteParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        // Its own guard rather than the caller's: `textContentStorage(_:textParagraphWith:)`
        // already refuses at its first line without the setting, but this branch is reached
        // directly too, and ADR-0018 §D10's switch has to mean off wherever it is asked.
        let revealed = revealedParagraphs.contains(range.location)
        guard hidesMarkup, !revealed || gutter > 0 else { return nil }
        guard let marker = marker(of: .blockquote, at: range) else { return nil }

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
        // One bar per `>`, character for character: the substitution is the same length as
        // what it replaces, which is `NSTextContentManager.h:120`'s constraint and the whole
        // reason nesting is unbounded here (R-03) - there is no depth to cap because there
        // is no table to keep, the file's own characters are the count.
        copy.replaceCharacters(
            in: NSRange(location: marker.range.location, length: level),
            with: String(repeating: Self.quoteBar, count: level)
        )
        // The single space after the last `>`, when the line wrote one: collapsed rather
        // than kept, so the quoted text sits against its bars instead of one space further
        // right than the line above it (ADR-0029 §D1).
        if marker.range.length > level {
            copy.addAttribute(
                .font, value: Self.collapsedFont,
                range: NSRange(
                    location: marker.range.location + level, length: marker.range.length - level
                )
            )
        }
        // The paragraph's other markers, collapsed exactly as the generic path in the main
        // file would have collapsed them: this branch returns early, and a quoted line whose
        // text is bold has to render both its bars and its hidden `**` in the one paragraph
        // the hook is allowed to hand back - the reuse `listParagraph` already makes.
        let markers = hiddenMarkers[range.location] ?? []
        for other in Self.survivors(among: markers.filter { $0.kind != .blockquote }, of: range, in: text) {
            copy.addAttribute(.font, value: Self.collapsedFont, range: other.range)
        }
        for tooltip in Self.linkTooltips(
            among: Self.survivors(among: markers, of: range, in: text), of: range, in: text
        ) {
            copy.addAttribute(.toolTip, value: tooltip.target, range: tooltip.range)
        }
        // The bars alone: the space after them is collapsed above and draws as nothing.
        if gutter > 0 {
            hangQuote(copy, level: level, displayedRun: String(repeating: Self.quoteBar, count: level))
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// Hangs `displayedRun` from the quote's column over the whole displayed paragraph (ADR-0081
    /// §D3): wrapped lines at `quoteColumn`, the first line `w` before it, clamped at zero. Composed
    /// on the style the paragraph already carries, so the page's line height, the gutter's tail
    /// indent and the paragraph gap survive.
    private func hangQuote(_ copy: NSMutableAttributedString, level: Int, displayedRun: String) {
        let style = NSMutableParagraphStyle()
        if let base = Self.bodyParagraphStyle(of: copy) { style.setParagraphStyle(base) }
        let column = EditorGutter.quoteColumn(level: level, font: proseFont, gutter: gutter)
        style.headIndent = column
        style.firstLineHeadIndent = max(0, column - markerWidths.width(of: displayedRun, in: proseFont))
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
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
    /// the quote marker grammar of `MarkdownBlockParser.lineTokens(in:)`: a range covering
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
