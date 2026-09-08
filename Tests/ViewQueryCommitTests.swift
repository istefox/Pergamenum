import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// Task 4, R-13: expectations come from the batch brief. Production declarations and
// stubs belong to the coder. No test-side implementation of the commit or its guards.

@MainActor
private final class CommitModel {
    var text: String

    init(_ text: String) { self.text = text }
}

@MainActor
private struct CommitEditor {
    let model: CommitModel
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let window: NSWindow

    func request(at offset: Int, source: String) -> ViewQueryEditRequest {
        ViewQueryEditRequest(id: UUID(), source: source) { body in
            coordinator.commitViewBlock(body, at: offset, in: textView)
        }
    }

    // Model and buffer advance together, as with an edit while the sheet is open.
    // The request must retain the earlier source even after both have advanced.
    func setLiveText(_ text: String) {
        model.text = text
        textView.string = text
    }
}

// Real NSTextView/storage/responder chain, copied from the existing editor fixtures.
@MainActor
private func commitEditor(_ text: String) -> CommitEditor {
    let model = CommitModel(text)
    let view = NoteTextView(
        text: Binding(get: { model.text }, set: { model.text = $0 }),
        theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)

    let window = NSWindow(
        contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = textView
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    coordinator.applyStyling(to: textView, theme: .emergency)
    window.makeFirstResponder(textView)
    textView.undoManager?.removeAllActions()
    return CommitEditor(model: model, textView: textView, coordinator: coordinator, window: window)
}

private enum CommitFixture {
    static let prefix = "Before 🧭 e\u{301}\n\n"
    static let body = "render: table"
    static let fence = "```pergamenum-view\nrender: table\n```"
    static let suffix = "\n\nAfter é 🧭\n"
    static let replacementBody = "render: list\nlimit: 7"
    static let replacement = "```pergamenum-view\nrender: list\nlimit: 7\n```"
    static let opening = (prefix as NSString).length
    static let note = prefix + fence + suffix
}

@MainActor
@Suite(.serialized)
struct ViewQueryCommitTests {
    // R-13: UTF-16 anchor, byte-identical surroundings, closing newline excluded.
    @Test func happyPathReplacesOnlyTheClosedFence() throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)

        #expect(request.commit(CommitFixture.replacementBody))
        let expected = CommitFixture.prefix + CommitFixture.replacement + CommitFixture.suffix
        #expect(Array(fixture.textView.string.utf8) == Array(expected.utf8))
        let run = try #require(EditorDecorationDelegate.viewBlockRun(
            in: fixture.textView.string as NSString, atParagraphStart: CommitFixture.opening
        ))
        #expect(run.range == NSRange(
            location: CommitFixture.opening, length: (CommitFixture.replacement as NSString).length
        ))
    }

    // R-13: start/end of note and zero/one/two newlines after the closing fence.
    @Test(arguments: ["", "\n", "\n\n"])
    func replacementDoesNotAppendOrSwallowATrailingNewline(suffix: String) {
        let fixture = commitEditor(CommitFixture.fence + suffix)
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.coordinator.commitViewBlock(CommitFixture.replacementBody, at: 0, in: fixture.textView))
        #expect(fixture.textView.string == CommitFixture.replacement + suffix)
    }

    // R-13: require a real undo manager, successful write, and no residual undo layer.
    @Test func exactlyOneUndoRestoresTheWholeNote() throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        #expect(!undo.canUndo)

        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)
        #expect(request.commit(CommitFixture.replacementBody))
        #expect(fixture.textView.string == CommitFixture.prefix + CommitFixture.replacement + CommitFixture.suffix)
        #expect(undo.canUndo)
        undo.undo()
        #expect(Array(fixture.textView.string.utf8) == Array(CommitFixture.note.utf8))
        #expect(!undo.canUndo)
        undo.undo()
        #expect(Array(fixture.textView.string.utf8) == Array(CommitFixture.note.utf8))
    }

    // R-13: a request's old opening offset cannot follow a fence that moved.
    @Test func insertingALineAboveTheFenceRefusesTheOldRequest() throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)
        let current = "Inserted line above the note\n" + CommitFixture.note
        fixture.setLiveText(current)

        try expectRefusal(request, fixture: fixture, current: current)
    }

    // R-13: no live run at the stored offset, including an offset beyond the new EOF.
    @Test(arguments: ["Before only\n", "Before 🧭 e\u{301}\n\nThe fence was deleted\n"])
    func deletingTheFenceRefusesTheOldRequest(current: String) throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)
        fixture.setLiveText(current)
        #expect(EditorDecorationDelegate.viewBlockRun(
            in: current as NSString, atParagraphStart: CommitFixture.opening
        ) == nil)

        try expectRefusal(request, fixture: fixture, current: current)
    }

    // R-13: equal-length changes defeat a range-only guard. Both live copies agree;
    // only the source recorded when the request opened can identify this stale request.
    @Test func changingTheFenceTextAtTheSameOffsetRefusesTheOldRequest() throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)
        let current = CommitFixture.note.replacingOccurrences(of: "render: table", with: "render: board")
        fixture.setLiveText(current)
        #expect((current as NSString).length == (CommitFixture.note as NSString).length)
        let run = try #require(EditorDecorationDelegate.viewBlockRun(
            in: current as NSString, atParagraphStart: CommitFixture.opening
        ))
        #expect(run.range.location == CommitFixture.opening)

        try expectRefusal(request, fixture: fixture, current: current)
    }

    // R-13: model/buffer divergence in either direction, with and without a live run.
    @Test(arguments: [true, false], ["render: board", "plain text"])
    func divergentModelAndBufferRefuseTheWrite(changeModel: Bool, replacement: String) throws {
        let fixture = commitEditor(CommitFixture.note)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)
        let changed = replacement == "plain text"
            ? CommitFixture.prefix + replacement + CommitFixture.suffix
            : CommitFixture.note.replacingOccurrences(of: CommitFixture.body, with: replacement)
        if changeModel {
            fixture.model.text = changed
        } else {
            fixture.textView.string = changed
        }
        let current = fixture.textView.string
        #expect(fixture.model.text != current)

        try expectRefusal(request, fixture: fixture, current: current)
    }

    // R-13: the canonical opening replaces indentation and trailing spaces as well.
    @Test func normalizesTheOpeningLineAndLeavesAParseableFence() throws {
        let original = CommitFixture.prefix + "  ```pergamenum-view   \nrender: table\n```" + CommitFixture.suffix
        let fixture = commitEditor(original)
        defer { fixture.window.orderOut(nil) }
        let request = fixture.request(at: CommitFixture.opening, source: CommitFixture.body)

        #expect(request.commit(CommitFixture.replacementBody))
        #expect(fixture.textView.string == CommitFixture.prefix + CommitFixture.replacement + CommitFixture.suffix)
        let run = try #require(EditorDecorationDelegate.viewBlockRun(
            in: fixture.textView.string as NSString, atParagraphStart: CommitFixture.opening
        ))
        let writtenFence = (fixture.textView.string as NSString).substring(with: run.range)
        let writtenBody = writtenFence.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst().dropLast().joined(separator: "\n")
        let parsed = try ViewBlock.parse(writtenBody)
        #expect(parsed.render == .list)
        #expect(parsed.limit == 7)
    }

    private func expectRefusal(
        _ request: ViewQueryEditRequest, fixture: CommitEditor, current: String
    ) throws {
        let undo = try #require(fixture.textView.undoManager)
        undo.removeAllActions()
        let previousModel = fixture.model.text
        #expect(!request.commit(CommitFixture.replacementBody))
        #expect(Array(fixture.textView.string.utf8) == Array(current.utf8))
        #expect(Array(fixture.model.text.utf8) == Array(previousModel.utf8))
        #expect(!undo.canUndo)
    }
}
