import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0082 §D5/§D7 and ADR-0081, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385).
//
// One hosted editor shared by the restyle budget, the grow-to-fit tests and the gutter tests: a
// `NoteTextView` coordinator wired the way `NoteTextView.makeNSView` wires it - delegate, undo,
// both decoration delegates, `wire(_:to:)` - on a `CompletingTextView(usingTextLayoutManager:)`
// inside an `NSScrollView` in an offscreen `NSWindow` that is never ordered front. It mirrors
// `EditorHeightTests`' window shape and adds what that fixture lacks: `textView.delegate`, so a
// keystroke reaches `shouldChangeText` and `textDidChange` the way it does in the app.

/// A binding that remembers what was written to it, for a test that has to see the app's own binding
/// write (`textDidChange`'s `parent.text = …`). `.constant` swallows it, so nothing could tell a
/// keystroke that reached `textDidChange` from one that did not (ADR-0093 §D7, plan Task 1).
@MainActor
final class BoundText {
    private(set) var value: String
    /// How many times the binding was written, whatever the value.
    private(set) var writes = 0

    init(_ value: String) { self.value = value }

    var binding: Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { self.value } },
            set: { newValue in MainActor.assumeIsolated { self.value = newValue; self.writes += 1 } }
        )
    }
}

@MainActor
struct ScrolledEditorFixture {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let scrollView: NSScrollView
    let window: NSWindow
    /// The recording binding the editor was built over, when the test asked for one.
    let bound: BoundText?

