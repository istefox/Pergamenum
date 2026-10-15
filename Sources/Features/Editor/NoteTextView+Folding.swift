import AppKit

// The folding pass's own state (ADR-0074 §D2). A file of its own because the pass and its caret
// rescue used to sit in `NoteTextView+Coordinator.swift`, which has no room for them. The
// Coordinator keeps `applyFolding(to:folded:theme:)` as a one-line forward under the name
// `updateNSView` calls (ADR-0074 §D5).

/// The last fold layout applied, so an unchanged fold does not invalidate the layout on every
/// view update, and the folding pass with its caret rescue.
@MainActor
final class FoldController {
    /// Held for ADR-0074 §D3's uniform shape (every controller receives the provider at `init`).
    /// The pass takes `folded` and `theme` as parameters, which `updateNSView` reads and hands down
    /// through `applyFolding`; the one read it makes itself, whether a callout toggle is wired, goes
    /// through it at the moment of use.
    private let parent: () -> NoteTextView?
    private let decorations: EditorDecorationDelegate
    /// The layout record; its door is the one way this pass invalidates the layout (ADR-0093 §D3).
    private let layoutDebt: LayoutDebt

    /// The fold already applied, so an unchanged one does not invalidate the layout on every
    /// view update.
    private(set) var lastFoldLayout = NoteFolding.Layout()
    /// Set when `shift(by:)` changes `lastFoldLayout`, and kept until a pass gets past the
    /// nothing-is-folded guard in `apply`, which reads and clears it.
    private var shiftedSinceApply = false
    /// The folded callouts last read (`CalloutFold.folds`), shifted with `lastFoldLayout`, and spliced
    /// over the dirty range an incremental restyle re-read (`restyled(_:replacing:)`); nil when the next
    /// pass must read them again: nothing read yet, a full restyle of a note holding a header, an edit
    /// reached a folded callout and no restyle spliced it back, or the flips changed. What keeps a
    /// keystroke, inside a callout or away from one, from reading the note (ADR-0096 §D7).
    private var calloutFolds: [(title: Int, lines: [Int])]?
    /// The folded callouts an edit reached, dropped from `calloutFolds` until the incremental restyle
    /// re-reads their run (its dirty range never cuts a quote run, `RestyleScope`); kept, at the offsets
    /// the edits left them, only to tell whether the re-read changed them. Non-nil means a splice is
    /// owed: a pass that finds it still owed reads the callouts whole.
    private var reachedFolds: [(title: Int, lines: [Int])]?
    /// Set when a splice changed the folded callouts, until the next pass applies them.
    private var splicedChange = false
    /// `lastFoldLayout` hides callout bodies and nothing else, so it is `calloutFolds`' lines.
    private var lastFoldIsCallouts = true
    /// Set when an edit moved `decorations.toggledCallouts` away from the tab's copy, until the editor
    /// reports it (`takeMovedFlips()`) or the next pass takes the tab's copy again.
    private var flipsMoved = false
    /// The passes that read the note's text (the callouts or the fold layout), for the update-path tests.
    private(set) var textReads = 0

