import AppKit
import SwiftUI

/// The Coordinator's own half of the view-query builder's commit (ADR-0034 §D3): the write a
/// "Fatto" tap in the sheet reaches - `commitTable`'s exact shape
/// (`NoteTextView+Tables.swift:169-192`), carried into this construct's own currency.
extension NoteTextView.Coordinator {
    /// Rewrites the fence whose opening line starts at `offset` to carry `body`, refusing -
    /// the buffer left untouched - the moment any of three sources disagree: the note as the
    /// **model** still spells it (`parent.text`), the note as the **buffer** spells it
    /// (`textView.string`), and, when there is one, the fence's own body as it was recorded
    /// at the last styling pass that actually drew it (`drawnViewBlocks`, ADR §D3's "the
    /// source recorded when the sheet opened").
    ///
    /// `commitTable`'s own guard only needs the first two - its edit applies to whatever the
    /// live table still is, by index. This commit instead replaces the whole body with text
    /// computed outside the buffer, so a change to the fence between the request opening and
    /// the commit has to be caught even when it leaves model and buffer back in agreement
    /// with each other (R-13's "equal-length changes defeat a range-only guard" case: model
    /// and buffer can both move to the *same* new text and still disagree with what the sheet
    /// was handed).
    ///
    /// The third check is conditional on `drawnViewBlocks` actually holding an entry for
    /// `offset`, rather than a required unwrap, because that store is reveal-gated
    /// (`applyViewBlocks`, ADR-0033 §D4): a fence the caret is sitting inside draws nothing
    /// and registers no entry there, and this call is reachable directly - not only through a
    /// sheet the app would never have shown over a revealed fence in the first place - so a
    /// caret parked on the fence must not make an otherwise-consistent commit unrefusable.
    /// Where a drawn record does exist, it is the strongest signal of drift and is honoured.
    ///
    /// `replaceAtomically(_:with:in:)` is the only write here (ADR-0019 §D7's precedent) - one
    /// `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` write, therefore one
    /// `Cmd+Z` regardless of how many controls moved in the sheet. The written text is always
    /// the canonical `` ```pergamenum-view\n<body>\n``` `` (ADR §D3): `viewBlockRun`'s range
    /// starts at the opening fence paragraph and ends at the closing fence line's own last
    /// character, its newline excluded, so writing over the whole range also normalises a
    /// hand-typed opening line's indentation or trailing spaces.
    @discardableResult
    func commitViewBlock(_ body: String, at offset: Int, in textView: NSTextView) -> Bool {
        guard parent.hidesMarkup,
              let recorded = EditorDecorationDelegate.viewBlockRun(
                  in: parent.text as NSString, atParagraphStart: offset
              ),
              let live = EditorDecorationDelegate.viewBlockRun(
                  in: textView.string as NSString, atParagraphStart: offset
              ),
              recorded.range == live.range,
              (parent.text as NSString).substring(with: recorded.range)
                  == (textView.string as NSString).substring(with: live.range)
        else { return false }

        let liveBody = Self.viewBlockBody(in: textView.string as NSString, range: live.range)
        if let recordedSource = drawnViewBlocks[offset]?.source, recordedSource != liveBody {
            return false
        }

        let fence = "```\(ViewBlock.language)\n" + body + "\n```"
        return replaceAtomically(live.range, with: fence, in: textView)
    }

    /// The fence's body alone, read back out of its own whole source range - the opening and
    /// closing fence lines split off, `DrawnViewBlock.source`'s own currency
    /// (`NoteTextView+ViewBlocks.swift`), so the live buffer's body can be compared against
    /// what the last styling pass recorded without re-parsing the fence a second way.
    private static func viewBlockBody(in text: NSString, range: NSRange) -> String {
        let lines = text.substring(with: range).components(separatedBy: "\n")
        guard lines.count >= 2 else { return "" }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}