    init(
        text: String, width: CGFloat = 900, height: CGFloat = 700,
        hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency,
        queries: ViewQuerySource? = nil,
        vault: NoteTextView.VaultInputs? = nil, revealsInlineSpans: Bool = false,
        forcesFullRestyle: Bool? = false, forcesFullLayout: Bool? = false,
        bound: BoundText? = nil
    ) {
        let view = NoteTextView(
            text: bound?.binding ?? .constant(text), theme: theme, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, revealsInlineSpans: revealsInlineSpans, readableWidth: readableWidth,
            onFollowLink: { _ in }, vault: vault ?? .init(transclusions: nil, queries: queries)
        )
        let coordinator = view.makeCoordinator()
        // Before the first styling and `openLikeTheApp()`, so a twin never takes the incremental
        // path for even one edit (ADR-0091 §D8, per-paragraph-restyle plan Task 3). Nil leaves what
        // the coordinator read from `EditorRestyleSwitch` at `init`, as a host that sets nothing does.
        if let forcesFullRestyle { coordinator.forcesFullRestyle = forcesFullRestyle }
        // The same for the layout switch (ADR-0093 §D6): off unless the test asks, whatever the
        // process was launched with. Nil leaves what the coordinator read at `init`.
        if let forcesFullLayout { coordinator.forcesFullLayout = forcesFullLayout }
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
        // The one line `pushInputs` runs in the app (`NoteTextView+Update.swift:14`): the window's
        // undo manager, which is what `textView.undoManager` resolves to once the view is in the window.
        coordinator.undoManager = textView.undoManager

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
        self.bound = bound
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

    /// The fold the model would hold for `heading`: that heading's UTF-16 offset in the text as it is
    /// now (the key `NoteTab.foldedEntries` keeps), or nothing when the heading is no longer there.
    ///
    /// Restated for ADR-0096 §D7 (PG-406, plan Task 4): this wrote the heading's ordinal into
    /// `outline.foldedEntries`, which the input no longer carries; the coordinator turns the offset into
    /// an ordinal itself. Which heading is folded, and when, is as it was.
    func fold(heading: String?) {
        guard let heading else { return }
        let text = textView.string
        let entries = NoteOutline.entries(in: text)
        let offset = entries.first { text[$0.range.lowerBound...].hasPrefix(heading) }
            .map { text.utf16.distance(from: text.startIndex, to: $0.range.lowerBound) }
        coordinator.parent.outline.foldedOffsets = offset.map { [$0] } ?? []
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
    ///
    /// `bindsIncremental` gives the incremental editor a recording binding (`BoundText`), which is what
    /// `realEdit`, `realUndo` and `realRedo` read to decide whether SwiftUI would have run an update
    /// (ADR-0093 §D7). The default keeps every existing caller on `.constant`.
    static func rich(text: String = RichNote.text, bindsIncremental: Bool = false) async throws -> RestyleTwin {
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
                revealsInlineSpans: true, forcesFullRestyle: forcing,
                bound: bindsIncremental && !forcing ? BoundText(text) : nil
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
        // N5 Realignment 4: the folded-callouts memo is offset-keyed and shifted, so it is compared too
        // (the flips ride in `decorations`).
        check("calloutFolds", left.calloutFolds, right.calloutFolds)
        check("revealed", left.revealed, right.revealed)
        check("revealedSpans", left.revealedSpans, right.revealedSpans)
        // ADR-0096 §D6 (plan Task 4): the outline the coordinator's store keeps is derived state too, and
        // the full-restyle twin rebuilds it after every edit, so it is the oracle.
        check("outline", left.outline, right.outline)
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
        if snapshot.outline.isEmpty { empty.append("outline") }
        return empty
    }
}

// MARK: - The real edit path (ADR-0093 §D7, R-03, R-04)
//
// `edit`, `undo` and `redo` above call the update pass by hand after every operation, which hides an
// operation that never reaches `textDidChange`: the hand call styles what the notification would have.
// These three do the same for the full twin (the oracle) and give the incremental editor only what
// SwiftUI would run: nothing, unless the operation wrote the binding (`textDidChange`'s
// `parent.text = …`), and then the `updateNSView` that write schedules.

/// R-04's probe: one printed line per operation, the fields the ADR records.
enum RealEditProbe {
    static func line(op: String, didChange: Bool, undoNotice: Bool, storageEdits: Int, styled: String) -> String {
        "real-edit-path op=\(op) did_change=\(didChange ? 1 : 0) undo_notice=\(undoNotice ? 1 : 0) "
            + "storage_edits=\(storageEdits) styled=\(styled)"
    }
}

/// What an operation did to the incremental editor before any pass ran, and what the probe saw.
struct RealEditOutcome {
    /// `NSText.didChangeNotification` posted by the incremental text view.
    var didChange: Bool
    /// The undo manager's did-undo or did-redo notification.
    var undoNotice: Bool
    /// Character edits the storage reported (`didProcessEditingNotification` with `.editedCharacters`).
    var storageEdits: Int
    /// `incremental`, `full`, `skipped` or `none`: which counter of the restyle log moved.
    var styled: String
    /// The binding was written, so SwiftUI would have run an update, and `ran` did.
    var wroteBinding: Bool
    // The state before any pass, which is where R-03 starts.
    var boundValue: String?
    var text: String
    var hasUnstyledEdits: Bool

    func line(op: String) -> String {
        RealEditProbe.line(op: op, didChange: didChange, undoNotice: undoNotice, storageEdits: storageEdits, styled: styled)
    }
}

/// Counts what one editor posts while an operation runs. Notifications are delivered synchronously
/// on the posting thread (no queue), which is the main thread here.
@MainActor
private final class RealEditObserver {
    private final class Counts: @unchecked Sendable {
        var didChange = 0
        var undo = 0
        var edits = 0
    }

    private let counts = Counts()
    private var tokens: [NSObjectProtocol] = []

    init(_ fixture: ScrolledEditorFixture) {
        let center = NotificationCenter.default
        let counts = counts
        tokens.append(center.addObserver(forName: NSText.didChangeNotification, object: fixture.textView, queue: nil) { _ in
            counts.didChange += 1
        })
        // A notification, not a delegate: the storage's delegate slot is the coordinator's.
        tokens.append(center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: fixture.textView.textStorage, queue: nil) { note in
            if let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) { counts.edits += 1 }
        })
        for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
            tokens.append(center.addObserver(forName: name, object: fixture.undoManager, queue: nil) { _ in
                counts.undo += 1
            })
        }
    }

    func finish() -> (didChange: Bool, undoNotice: Bool, edits: Int) {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        return (counts.didChange > 0, counts.undo > 0, counts.edits)
    }
}

