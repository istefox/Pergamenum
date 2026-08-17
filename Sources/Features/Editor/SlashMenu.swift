import AppKit
import SwiftUI

/// The window the slash menu is drawn in (M8).
///
/// The first version of this menu used AppKit's completion list, the one `[[` and `#`
/// still use, and that was the right way to start: arrow keys, Escape, scrolling and
/// placement near the caret all came free. What it cannot do is look like this app. A
/// system list takes no design token, shows no icon, and highlights with the system blue,
/// and `EditorCommand.symbol` sat unused because there was nowhere to draw it.
///
/// So this panel replaces it **for the slash menu only**. A list of note titles after
/// `[[` is exactly what AppKit's list is for and keeps using it; a command palette is not.
///
/// The panel never becomes key. The text view keeps first responder the whole time, which
/// is what lets typing carry on filtering the list, and it is why the keys are handled in
/// `CompletingTextView.doCommandBySelector` rather than here.
@MainActor
final class SlashMenu {
    private var panel: NSPanel?
    private(set) var commands: [EditorCommand] = []
    private(set) var selectedIndex = 0
    /// What the last `show` was given, so an arrow key can rebuild the list without the
    /// caller having to hand it all back.
    private var query = ""
    private var theme: Theme?

    var isVisible: Bool { panel?.isVisible ?? false }
    var selected: EditorCommand? {
        commands.indices.contains(selectedIndex) ? commands[selectedIndex] : nil
    }

    // MARK: Showing

    /// Shows or updates the menu under the caret.
    ///
    /// `caretRect` is in screen coordinates, which is what
    /// `firstRect(forCharacterRange:actualRange:)` already returns - converting it by hand
    /// is how a popup ends up on the wrong display.
    func show(
        _ commands: [EditorCommand],
        query: String,
        caretRect: NSRect,
        over parent: NSWindow?,
        theme: Theme
    ) {
        // The selection follows the list rather than surviving it: after typing another
        // letter the third entry is a different command, and keeping the index would
        // silently move the choice under the user's hands.
        if commands.map(\.id) != self.commands.map(\.id) { selectedIndex = 0 }
        self.commands = commands
        self.query = query
        self.theme = theme

        let panel = panel ?? makePanel()
        self.panel = panel
        render(into: panel)
        place(panel, under: caretRect)

        if let parent, panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        commands = []
        selectedIndex = 0
    }

    /// Moves the highlight, stopping at the ends rather than wrapping.
    ///
    /// Wrapping in a list this long turns "I have gone too far" into "where am I": the
    /// first press of Up at the top would jump to the bottom of forty-three entries.
    func moveSelection(by offset: Int) {
        guard !commands.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), commands.count - 1)
        if let panel { render(into: panel) }
    }

    /// Rebuilds the content for the current selection.
    ///
    /// A whole new `NSHostingView` on each arrow key, which sounds wasteful and is not:
    /// the list is at most forty-three rows and this runs on a key press. The cheaper
    /// shape - an `@Observable` model the SwiftUI view watches - buys nothing here and
    /// adds a second place where the selection lives.
    private func render(into panel: NSPanel) {
        guard let theme else { return }
        panel.contentView = NSHostingView(
            rootView: SlashMenuView(commands: commands, query: query, selectedIndex: selectedIndex)
                .environment(\.theme, theme)
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
    }

    // MARK: Building

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            // `.nonactivatingPanel` is the one that matters, for the same reason it does
            // in the capture panel: showing this must not take focus from what is being
            // typed into, or the next keystroke would go nowhere.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        // Never key and never main: the text view keeps first responder, which is the
        // whole design.
        panel.ignoresMouseEvents = false
        return panel
    }

    /// Below the caret, or above it when there is no room, and never off the screen edge.
    private func place(_ panel: NSPanel, under caretRect: NSRect) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(caretRect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height - 6)
        // Not enough room underneath: flip above the line rather than clipping.
        if origin.y < visible.minY {
            origin.y = caretRect.maxY + 6
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
    }
}
