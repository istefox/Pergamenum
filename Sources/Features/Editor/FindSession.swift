import Foundation
import Observation

/// What the find bar is currently asking, and what came back (SPEC §10, M8).
///
/// Owned by `VaultBrowser` and handed to the bar and to the text view, so the three agree on
/// one search rather than each keeping its own. The note's text is not held here: it lives
/// in `VaultController`, and a second copy would be a second thing to keep in step. It
/// arrives as an argument to `update(in:)` instead, which the browser calls whenever the
/// query, an option or the note itself changes.
///
/// Recomputing the whole note on every keystroke is what `MarkdownStyler.spans` already does
/// on the same events, so this needs no cleverness and gets none.
@MainActor
@Observable
final class FindSession {
    /// Whether the bar is on screen at all, and whether it shows its second row.
    private(set) var isOpen = false
    private(set) var showsReplace = false

    var query = "" { didSet { if query != oldValue { current = 0 } } }
    var replacement = ""
    var isRegex = false { didSet { if isRegex != oldValue { current = 0 } } }
    var isCaseSensitive = false { didSet { if isCaseSensitive != oldValue { current = 0 } } }

    /// The selection the bar was opened over, or nil for the whole note. Captured once, when
    /// the bar opens, which is what AppKit's own bar did: a scope that followed the caret
    /// would shrink to nothing the moment the search moved the selection to a match.
    private(set) var scope: NSRange?

    private(set) var result: NoteFind.Result = .idle
    /// Which match the stepper is on. An index and not a range, so it survives the text
    /// changing underneath it - clamped rather than reset, below.
    private(set) var current = 0

    /// Bumped to put the caret in the find field. The same shape `ComposerTextField` and
    /// `NoteTextView` already use for focus.
    private(set) var focusRequest = 0

    var matches: [NSRange] { result.ranges }

    /// The match the stepper is on, or nil when there is none to be on.
    var currentMatch: NSRange? {
        guard matches.indices.contains(current) else { return nil }
        return matches[current]
    }

    /// What goes in the corner where the count lives: a number, or the reason there is none.
    ///
    /// One property because it is one line on screen and the three states are mutually
    /// exclusive. Nil means the field is empty and nothing should be said at all - an empty
    /// field is not a search that found nothing.
    var tally: String? {
        switch result {
        case .idle: nil
        case .invalidPattern: "pattern incompleto"
        case let .matches(ranges):
            ranges.isEmpty ? "nessuna corrispondenza" : "\(current + 1) di \(ranges.count)"
        }
    }

    /// Whether the tally is a count or a reason, which is what colours it.
    var tallyIsPlain: Bool {
        if case let .matches(ranges) = result { return !ranges.isEmpty }
        return false
    }

    var currentQuery: NoteFind.Query {
        NoteFind.Query(text: query, isRegex: isRegex, isCaseSensitive: isCaseSensitive)
    }

    // MARK: Opening and closing

    /// Opens the bar over `selection`, or widens an open one to show the replace row.
    ///
    /// Reopening does not clear the query: Cmd+F with a search already running is how a
    /// person comes back to it, and an emptied field would be a search thrown away.
    func open(replacing: Bool, over selection: NSRange?, in text: String) {
        // A caret is not a scope. Selecting nothing and pressing Cmd+F means the note.
        scope = (selection?.length ?? 0) > 1 ? selection : nil
        isOpen = true
        showsReplace = showsReplace || replacing
        focusRequest += 1
        update(in: text)
    }

    func close() {
        isOpen = false
        showsReplace = false
        result = .idle
        current = 0
        scope = nil
    }

    // MARK: The search

    func update(in text: String) {
        guard isOpen else { return }
        result = NoteFind.run(currentQuery, in: text, within: scope)
        // Clamped, never reset: an edit that removes the last match should leave the stepper
        // on the new last one, not send it back to the top of the note.
        current = min(current, max(matches.count - 1, 0))
    }

    /// Moves the stepper, wrapping at both ends - which is what AppKit's bar did, and what
    /// makes the count honest: «12 di 12» followed by «1 di 12» says the search went round.
    func step(by offset: Int) {
        guard !matches.isEmpty else { return }
        current = (current + offset + matches.count) % matches.count
    }

    /// Every replacement replace-all is about to make, **last match first**.
    ///
    /// The order is the whole of why this is a method and not a loop at the call site:
    /// applied from the top, the first replacement moves every range after it and the second
    /// one lands in the wrong place. From the bottom, nothing an earlier range depends on
    /// has moved yet.
    func replacements(in text: String) -> [(range: NSRange, text: String)] {
        matches.reversed().map { range in
            (range, NoteFind.replacement(
                for: currentQuery, matching: range, in: text, template: replacement
            ))
        }
    }
}
