import AppKit
@testable import Pergamenum

// ADR-0082 §D5/§D7 and ADR-0081, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385).
//
// One hosted editor shared by the restyle budget, the grow-to-fit tests and the gutter tests: a
// `NoteTextView` coordinator wired the way `NoteTextView.makeNSView` wires it - delegate, undo,
// both decoration delegates, `wire(_:to:)` - on a `CompletingTextView(usingTextLayoutManager:)`
// inside an `NSScrollView` in an offscreen `NSWindow` that is never ordered front. It mirrors
// `EditorHeightTests`' window shape and adds what that fixture lacks: `textView.delegate`, so a
// keystroke reaches `shouldChangeText` and `textDidChange` the way it does in the app.

@MainActor
struct ScrolledEditorFixture {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let scrollView: NSScrollView
    let window: NSWindow

    init(
        text: String, width: CGFloat = 900, height: CGFloat = 700,
        hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency,
        queries: ViewQuerySource? = nil,
        vault: NoteTextView.VaultInputs? = nil, revealsInlineSpans: Bool = false,
        forcesFullRestyle: Bool? = false
    ) {
        let view = NoteTextView(
            text: .constant(text), theme: theme, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, revealsInlineSpans: revealsInlineSpans, readableWidth: readableWidth,
            onFollowLink: { _ in }, vault: vault ?? .init(transclusions: nil, queries: queries)
        )
        let coordinator = view.makeCoordinator()
        // Before the first styling and `openLikeTheApp()`, so a twin never takes the incremental
        // path for even one edit (ADR-0091 §D8, per-paragraph-restyle plan Task 3). Nil leaves what
        // the coordinator read from `EditorRestyleSwitch` at `init`, as a host that sets nothing does.
        if let forcesFullRestyle { coordinator.forcesFullRestyle = forcesFullRestyle }
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(
            width: NoteTextView.Coordinator.minimumHorizontalInset,
            height: NoteTextView.Coordinator.verticalInset
        )
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [:]
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.wire(textView, to: coordinator)

        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        coordinator.textView = textView

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = scrollView
        window.layoutIfNeeded()

        coordinator.applyReadableWidth(to: textView)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        // Assigning `.string` posts no `textDidChange` and registers no undo action, so the text
        // is in place before anything the delegate does can see it.
        textView.string = text
        coordinator.applyStyling(to: textView, theme: theme)
        window.makeFirstResponder(textView)

        self.textView = textView
        self.coordinator = coordinator
        self.scrollView = scrollView
        self.window = window
    }

    /// The state the app's text view is in by the time a person types: the note open and the
    /// passes through, whose last step is `growToFitTheText`. That step sizes the frame to what
    /// TextKit reports, and the app runs it on every update, so by a keystroke the frame is as tall
    /// as the note and has stopped moving. Here it is run until the height settles (at most five
    /// times), so a keystroke meets a frame already as tall as the note, not the 700 pt this
    /// fixture was built with (`(n2-page R-17)`).
    func openLikeTheApp() {
        var previous = textView.frame.height
        for _ in 0..<5 {
            coordinator.growToFitTheText(textView)
            if abs(textView.frame.height - previous) <= 0.5 { break }
            previous = textView.frame.height
        }
    }

