import AppKit
import SwiftUI

/// An `NSTextView` that completes note titles after `[[` and tags after `#`.
///
/// Uses AppKit's own completion list rather than a custom popup: it already handles
/// arrow keys, Escape, and placement near the insertion point, and matching that
/// behaviour by hand is how a completion list ends up feeling wrong.
final class CompletingTextView: NSTextView {
    var noteTitles: [String] = []
    var tagSuggestions: [String] = []
    /// The slash menu's catalogue, already filtered to what can run right now (M8).
    /// Set from the SwiftUI layer, because whether a command can run is a fact about the
    /// app and not about the text.
    var editorCommands: [EditorCommand] = []
    /// Runs a command the app owns. The text view never performs one itself.
    var onRunCommand: ((ShortcutCommand) -> Void)?
    /// Called with pasted text; returns true when it handled the paste itself.
    var onPasteURL: ((String) -> Bool)?
    /// Called with the PNG bytes of a pasted image; returns the name it was saved under.
    var onPasteImage: ((Data) -> String?)?
    /// Called with a dropped file, returning the name to embed (SPEC §5).
    var onDropFile: ((URL) -> String?)?

    /// Pasting a URL over a selection writes a markdown link (SPEC §5); pasting a
    /// picture writes the file into the vault and embeds it.
    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string),
           onPasteURL?(pasted) == true {
            return
        }
        if let onPasteImage, let png = Self.pastedImagePNG(), let name = onPasteImage(png) {
            insertText(EditorEdits.embed(forFileNamed: name), replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    /// PNG bytes for an image sitting on the pasteboard, whatever form it arrived in.
    ///
    /// A screenshot comes as TIFF and a picture copied from a browser as PNG, so both
    /// are normalised here and the vault only ever receives one format. A file copied in
    /// the Finder is deliberately left alone: it arrives as a URL and belongs to the drop
    /// path, which keeps the name it already has.
    private static func pastedImagePNG() -> Data? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.data(forType: .fileURL) == nil else { return nil }
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // A note title dragged from the sidebar onto a task line links the two
        // (SPEC §7.2, "collegamento assistito"). Checked before the file case: a
        // sidebar row carries a string, not a URL.
        if let title = sender.draggingPasteboard.string(forType: .string),
           !title.contains("\n"),
           noteTitles.contains(title),
           linkTitle(title, at: sender.draggingLocation) {
            return true
        }

        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil
        ) as? [URL] ?? []
        guard !urls.isEmpty, let onDropFile else { return super.performDragOperation(sender) }

        // Each dropped file is copied into the vault and embedded by name; the app
        // never links to a path outside the vault, which would break the day the file
        // moves or the disk is not mounted.
        let embeds = urls.compactMap(onDropFile).map(EditorEdits.embed(forFileNamed:))
        guard !embeds.isEmpty else { return super.performDragOperation(sender) }

        insertText(embeds.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }

    /// Appends `[[title]]` to the task line under the drop point.
    ///
    /// Only a task line: dropping a note in the middle of a paragraph would rewrite
    /// prose the user did not ask to change, and §7.2 is about tasks.
    private func linkTitle(_ title: String, at windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        let index = characterIndexForInsertion(at: point)
        let text = string as NSString
        guard index <= text.length else { return false }

        let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        guard TaskParser.parse(line: line, sourcePath: "", lineIndex: 0) != nil else { return false }
        guard !line.contains("[[\(title)]]") else { return true }

        // Before the newline, so the link joins the task rather than starting a line.
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line
        let replacement = trimmed + " [[\(title)]]" + (line.hasSuffix("\n") ? "\n" : "")
        insertText(replacement, replacementRange: lineRange)
        return true
    }

    private enum Context {
        case wikilink(prefix: String)
        case tag(prefix: String)
        /// The prefix carries the `/` itself, like the tag one carries its `#`, so the
        /// range to replace is simply its length.
        case slash(prefix: String)
    }

    /// True right after the user typed the trigger, so the list opens without a
    /// keyboard shortcut.
    func shouldOfferCompletion() -> Bool {
        completionContext() != nil
    }

    override var rangeForUserCompletion: NSRange {
        // The default is a word range, which stops at the space inside "Curva di
        // trasmissibilità" and would complete against the last word only.
        guard let context = completionContext() else { return super.rangeForUserCompletion }
        let cursor = selectedRange().location
        let length: Int = switch context {
        case .wikilink(let prefix): prefix.count
        case .tag(let prefix): prefix.count
        case .slash(let prefix): prefix.count
        }
        return NSRange(location: cursor - length, length: length)
    }

    override func completions(
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String]? {
        guard let context = completionContext() else { return nil }
        index?.pointee = 0

        switch context {
        case .wikilink(let prefix):
            // Broken into steps: as one chained expression the type checker gives up.
            var scored: [(title: String, score: Int)] = []
            for title in noteTitles {
                guard let score = FuzzyMatch.score(query: prefix, candidate: title) else { continue }
                scored.append((title, score))
            }
            scored.sort { left, right in
                left.score == right.score ? left.title.count < right.title.count : left.score > right.score
            }
            let matches = scored.prefix(12).map(\.title)
            return matches.isEmpty ? nil : Array(matches)
        case .tag(let prefix):
            let matches = tagSuggestions.filter { $0.hasPrefix(prefix) }.prefix(12)
            return matches.isEmpty ? nil : Array(matches)
        case .slash(let prefix):
            // No cap, unlike the two above. Twelve is right for a list of note titles,
            // where the twelfth is already a bad guess; here the list *is* the catalogue,
            // and M8 exists to make everything the app can do reachable from the caret.
            // Capped at twelve, `/` alone showed the editor entries and hid every app
            // command behind a query you had to know to type. AppKit's list scrolls.
            let matches = EditorCommand
                .matching(String(prefix.dropFirst()), in: editorCommands)
                .map(\.title)
            return matches.isEmpty ? nil : matches
        }
    }

    /// Runs the chosen slash command instead of typing its name into the note.
    ///
    /// AppKit's completion list exists to insert the string it shows, so this is the one
    /// place a command menu can be built on it. Three behaviours worth stating, because
    /// each would be a visible defect if it were the other way round:
    ///
    /// - **Not final**: nothing happens. Arrowing through the list previews a completion
    ///   by inserting it, which for this list would write "Blocco di codice" into the
    ///   note while the user is still choosing.
    /// - **Cancelled**: nothing happens either. Escape has to leave `/cod` exactly as it
    ///   was typed.
    /// - **Chosen**: the `/prefisso` is replaced in one edit, so undo takes the whole
    ///   thing back rather than peeling it a character at a time.
    override func insertCompletion(
        _ word: String,
        forPartialWordRange charRange: NSRange,
        movement: Int,
        isFinal: Bool
    ) {
        guard case .slash = completionContext() else {
            super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: isFinal)
            return
        }
        guard isFinal, movement != NSTextMovement.cancel.rawValue else { return }
        guard let command = editorCommands.first(where: { $0.title == word }) else { return }

        switch command.action {
        case .insert(let text, let cursorBack):
            insertText(text, replacementRange: charRange)
            // Counted in UTF-16, which is what an `NSRange` is measured in: `count` on a
            // String would put the caret in the wrong place the first time a template
            // carries an emoji.
            let end = charRange.location + (text as NSString).length
            setSelectedRange(NSRange(location: max(charRange.location, end - cursorBack), length: 0))
        case .app(let appCommand):
            // The typed `/prefisso` goes first: the command may open a panel or move to
            // another pane, and coming back to find `/oggi` still in the note reads as
            // the menu having failed.
            insertText("", replacementRange: charRange)
            onRunCommand?(appCommand)
        }
    }

    /// Looks backwards from the cursor for a `[[` or `#` trigger on the current line.
    private func completionContext() -> Context? {
        let cursor = selectedRange().location
        guard cursor > 0 else { return nil }

        let text = string as NSString
        guard cursor <= text.length else { return nil }

        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let beforeCursor = text.substring(with: NSRange(
            location: lineRange.location, length: cursor - lineRange.location
        ))

        if let open = beforeCursor.range(of: "[[", options: .backwards) {
            let prefix = String(beforeCursor[open.upperBound...])
            // A closed link is not a completion context any more.
            if !prefix.contains("]]") { return .wikilink(prefix: prefix) }
        }
        if let hash = beforeCursor.range(of: "#", options: .backwards) {
            let prefix = String(beforeCursor[hash.lowerBound...])
            let atLineStart = hash.lowerBound == beforeCursor.startIndex
            // `.last`, not `index(before:)`: a line that begins with `#` has nothing before it.
            let afterSpace = beforeCursor.dropLast(prefix.count).last == " "
            // `# ` opens a heading, not a tag, and a space ends the tag.
            if atLineStart || afterSpace, !prefix.contains(" ") { return .tag(prefix: prefix) }
        }
        // Last, so the two triggers that existed first keep behaving exactly as they did.
        if let slash = beforeCursor.range(of: "/", options: .backwards) {
            let prefix = String(beforeCursor[slash.lowerBound...])
            let atLineStart = slash.lowerBound == beforeCursor.startIndex
            let afterSpace = beforeCursor.dropLast(prefix.count).last == " "
            // The strictness is the whole design. `/` is ordinary in prose and in dates
            // and in URLs, so it opens a menu only where a person would not otherwise be
            // typing one: at the start of a line or after a space. That rules out
            // `24/08/2026` (a digit before it), `http://x` (a slash before it) and `e/o`
            // (a letter before it) without naming any of them, and a space ends the menu.
            if atLineStart || afterSpace, !prefix.contains(" ") { return .slash(prefix: prefix) }
        }
        return nil
    }
}
