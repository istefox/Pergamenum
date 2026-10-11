import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// PG-219, R-05, R-07, R-09: which pointer a text view asks for under a point, and that the two
// classes name no AppKit cursor themselves (`EditorPointer.apply()` is the one place that does).
//
// What the screen draws is the hand check's (ADR-0090 §D9); `EditorPointerHostTests` pins what
// reaches `NSCursor.current`.

// MARK: - Shared support

@MainActor
final class TextBox {
    var text: String
    init(_ text: String) { self.text = text }
}

/// Real views in an offscreen window, styled through the coordinator.
@MainActor
enum PointerFixtures {
    struct Note {
        let textView: CompletingTextView
        let coordinator: NoteTextView.Coordinator
        let window: NSWindow
        let box: TextBox
    }

    /// `TagDateClickTargetTests.fixture`'s construction, with the text behind a box so an edit
    /// reaches a binding, and the coordinator as the delegate so `didChangeText` restyles.
    static func note(text: String, hidesMarkup: Bool = false) -> Note {
        let box = TextBox(text)
        let view = NoteTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        textView.delegate = coordinator
        coordinator.textView = textView
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        coordinator.applyStyling(to: textView, theme: .emergency)
        layOut(textView)
        return Note(textView: textView, coordinator: coordinator, window: window, box: box)
    }

    /// `TableGridHostedAttachmentTests`' construction: inside a real `NSScrollView`, which is
    /// what makes TextKit 2 place a table's grid.
    static func scrolledNote(text: String, hidesMarkup: Bool) -> Note {
        let box = TextBox(text)
        let view = NoteTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        coordinator.textView = textView
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        view.wire(textView, to: coordinator)
        textView.string = text
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        let window = NSWindow(
            contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = scroll
        window.layoutIfNeeded()
        coordinator.applyStyling(to: textView, theme: .emergency)
        layOut(textView)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        return Note(textView: textView, coordinator: coordinator, window: window, box: box)
    }

    struct Card {
        let textView: FormattingTextView
        let coordinator: CardTextView.Coordinator
        let window: NSWindow
    }

    /// What `CardTextView.makeNSView` builds, minus the scroll view: styled through the card's own
    /// coordinator and `CardTextAttributes`.
    static func card(text: String, editable: Bool) -> Card {
        let view = CardTextView(
            text: .constant(text), theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: editable, hidesMarkup: false
        )
        let coordinator = view.makeCoordinator()
        let textView = FormattingTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.frame = CGRect(x: 0, y: 0, width: 400, height: 500)
        textView.textContainer?.size = CGSize(width: 396, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        coordinator.configure(textView, editable: editable)
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        coordinator.applyStyling(to: textView)
        layOut(textView)
        return Card(textView: textView, coordinator: coordinator, window: window)
    }

    static func layOut(_ textView: NSTextView) {
        guard let layout = textView.textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
        textView.layoutSubtreeIfNeeded()
    }

    /// Every segment frame of `range`, in the view's own coordinates (one per wrapped line).
    static func segments(of range: NSRange, in textView: NSTextView) -> [CGRect] {
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return [] }
        let origin = textView.textContainerOrigin
        var frames: [CGRect] = []
        layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return frames
    }

    /// The midpoint of the first segment of the first occurrence of `needle`.
    static func midpoint(of needle: String, in textView: NSTextView) -> CGPoint? {
        let range = (textView.string as NSString).range(of: needle)
        guard range.location != NSNotFound, let frame = segments(of: range, in: textView).first
        else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

private let decisionText = """
riga semplice
[[Seconda nota]]
[etichetta](https://example.com)
#client-acme
>2026-10-14
!2026-10-15
[[un wikilink molto lungo che deve andare a capo perché la colonna è stretta abbastanza da forzarlo su due righe]]
chiusura

"""

// MARK: - The decision on CompletingTextView (R-05)

@MainActor
@Suite struct CompletingTextViewPointerDecision {
    private func pointer(over needle: String, in fixture: PointerFixtures.Note) throws -> EditorPointer? {
        let point = try #require(PointerFixtures.midpoint(of: needle, in: fixture.textView), "\(needle)")
        return fixture.textView.pointer(at: point)
    }

    @Test func aWikilinkIsALink() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: "Seconda nota", in: fixture) == .link)
    }

