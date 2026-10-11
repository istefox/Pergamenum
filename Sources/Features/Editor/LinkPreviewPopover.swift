import AppKit
import SwiftUI

// ADR-0083 §D7 (PG-386, N3 session B).

/// Where the Cmd+hover preview is shown. A seam because a hosted test never orders a window
/// front, so a spy stands in; the real popover is proved by one GUI test.
@MainActor
protocol LinkPreviewPresenting: AnyObject {
    var isShowing: Bool { get }
    /// Shows `content` beside `rect` (the link run's rect, in `view`'s coordinates). False when it
    /// could not be shown: the caller then stays hidden until a fresh dwell.
    @discardableResult
    func show(_ content: LinkPreviewContent, anchoredTo rect: NSRect, in view: NSTextView) -> Bool
    func hide()
}

/// Whether the editor still holds the keyboard, sampled before and after a popover is shown.
struct LinkPreviewFocus: Equatable, Sendable {
    var windowIsKey: Bool
    var textViewIsFirstResponder: Bool

    /// True when the window stopped being key or the text view stopped being first responder
    /// between the two samples. Something not held before cannot be lost.
    static func lostKeyboard(before: LinkPreviewFocus, after: LinkPreviewFocus) -> Bool {
        (before.windowIsKey && !after.windowIsKey)
            || (before.textViewIsFirstResponder && !after.textViewIsFirstResponder)
    }

    @MainActor
    init(of view: NSTextView) {
        windowIsKey = view.window?.isKeyWindow ?? false
        textViewIsFirstResponder = view.window?.firstResponder === view
    }

    init(windowIsKey: Bool, textViewIsFirstResponder: Bool) {
        self.windowIsKey = windowIsKey
        self.textViewIsFirstResponder = textViewIsFirstResponder
    }
}

/// The production presenter: one `NSPopover`, created once and reused.
///
/// `.applicationDefined` because the controller decides every close (Command up, the pointer
/// leaving, a key, a scroll); a transient popover would also close itself on the next click, which
/// is the Cmd+click the card must not stand in front of. No animation, so a card that follows the
/// pointer from link to link does not lag behind it.
@MainActor
final class LinkPreviewPopover: LinkPreviewPresenting {
    let popover = NSPopover()
    private let hosting: NSHostingController<LinkPreviewView>
    /// The editor's theme at the moment of showing; the hosted view is outside the SwiftUI tree the
    /// app injects it into.
    private let theme: () -> Theme

    init(theme: @escaping () -> Theme = { .emergency }) {
        self.theme = theme
        hosting = NSHostingController(rootView: LinkPreviewView(content: LinkPreviewContent(kind: .board(name: ""))))
        hosting.sizingOptions = [.preferredContentSize]
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = hosting
    }

    var isShowing: Bool { popover.isShown }

    /// Refuses, without showing, a text view with no visible window, a window that is not key (a
    /// dwell that ran out after an app switch, Command still held, must not put a card over a
    /// background window) and an empty rect: a popover anchored to the last lands in a screen
    /// corner rather than beside the link. If showing took the keyboard from the editor anyway, it
    /// is closed and the keyboard handed back.
    func show(_ content: LinkPreviewContent, anchoredTo rect: NSRect, in view: NSTextView) -> Bool {
        guard let window = view.window, window.isVisible, window.isKeyWindow, !rect.isEmpty else { return false }
        hosting.rootView = LinkPreviewView(content: content, theme: theme())
        popover.appearance = view.effectiveAppearance
        let before = LinkPreviewFocus(of: view)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        if LinkPreviewFocus.lostKeyboard(before: before, after: LinkPreviewFocus(of: view)) {
            popover.close()
            window.makeFirstResponder(view)
            return false
        }
        return popover.isShown
    }

    func hide() {
        guard popover.isShown else { return }
        popover.close()
    }
}
