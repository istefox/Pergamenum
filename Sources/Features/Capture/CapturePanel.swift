import AppKit
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
    private var panel: NSPanel?
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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
            // `.nonactivatingPanel` is the one that matters: without it, showing the
            // panel brings Pergamenum forward and the app the user was in loses focus.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
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
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
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
