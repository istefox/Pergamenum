import AppKit

/// The list-rendering half of `EditorDecorationDelegate`'s substitution mechanism,
/// split out on its own (ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 8
/// review) once the main file crossed SwiftLint's `type_body_length` warning. Follows this
/// chain's own precedent (`NoteTextView+ListEditing.swift`, `CardTextView+Fold.swift` and
/// siblings): one self-contained concern, one `extension` file.
extension EditorDecorationDelegate {
    /// The list branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// draws a list item's opening run the way a reader expects it - the unordered marker
    /// character replaced by `ListMarkerRendering.glyph(for:)`, an ordered marker's digits
    /// left exactly as the file spells them (ADR-0028 §D4), the indentation it hangs at
    /// collapsed into `collapsedFont` so the paragraph style is the only thing indenting the
    /// line, and `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` applied over the
    /// whole displayed paragraph, composed onto the style that paragraph already carries.
    ///
    /// One character out, one character in, never more: the displayed paragraph keeps its
    /// stored length, which is `NSTextContentManager.h:120`'s constraint and the reason a
    /// bullet can only ever *replace* a marker rather than be inserted before it.
    ///
    /// Nil - leaving the raw source on screen exactly as today - whenever there is nothing
    /// to draw: no list marker at this offset, the paragraph revealed because the caret is
    /// in it (R-03), or the marker gone stale against the real characters since the last
    /// styling pass.
    func listParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard !revealedParagraphs.contains(range.location) else { return nil }
        let markers = hiddenMarkers[range.location] ?? []
        guard let marker = markers.first(where: { $0.kind == .list }),
              NSMaxRange(marker.range) <= range.length
        else { return nil }

