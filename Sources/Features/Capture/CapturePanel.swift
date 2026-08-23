import AppKit
import OSLog
import SwiftUI

/// The window the capture panel lives in: a floating, non-activating `NSPanel` that
/// appears over whatever application the user is in and gives the focus straight back
/// (ADR-0008 §D3).
///
/// A `Window` scene could not do this. SwiftUI has no way to say "do not activate my
/// app", and activating is precisely what must not happen: the whole feature is being
/// able to capture without leaving what you are doing.
@MainActor
final class CapturePanel {
    private var panel: EscapableCapturePanel?
    private let controller: CaptureController

    /// Read when the panel is shown rather than held, so a vault opened after launch is
    /// the one it writes to.
    private let session: () -> VaultSession?
    private let theme: () -> Theme
    private let shortcutCaption: () -> String?

    init(
        controller: CaptureController,
        session: @escaping () -> VaultSession?,
        theme: @escaping () -> Theme,
        shortcutCaption: @escaping () -> String?
    ) {
        self.controller = controller
        self.session = session
        self.theme = theme
        self.shortcutCaption = shortcutCaption
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the panel, or hides it when it is already up: the same key that opens it
    /// closes it, which is what a panel bound to one combination has to do.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        controller.prepare()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        centreOnActiveScreen(panel)

        // A `.nonactivatingPanel` never gets `windowDidBecomeKey` on its own, so key
        // status is taken explicitly; `orderFrontRegardless` is what puts it over an
        // application that is not ours.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // Read back from the panel rather than assumed: "ordered front" and "on screen
        // where the user is looking" are two different claims, and a panel sized to zero
        // or placed on the other display is invisible while every call above succeeded.
        Logger.capture.info(
            """
            pannello: visibile \(panel.isVisible, privacy: .public) \
            frame \(NSStringFromRect(panel.frame), privacy: .public) \
            schermo \(NSStringFromRect(panel.screen?.frame ?? .zero), privacy: .public)
            """
        )
    }

    func hide() {
        controller.hold()
        panel?.orderOut(nil)
    }

    // MARK: Building

    private var content: some View {
        CapturePanelView(
            controller: controller,
            session: session(),
            shortcutCaption: shortcutCaption(),
            onClose: { [weak self] in self?.hide() }
        )
        .environment(\.theme, theme())
    }

    private func makePanel() -> EscapableCapturePanel {
        let panel = EscapableCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
            // `.nonactivatingPanel` is the one that matters: without it, showing the
            // panel brings Pergamenum forward and the app the user was in loses focus.
            // No `.titled`: a titled window reserves titlebar height even with the
            // title and buttons hidden, and `setContentSize(_:)` does not subtract
            // it - the SwiftUI content ended up shorter than the window, leaving an
            // empty strip of raw panel background above the card. A borderless panel
            // has no titlebar to reserve space for, so the content fills the window.
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // A borderless window is opaque and square by default - `.titled` was what
        // gave it macOS's own rounded corners, along with the reserved titlebar
        // height. Without `.titled`, the window itself has to go transparent so only
        // `CapturePanelView`'s own rounded, shadowed card shows - otherwise the card
        // floats inside a square, opaque frame the same colour as the desktop behind
        // it, which reads as "a rectangle with a smaller rounded rectangle in it".
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        // Follows the user across Spaces, and `.fullScreenAuxiliary` is the attempt at
        // the limit Craft documents for itself - its panel does not appear over a
        // full-screen app. Whether this is enough here is a thing to try, not to assume.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onDismiss = { [weak self] in self?.hide() }
        return panel
    }

    /// Puts the panel where the pointer is, a third of the way down.
    ///
    /// The screen with the pointer rather than the main one: on two displays the panel
    /// appearing on the other monitor reads as it not appearing at all.
    private func centreOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY + frame.height / 6 - size.height / 2
        ))
    }
}

/// A panel that closes on Escape and can always reclaim keyboard focus with a click.
///
/// `CapturePanelView`'s `.onExitCommand` was the first attempt at Escape, and it is
/// silent: with the composer's `ComposerTextField` holding first responder (an
/// `NSTextField`, not a SwiftUI view), `cancelOperation:` reaches the field's editor
/// first, and an `NSTextField` field editor with nothing further to cancel does not
/// forward the action up the responder chain to where SwiftUI's exit-command handling
/// is listening - `.onExitCommand` never fires. Overriding `cancelOperation(_:)` here
/// catches it at the window itself, upstream of that dead end, regardless of which view
/// happens to have focus.
///
/// `canBecomeKey` matters for a different reason, found on screen: dropping `.titled`
/// from the panel's `styleMask` (to stop AppKit reserving titlebar height for a hidden
/// title bar) also dropped `NSWindow`'s default `canBecomeKeyWindow`, which is `true`
/// only when `.titled` is set. Losing it meant that once some other window took key
/// status - clicking anywhere else on screen - clicking back on this panel could not
/// give it back: not just Escape, typing itself stopped reaching the text field, the
/// panel sitting there inert until the hotkey was pressed again. Overriding it back to
/// `true` is the one line a borderless panel needs to stay interactive for its whole
/// life, not only for the first click that opened it.
private final class EscapableCapturePanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
