import Foundation

/// The range of an embed's own syntax, when a line consists of nothing else (ADR-0018,
/// slice 3).
///
/// A recogniser only: this file never draws a preview, never swaps a character for
/// `NSAttachmentCharacter`, never touches the caret or a deletion. The probe that worked
/// out how the drawn copy has to look (slice 3's Step 0) found that mechanism belongs on
/// the drawing side - a *copy* of the paragraph being rendered, never the real storage -
/// which is Step 3's problem, not this file's. `MarkdownStyler.spans(inLine:at:in:)` calls
/// this the same way it already calls `taskMarker(in:)`, on a line that is not inside a
/// fence, and reports what comes back as `.embedRun`.
///
/// "Is this line a file, or a note?" is not decided here - it already has an owner.
/// `Transclusion.target(ofLine:)` tells the two apart under ADR-0010 §D2: `![[nota]]`
/// with no extension answers `.note`, never `.file` (D4 - a bare wikilink stays a
/// transclusion, it must never collapse the way an image does), and a remote target
/// answers neither (principle 2, fully offline - `Attachment.isRemote` is what filters
/// it out, inside `target(ofLine:)`). This function only asks that question and, when the
/// answer is `.file`, trims the line down to the embed's own characters.
func embedRun(inLine line: String) -> Range<String.Index>? {
    guard case .file? = Transclusion.target(ofLine: line) else { return nil }
    // Indentation is tolerated, trailing whitespace likewise - the caller wants the
    // embed's own characters, not the row it sits on, matching what
    // `Attachment.embed(inLine:)` itself trims before recognising either spelling.
    guard let start = line.firstIndex(where: { !$0.isWhitespace }),
          let end = line.lastIndex(where: { !$0.isWhitespace })
    else { return nil }
    return start..<line.index(after: end)
}
