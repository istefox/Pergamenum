import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 8 (R-10).
//
// Scope of this file: the one promise the whole chain is measured against, end to end - **the
// file on disk is never touched by the way it is drawn**. Every other rendering test in this
// chain asks about one construct in isolation (`MarkupHidingTests` per marker kind,
// `CardConcealmentTests` per surface, `CardFoldTests` per fold); this one takes a realistic
// card's worth of text carrying *all* of them at once, through both halves of the round trip -
// the stores that write and read it, and the styling, concealment and reveal that draw it.
//
// A regression guard, not a red-first specification: the plan gives this task no "then
// implement" step. Every assertion below is expected to hold on arrival - the stores predate
// this chain, and length invariance is what Task 3's
// `theStorageNeverGainsOrLosesACharacterForAnyListCase` pins per construct. What is new is the
// *combination*: a substitution that is length-correct alone can still be wrong beside its
// neighbour. The half no assertion here can cover is the manual Obsidian round trip (plan Task
// 8, step 4), which the SPEC itself marks `no-test`.

// MARK: - The fixture

/// Every construct this chain renders, in one text: a heading, a top-level bullet, a nested
/// bullet, an ordered item, a checkbox line (which deliberately gets no bullet, ADR-0028 §D11)
/// and an emphasis pair.
///
/// The multi-line literal strips the indentation of its closing delimiter, so `- annidato`
/// really carries two leading spaces and nothing else - checked byte by byte in the first test
/// below, since a fixture reindented by a formatter would quietly turn this whole file into a
/// test of flat prose.
private let everyConstruct = """
    # Titolo
    - primo
      - annidato
    1. uno
    - [ ] fai
    **grassetto**

    """

/// Where each line of `everyConstruct` begins, in UTF-16 - the key space `hiddenMarkers` and
/// `EditorDecorationDelegate` both speak. Written out rather than computed so a test that goes
/// red says which construct moved.
private enum Line {
    static let titolo = 0
    static let primo = 9
    static let annidato = 17
    static let uno = 30
    static let fai = 37
    static let grassetto = 47
    static let all = [titolo, primo, annidato, uno, fai, grassetto]
}

// MARK: - Harnesses

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-card-round-trip-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// A card wired the way `CardTextView.makeNSView` wires it, minus the `Context` no test can
/// build - the compromise `Tests/CardConcealmentTests.swift` and `Tests/CardFoldTests.swift`
/// already make, restated here because each of those helpers is `private` to its own file.
@MainActor
private func makeCard(_ text: String, editable: Bool = true) throws -> (FormattingTextView, CardTextView.Coordinator) {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: nil),
        isEditable: editable,
        hidesMarkup: true
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )
    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = text
    coordinator.configure(textView, editable: editable)
    coordinator.applyStyling(to: textView)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return (textView, coordinator)
}