extension RestyleTwin {
    /// The incremental editor's side of a real operation: observed, then given the one pass SwiftUI
    /// would run if the binding moved.
    private func observeIncremental(_ operation: () -> Void) -> RealEditOutcome {
        let editor = incremental
        let observer = RealEditObserver(editor)
        let logBefore = editor.coordinator.restyleLog
        let writesBefore = editor.bound?.writes ?? 0
        operation()
        let logAfter = editor.coordinator.restyleLog
        let seen = observer.finish()
        if editor.bound == nil { Issue.record("realEdit, realUndo and realRedo need `rich(bindsIncremental: true)`") }
        let wrote = editor.bound.map { $0.writes > writesBefore } ?? true
        let styled: String
        if logAfter.full > logBefore.full { styled = "full" }
        else if logAfter.incremental > logBefore.incremental { styled = "incremental" }
        else if logAfter.skipped > logBefore.skipped { styled = "skipped" }
        else { styled = "none" }
        let outcome = RealEditOutcome(
            didChange: seen.didChange, undoNotice: seen.undoNotice, storageEdits: seen.edits, styled: styled,
            wroteBinding: wrote, boundValue: editor.bound?.value, text: editor.textView.string,
            hasUnstyledEdits: editor.coordinator.hasUnstyledEdits
        )
        if wrote {
            editor.fold(heading: foldedHeading)
            editor.runPasses()
        }
        return outcome
    }

    /// Any change, given to the full twin with the passes by hand (the oracle) and to the incremental
    /// editor with nothing but what SwiftUI would run. One undo group per call, as `edit`.
    @discardableResult
    func realEdit(_ body: (ScrolledEditorFixture) -> Void) -> RealEditOutcome {
        full.undoManager?.beginUndoGrouping()
        body(full)
        full.undoManager?.endUndoGrouping()
        full.fold(heading: foldedHeading)
        full.runPasses()
        return observeIncremental {
            incremental.undoManager?.beginUndoGrouping()
            body(incremental)
            incremental.undoManager?.endUndoGrouping()
        }
    }

    /// The undo manager's `undo()`, as Cmd+Z reaches it.
    @discardableResult
    func realUndo() -> RealEditOutcome {
        full.undoManager?.undo()
        full.fold(heading: foldedHeading)
        full.runPasses()
        return observeIncremental { incremental.undoManager?.undo() }
    }

    /// The undo manager's `redo()`, as Cmd+Shift+Z reaches it.
    @discardableResult
    func realRedo() -> RealEditOutcome {
        full.undoManager?.redo()
        full.fold(heading: foldedHeading)
        full.runPasses()
        return observeIncremental { incremental.undoManager?.redo() }
    }
}

// MARK: - The layout witness (ADR-0093 §D4)

extension ScrolledEditorFixture {
    /// What an estimate would move: the usage height of the text container, and where the last
    /// laid-out fragment starts. A fragment-counting probe cannot see reuse (TextKit requests no
    /// fragment for a layout it kept); these two numbers can, since an estimate is exactly a height
    /// that changes when the rest of the document is laid out (`EditorGrowToFitScopeTests`).
    struct LayoutExtent: Equatable {
        var height: CGFloat
        var lastFragmentY: CGFloat
    }

    func layoutExtent() -> LayoutExtent? {
        guard let layout = textView.textLayoutManager else { return nil }
        var lastY: CGFloat = -1
        layout.enumerateTextLayoutFragments(from: layout.documentRange.endLocation, options: [.reverse]) { fragment in
            lastY = fragment.layoutFragmentFrame.minY
            return false
        }
        return LayoutExtent(height: layout.usageBoundsForTextContainer.height, lastFragmentY: lastY)
    }

    /// After the passes a keystroke runs, laying out the whole document changes neither number: no
    /// height in the note was an estimate. Leaves the whole document laid out.
    func expectNoEstimate(_ place: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let layout = textView.textLayoutManager, let grown = layoutExtent() else {
            Issue.record("\(place): no layout manager", sourceLocation: sourceLocation)
            return
        }
        layout.ensureLayout(for: layout.documentRange)
        guard let complete = layoutExtent() else { return }
        #expect(
            abs(grown.height - complete.height) < 0.5,
            "\(place): the note measured \(grown.height) pt before laying out the whole document and \(complete.height) pt after",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(grown.lastFragmentY - complete.lastFragmentY) < 0.5,
            "\(place): the last fragment started at \(grown.lastFragmentY) and then at \(complete.lastFragmentY)",
            sourceLocation: sourceLocation
        )
    }
}
