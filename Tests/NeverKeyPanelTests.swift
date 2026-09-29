import AppKit
import Testing
@testable import Pergamenum

// ADR-0071 §D9, plan pg-144 Task 2 (R-03). Pins the contract of the shared `NeverKeyPanel.make`,
// which `CompletionPanel` and `FormatBarPanel` both build their panel with. Builds the panel only
// and never orders it front: no test takes the screen.

@MainActor
struct NeverKeyPanelTests {
    private func make(shadow: Bool = true) -> NSPanel {
        NeverKeyPanel.make(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), hasShadow: shadow)
    }

    @Test func isANeverKeyPanelThatCannotBecomeKeyOrMain() {
        let panel = make()
        #expect(panel is NeverKeyPanel)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test func styleMaskIsBorderlessNonactivating() {
        #expect(make().styleMask == [.borderless, .nonactivatingPanel])
    }

    @Test func floatsAtPopUpMenuLevel() {
        let panel = make()
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .popUpMenu)
    }

    @Test func shadowIsAsPassed() {
        #expect(make(shadow: true).hasShadow)
        #expect(!make(shadow: false).hasShadow)
    }

    @Test func contentRectIsAsPassed() {
        let panel = NeverKeyPanel.make(contentRect: NSRect(x: 0, y: 0, width: 240, height: 32), hasShadow: false)
        #expect(panel.contentRect(forFrameRect: panel.frame).size == NSSize(width: 240, height: 32))
    }

    @Test func backgroundIsClearAndNotOpaque() {
        let panel = make()
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isOpaque)
    }

    @Test func lifecycleFlags() {
        let panel = make()
        #expect(panel.hidesOnDeactivate)
        #expect(panel.animationBehavior == .utilityWindow)
        #expect(!panel.isReleasedWhenClosed)
    }

    @Test func doesNotIgnoreMouseEvents() {
        #expect(!make().ignoresMouseEvents)
    }
}
