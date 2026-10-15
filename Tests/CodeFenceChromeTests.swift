import AppKit
import Testing
@testable import Pergamenum

// ADR-0087 §D6, plan docs/plans/note-workflow-n5.md, Task 3 (R-37).
//
// A closed fence's opening line reads as a header and its closing line as a quiet rule, both drawn by
// a `CodeFenceFragment`; the body stays ordinary editable text; «Copia il blocco» copies the body.
//
// Layout of `note` below, in UTF-16 offsets: `intro` at 0, the opening line at 7, body lines at 16 and
// 26, the closing line at 36, `fine` at 41.

@MainActor
@Suite(.serialized) struct CodeFenceChrome {
    private static let note = "intro\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nfine\n"
    private static let opening = 7
    private static let firstBody = 16
    private static let secondBody = 26
    private static let closing = 36
    private static let body = "let a = 1\nlet b = 2"

    private static func role(_ built: N5Editor.Built, at offset: Int) -> CodeFenceFragment.Role? {
        (N5Editor.fragments(built)[offset] as? CodeFenceFragment)?.role
    }

    // MARK: Fragments

    @Test func aClosedFenceOpensWithAHeaderFragmentCarryingItsLanguageAndLineCount() { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        #expect(Self.role(built, at: Self.opening) == .header(language: "swift", lineCount: 2))
    }

    @Test func itsClosingLineIsAClosingFragment() { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        #expect(Self.role(built, at: Self.closing) == .closing)
    }

    @Test func offTheCaretTheFenceLinesAreCollapsed() { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        #expect(N5Editor.isConcealed(built, paragraph: Self.opening, at: Self.opening))
        #expect(N5Editor.isConcealed(built, paragraph: Self.closing, at: Self.closing))
    }

    @Test func theCaretOnTheOpeningLineRevealsItAsRawBackticks() { // R-37
        let built = N5Editor.build(Self.note, caret: Self.opening + 2)
        #expect(Self.role(built, at: Self.opening) == nil)
        #expect(!(N5Editor.fragments(built)[Self.opening] is CodeFenceFragment))
        #expect(!N5Editor.isConcealed(built, paragraph: Self.opening, at: Self.opening))
        // The other end of the fence is still drawn: the reveal is per line.
        #expect(Self.role(built, at: Self.closing) == .closing)
    }

    @Test func theCaretOnTheClosingLineRevealsIt() { // R-37
        let built = N5Editor.build(Self.note, caret: Self.closing + 1)
        #expect(!(N5Editor.fragments(built)[Self.closing] is CodeFenceFragment))
        #expect(!N5Editor.isConcealed(built, paragraph: Self.closing, at: Self.closing))
        #expect(Self.role(built, at: Self.opening) == .header(language: "swift", lineCount: 2))
    }

    @Test func theDisplayedFenceLinesKeepTheirStoredLength() { // R-37
        for caret in [0, Self.opening + 2] {
            let built = N5Editor.build(Self.note, caret: caret)
            for line in [Self.opening, Self.closing] {
                let lengths = N5Editor.lengths(built, at: line)
                #expect(lengths.displayed == lengths.stored, "caret \(caret), line \(line): \(lengths)")
            }
        }
    }

    // MARK: The body

    @Test func bodyLinesStayInTheLayoutAsOrdinaryFragments() { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        let fragments = N5Editor.fragments(built)
        for line in [Self.firstBody, Self.secondBody] {
            #expect(fragments[line] != nil, "la riga \(line) è uscita dal layout")
            #expect(!(fragments[line] is CodeFenceFragment))
        }
    }

    @Test func aBodyLineAcceptsTypedText() { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        built.textView.insertText("z", replacementRange: NSRange(location: Self.firstBody, length: 0))
        #expect(built.textView.string.contains("zlet a = 1"))
    }

    // MARK: Fences that get no chrome

    @Test func anUnclosedFenceGetsNoFenceFragment() { // R-37
        let built = N5Editor.build("intro\n\n```swift\nlet a = 1\n", caret: 0)
        #expect(!N5Editor.fragments(built).values.contains { $0 is CodeFenceFragment })
        #expect(!N5Editor.isConcealed(built, paragraph: Self.opening, at: Self.opening))
    }

    @Test func aPergamenumViewFenceGetsNoFenceFragment() { // R-37
        let built = N5Editor.build("intro\n\n```pergamenum-view\nrender: table\n```\n\nfine\n", caret: 0)
        #expect(!N5Editor.fragments(built).values.contains { $0 is CodeFenceFragment })
    }

    // MARK: «Copia il blocco»

