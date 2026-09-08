import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// Task 8 contract, derived only from the supplied brief (R-01, R-02, R-03, C8).
// The coder must declare the optional onEditQuery inputs; tests do not supply stubs.
// Reflection follows ViewBlockOutOfScopeTests: inspect the real SwiftUI value, never
// manufacture the request whose source is under test. This is not a pixel/layout test.

private func entryPointFind<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    guard depth < 50 else { return nil }
    if let match = value as? T { return match }
    for child in Mirror(reflecting: value).children {
        if let match = entryPointFind(type, in: child.value, depth: depth + 1) { return match }
    }
    return nil
}

private func entryPointStrings(in value: Any, depth: Int = 0) -> [String] {
    guard depth < 50 else { return [] }
    if let string = value as? String { return [string] }
    return Mirror(reflecting: value).children.flatMap {
        entryPointStrings(in: $0.value, depth: depth + 1)
    }
}

@MainActor
private final class EntryPointModel {
    var text: String
    var requests: [ViewQueryEditRequest] = []

    init(_ text: String) { self.text = text }
}

@MainActor
private struct EntryPointEditor {
    let model: EntryPointModel
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator

    func style(_ text: String) {
        model.text = text
        textView.string = text
        // The fixture always starts with prose. A caret in the fence reveals its
        // source instead of rendering it, which is a different entry point.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.applyStyling(to: textView, theme: .emergency)
    }

    func block(at ordinal: Int) throws -> RenderedViewBlock {
        let host = coordinator.viewBlockHosts.host(for: ordinal, in: textView)
        return try #require(entryPointFind(RenderedViewBlock.self, in: host.rootView))
    }

    func click(at ordinal: Int) throws -> ViewQueryEditRequest {
        let rendered = try block(at: ordinal)
        let callback = try #require(rendered.onEditQuery, "R-02/R-03: the styled host needs an edit action")
        let before = model.requests.count
        callback()
        try #require(model.requests.count == before + 1, "One click must emit exactly one request")
        return try #require(model.requests.last)
    }
}

@MainActor
private func entryPointEditor(_ text: String, enabled: Bool = true) -> EntryPointEditor {
    let model = EntryPointModel(text)
    var view = NoteTextView(
        text: Binding(get: { model.text }, set: { model.text = $0 }),
        theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    if enabled { view.onEditQuery = { model.requests.append($0) } }
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)
    let editor = EntryPointEditor(model: model, textView: textView, coordinator: coordinator)
    editor.style(text)
    return editor
}

private func entryPointNote(_ source: String, prefix: String = "Before 🧭 e\u{301}\n") -> String {
    prefix + "```pergamenum-view\n" + (source.isEmpty ? "" : source + "\n") + "```\nAfter\n"
}

@MainActor
@Suite(.serialized)
struct ViewQueryEntryPointTests {
    // R-01/R-03: the same edit affordance exists in success and parse-failure states.
    @Test(arguments: ["render: table", "outsider: invalid"])
    func bothFenceStatesOfferExactlyOneEditControl(source: String) throws {
        if source == "render: table" {
            _ = try ViewBlock.parse(source)
        } else {
            #expect(throws: ViewBlockError.self) { try ViewBlock.parse(source) }
        }
        var rendered = RenderedViewBlock(source: source)
        rendered.onEditQuery = {}
        let strings = entryPointStrings(in: rendered.body)
        #expect(strings.filter { $0 == "rendered-view-edit-query" }.count == 1)
        // Positive control: an opaque or untraversable body cannot pass an absence check.
        #expect(strings.contains("rendered-view-refresh"))
    }

    // R-01 boundary: default callers, including transclusion/export, gain no action.
    @Test(arguments: ["render: table", "outsider: invalid"])
    func defaultRenderedBlockDrawsNoEditQueryControl(source: String) {
        let rendered = RenderedViewBlock(source: source)
        #expect(rendered.onEditQuery == nil)
        let strings = entryPointStrings(in: rendered.body)
        #expect(strings.contains("rendered-view-refresh"))
        #expect(!strings.contains("rendered-view-edit-query"))
    }

    @Test func rootViewForwardsTheEditAction() throws {
        var calls = 0
        let root = ViewBlockHostStore.rootView(
            source: "render: table", onEditQuery: { calls += 1 }, theme: .emergency
        )
        let rendered = try #require(entryPointFind(RenderedViewBlock.self, in: root))
        let callback = try #require(rendered.onEditQuery)
        callback()
        #expect(calls == 1)
    }