    /// A keystroke: the selection set at `location`, then `insertText(_:replacementRange:)` over
    /// it, so `shouldChangeText` and `textDidChange` run as they do for a key.
    func type(_ string: String, at location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

// MARK: - Per-paragraph restyle: the passes, the edits, and the twin
//
// ADR-0091 §D6 to §D8, plan docs/plans/per-paragraph-restyle.md, Task 3.
//
// A twin is a second fixture with `forcesFullRestyle = true`, fed the same edits through the same
// entry points. The full restyle is what the editor did before the incremental path existed, so it
// is the oracle: nothing here re-derives what the attributes should be.

extension ScrolledEditorFixture {
    /// What `updateNSView` does after a text sync: the passes, in the app's order. A keystroke
    /// reaches `textDidChange` first and this second, as it does in the app.
    func runPasses() {
        coordinator.parent.runPasses(on: textView, coordinator: coordinator)
    }

    /// The fold the model would hold for `heading`: the index of that heading among the outline's
    /// entries in the text as it is now (`NoteFolding` reads `foldedEntries` as outline indices), or
    /// nothing when the heading is no longer there.
    func fold(heading: String?) {
        guard let heading else { return }
        let text = textView.string
        let entries = NoteOutline.entries(in: text)
        let index = entries.firstIndex { text[$0.range.lowerBound...].hasPrefix(heading) }
        coordinator.parent.outline.foldedEntries = index.map { [$0] } ?? []
    }

    /// An edit the way a paste or a programmatic change makes it: `shouldChangeText`, the storage
    /// replacement, `didChangeText`; then the caret after the new text.
    func replace(_ range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }

    /// A keystroke that overwrites `range`, through the same `insertText` a key uses.
    func type(_ string: String, over range: NSRange) {
        textView.insertText(string, replacementRange: range)
    }

    var undoManager: UndoManager? { textView.undoManager }
}

/// The attribute runs of a storage, with what cannot be compared by `isEqual` named instead:
/// an attachment is its class, not its object.
@MainActor
enum StorageComparison {
    private static func normalised(_ attributes: [NSAttributedString.Key: Any]) -> NSDictionary {
        let result = NSMutableDictionary()
        for (key, value) in attributes {
            if key == .attachment, let attachment = value as? NSTextAttachment {
                result[key] = "attachment:\(type(of: attachment))"
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func runs(_ storage: NSTextStorage) -> [(range: NSRange, attributes: NSDictionary)] {
        var found: [(range: NSRange, attributes: NSDictionary)] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attributes, range, _ in
            found.append((range, normalised(attributes)))
        }
        return found
    }

    /// The first difference between two storages, or nil when their text and their attributes agree
    /// run by run.
    static func firstDifference(_ left: NSTextStorage, _ right: NSTextStorage) -> String? {
        guard left.string == right.string else { return "text differs" }
        let a = runs(left)
        let b = runs(right)
        for index in 0..<min(a.count, b.count) {
            if a[index].range != b[index].range {
                return "run \(index): \(a[index].range) against \(b[index].range)"
            }
            if !a[index].attributes.isEqual(b[index].attributes) {
                var differing: Set<String> = []
                for key in a[index].attributes.allKeys + b[index].attributes.allKeys {
                    let x = a[index].attributes.object(forKey: key) as? NSObject
                    let y = b[index].attributes.object(forKey: key) as? NSObject
                    if x != y { differing.insert("\(key)") }
                }
                return "run \(index) at \(a[index].range): attributes differ in \(differing.sorted())"
            }
        }
        return a.count == b.count ? nil : "\(a.count) runs against \(b.count)"
    }
}

/// The note the twin tests edit: prose above, and below it everything the editor derives an offset
/// from. Every edit lands in the prose, so everything below moves and has to be found again.
enum RichNote {
    static let heading = "# Titolo\n\n"
    /// Where the random edits land: prose, a list, and a paragraph of inline markup. Nothing in it
    /// can open a fence, a table or a link by itself.
    static let zone = "Intro con *enfasi* e `codice` in prosa.\n\n1. uno\n2. due\n3. tre\n\nSecondo paragrafo di prosa.\n"
    static let tail = """

    ## Sezione piegata

    Testo nascosto dalla piega.

    ## Tabella

    | a | b |
    |---|---|
    | 1 | 2 |

    ![[foto.png]]

    ![[Prove]]

    ```pergamenum-view
    render: list
    ```

    - uno
      - due

    Coda con **forte**.

    """
    static let text = heading + zone + tail
    static let foldedHeading = "## Sezione piegata"
    static let transclusionLine = "![[Prove]]"

    /// The first offset of the derived blocks: the zone ends two characters before it, so an edit
    /// can never join the zone to the heading.
    static func zoneEnd(in text: String) -> Int {
        let found = (text as NSString).range(of: foldedHeading)
        return found.location == NSNotFound ? 0 : max(0, found.location - 2)
    }

    static func transclusions() -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                // Any target that starts with "Prove" resolves, so a letter typed inside the target of
                // the transclusion line names another note that exists, and one that does not start
                // with it names none.
                guard reference.hasPrefix("Prove") else { return nil }
                return TransclusionSource.Resolved(
                    title: reference, relativePath: "\(reference).md", text: "# \(reference)\n\nTre serie di misure.\n"
                )
            },
            generation: 1
        )
    }

    private struct EmptyCorpus: ViewCorpus {
        var records: [NoteRecord] { [] }
        func paths(forTitle title: String) -> [String] { [] }
    }

    /// A query source with no rows: enough for a fence to be drawn as a view block.
    @MainActor static func queries() -> ViewQuerySource {
        ViewQuerySource(
            evaluate: { block in ViewEvaluator.evaluate(block, over: EmptyCorpus(), today: CalendarDate(iso: "2026-10-11")!) },
            generation: 1
        )
    }
}

@MainActor
struct RestyleTwin {
    let incremental: ScrolledEditorFixture
    let full: ScrolledEditorFixture
    let foldedHeading: String?
    /// The vault root of a rich twin, removed by `tearDown()`.
    let root: URL?

