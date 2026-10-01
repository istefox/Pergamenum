import AppKit
import Testing
@testable import Pergamenum

// The editor's «nascondi frontmatter» toggle: the lines `NoteFolding.hiddenFrontmatter` names,
// the pass that applies them and the caret rescue that goes with it.

@Suite struct HiddenFrontmatterLines {
    @Test func namesEveryLineOfTheBlockAndWhereTheBodyStarts() {
        let text = "---\ntags: [a]\n---\n# Titolo\ncorpo\n"
        let hidden = NoteFolding.hiddenFrontmatter(in: text)
        #expect(hidden?.lineOffsets == [0, 4, 14])
        #expect(hidden?.firstVisibleOffset == 18)
    }

    @Test func crlfNumbersItsLinesLikeItsLfTwin() {
        let text = "---\r\ntags: [a]\r\n---\r\n# Titolo\r\n"
        let hidden = NoteFolding.hiddenFrontmatter(in: text)
        #expect(hidden?.lineOffsets == [0, 5, 16])
        #expect(hidden?.firstVisibleOffset == 21)
    }

    @Test func aNoteWithoutFrontmatterHidesNothing() {
        #expect(NoteFolding.hiddenFrontmatter(in: "# Titolo\ncorpo\n") == nil)
        #expect(!NoteFrontmatter.exists(in: "# Titolo\n---\n"))
    }

    @Test func anUnclosedBlockIsNotFrontmatter() {
        #expect(NoteFolding.hiddenFrontmatter(in: "---\ntags: [a]\ncorpo\n") == nil)
    }

    @Test func aNoteThatIsOnlyFrontmatterResumesAtItsEnd() {
        let text = "---\ntags: [a]\n---"
        let hidden = NoteFolding.hiddenFrontmatter(in: text)
        #expect(hidden?.lineOffsets == [0, 4, 14])
        #expect(hidden?.firstVisibleOffset == text.utf16.count)
    }
}

@Suite @MainActor struct HiddenFrontmatterPass {
    private static func editor(_ text: String) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        coordinator.textView = textView
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        return (textView, coordinator)
    }

    @Test func aCaretInsideTheHiddenBlockMovesToTheFirstLineAfterIt() {
        let note = "---\ntags: [a]\n---\n# Titolo\ncorpo\n"
        let (textView, coordinator) = Self.editor(note)
        coordinator.applyStyling(to: textView, theme: .emergency)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        coordinator.applyFolding(to: textView, folded: [], hidesFrontmatter: true, theme: .emergency)

        #expect(textView.selectedRange() == NSRange(location: 18, length: 0))
    }

    @Test func showingTheBlockAgainLeavesTheCaretAlone() {
        let note = "---\ntags: [a]\n---\n# Titolo\n"
        let (textView, coordinator) = Self.editor(note)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyFolding(to: textView, folded: [], hidesFrontmatter: true, theme: .emergency)
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        coordinator.applyFolding(to: textView, folded: [], hidesFrontmatter: false, theme: .emergency)

        #expect(textView.selectedRange() == NSRange(location: 20, length: 0))
        #expect(coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty)
    }
}

@Suite struct HiddenFrontmatterTabState {
    @Test func aTabStartsWithTheBlockShownAndAnotherNoteResetsIt() {
        let note = VaultController.OpenNote(
            relativePath: "a.md", title: "a", text: "---\n---\n", savedText: "---\n---\n"
        )
        var tab = NoteTab(note: note)
        #expect(!tab.hidesFrontmatter)
        tab.hidesFrontmatter = true
        #expect(!tab.showing(note).hidesFrontmatter)
    }
}