    private static func event(at point: NSPoint, in window: NSWindow?) -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private static func baseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        return menu
    }

    private static func blockItem(in menu: NSMenu?) -> NSMenuItem? {
        menu?.items.first { $0.title == "Copia il blocco" }
    }

    @Test(arguments: [8, 18, 37])
    func theMenuOffersCopyTheBlockForAnIndexInsideTheFence(index: Int) { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        let menu = built.coordinator.textView(
            built.textView, menu: Self.baseMenu(), for: Self.event(at: .zero, in: built.window), at: index
        )
        #expect(Self.blockItem(in: menu) != nil, "nessuna voce «Copia il blocco» all'indice \(index)")
        // The menu's other items are still there.
        #expect(menu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true)
        #expect(menu?.items.contains { $0.action == #selector(NSText.paste(_:)) } == true)
    }

    /// PG-420: the early return tests for the backtick mark alone, as `CodeFence.marks` does, so a tilde
    /// fence never gets the item, and a note holding both still gets it on the backtick block.
    @Test func aTildeFenceGetsNoCopyItem() { // R-37
        let note = "intro\n\n~~~\nlet a = 1\n~~~\n\nfine\n"
        let built = N5Editor.build(note, caret: 0)
        let inside = (note as NSString).range(of: "let a").location
        let menu = built.coordinator.textView(
            built.textView, menu: Self.baseMenu(), for: Self.event(at: .zero, in: built.window), at: inside
        )
        #expect(Self.blockItem(in: menu) == nil)
        #expect(menu?.items.count == 2)
    }

    @Test func aBacktickFenceBesideATildeOneStillGetsTheItem() { // R-37
        let note = "~~~\nx\n~~~\n\n```swift\nlet a = 1\n```\n"
        let built = N5Editor.build(note, caret: 0)
        let inside = (note as NSString).range(of: "let a").location
        let menu = built.coordinator.textView(
            built.textView, menu: Self.baseMenu(), for: Self.event(at: .zero, in: built.window), at: inside
        )
        #expect(Self.blockItem(in: menu) != nil)
    }

    @Test(arguments: [0, 3, 42])
    func theMenuIsUnchangedOutsideTheFence(index: Int) { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        let base = Self.baseMenu()
        let menu = built.coordinator.textView(
            built.textView, menu: base, for: Self.event(at: .zero, in: built.window), at: index
        )
        #expect(Self.blockItem(in: menu) == nil)
        #expect(menu?.items.count == 2)
    }

    /// The route, proved on this SDK: a right-click on a body line reaches the delegate through the
    /// text view's own `menu(for:)`, the protected `CompletingTextView+Pasteboard.swift` untouched.
    @Test func aRightClickInTheBodyReachesTheDelegateThroughTheTextViewsOwnMenu() throws { // R-37
        let built = N5Editor.build(Self.note, caret: 0)
        // Settle the view first: a vertically resizable `NSTextView` shrinks to its text (800 to ~285 pt
        // here) on its first layout pass, and a window point computed from the pre-shrink frame lands
        // below the text once `menu(for:)` converts it back. The menu itself is not at fault.
        built.textView.sizeToFit()
        built.textView.layoutSubtreeIfNeeded()
        let frame = EmbedEditorFixtures.fragmentFrame(at: Self.firstBody, in: built.textView)
        try #require(!frame.isNull, "the body line has no frame")
        let inView = NSPoint(x: frame.minX + 40, y: frame.midY)
        let event = Self.event(at: built.textView.convert(inView, to: nil), in: built.window)
        let menu = built.textView.menu(for: event)
        #expect(Self.blockItem(in: menu) != nil)
        #expect(menu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true)
    }

    @Test func invokingTheItemPutsExactlyTheBodyOnThePasteboard() throws { // R-37
        // A private pasteboard: the general one is the person's clipboard, and a test that wrote it could
        // restore only the flavours it knew of.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("it.stefer.pergamenum.tests.fence-copy"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("sentinella", forType: .string)

        let built = N5Editor.build(Self.note, caret: 0)
        let menu = built.coordinator.textView(
            built.textView, menu: Self.baseMenu(), for: Self.event(at: .zero, in: built.window), at: 18
        )
        let item = try #require(Self.blockItem(in: menu))
        #expect(item.action == #selector(NoteTextView.Coordinator.copyFenceBlock(_:)))
        #expect(item.target === built.coordinator)
        built.coordinator.copyFenceBlock(item, to: pasteboard)

        let copied = try #require(pasteboard.string(forType: .string))
        #expect(copied.trimmingCharacters(in: .newlines) == Self.body)
        #expect(!copied.contains("`"), "i segni della recinzione non vanno copiati")
    }
}