    init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate, layout: LayoutDebt) {
        self.parent = parent
        self.decorations = decorations
        layoutDebt = layout
    }

    /// Recomputes the fold and makes the layout read it again.
    ///
    /// `edited(.editedAttributes,…)` is what re-runs the content manager's enumeration
    /// without a character changing - the same trick the reveal-on-caret probe used in
    /// the TextKit study. Skipped entirely when nothing is folded and nothing was, or when only
    /// callouts are and no edit since changed which, so an ordinary keystroke pays nothing for this.
    ///
    /// `hidesFrontmatter` leaves the frontmatter block's lines out of the layout through the same
    /// hidden-line set a fold uses, so the text itself is never touched; so do the bodies of the
    /// folded callouts, `toggledCallouts` being the title offsets the tab flipped (ADR-0087 §D8).
    func apply(
        to textView: NSTextView, folded: Set<Int>, hidesFrontmatter: Bool = false,
        toggledCallouts: Set<Int> = [], theme: Theme
    ) {
        // A callout folds only where the person can open it again: the markup is hidden (the chevron
        // is a fragment of the hidden-markup path) and a toggle is wired (the Diario and Oggi editors
        // wire none). Otherwise every callout is open and draws no chevron (ADR-0087 §D8).
        let foldsCallouts = decorations.hidesMarkup && parent()?.outline.onToggleCallout != nil
        // A title's chevron reads the flips, and whether it exists, whether or not anything is hidden.
        let flipsChanged = decorations.toggledCallouts != toggledCallouts
            || decorations.foldsCallouts != foldsCallouts
        decorations.toggledCallouts = toggledCallouts
        decorations.foldsCallouts = foldsCallouts
        flipsMoved = false
        // A splice still owed: an edit reached a folded callout and no incremental restyle re-read it.
        if flipsChanged || !foldsCallouts || reachedFolds != nil { calloutFolds = nil }
        reachedFolds = nil
        let spliced = splicedChange
        splicedChange = false
        // A callout's `-` folds with nothing toggled, so the callouts are read whenever their memo
        // went stale, and only then: a keystroke that reached none, or whose run the restyle spliced
        // back, keeps it (ADR-0096 §D7).
        let readsCallouts = foldsCallouts && calloutFolds == nil
        if readsCallouts {
            textReads += 1
            calloutFolds = CalloutFold.folds(in: textView.string, toggled: toggledCallouts)
        }
        let callouts = foldsCallouts ? calloutFolds ?? [] : []
        // Nothing but callouts is folded, now and at the last pass, and they were neither read again nor
        // changed by a splice: the shifted layout is the one a read would compute, so there is nothing
        // to apply.
        guard readsCallouts || spliced || flipsChanged || !folded.isEmpty || hidesFrontmatter
            || decorations.isFolding || !lastFoldIsCallouts
        else { return }
        // `isFolding` reads folded headings only: a hidden frontmatter block leaves it false, so
        // showing the block again must also look at the layout last applied, or it never reverts.
        guard decorations.isFolding || !folded.isEmpty || hidesFrontmatter || flipsChanged
            || !lastFoldLayout.hiddenLineOffsets.isEmpty || !callouts.isEmpty
        else {
            lastFoldIsCallouts = true
            return
        }
        textReads += 1
        var layout = NoteFolding.layout(in: textView.string, foldedEntries: folded)
        let frontmatter = hidesFrontmatter ? NoteFolding.hiddenFrontmatter(in: textView.string) : nil
        if let frontmatter { layout.hiddenLineOffsets.formUnion(frontmatter.lineOffsets) }
        for callout in callouts { layout.hiddenLineOffsets.formUnion(callout.lines) }
        lastFoldIsCallouts = folded.isEmpty && frontmatter == nil
        let shifted = shiftedSinceApply
        shiftedSinceApply = false
        guard layout != lastFoldLayout || flipsChanged else {
            // A shifted layout equals the new one where an unshifted one would not, and the full
            // restyle re-applies the fold after such an edit, rescuing a caret left in a hidden
            // line. The rescue is the part a person sees, so it runs here too (ADR-0091 §D6).
            if shifted { rescueCaret(in: textView, from: layout, frontmatter: frontmatter, callouts: callouts) }
            return
        }
        lastFoldLayout = layout

        decorations.badgeColor = NSColor(theme.color(.textTertiary))
        decorations.badgeBackground = NSColor(theme.color(.backgroundTertiary))
        decorations.apply(hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings)

        let length = (textView.string as NSString).length
        textView.textContentStorage?.textStorage?.edited(
            .editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0
        )
        layoutDebt.invalidateWholeDocument(of: textView)
        rescueCaret(in: textView, from: layout, frontmatter: frontmatter, callouts: callouts)
    }

    /// Moves the caret out of a section that has just been folded.
    ///
    /// The folded lines are not in the layout, so a caret left inside one is an
    /// insertion point with nowhere to be drawn and nowhere to type. It goes to the
    /// heading that swallowed it, which is where a person would look for it. The rule is
    /// `CaretRescue`'s (ADR-0074 §D8); the owner is the nearest folded heading at or
    /// above the caret, and the caret is placed at once rather than after `endEditing`. A caret
    /// inside a hidden frontmatter block has no heading to go to: it goes to the first line after
    /// the block. A caret in a folded callout's body goes to its title line, unless that line is
    /// itself folded away under a heading.
    private func rescueCaret(
        in textView: NSTextView, from layout: NoteFolding.Layout, frontmatter: NoteFolding.HiddenFrontmatter?,
        callouts: [(title: Int, lines: [Int])]
    ) {
        let selection = textView.selectedRange()
        let heading = CaretRescue.target(
            for: selection, hidden: layout.hiddenLineOffsets, in: textView.string as NSString
        ) { line in
            if let frontmatter, frontmatter.lineOffsets.contains(line) { return frontmatter.firstVisibleOffset }
            if let callout = callouts.first(where: { $0.lines.contains(line) }),
               !layout.hiddenLineOffsets.contains(callout.title) {
                return callout.title
            }
            return layout.foldedHeadings.keys.filter { $0 <= selection.location }.max() ?? 0
        }
        CaretRescue.place(heading, in: textView)
    }
}

extension FoldController {
    /// Moves the last fold layout past `edit` (ADR-0091 §D6), so the folding pass compares the
    /// fold it computes with the one on screen at the offsets they now have. The delegate's copy
    /// moves with `EditorDecorationDelegate.shift(by:)`.
    func shift(by edit: StorageEdit) {
        let unshifted = lastFoldLayout
        lastFoldLayout.hiddenLineOffsets = edit.shiftedKeys(lastFoldLayout.hiddenLineOffsets)
        lastFoldLayout.foldedHeadings = edit.shiftedKeys(lastFoldLayout.foldedHeadings)
        // Only a shift that moved the layout: an unmoved one is what the full path compares
        // against too, and it rescues nothing then.
        if lastFoldLayout != unshifted { shiftedSinceApply = true }
        shiftCallouts(by: edit)
    }

