import AppKit
import Testing
@testable import Pergamenum

// (coverage) ADR-0087 §D8, plan docs/plans/note-workflow-n5.md, Task 6: `toggleCallout(at:in:)`, the
// `onClickInMargin` claimant for a callout title's chevron (`NoteTextView+CalloutClick.swift`).
// Its documented contract is in the file's own header: it claims only a click inside the chevron, so a
// click on the title places the caret; it claims nothing where the callout is not foldable, where the
// note holds no `[!`, or where the editor passes no `onToggleCallout` (Diario and Oggi).
//
// Driven through a real `NoteTextView` offscreen, the way `FoldBadgeClick` drives the heading badge: a
// decoration's rectangle is in the text container's coordinates and a click arrives in the view's.

@MainActor
@Suite struct CalloutChevronClick {
    private static let folded = "intro\n\n> [!avviso]- Titolo\n> uno\n> due\n\nfine\n"
    private static let open = "intro\n\n> [!tip]+ Titolo\n> uno\n\nfine\n"
    private static let fixed = "intro\n\n> [!note] Titolo\n> uno\n\nfine\n"
    private static let title = 7

    private static func editor(_ note: String, onToggle: ((Int) -> Void)?) -> N5Editor.Built {
        let built = N5Editor.build(note, caret: 0, outline: .init(onToggleCallout: onToggle))
        // The fold pass decides whether a title draws a chevron (it needs a wired toggle), as in the app.
        built.coordinator.applyFolding(to: built.textView, folded: [], theme: built.theme)
        return built
    }

    /// The chevron's rectangle in the view's coordinates, `.null` when the title draws none.
    private static func chevron(in built: N5Editor.Built) -> CGRect {
        guard let fragment = N5Editor.fragments(built)[title] as? CalloutTitleFragment,
              let frame = fragment.chevronFrameInContainer
        else { return .null }
        let origin = built.textView.textContainerOrigin
        return frame.offsetBy(dx: origin.x, dy: origin.y)
    }

    @Test func aClickOnTheChevronClaimsTheClickAndReportsTheTitleOffset() { // R-38 (coverage)
        var toggled: [Int] = []
        let built = Self.editor(Self.folded) { toggled.append($0) }

        let box = Self.chevron(in: built)
        #expect(box.width > 0)
        let claimed = built.coordinator.toggleCallout(
            at: CGPoint(x: box.midX, y: box.midY), in: built.textView, modifiers: []
        )
        #expect(claimed)
        #expect(toggled == [Self.title])
    }

    @Test func aModifiedClickOnTheChevronBelongsToTheText() { // R-38 (coverage)
        // Command, Shift, Option or Control keep their text-view meaning, as on an embed chip.
        var toggled: [Int] = []
        let built = Self.editor(Self.folded) { toggled.append($0) }

        let box = Self.chevron(in: built)
        #expect(box.width > 0)
        let center = CGPoint(x: box.midX, y: box.midY)
        for flags: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            #expect(!built.coordinator.toggleCallout(at: center, in: built.textView, modifiers: flags), "\(flags)")
        }
        #expect(toggled.isEmpty)
        // Caps Lock is not a modifier of the click.
        #expect(built.coordinator.toggleCallout(at: center, in: built.textView, modifiers: .capsLock))
        #expect(toggled == [Self.title])
    }

    @Test func aPlusCalloutsChevronAnswersToo() { // R-38 (coverage)
        var toggled: [Int] = []
        let built = Self.editor(Self.open) { toggled.append($0) }

        let box = Self.chevron(in: built)
        #expect(box.width > 0)
        #expect(built.coordinator.toggleCallout(
            at: CGPoint(x: box.midX, y: box.midY), in: built.textView, modifiers: []
        ))
        #expect(toggled == [Self.title])
    }

    @Test func aClickOnTheTitleTextBelongsToTheText() { // R-38 (coverage)
        // Swallowing it would stop a click placing the caret in the title.
        var toggled: [Int] = []
        let built = Self.editor(Self.folded) { toggled.append($0) }

        let box = Self.chevron(in: built)
        #expect(box.width > 0)
        let onTheTitle = CGPoint(x: max(1, box.minX - 120), y: box.midY)
        #expect(!built.coordinator.toggleCallout(at: onTheTitle, in: built.textView))
        #expect(toggled.isEmpty)
    }

    @Test func aClickOnABodyLineBelongsToTheText() { // R-38 (coverage)
        var toggled: [Int] = []
        let built = Self.editor(Self.open) { toggled.append($0) }

        let box = Self.chevron(in: built)
        // One line height below the chevron is the first body line, at the same x.
        let onTheBody = CGPoint(x: box.midX, y: box.maxY + 20)
        #expect(!built.coordinator.toggleCallout(at: onTheBody, in: built.textView))
        #expect(toggled.isEmpty)
    }

    @Test func aCalloutWithNoSignHasNoChevronToClick() { // R-38 (coverage)
        // The rectangle exists as arithmetic even for a callout that cannot fold, so the hit test is
        // guarded by the fold state and not only by the geometry.
        var toggled: [Int] = []
        let built = Self.editor(Self.fixed) { toggled.append($0) }

        #expect(Self.chevron(in: built).isNull)
        for x in stride(from: 20.0, through: 560.0, by: 20.0) {
            #expect(!built.coordinator.toggleCallout(at: CGPoint(x: x, y: 70), in: built.textView), "x \(x)")
        }
        #expect(toggled.isEmpty)
    }

    @Test func aNoteWithNoCalloutClaimsNothing() { // R-38 (coverage)
        var toggled: [Int] = []
        let built = Self.editor("intro\n\n> citazione\n\nfine\n") { toggled.append($0) }
        #expect(!built.coordinator.toggleCallout(at: CGPoint(x: 300, y: 70), in: built.textView))
        #expect(toggled.isEmpty)
    }

    @Test func anEditorWithNoToggleHandlerClaimsNothing() { // R-38 (coverage)
        // Diario and Oggi pass none and draw the file's default (plan Task 6). A callout folds only where
        // a toggle can open it, so here the title draws no chevron at all (it used to draw one that did
        // nothing, over a body left hidden); the click is tried where the wired editor draws its chevron.
        let wired = Self.chevron(in: Self.editor(Self.folded) { _ in })
        #expect(wired.width > 0)
        let built = Self.editor(Self.folded, onToggle: nil)
        #expect(Self.chevron(in: built).isNull)
        #expect(!built.coordinator.toggleCallout(at: CGPoint(x: wired.midX, y: wired.midY), in: built.textView))
    }
}