        let text = storage.string as NSString
        let markerRange = NSRange(
            location: range.location + marker.range.location, length: marker.range.length
        )
        guard let item = Self.stillSpellsAListMarker(text, at: markerRange) else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // A substitution, not an insertion: one character out, one in, the paragraph's own
        // length unmoved - `NSTextContentManager.h:120`'s constraint, the same one the
        // embed branch in the main file keeps. Nil for an ordered marker, whose own digits
        // are the rendered ordinal and are therefore left exactly as the file spells them
        // (ADR-0028 §D4).
        if let glyph = ListMarkerRendering.glyph(for: item.kind) {
            copy.replaceCharacters(
                in: NSRange(location: marker.range.location + item.indent, length: 1),
                with: String(glyph)
            )
        }
        if item.indent > 0 {
            copy.addAttribute(
                .font, value: Self.collapsedFont,
                range: NSRange(location: marker.range.location, length: item.indent)
            )
        }
        // The paragraph's other markers, collapsed exactly as the generic path in the main
        // file would have collapsed them: this branch returns early, and a list item whose
        // text is bold has to render both its bullet and its hidden `**` in the one
        // paragraph the hook is allowed to hand back.
        for other in Self.survivors(among: markers.filter { $0.kind != .list }, of: range, in: text) {
            copy.addAttribute(.font, value: Self.collapsedFont, range: other.range)
        }
        copy.addAttribute(
            .paragraphStyle,
            value: ListMarkerRendering.paragraphStyle(
                level: item.level, font: Self.bodyFont(of: copy, after: marker.range),
                // The style the paragraph already carries, composed onto rather than replaced
                // (ADR-0030 §D5): `MarkdownAttributedText.base(theme:)` puts the page's
                // `lineHeightMultiple` on every character of the note, and this attribute is
                // written over the whole displayed paragraph - so without handing it back in,
                // a line's interline spacing would collapse the moment it became a list item.
                basedOn: Self.bodyParagraphStyle(of: copy)
            ),
            // The whole displayed paragraph, not only the marker: an item that wrapped
            // would otherwise lose its indentation on its second line (R-05).
            range: NSRange(location: 0, length: copy.length)
        )
        return NSTextParagraph(attributedString: copy)
    }

    /// The font a list item's own text is drawn in, read from the character just past its
    /// marker - the one place in the paragraph guaranteed to be neither indentation nor
    /// marker, and so to carry the body font `ListMarkerRendering.paragraphStyle` steps in
    /// proportion to. The system font when the storage carries no font at all, which is
    /// what an offscreen harness building a paragraph out of a bare string has.
    private static func bodyFont(of paragraph: NSAttributedString, after marker: NSRange) -> NSFont {
        let probe = NSMaxRange(marker)
        guard probe < paragraph.length,
              let font = paragraph.attribute(.font, at: probe, effectiveRange: nil) as? NSFont
        else { return .systemFont(ofSize: NSFont.systemFontSize) }
        return font
    }

    /// The paragraph style the displayed paragraph already carries, read at its first
    /// character - a paragraph style is a property of the whole paragraph, so any offset
    /// inside it answers the same and offset 0 is the one always present.
    ///
    /// `nil` when the storage carries none, which is what an offscreen harness building a
    /// paragraph out of a bare string has; `ListMarkerRendering.paragraphStyle` then builds a
    /// fresh style exactly as it did before ADR-0030.
    private static func bodyParagraphStyle(of paragraph: NSAttributedString) -> NSParagraphStyle? {
        guard paragraph.length > 0 else { return nil }
        return paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    /// Whether `range` still spells a list item's whole opening run - an optional
    /// indentation of spaces and tabs, then `- `/`* `/`+ ` or `12. `/`12) `, and never a
    /// checkbox - read from the text as it is right now, with the three things drawing it
    /// needs: how much of that run is indentation, which kind of marker closes it, and how
    /// deep it therefore is.
    ///
    /// Returns a value rather than a `Bool`, the way `stillSpellsAnEmbed` in the main file
    /// does and unlike the heading and emphasis re-checks: those two say *whether* to
    /// collapse a range, this one also says *what* to draw over it. The level is derived
    /// here, from the characters, and never carried on the marker - `HiddenMarker.Kind.list`
    /// has no level field precisely because a table entry can go stale between a styling
    /// pass and a layout pass, and an indentation read one pass late would indent the wrong
    /// item.
    ///
    /// The rule is `listMarkerSpan`'s own, restated: the marker grammar is private to
    /// `MarkdownStyler.swift` and this re-read has to happen against the live characters
    /// anyway, which is what the whole `stillSpells` family exists for. The checkbox
    /// refusal is restated with it for the same reason it is restated there - `- [ ] fai`
    /// is a task line, and its rendering is not this one (ADR-0028 §D2, R-06). The level
    /// itself is `ListNesting.level` (PG-085) - CommonMark's content-column depth, computed
    /// fresh from `text`, the whole document, exactly as this function already receives it.
    private static func stillSpellsAListMarker(_ text: NSString, at range: NSRange) -> ListItem? {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let candidate = text.substring(with: range)
        let indent = candidate.prefix(while: { $0 == " " || $0 == "\t" })
        let marker = candidate.dropFirst(indent.count)
        guard let first = marker.first else { return nil }

        let kind: MarkdownStyler.Span.ListKind
        if first == "-" || first == "*" || first == "+" {
            // Exactly the marker and its one trailing space, nothing else: a range that
            // covers more than that is not the run the styling pass recorded.
            guard marker.count == 2, marker.last == " " else { return nil }
            if first != "+", Self.checkboxFollows(range, in: text) { return nil }
            kind = .bullet
        } else {
            let digits = marker.prefix(while: { $0.isASCII && $0.isNumber })
            let afterDigits = marker.dropFirst(digits.count)
            guard !digits.isEmpty, afterDigits.count == 2,
                  let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
                  afterDigits.last == " "
            else { return nil }
            kind = .ordered
        }

        let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let swiftText = text as String
        guard let lineStart = Range(NSRange(location: range.location, length: 0), in: swiftText)?.lowerBound
        else { return nil }
        let level = ListNesting.level(in: swiftText, lineStart: lineStart, indent: columns)
        return ListItem(indent: indent.count, kind: kind, level: level)
    }

    /// What a live re-read of a list marker's run says about drawing it: how many of its
    /// characters are indentation to collapse, which kind of marker closes it, and how deep
    /// the item sits. A value rather than the three-part tuple it replaced, because all
    /// three are read at one call site and `indent` and `level` are both plain `Int`s that
    /// a tuple would let a caller swap without a word from the compiler.
    private struct ListItem {
        /// In UTF-16 units, the same space `HiddenMarker.range` is measured in - and equal
        /// to the character count, since only spaces and tabs are counted into it.
        let indent: Int
        let kind: MarkdownStyler.Span.ListKind
        let level: Int
    }

    /// Whether the three characters after a `- `/`* ` marker spell a checkbox's `[ ]`,
    /// which is what makes the line a task rather than a list item. Read past the marker's
    /// own range on purpose: the range is the marker, and `- ` is a marker either way -
    /// only what follows it tells the two apart.
    private static func checkboxFollows(_ marker: NSRange, in text: NSString) -> Bool {
        let start = NSMaxRange(marker)
        guard start + 3 <= text.length else { return false }
        // By character and not by UTF-16 unit: three units are not always three characters,
        // and a range that cuts a surrogate pair in half must answer «no checkbox» rather
        // than trap on the subscript.
        let brackets = Array(text.substring(with: NSRange(location: start, length: 3)))
        return brackets.count == 3 && brackets[0] == "[" && brackets[2] == "]"
    }
}