    /// The full restyle's word that it styled the whole note: a note holding a header is read again, and
    /// so is one an edit reached a folded callout in, even when that edit took the last header out, or
    /// the memo (now without that callout) would keep the layout still hiding its body.
    func restyled(_ text: String) {
        if calloutFolds != nil, reachedFolds != nil || text.contains("[!") { calloutFolds = nil }
        reachedFolds = nil
    }

    /// The incremental restyle's word that it re-read `fragment`, the note's text over `dirty`. The
    /// restyle scope widens a range over every quote run it touches or adjoins and never cuts one
    /// (`RestyleScope`), so every callout an edit reached, or made, lies whole inside `dirty`: its folds
    /// are read from the fragment alone and spliced over the ones the memo held there. A keystroke
    /// inside a callout reads the run it typed in, never the note (ADR-0096 §D7).
    func restyled(_ fragment: String, replacing dirty: NSRange) {
        guard let folds = calloutFolds else { return }
        let end = NSMaxRange(dirty)
        let inside = { (offset: Int) in offset >= dirty.location && offset < end }
        let toggled = Set(decorations.toggledCallouts.filter(inside).map { $0 - dirty.location })
        let fresh = CalloutFold.folds(
            in: fragment, toggled: toggled, readsFrontmatter: dirty.location == 0
        ).map { fold in (title: fold.title + dirty.location, lines: fold.lines.map { $0 + dirty.location }) }
        let replaced = folds.filter { inside($0.title) } + (reachedFolds ?? [])
        let kept = folds.filter { !inside($0.title) }
        reachedFolds = nil
        guard !(fresh.isEmpty && replaced.isEmpty) else { return }
        calloutFolds = (kept + fresh).sorted { $0.title < $1.title }
        // Compared as title-then-lines arrays, tuples being no `Equatable`.
        let key = { (folds: [(title: Int, lines: [Int])]) in
            folds.map { [$0.title] + $0.lines }.sorted { $0[0] < $1[0] }
        }
        if key(fresh) != key(replaced) { splicedChange = true }
    }

    /// Moves the flipped callouts and the folded ones past `edit`. The flips are the tab's title offsets
    /// (`NoteTab.toggledCallouts`) and move the way every offset-keyed holder does (ADR-0091 §D6), so
    /// typing above a flipped callout leaves it flipped; the ones that moved wait in `takeMovedFlips()`
    /// for the tab. A folded callout the edit reached (title through last body line, either end
    /// touching) leaves the memo for `reachedFolds`, until the restyle splices its run back.
    private func shiftCallouts(by edit: StorageEdit) {
        shiftFlips(by: edit)
        let shift = { (fold: (title: Int, lines: [Int])) in
            (title: edit.shifted(fold.title), lines: fold.lines.map { edit.shifted($0) })
        }
        reachedFolds = reachedFolds?.map(shift)
        guard let folds = calloutFolds else { return }
        let old = edit.oldRange
        let reaches = { (fold: (title: Int, lines: [Int])) in
            old.location <= (fold.lines.last ?? fold.title) && NSMaxRange(old) >= fold.title
        }
        let reached = folds.filter(reaches)
        if !reached.isEmpty { reachedFolds = (reachedFolds ?? []) + reached.map(shift) }
        calloutFolds = folds.filter { !reaches($0) }.map(shift)
    }

    /// Moves the flipped callouts alone past `edit`. The kill switch calls it too: a full restyle
    /// rebuilds the styling, never the tab's flips, so without it an edit above a flipped callout would
    /// leave the tab holding an offset that is no longer its title.
    func shiftFlips(by edit: StorageEdit) {
        let flips = decorations.toggledCallouts
        guard !flips.isEmpty else { return }
        let moved = edit.shiftedKeys(flips)
        guard moved != flips else { return }
        decorations.toggledCallouts = moved
        flipsMoved = true
    }

    /// The folded callouts memo as comparable values, each a title followed by its body lines (tuples
    /// are no `Equatable`); nil while no memo is held. For `DerivedStateSnapshot` (ADR-0091 §D6).
    var calloutFoldKeys: [[Int]]? {
        calloutFolds?.map { [$0.title] + $0.lines }
    }

    /// The flipped callouts' offsets after the edits since the last report, once, for the tab to keep
    /// (`NoteTab.toggledCallouts`): nil when no edit moved one.
    func takeMovedFlips() -> Set<Int>? {
        guard flipsMoved else { return nil }
        flipsMoved = false
        return decorations.toggledCallouts
    }
}