    @Test func rootViewAndNoteTextViewDefaultToNoEditAction() throws {
        let root = ViewBlockHostStore.rootView(source: "render: table", theme: .emergency)
        let rendered = try #require(entryPointFind(RenderedViewBlock.self, in: root))
        #expect(rendered.onEditQuery == nil)
        let view = NoteTextView(
            text: .constant(""), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in }
        )
        #expect(view.onEditQuery == nil)
    }

    @Test(arguments: ["render: table", "outsider: invalid"])
    func stylingWithoutAnEditorCallbackDoesNotExposeAControl(source: String) throws {
        let editor = entryPointEditor(entryPointNote(source), enabled: false)
        let rendered = try editor.block(at: 0)
        #expect(rendered.onEditQuery == nil)
        let strings = entryPointStrings(in: rendered.body)
        #expect(strings.contains("rendered-view-refresh"))
        #expect(!strings.contains("rendered-view-edit-query"))
        #expect(editor.model.requests.isEmpty)
    }

    // R-02: real styling and the callback it installed, not a test-built request.
    @Test func requestCarriesTheCurrentParseableBody() throws {
        let source = "render: table\nlimit: 7"
        _ = try ViewBlock.parse(source)
        let editor = entryPointEditor(entryPointNote(source))
        #expect(editor.model.requests.isEmpty, "Styling alone must not open the sheet")
        let request = try editor.click(at: 0)
        #expect(request.source == source)
        #expect(try editor.block(at: 0).source == request.source)
    }

    @Test func aNewPassRebuildsTheRequestAfterAnEqualLengthBodyEdit() throws {
        let before = "render: table\nlimit: 7"
        let after = "render: table\nlimit: 9"
        let editor = entryPointEditor(entryPointNote(before))
        let first = try editor.click(at: 0)
        let host = editor.coordinator.viewBlockHosts.host(for: 0, in: editor.textView)
        // Same offsets and same line count deliberately exercise the stale-closure case.
        editor.style(entryPointNote(after))
        let second = try editor.click(at: 0)
        #expect(first.source == before)
        #expect(second.source == after)
        #expect(try editor.block(at: 0).source == second.source)
        #expect(editor.coordinator.viewBlockHosts.host(for: 0, in: editor.textView) === host)
    }

    // R-02/R-03: invalid and empty bodies must reach the fix-it flow unchanged.
    @Test(arguments: ["outsider: invalid", "", "  outsider: é 🧭  \n\ninvalid !!!  "])
    func anUnparseableFenceEmitsItsRawBody(source: String) throws {
        if !source.isEmpty {
            #expect(throws: ViewBlockError.self) { try ViewBlock.parse(source) }
        }
        let editor = entryPointEditor(entryPointNote(source))
        let request = try editor.click(at: 0)
        #expect(Array(request.source.utf8) == Array(source.utf8))
        #expect(try editor.block(at: 0).source == request.source)
    }

    @Test func twoFencesProduceDistinctSourcesInTheirOwnOrdinalSlots() throws {
        let firstSource = "outsider: invalid"
        let secondSource = "render: list"
        let editor = entryPointEditor(entryPointNote(firstSource) + entryPointNote(secondSource))
        // Reverse click order catches accidentally capturing the last loop iteration.
        let second = try editor.click(at: 1)
        let first = try editor.click(at: 0)
        #expect(first.source == firstSource)
        #expect(second.source == secondSource)
        #expect(first.source != second.source)
        let firstHost = editor.coordinator.viewBlockHosts.host(for: 0, in: editor.textView)
        let secondHost = editor.coordinator.viewBlockHosts.host(for: 1, in: editor.textView)
        #expect(firstHost !== secondHost)
    }

    @Test func editingAboveTheFenceKeepsTheHostAndRefreshesTheRequest() throws {
        let editor = entryPointEditor(entryPointNote("render: table"))
        let host = editor.coordinator.viewBlockHosts.host(for: 0, in: editor.textView)
        _ = try editor.click(at: 0)
        editor.style(entryPointNote("render: list\nlimit: 12", prefix: "New 🧭 line\nBefore\n"))
        let request = try editor.click(at: 0)
        #expect(request.source == "render: list\nlimit: 12")
        #expect(editor.coordinator.viewBlockHosts.host(for: 0, in: editor.textView) === host)
    }

    // R-01/C8 explicitly requires one declaration in header(renderer:count:), shared
    // by both branches. This structural assertion complements the value-tree checks.
    @Test func bothBranchesShareTheSingleHeaderEditControl() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Sources/Features/Views/RenderedViewBlock.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let code = source.replacingOccurrences(of: #"(?m)//[^\n]*"#, with: "", options: .regularExpression)
        let headerStart = try #require(code.range(of: "private func header("))
        let headerEnd = try #require(code.range(of: "private func ", range: headerStart.upperBound..<code.endIndex))
        let header = String(code[headerStart.lowerBound..<headerEnd.lowerBound])
        let identifier = "rendered-view-edit-query"
        #expect(code.components(separatedBy: identifier).count - 1 == 1)
        #expect(header.contains(identifier))
        for branch in ["failure", "success"] {
            let pattern = "case \\." + branch + #"\([^:]*\):\s*header\(renderer:"#
            #expect(code.range(of: pattern, options: .regularExpression) != nil)
        }
    }
}
