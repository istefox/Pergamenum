import AppKit
import SwiftUI

/// One row of the completion panel.
///
/// Two kinds because there are two things a completion can be. A `command` runs or writes
/// what the slash menu's catalogue says; a `text` is a candidate string - a note title, a
/// heading, a tag - that replaces what has been typed and nothing more. Keeping them in
/// one type is what lets a single panel, a single selection and a single set of keys serve
/// all four triggers.
enum CompletionItem: Identifiable, Equatable {
    case command(EditorCommand)
    case text(String, symbol: String)
    /// The one row that draws a glyph instead of an SF Symbol, because what it is offering
    /// *is* the glyph. SPEC §11.2's single stated exception.
    case emoji(glyph: String, name: String)

    var id: String {
        switch self {
        case .command(let command): "cmd:\(command.id)"
        case .text(let value, _): "txt:\(value)"
        case .emoji(let glyph, _): "emo:\(glyph)"
        }
    }

    var title: String {
        switch self {
        case .command(let command): command.title
        case .text(let value, _): value
        case .emoji(_, let name): name
        }
    }

    var symbol: String {
        switch self {
        case .command(let command): command.symbol
        case .text(_, let symbol): symbol
        // Never drawn - `CompletionPanelView` reaches for the glyph on this case - and
        // answered rather than trapped, so a future row that asks is not a crash.
        case .emoji: "face.smiling"
        }
    }

    /// Only a command carries one; a note title has no keyboard equivalent to teach.
    var shortcutCaption: String? {
        switch self {
        case .command(let command): command.shortcutCaption
        case .text, .emoji: nil
        }
    }

    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
}

/// The window every completion in the editor is drawn in (M8).
///
/// It began as the slash menu's own panel, because AppKit's completion list - the one
/// `[[`, `#` and `[[Nota#` used to use - cannot look like this app: it takes no design
/// token, shows no icon, and highlights with the system blue. Then the placement turned
/// out to be the more serious complaint (PG-023). AppKit puts its list wherever it likes,
/// and near the bottom edge of the window that is over the caret's own line or off the
/// screen entirely, so a completion started on the last lines of a note cannot be read.
///
/// `place(_:under:)` below is the whole fix, and it was already written: below the caret
/// when there is room, above the line when there is not, never past a screen edge. Moving
/// the other three triggers onto this panel deletes the defect rather than working around
/// it.
///
/// The panel never becomes key. The text view keeps first responder the whole time, which
/// is what lets typing carry on filtering the list, and it is why the keys are handled in
/// `CompletingTextView.doCommand(by:)` rather than here.
@MainActor
final class CompletionPanel {
    /// Everything the panel draws, which is one value because the three parts are computed
    /// together and consumed together: a list, what was typed to get it, and what to say
    /// when it came back empty. `noMatch` cannot be derived from the other two - an empty
    /// list carries no clue about which trigger produced it - and nil there means this
    /// trigger never shows an empty panel at all.
    struct Content: Equatable {
        var items: [CompletionItem]
        var query: String
        var noMatch: String?
    }

    private var panel: NSPanel?
    /// What the last `show` was given, so an arrow key can rebuild the list without the
    /// caller having to hand it all back.
    private(set) var content = Content(items: [], query: "", noMatch: nil)
    private(set) var selectedIndex = 0
    var items: [CompletionItem] { content.items }
    var noMatch: String? { content.noMatch }
    private var theme: Theme?
    /// Called when a row is clicked. The panel never acts on a choice itself: what an item
    /// means is the text view's business, and there is one place that decides it.
    var onChoose: ((CompletionItem) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }
    var selected: CompletionItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    // MARK: Showing

    /// Shows or updates the panel under the caret.
    ///
    /// `caretRect` is in screen coordinates, which is what
    /// `CompletingTextView.caretRectOnScreen()` hands over - converting it here by hand is
    /// how a popup ends up on the wrong display.
    func show(
        _ content: Content,
        caretRect: NSRect,
        over parent: NSWindow?,
        theme: Theme
    ) {
        // The selection follows the list rather than surviving it: after typing another
        // letter the third entry is a different command, and keeping the index would
        // silently move the choice under the user's hands.
        if content.items.map(\.id) != items.map(\.id) { selectedIndex = 0 }
        self.content = content
        self.theme = theme

        let panel = panel ?? makePanel()
        self.panel = panel
        // The height first, because it decides the placement: a panel taller than the room
        // on either side of the caret has nowhere to go that is not on top of the caret.
        let visible = Self.visibleFrame(containing: caretRect)
        lastMaxHeight = Self.roomForPanel(besides: caretRect, in: visible)
        render(into: panel, maxHeight: lastMaxHeight)
        panel.setFrameOrigin(
            Self.origin(forPanelOf: panel.frame.size, under: caretRect, in: visible)
        )

        if let parent, panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        content = Content(items: [], query: "", noMatch: nil)
        selectedIndex = 0
    }

