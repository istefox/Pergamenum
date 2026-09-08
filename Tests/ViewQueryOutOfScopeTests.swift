import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// Task 10 contract only: R-15 serialization, R-16 excluded surfaces, and the
// three named R-13 regressions. R-14 is a human gate; R-17 is diff/build evidence.
private func outOfScopeFind<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    guard depth < 50 else { return nil }
    if let match = value as? T { return match }
    for child in Mirror(reflecting: value).children {
        if let match = outOfScopeFind(type, in: child.value, depth: depth + 1) { return match }
    }
    return nil
}

@MainActor
private final class OutOfScopeEditor {
    var text: String
    let textView = CompletingTextView(usingTextLayoutManager: true)
    var coordinator: NoteTextView.Coordinator!

    init(_ text: String) {
        self.text = text
        let view = NoteTextView(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        coordinator = view.makeCoordinator()
        textView.delegate = coordinator
        textView.isRichText = false
        textView.string = text
        coordinator.textView = textView
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        view.wire(textView, to: coordinator)
        coordinator.applyStyling(to: textView, theme: .emergency)
    }

    func tearDown() {
        textView.delegate = nil
        coordinator = nil
    }
}

@MainActor
@Suite(.serialized)
struct ViewQueryOutOfScopeTests {
    // The card's real switch runs through applyStyling; no test-side kind mapping.
    @Test(arguments: ["render: table", "render: board\ngroup: tag(\"status-*\")", "outsider: invalid", ""],
          [true, false])
    func workspaceTextCardNeverProducesAViewBlockKind(body: String, editable: Bool) throws {
        let fence = "```pergamenum-view\n\(body)\n```"
        let prefix = "# Before\n"
        let text = prefix + fence + "\nAfter"
        let card = CardTextView(
            text: .constant(text), theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: editable, hidesMarkup: true
        )
        let coordinator = card.makeCoordinator()
        let scroll = FormattingTextView.scrollableTextView()
        let textView = try #require(scroll.documentView as? FormattingTextView)
        defer { CardTextView.dismantleNSView(scroll, coordinator: coordinator) }
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        coordinator.configure(textView, editable: editable)

        // Positive control: this is a view span, and the card still processes headings.
        #expect(MarkdownStyler.spans(in: text).contains { $0.span == .viewBlockRun })
        coordinator.applyStyling(to: textView)
        #expect(coordinator.hiddenMarkers[0]?.contains { $0.kind == .heading } == true)
        let start = (prefix as NSString).length
        let end = start + (fence as NSString).length
        #expect(coordinator.hiddenMarkers.keys.allSatisfy { $0 < start || $0 >= end })
        let storage = try #require(textView.textContentStorage)
        let paragraph = (text as NSString).paragraphRange(for: NSRange(location: start, length: 0))
        #expect(coordinator.decorations.textContentStorage(storage, textParagraphWith: paragraph) == nil)
        #expect(Array(textView.string.utf8) == Array(text.utf8))
    }

    // R-16: exercise the actual routing switch, including a broken and empty body.
    @Test(arguments: ["render: table", "render: board\ngroup: tag(\"status-*\")", "outsider: invalid", ""],
          [true, false])
    func markdownReadingRouteNeverPassesAnEditQuery(body: String, hasQueries: Bool) throws {
        let queries: ViewQuerySource? = hasQueries
            ? ViewQuerySource(evaluate: { _ in ViewResult(groups: [], total: 0) }, generation: 7)
            : nil
        let view = MarkdownBlocksView(blocks: [], notePath: "Note.md", queries: queries)
        let block = MarkdownBlock.code(language: ViewBlock.language, lines: body.components(separatedBy: "\n"))
        let rendered = try #require(outOfScopeFind(RenderedViewBlock.self, in: view.view(for: block)))
        #expect(rendered.source == body)
        #expect(rendered.notePath == "Note.md")
        #expect(rendered.queries?.generation == queries?.generation)
        #expect(rendered.onEditQuery == nil, "R-16: excluded reading surfaces must not gain a builder")
    }

    @Test func anotherCodeLanguageNeverReachesTheViewRenderer() {
        let view = MarkdownBlocksView(blocks: [])
        let block = MarkdownBlock.code(language: "swift", lines: ["render: table"])
        #expect(outOfScopeFind(RenderedViewBlock.self, in: view.view(for: block)) == nil)
    }

    // R-15: literal hand-written expectations, seeded and serialized, then written
    // through the editor's production commit. Defaults are never inferred from output.
    @Test(arguments: [
        "render: table", "render: list", "render: gallery", "render: calendar",
        "group: tag(\"status-*\")\nrender: board",
    ], [true, false])
    func untouchedDefaultsCommitAsTheMinimalHandWrittenFence(body: String, explicitDefaults: Bool) throws {
        let expectedBlock = try ViewBlock.parse(body)
        var draft = ViewQueryDraft.seed(from: body)
        if explicitDefaults { draft.columns = expectedBlock.effectiveColumns }
        let written = ViewQueryText.body(of: draft)
        for key in ["columns:", "from:", "limit:"] {
            #expect(!written.components(separatedBy: "\n").contains { $0.hasPrefix(key) })
        }
        #expect(Array(written.utf8) == Array(body.utf8))

        let prefix = "Before 🧭 e\u{301}\n\n"
        let suffix = "\n\nAfter é\n"
        let editor = OutOfScopeEditor(prefix + "```pergamenum-view\nrender: table\nlimit: 9\n```" + suffix)
        defer { editor.tearDown() }
        let offset = (prefix as NSString).length
        #expect(editor.coordinator.commitViewBlock(written, at: offset, in: editor.textView))
        let expected = prefix + "```pergamenum-view\n" + body + "\n```" + suffix
        #expect(Array(editor.textView.string.utf8) == Array(expected.utf8))
        #expect(Array(editor.text.utf8) == Array(expected.utf8))
        let run = try #require(EditorDecorationDelegate.viewBlockRun(
            in: editor.textView.string as NSString, atParagraphStart: offset
        ))
        #expect(run.block == expectedBlock)
    }

    // R-15 boundary: defaults in a different order are an explicit choice.
    @Test func reorderedColumnsSurviveTheSeedWriterParserRoundTrip() throws {
        let body = "group: tag(\"status-*\")\nrender: board\ncolumns: [tags, title]"
        let written = ViewQueryText.body(of: ViewQueryDraft.seed(from: body))
        #expect(written == body)
        #expect(try ViewBlock.parse(written).columns == [.tags, .title])
    }

    // Direct calls keep Task 4's named coverage executable, not a source grep that
    // could report green for a disabled test. No duplication of its private harness.
    @Test("R-13: one atomic rewrite")
    func oneAtomicRewrite() throws {
        try ViewQueryCommitTests().happyPathReplacesOnlyTheClosedFence()
    }

    @Test("R-13: one undo step")
    func oneUndoStep() throws {
        try ViewQueryCommitTests().exactlyOneUndoRestoresTheWholeNote()
    }

    @Test("R-13: refused commit leaves the buffer untouched")
    func refusedCommitLeavesTheBufferUntouched() throws {
        try ViewQueryCommitTests().insertingALineAboveTheFenceRefusesTheOldRequest()
    }
}