    init(incremental: ScrolledEditorFixture, full: ScrolledEditorFixture, foldedHeading: String? = nil, root: URL? = nil) {
        self.incremental = incremental
        self.full = full
        self.foldedHeading = foldedHeading
        self.root = root
        for fixture in [incremental, full] {
            // One undo step per call below, whatever the run loop does between them.
            fixture.undoManager?.groupsByEvent = false
        }
    }

    /// Two plain editors on `text`, with no vault behind them.
    static func plain(
        _ text: String, hidesMarkup: Bool = true, revealsInlineSpans: Bool = false
    ) -> RestyleTwin {
        RestyleTwin(
            incremental: ScrolledEditorFixture(
                text: text, hidesMarkup: hidesMarkup, revealsInlineSpans: revealsInlineSpans
            ),
            full: ScrolledEditorFixture(
                text: text, hidesMarkup: hidesMarkup, revealsInlineSpans: revealsInlineSpans, forcesFullRestyle: true
            )
        )
    }

    /// Two editors on the rich note: a table, a view block, an embed, a transclusion, a fold, hidden
    /// markers and the spell checker's skipped ranges, all below the prose the tests edit. The
    /// picture is rendered before this returns, so its rendition is part of the state from the start.
    static func rich(text: String = RichNote.text) async throws -> RestyleTwin {
        let root = try EmbedEditorFixtures.makeTempVaultRoot(prefix: "pergamenum-restyle-")
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        func editor(forcing: Bool) -> ScrolledEditorFixture {
            let thumbnails = ThumbnailStore(
                root: root, directory: root.appending(path: forcing ? "cache-full" : "cache-incremental", directoryHint: .isDirectory)
            )
            return ScrolledEditorFixture(
                text: text,
                vault: .init(
                    vaultRoot: root, notePath: "Nota.md", thumbnails: thumbnails,
                    transclusions: RichNote.transclusions(), queries: RichNote.queries()
                ),
                revealsInlineSpans: true, forcesFullRestyle: forcing
            )
        }
        let twin = RestyleTwin(
            incremental: editor(forcing: false), full: editor(forcing: true),
            foldedHeading: RichNote.foldedHeading, root: root
        )
        twin.both { $0.fold(heading: RichNote.foldedHeading); $0.runPasses() }
        for _ in 0..<100 {
            if twin.both({ $0.coordinator.embeds.renditions }).allSatisfy({ !$0.isEmpty }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        twin.both { $0.runPasses() }
        return twin
    }

    func tearDown() {
        incremental.window.orderOut(nil)
        full.window.orderOut(nil)
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    @discardableResult
    func both<T>(_ body: (ScrolledEditorFixture) -> T) -> [T] {
        [body(incremental), body(full)]
    }

    /// Any change to both editors, inside one undo group (the managers have `groupsByEvent` off, so a
    /// change outside a group would register its undo with none open), then the passes.
    func edit(_ body: (ScrolledEditorFixture) -> Void) {
        both { fixture in
            fixture.undoManager?.beginUndoGrouping()
            body(fixture)
            fixture.undoManager?.endUndoGrouping()
            fixture.fold(heading: foldedHeading)
            fixture.runPasses()
        }
    }

    func type(_ string: String, at location: Int) { edit { $0.type(string, at: location) } }
    func type(_ string: String, over range: NSRange) { edit { $0.type(string, over: range) } }
    func replace(_ range: NSRange, with replacement: String) { edit { $0.replace(range, with: replacement) } }

    var canUndo: Bool { incremental.undoManager?.canUndo ?? false }
    var canRedo: Bool { incremental.undoManager?.canRedo ?? false }

    func undo() {
        both { fixture in
            fixture.undoManager?.undo()
            fixture.fold(heading: foldedHeading)
            fixture.runPasses()
        }
    }

    func redo() {
        both { fixture in
            fixture.undoManager?.redo()
            fixture.fold(heading: foldedHeading)
            fixture.runPasses()
        }
    }

    // MARK: Comparison

    /// What differs between the two editors, as readable lines; empty when they are equal. Text,
    /// selection, attributes run by run, and every field of the derived-state snapshot.
    func differences() -> [String] {
        var found: [String] = []
        if incremental.textView.string != full.textView.string { found.append("text") }
        if incremental.textView.selectedRange() != full.textView.selectedRange() {
            found.append("selection \(incremental.textView.selectedRange()) against \(full.textView.selectedRange())")
        }
        if let storages = incremental.textView.textStorage.flatMap({ left in full.textView.textStorage.map { (left, $0) } }),
           let difference = StorageComparison.firstDifference(storages.0, storages.1) {
            found.append("attributes: \(difference)")
        }
        found.append(contentsOf: Self.snapshotDifferences(
            incremental.coordinator.derivedStateSnapshot(), full.coordinator.derivedStateSnapshot()
        ))
        return found
    }

    static func snapshotDifferences(_ left: DerivedStateSnapshot, _ right: DerivedStateSnapshot) -> [String] {
        var found: [String] = []
        func check<T: Equatable>(_ name: String, _ a: T, _ b: T) {
            if a != b { found.append("\(name): \(a) against \(b)") }
        }
        check("decorations", left.decorations, right.decorations)
        check("unspellable", left.unspellable, right.unspellable)
        check("embedRuns", left.embedRuns, right.embedRuns)
        check("tablesDrawn", left.tablesDrawn, right.tablesDrawn)
        check("tableHiddenRows", left.tableHiddenRows, right.tableHiddenRows)
        check("viewBlocksDrawn", left.viewBlocksDrawn, right.viewBlocksDrawn)
        check("viewBlockHiddenLines", left.viewBlockHiddenLines, right.viewBlockHiddenLines)
        check("embedRenditions", left.embedRenditions, right.embedRenditions)
        check("transclusionRenditions", left.transclusionRenditions, right.transclusionRenditions)
        check("foldLayout", left.foldLayout, right.foldLayout)
        check("revealed", left.revealed, right.revealed)
        check("revealedSpans", left.revealedSpans, right.revealedSpans)
        return found
    }

    /// The fields of a snapshot that hold nothing. A comparison on a fixture where one is empty
    /// compares nothing there, so the tests fail on it instead of passing.
    static func emptyFields(of snapshot: DerivedStateSnapshot) -> [String] {
        var empty: [String] = []
        if snapshot.decorations.hiddenMarkerKeys.isEmpty { empty.append("decorations.hiddenMarkerKeys") }
        if snapshot.decorations.hiddenLineOffsets.isEmpty { empty.append("decorations.hiddenLineOffsets") }
        if snapshot.decorations.foldedHeadings.isEmpty { empty.append("decorations.foldedHeadings") }
        if snapshot.decorations.tableRowOffsets.isEmpty { empty.append("decorations.tableRowOffsets") }
        if snapshot.decorations.viewBlockLineOffsets.isEmpty { empty.append("decorations.viewBlockLineOffsets") }
        if snapshot.decorations.renditionKeys.isEmpty { empty.append("decorations.renditionKeys") }
        if snapshot.decorations.embedRenditionKeys.isEmpty { empty.append("decorations.embedRenditionKeys") }
        if snapshot.decorations.tableViewKeys.isEmpty { empty.append("decorations.tableViewKeys") }
        if snapshot.decorations.viewBlockHostKeys.isEmpty { empty.append("decorations.viewBlockHostKeys") }
        if snapshot.unspellable.isEmpty { empty.append("unspellable") }
        if snapshot.embedRuns.isEmpty { empty.append("embedRuns") }
        if snapshot.tablesDrawn.isEmpty { empty.append("tablesDrawn") }
        if snapshot.tableHiddenRows.isEmpty { empty.append("tableHiddenRows") }
        if snapshot.viewBlocksDrawn.isEmpty { empty.append("viewBlocksDrawn") }
        if snapshot.viewBlockHiddenLines.isEmpty { empty.append("viewBlockHiddenLines") }
        if snapshot.embedRenditions.isEmpty { empty.append("embedRenditions") }
        if snapshot.transclusionRenditions.isEmpty { empty.append("transclusionRenditions") }
        if snapshot.foldLayout.hiddenLineOffsets.isEmpty { empty.append("foldLayout.hiddenLineOffsets") }
        if snapshot.revealed.isEmpty { empty.append("revealed") }
        return empty
    }
}
