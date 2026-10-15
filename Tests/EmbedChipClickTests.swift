import AppKit
import Testing
@testable import Pergamenum

// (coverage) ADR-0087 §D9, plan docs/plans/note-workflow-n5.md, Task 7: `previewChip(at:in:)`, the
// `onClickInMargin` claimant for an embed chip (`NoteTextView+EmbedChip.swift`). Its documented
// contract is in the file's header: a plain click on the pill of a chip whose paragraph is not
// revealed opens the file through `onOpenEmbed`; a revealed paragraph shows the raw `![[…]]`, and a
// click there places the caret, so it claims nothing.
//
// Driven through a real `NoteTextView` offscreen. The pill is found the way the painter finds it
// (`InlineChipPainter.rects`), in the fragment's coordinates, then moved into the view's, which is
// where a click arrives.

@MainActor
@Suite struct EmbedChipClick {
    private static let note = "intro\n\nvedi ![[scheda.pdf]] fine\n"
    private static let paragraph = 7

    private static func editor(
        caret: Int = 0, hidesMarkup: Bool = true, onOpen: ((String) -> Void)?
    ) -> N5Editor.Built {
        var vault = NoteTextView.VaultInputs()
        vault.onOpenEmbed = onOpen
        return N5Editor.build(note, hidesMarkup: hidesMarkup, caret: caret, vault: vault)
    }

    /// The embed chip's pill, in the view's coordinates; `.null` when the paragraph draws none.
    private static func pill(in built: N5Editor.Built) -> CGRect {
        guard let fragment = N5Editor.fragments(built)[paragraph],
              let text = fragment.textLineFragments.first?.attributedString
        else { return .null }
        var found: CGRect = .null
        text.enumerateAttribute(.pergamenumChip, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            guard (value as? InlineChip.Style)?.symbolName != nil else { return }
            let padding = built.coordinator.decorations.constructStyle.chip.padding
            found = InlineChipPainter.rects(for: range, in: fragment, padding: padding).first ?? .null
            stop.pointee = true
        }
        guard !found.isNull else { return .null }
        let frame = fragment.layoutFragmentFrame
        let origin = built.textView.textContainerOrigin
        return found.offsetBy(dx: frame.minX + origin.x, dy: frame.minY + origin.y)
    }

    @Test func aPlainClickOnThePillOpensTheFileItNames() {  // R-40 (coverage)
        var opened: [String] = []
        let built = Self.editor { opened.append($0) }

        let box = Self.pill(in: built)
        #expect(box.width > 0)
        #expect(built.coordinator.previewChip(at: CGPoint(x: box.midX, y: box.midY), in: built.textView, modifiers: []))
        #expect(opened == ["scheda.pdf"])
    }

    @Test func aCommandClickOnThePillIsLeftToTheText() {  // R-40 (coverage)
        var opened: [String] = []
        let built = Self.editor { opened.append($0) }

        let box = Self.pill(in: built)
        #expect(box.width > 0)
        let center = CGPoint(x: box.midX, y: box.midY)
        #expect(!built.coordinator.previewChip(at: center, in: built.textView, modifiers: .command))
        #expect(opened.isEmpty)
    }

    @Test func onlyCommandShiftOptionAndControlMakeAClickNotPlain() {  // R-40 (coverage)
        typealias Coordinator = NoteTextView.Coordinator
        #expect(Coordinator.isPlainClick([]))
        #expect(Coordinator.isPlainClick([.capsLock, .function, .numericPad]))
        for flag: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            #expect(!Coordinator.isPlainClick(flag), "\(flag)")
            #expect(!Coordinator.isPlainClick([flag, .capsLock]), "\(flag) with Caps Lock")
        }
    }

    @Test func aClickOnTheProseBesideTheChipBelongsToTheText() {  // R-40 (coverage)
        var opened: [String] = []
        let built = Self.editor { opened.append($0) }

        let box = Self.pill(in: built)
        #expect(box.width > 0)
        // `vedi ` sits to the left of the pill, on the same line.
        let onTheProse = CGPoint(x: max(1, box.minX - 30), y: box.midY)
        #expect(!built.coordinator.previewChip(at: onTheProse, in: built.textView))
        #expect(opened.isEmpty)
    }

    @Test func withTheCaretInTheParagraphTheRawSyntaxIsShownAndTheClickPlacesTheCaret() {  // R-40 (coverage)
        var opened: [String] = []
        let built = Self.editor(caret: 16) { opened.append($0) }

        // The pill is where it was drawn off the caret; the paragraph is now revealed.
        let unrevealed = Self.editor(caret: 0) { _ in }
        let box = Self.pill(in: unrevealed)
        #expect(box.width > 0)
        #expect(!built.coordinator.previewChip(at: CGPoint(x: box.midX, y: box.midY), in: built.textView))
        #expect(opened.isEmpty)
    }

    @Test func withMarkupShownAsWrittenThereIsNoPillToClick() {  // R-40 (coverage)
        var opened: [String] = []
        let built = Self.editor(hidesMarkup: false) { opened.append($0) }

        #expect(!built.coordinator.previewChip(at: CGPoint(x: 120, y: 70), in: built.textView))
        #expect(opened.isEmpty)
    }

    @Test func anEditorWithNoOpenHandlerClaimsNothing() {  // R-40 (coverage)
        let built = Self.editor(onOpen: nil)
        let box = Self.pill(in: built)
        #expect(box.width > 0)
        #expect(!built.coordinator.previewChip(at: CGPoint(x: box.midX, y: box.midY), in: built.textView))
    }

    @Test func aParagraphWithNoChipClaimsNothing() {  // R-40 (coverage)
        var opened: [String] = []
        var vault = NoteTextView.VaultInputs()
        vault.onOpenEmbed = { opened.append($0) }
        let built = N5Editor.build("intro\n\nsolo prosa qui\n", caret: 0, vault: vault)

        #expect(!built.coordinator.previewChip(at: CGPoint(x: 100, y: 70), in: built.textView))
        #expect(opened.isEmpty)
    }
}