    @Test func aCommonMarkLabelIsALink() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: "etichetta", in: fixture) == .link)
    }

    @Test func aTagIsALink() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: "#client-acme", in: fixture) == .link)
    }

    @Test func aScheduledDateIsALink() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: ">2026-10-14", in: fixture) == .link)
    }

    @Test func aDueDateIsALink() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: "!2026-10-15", in: fixture) == .link)
    }

    @Test func plainTextIsText() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        #expect(try pointer(over: "riga semplice", in: fixture) == .text)
        #expect(try pointer(over: "chiusura", in: fixture) == .text)
    }

    @Test func emptySpaceBelowTheLastLineIsText() {
        // (R-05, reading G4(a)) the view's own empty area still asks for the text pointer.
        let fixture = PointerFixtures.note(text: decisionText)
        let point = CGPoint(x: 300, y: fixture.textView.bounds.height - 20)
        #expect(fixture.textView.pointer(at: point) == .text)
    }

    @Test func outsideTheViewThereIsNoPointer() {
        // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        let bounds = fixture.textView.bounds
        #expect(fixture.textView.pointer(at: CGPoint(x: -10, y: 30)) == nil)
        #expect(fixture.textView.pointer(at: CGPoint(x: bounds.width + 5, y: 30)) == nil)
        #expect(fixture.textView.pointer(at: CGPoint(x: 100, y: bounds.height + 50)) == nil)
    }

    @Test func aWrappedLinkIsALinkOnBothSegments() throws { // (R-05)
        let fixture = PointerFixtures.note(text: decisionText)
        let range = (decisionText as NSString).range(of: "[[un wikilink")
        let whole = NSRange(
            location: range.location,
            length: (decisionText as NSString).range(of: "due righe]]").upperBound - range.location
        )
        let frames = PointerFixtures.segments(of: whole, in: fixture.textView)
        let two = try #require(
            frames.count == 2 ? frames : nil, "the link must wrap to two segments, got \(frames.count)"
        )
        for frame in two {
            #expect(fixture.textView.pointer(at: CGPoint(x: frame.midX, y: frame.midY)) == .link, "\(frame)")
        }
    }

    @Test func hoverAndClickAgreeAtEveryPointOfTheLinkLine() throws {
        // (R-05, PG-220) `pointer(at:) == .link` exactly when `linkCharacterIndex(at:) != nil`.
        let fixture = PointerFixtures.note(text: decisionText)
        let textView = fixture.textView
        let frame = try #require(
            PointerFixtures.segments(
                of: (decisionText as NSString).range(of: "[[Seconda nota]]"), in: textView
            ).first
        )
        var linkPoints = 0
        var disagreements: [CGFloat] = []
        for step in 0..<Int(textView.bounds.width) {
            let point = CGPoint(x: CGFloat(step), y: frame.midY)
            let clickable = textView.linkCharacterIndex(at: point) != nil
            if clickable { linkPoints += 1 }
            if (textView.pointer(at: point) == .link) != clickable { disagreements.append(point.x) }
        }
        #expect(linkPoints > 0, "the sweep never crossed the link")
        #expect(disagreements.isEmpty, "hover and click disagree at x = \(disagreements)")
    }
}

// MARK: - Hosted attachments (R-05)

@MainActor
@Suite struct CompletingTextViewPointerOverAttachments {
    @Test func aTableGridAnswersNothing() throws {
        let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
        let fixture = PointerFixtures.scrolledNote(text: note, hidesMarkup: true)
        let textView = fixture.textView
        let grid = try #require(fixture.coordinator.decorations.tableViews[6], "no table grid was built")
        try #require(grid.superview != nil, "the grid is not on screen")
        let centre = textView.convert(CGPoint(x: grid.bounds.midX, y: grid.bounds.midY), from: grid)
        // The line above the table still asks for the text pointer, so the nil below is the grid's.
        let prima = try #require(PointerFixtures.midpoint(of: "prima", in: textView))
        #expect(textView.pointer(at: prima) == .text)
        #expect(textView.pointer(at: centre) == nil)
    }

