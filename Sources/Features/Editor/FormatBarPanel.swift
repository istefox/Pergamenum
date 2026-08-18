import AppKit
import SwiftUI

/// The panel the format bar floats in (SPEC §10, M8).
///
/// A child window and not a SwiftUI overlay, for the reason `CompletionPanel` is one: it has
/// to hang over the text at a position taken from a character range, and the text view has to
/// keep first responder the whole time. Everything structural here is that panel's, deliberately
/// - a window that cannot become key, a hosting view inside it, and the action handed straight
/// back out rather than acted on here.
@MainActor
final class FormatBarPanel {
    private var panel: NSPanel?
    private var theme: Theme?
    /// Which buttons are lit, meaning «the selection already has this, and pressing me takes
    /// it away».
    private var applied: Set<InlineFormat> = []

    /// Room around the pill that belongs to the shadow and to nothing else.
    ///
    /// `panel.hasShadow` used to do this job and drew a second, AppKit-computed shadow around
    /// whatever alpha the window's backing store carried at its own edge - which is where the
    /// pixel-by-pixel look at Stefano's screenshot found a hard dark ring immediately followed
    /// by a bright one, tracing the capsule exactly rather than the panel's rectangle, at every
    /// edge including the rounded ends. Two shadows drawn by two different systems is a stray
    /// line neither one intends. This margin is what lets the single shadow SwiftUI already
    /// draws - `.themedShadow(.raised)`, in `FormatBar` - have room to render at all once the
    /// native one is turned off; the window's own bounds would otherwise clip it flush against
    /// the pill.
    private static let shadowMargin: CGFloat = 24

    /// The pill's own size, without the invisible margin around it - what `PanelPlacement`
    /// reasons about, so the gap it computes lands beside the pill rather than beside the
    /// padded window that carries it.
    private var pillSize: NSSize = .zero

    /// Called with what was pressed. The panel never edits the note itself: what a button
    /// means is the text view's business, and there is one place that decides it.
    var onChoose: ((FormatBar.Action) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows or updates the bar beside `selectionRect`, in screen coordinates - which is what
    /// `CompletingTextView.caretRectOnScreen()` hands over. Converting by hand here is how a
    /// popup ends up on the wrong display.
    func show(
        applied: Set<InlineFormat>, selectionRect: NSRect, preferring side: PanelPlacement.Side,
        over parent: NSWindow?, theme: Theme
    ) {
        self.applied = applied
        self.theme = theme

        let panel = panel ?? makePanel()
        self.panel = panel
        render(into: panel)

        let visible = PanelPlacement.visibleFrame(containing: selectionRect)
        // Which side is the caller's: a one-line selection wants the bar above it, a selection
        // spanning several wants it below its last line, because above that line is the middle
        // of what is selected. Either way the flip when there is no room is the same rule the
        // completion panel uses.
        //
        // `pillSize`, not `panel.frame.size`: the panel is `shadowMargin` points bigger on
        // every side so the shadow has somewhere to draw, and placing *that* beside the
        // selection would leave a gap of `gap + shadowMargin` instead of the six points the
        // mockup shows.
        let pillOrigin = PanelPlacement.origin(
            forPanelOf: pillSize, besides: selectionRect, in: visible, preferring: side
        )
        panel.setFrameOrigin(NSPoint(
            x: pillOrigin.x - Self.shadowMargin, y: pillOrigin.y - Self.shadowMargin
        ))

        if let parent, panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
    }

    private func render(into panel: NSPanel) {
        guard let theme else { return }
        let hosting = NSHostingView(
            rootView: FormatBar(
                applied: applied,
                onChoose: { [weak self] action in self?.onChoose?(action) }
            )
            .environment(\.theme, theme)
            // The invisible canvas `shadowMargin` promises. Padding rather than a fixed
            // frame, so the pill still centres itself as the button set's width changes.
            .padding(Self.shadowMargin)
        )
        // `panel.isOpaque = false` and `.backgroundColor = .clear` are the window's own
        // half of this; the hosting view is layer-backed and paints its *own* opaque fill
        // behind whatever SwiftUI draws unless told not to. `CompletionPanel` never shows
        // it because its content is a `RoundedRectangle` covering the panel edge to edge -
        // this bar is a `Capsule` narrower than its own bounding box, and the four corners
        // outside the curve would otherwise be that fill showing through.
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        let padded = hosting.fittingSize
        pillSize = NSSize(
            width: padded.width - Self.shadowMargin * 2, height: padded.height - Self.shadowMargin * 2
        )
        panel.setContentSize(padded)
    }

    /// A panel that cannot become key, enforced rather than assumed - the same guarantee
    /// `CompletionPanel.NeverKeyPanel` makes, and for the same reason: `.nonactivatingPanel`
    /// stops the *app* being activated and does not stop the panel becoming this app's key
    /// window, and a key panel is a text view that has stopped receiving keystrokes.
    private final class NeverKeyPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private func makePanel() -> NSPanel {
        let panel = NeverKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // Not `true`: a window with `hasShadow` computes its own shadow from the alpha of
        // whatever the backing store holds, and for a shape as tight as this capsule that
        // computation is what put a ring around the pill - a hard dark line right at the
        // capsule's edge with a bright one immediately inside it, on every side including
        // the rounded ends, found by sampling the screenshot pixel by pixel rather than by
        // eye. `FormatBar`'s own `.themedShadow(.raised)` is the only shadow this panel
        // shows now, and `shadowMargin` above is what gives it room to draw.
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        // A window that cannot become key can still be clicked, which is what makes the
        // buttons work while the note keeps the keyboard.
        panel.ignoresMouseEvents = false
        return panel
    }
}