    /// Moves the highlight, stopping at the ends rather than wrapping.
    ///
    /// Wrapping in a list this long turns "I have gone too far" into "where am I": the
    /// first press of Up at the top would jump to the bottom of forty-three entries.
    func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), items.count - 1)
        if let panel { render(into: panel, maxHeight: lastMaxHeight) }
    }

    /// Rebuilds the content for the current selection.
    ///
    /// A whole new `NSHostingView` on each arrow key, which sounds wasteful and is not:
    /// the list is at most forty-three rows and this runs on a key press. The cheaper
    /// shape - an `@Observable` model the SwiftUI view watches - buys nothing here and
    /// adds a second place where the selection lives.
    private func render(into panel: NSPanel, maxHeight: CGFloat) {
        guard let theme else { return }
        panel.contentView = NSHostingView(
            rootView: CompletionPanelView(
                items: content.items,
                query: content.query,
                noMatch: content.noMatch,
                selectedIndex: selectedIndex,
                maxHeight: maxHeight,
                onChoose: { [weak self] item in self?.onChoose?(item) }
            )
            .environment(\.theme, theme)
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
    }

    /// The last height the panel was rendered at, so an arrow key rebuilds it the same
    /// size rather than growing it back over the caret.
    private var lastMaxHeight: CGFloat = 320

    // MARK: Building

    /// A panel that cannot become key, enforced rather than assumed.
    ///
    /// `.nonactivatingPanel` stops the *app* being activated; it does not stop the panel
    /// itself becoming this app's key window, and a key panel is a text view that has
    /// stopped receiving keystrokes. The whole design rests on the text view keeping first
    /// responder while the list is up, so the guarantee belongs in the type.
    private final class NeverKeyPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private func makePanel() -> NSPanel {
        let panel = NeverKeyPanel(
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
        // Mouse events still arrive - a window that cannot become key can still be clicked -
        // which is what makes a row clickable.
        panel.ignoresMouseEvents = false
        return panel
    }

    /// The gap between the caret's line and the panel, and the margin kept from the screen.
    /// `nonisolated` because the placement rule is pure and is checked without a screen.
    nonisolated private static let gap: CGFloat = 6
    nonisolated private static let margin: CGFloat = 8

    nonisolated static func visibleFrame(containing caretRect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(caretRect) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    /// How tall the panel may be: the taller of the two sides of the caret's line.
    ///
    /// Asked before the panel is built, because the height decides the placement rather than
    /// following from it. Without this the list grew to its content, found room on neither
    /// side, and had to be put somewhere - and every "somewhere" that fits on the screen is
    /// on top of the line being typed into.
    nonisolated static func roomForPanel(besides caretRect: NSRect, in visible: NSRect) -> CGFloat {
        let below = caretRect.minY - visible.minY - gap - margin
        let above = visible.maxY - caretRect.maxY - gap - margin
        return max(below, above)
    }

    /// The placement rule, with no window in it so it can be checked without a screen.
    ///
    /// Screen coordinates throughout, so y grows upwards and below the caret means a smaller
    /// y. Under the line when it fits there, above it when it does not, and **never a clamp
    /// that crosses the line**: pulling a panel back inside the screen is what put it over
    /// the text the person was typing. If it fits on neither side it hangs off the screen
    /// edge instead, which is the honest failure of the two.
    nonisolated static func origin(
        forPanelOf size: NSSize, under caretRect: NSRect, in visible: NSRect
    ) -> NSPoint {
        var y = caretRect.minY - size.height - gap
        if y < visible.minY + margin { y = caretRect.maxY + gap }
        let x = min(
            max(caretRect.minX, visible.minX + margin),
            max(visible.minX + margin, visible.maxX - size.width - margin)
        )
        return NSPoint(x: x, y: y)
    }
}