    @Test func aDrawnImageEmbedAnswersNothing() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        try #require(!box.isNull, "the embed's picture was never laid out")
        let textView = fixture.textView
        let prima = try #require(PointerFixtures.midpoint(of: "prima", in: textView))
        #expect(textView.pointer(at: prima) == .text)
        #expect(textView.pointer(at: CGPoint(x: box.midX, y: box.midY)) == nil)
    }
}

// MARK: - The decision on FormattingTextView (R-05)

@MainActor
@Suite struct FormattingTextViewPointerDecision {
    private static let text = "riga semplice\n[[Seconda nota]]\n#client-acme\nfine"

    @Test func anEditableCardAsksForALinkOverAWikilinkAndATag() throws { // (R-05)
        let card = PointerFixtures.card(text: Self.text, editable: true)
        let wikilink = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: card.textView))
        let tag = try #require(PointerFixtures.midpoint(of: "#client-acme", in: card.textView))
        #expect(card.textView.pointer(at: wikilink) == .link)
        #expect(card.textView.pointer(at: tag) == .link)
    }

    @Test func anEditableCardAsksForTextOverPlainText() throws { // (R-05)
        let card = PointerFixtures.card(text: Self.text, editable: true)
        let plain = try #require(PointerFixtures.midpoint(of: "riga semplice", in: card.textView))
        #expect(card.textView.pointer(at: plain) == .text)
    }

    @Test func anEditableCardAsksForNothingOutsideItself() {
        // (R-05)
        let card = PointerFixtures.card(text: Self.text, editable: true)
        #expect(card.textView.pointer(at: CGPoint(x: -10, y: 10)) == nil)
        #expect(card.textView.pointer(at: CGPoint(x: 100, y: card.textView.bounds.height + 40)) == nil)
    }

    @Test func aCardNotBeingEditedAsksForNothingAnywhere() throws { // (R-05)
        let card = PointerFixtures.card(text: Self.text, editable: false)
        #expect(!card.textView.isEditable)
        let wikilink = try #require(PointerFixtures.midpoint(of: "Seconda nota", in: card.textView))
        let plain = try #require(PointerFixtures.midpoint(of: "riga semplice", in: card.textView))
        // Control: with the card editable the same two points answer, so the nil is `isEditable`'s.
        let editable = PointerFixtures.card(text: Self.text, editable: true)
        #expect(editable.textView.pointer(at: wikilink) == .link)
        #expect(card.textView.pointer(at: wikilink) == nil)
        #expect(card.textView.pointer(at: plain) == nil)
        #expect(card.textView.pointer(at: CGPoint(x: 100, y: card.textView.bounds.height - 5)) == nil)
    }
}

// MARK: - No AppKit cursor (R-09)

@Suite struct NoAppKitCursorInTheTextViews {
    private static func sources(under directory: String, prefix: String) throws -> [(name: String, lines: [String])] {
        let folder = try resolvedRepoRoot().appendingPathComponent(directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".swift") }
            .sorted()
        return try names.map { name in
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            return (name, text.components(separatedBy: "\n"))
        }
    }

    @Test func noLineOutsideACommentNamesNSCursor() throws { // (R-09, ADR-0090 §D1)
        let files = try Self.sources(under: "Sources/Features/Editor", prefix: "CompletingTextView")
            + Self.sources(under: "Sources/Features/Workspace", prefix: "FormattingTextView")
        #expect(files.count >= 8, "only \(files.count) files read: the listing went wrong")
        var offences: [String] = []
        for file in files {
            for (index, line) in file.lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains("NSCursor") else { continue }
                offences.append("\(file.name):\(index + 1): \(trimmed)")
            }
        }
        #expect(offences.isEmpty, "an AppKit cursor is left: \(offences)")
    }
}