/// The note editor's own wiring, `Tests/MarkupHidingTests.swift`'s `MarkupCoordinator.editor`.
/// Present because the note is the surface that opens the `.md` file the first test writes: a
/// styling pass that corrupted the buffer there would reach disk on the next save.
@MainActor
private func makeEditor(_ text: String) -> (NSTextView, NoteTextView.Coordinator) {
    let view = NoteTextView(
        text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = NSTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.string = text
    coordinator.applyStyling(to: textView, theme: .emergency)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return (textView, coordinator)
}

@MainActor
@Suite struct CardRoundTrip {
    // MARK: - The fixture itself

    /// The premise every other test rests on, asserted before they do: the six lines are spelled
    /// exactly as the plan spells them, the nested item carries its two spaces, and the text is
    /// 61 UTF-16 units long with its paragraphs where `Line` says.
    @Test func theFixtureSpellsEveryConstructThisChainRenders() {
        #expect(everyConstruct == "# Titolo\n- primo\n  - annidato\n1. uno\n- [ ] fai\n**grassetto**\n")
        #expect((everyConstruct as NSString).length == 61)
        var starts: [Int] = []
        var offset = 0
        while offset < (everyConstruct as NSString).length {
            let range = (everyConstruct as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            starts.append(range.location)
            offset = NSMaxRange(range)
        }
        #expect(starts == Line.all)
    }

    // MARK: - R-10, the storage half: what is written is what is read

    /// Principle 1 at the file level. `NoteStore.write` takes a `String` and `read` hands one
    /// back; between them sits UTF-8 encoding, an atomic write and a decode, and this asserts
    /// that nothing in that path normalises, reflows or re-indents a list.
    ///
    /// Compared on the raw bytes too, not only on the decoded string: two different byte
    /// sequences can decode to equal `String`s under canonical equivalence, and it is the bytes
    /// Obsidian will read.
    @Test func aNoteIsByteIdenticalAfterAWriteAndAReadThroughNoteStore() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(root: root)
        let path = "01 Progetti/Ogni costrutto.md"

        try store.write(everyConstruct, to: path)
        let (record, text) = try store.read(path)
        let bytes = try Data(contentsOf: store.url(for: path))

        #expect(text == everyConstruct)
        #expect(bytes == Data(everyConstruct.utf8))
        #expect(record.byteSize == Data(everyConstruct.utf8).count)
    }

    /// The same claim for the surface this chain is actually about: a `.text` node's `text`
    /// property, through the JSON codec that has to survive `\n`, two leading spaces and a `**`
    /// pair without touching any of them.
    @Test func aTextNodeIsByteIdenticalAfterASaveAndALoadThroughCanvasStore() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CanvasStore(root: root)
        let board = "01 Progetti/Lavagna.canvas"
        let document = CanvasDocument(nodes: [
            CanvasNode(id: "a1b2c3d4e5f60718", kind: .text(everyConstruct), x: 0, y: 0, width: 260, height: 180)
        ])

        try store.save(document, board: board)
        let loaded = try store.load(board: board)
        let node = try #require(loaded.nodes.first)
        guard case .text(let readBack) = node.kind else {
            Issue.record("il nodo riletto non è di tipo text: \(node.typeName)")
            return
        }

        #expect(readBack == everyConstruct)
        #expect(Array(readBack.utf8) == Array(everyConstruct.utf8))
        // The whole document round-trips, not only the one field being read out of it.
        #expect(loaded == document)
    }

    // MARK: - R-10, the rendering half: what is drawn never becomes what is stored

    /// The card's full cycle, with the caret placed on every line in turn: styling fills the
    /// marker table, the reveal publishes the caret's paragraph, and the storage must come out
    /// of both untouched. Every paragraph, because reveal is the one step that writes back into
    /// the storage (`storage.edited(.editedAttributes, …)`), and a `changeInLength` that was not
    /// zero would show up here and nowhere else in the suite.
    @Test func aCardsStorageIsCharacterIdenticalAfterStylingConcealmentAndRevealOnEveryLine() throws {
        let (textView, coordinator) = try makeCard(everyConstruct)
        let storage = try #require(textView.textStorage)
        #expect(coordinator.hiddenMarkers.isEmpty == false, "premessa: la passata di stile ha riempito la tabella")

        for offset in Line.all {
            textView.setSelectedRange(NSRange(location: offset, length: 0))
            coordinator.applyReveal(to: textView)
            #expect(textView.string == everyConstruct, "cursore a \(offset): il testo della card è cambiato")
            #expect(storage.string == everyConstruct, "cursore a \(offset): lo storage della card è cambiato")
        }
        // And after a second styling pass over the already-styled buffer, which is what every
        // SwiftUI update of the card runs.
        coordinator.applyStyling(to: textView)
        #expect(storage.string == everyConstruct)
        #expect(storage.length == (everyConstruct as NSString).length)
    }

    /// The same cycle on the note editor, because the `.md` file written above is opened there.
    @Test func aNotesStorageIsCharacterIdenticalAfterStylingConcealmentAndRevealOnEveryLine() throws {
        let (textView, coordinator) = makeEditor(everyConstruct)
        let storage = try #require(textView.textStorage)

        for offset in Line.all {
            textView.setSelectedRange(NSRange(location: offset, length: 0))
            coordinator.applyReveal(to: textView)
            #expect(textView.string == everyConstruct, "cursore a \(offset): il testo della nota è cambiato")
            #expect(storage.string == everyConstruct, "cursore a \(offset): lo storage della nota è cambiato")
        }
    }

    /// Through a real TextKit 2 layout pass, driven with the marker table the card's own styling
    /// walk produced - the end-to-end form of `MarkupHidingLists`' per-construct length check.
    ///
    /// Two things are asserted at once, and they are not the same thing. The stored text must be
    /// unchanged after layout (the file), and every *displayed* paragraph must have its stored
    /// paragraph's length (`NSTextContentManager.h:120`, the constraint that forbids inserting a
    /// bullet rather than substituting one). A substitution that broke the second would not draw
    /// visibly wrong; it would drift the offsets between storage and layout later on.
    @Test func aRealLayoutPassOverTheWholeFixtureNeverChangesTheStoredText() throws {
        let (_, coordinator) = try makeCard(everyConstruct)
        let markers = coordinator.hiddenMarkers

        // The premise, so this cannot pass vacuously over an empty table: all six lines are
        // concealed - the heading, the three list items, the emphasis pair, and now the checkbox
        // line too, drawn as a glyph rather than hidden as a list marker (PG-086, ADR-0028 §D11
        // reopened): a checkbox is still never a list marker, it is its own `.checkbox` kind. A
        // round trip that stayed identical only because nothing was being drawn over it would
        // prove nothing at all.
        #expect(Set(markers.keys) == [Line.titolo, Line.primo, Line.annidato, Line.uno, Line.fai, Line.grassetto])
        #expect(markers[Line.fai]?.contains { $0.kind == .checkbox } == true, "la riga con casella di spunta entra nella tabella con un marcatore .checkbox")
        #expect(markers.values.reduce(0) { $0 + $1.count } == 7)

        for hides in [true, false] {
            for revealed in [Set<Int>(), Set(Line.all)] {
                let content = NSTextContentStorage()
                let layout = NSTextLayoutManager()
                content.addTextLayoutManager(layout)
                let container = NSTextContainer(
                    size: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                )
                container.lineFragmentPadding = 0
                layout.textContainer = container

                let delegate = EditorDecorationDelegate()
                delegate.apply(hiddenMarkers: markers, hidingMarkup: hides)
                _ = delegate.apply(revealedParagraphs: revealed)
                content.delegate = delegate
                layout.delegate = delegate

                content.textStorage?.setAttributedString(NSAttributedString(string: everyConstruct))
                layout.ensureLayout(for: layout.documentRange)

                let label = "nascondi=\(hides) rivelato=\(revealed.count)"
                #expect(content.textStorage?.string == everyConstruct, "\(label): lo storage è cambiato")
                #expect(content.textStorage?.length == (everyConstruct as NSString).length, "\(label): lunghezza")

                var substituted = 0
                for offset in Line.all {
                    let range = (everyConstruct as NSString)
                        .paragraphRange(for: NSRange(location: offset, length: 0))
                    guard let displayed = delegate.textContentStorage(content, textParagraphWith: range) else {
                        continue  // Nil is "draw the stored paragraph as it is" - nothing to measure.
                    }
                    substituted += 1
                    #expect(
                        displayed.attributedString.length == range.length,
                        "\(label) riga \(offset): \(displayed.attributedString.length) invece di \(range.length)"
                    )
                }
                // The loop above must have had something to measure in the one configuration where
                // every marker is concealed - otherwise its `continue` would carry the whole test.
                if hides, revealed.isEmpty {
                    #expect(substituted == 6, "\(label): \(substituted) paragrafi sostituiti invece di 6")
                }
            }
        }
    }
}
