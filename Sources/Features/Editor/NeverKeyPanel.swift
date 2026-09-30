import AppKit

/// A panel that cannot become key, enforced rather than assumed (ADR-0074 §D9). Shared by
/// `CompletionPanel` and `FormatBarPanel`.
///
/// `.nonactivatingPanel` stops the *app* being activated; it does not stop the panel
/// itself becoming this app's key window, and a key panel is a text view that has
/// stopped receiving keystrokes. The whole design rests on the text view keeping first
/// responder while the panel is up, so the guarantee belongs in the type.
final class NeverKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The panel both editor popups float in. Only the size and the shadow differ between them:
    /// `FormatBarPanel` turns the window shadow off and draws its own.
    static func make(contentRect: NSRect, hasShadow: Bool) -> NSPanel {
        let panel = NeverKeyPanel(
            contentRect: contentRect,
            // `.nonactivatingPanel` is the one that matters, for the same reason it does
            // in the capture panel: showing this must not take focus from what is being
            // typed into, or the next keystroke would go nowhere.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = hasShadow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        // Mouse events still arrive - a window that cannot become key can still be clicked -
        // which is what makes a completion row or a format-bar button clickable while the
        // text view keeps the keyboard.
        panel.ignoresMouseEvents = false
        return panel
    }
}
