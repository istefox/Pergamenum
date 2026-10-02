import AppKit
import QuickLookUI
import SwiftUI

/// Spacebar preview, the system panel, exactly as in the Finder (SPEC §6.6).
///
/// `QLPreviewPanel` is driven through the responder chain: it asks the first
/// responder whether it wants to control the panel, and only then reads its data
/// source. That is why this is an `NSView` rather than a plain object - a SwiftUI
/// view cannot be in the responder chain on its own.
/// The two Quick Look protocols predate Swift concurrency annotations and are not
/// `@MainActor`, while `NSView` is; `@preconcurrency` is how a main-actor type adopts
/// them without the compiler assuming a cross-actor call that AppKit never makes.
final class QuickLookHostView: NSView, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    /// The files the panel should show, in order. Set from SwiftUI.
    var urls: [URL] = [] {
        didSet {
            guard urls != oldValue else { return }
            guard QLPreviewPanel.sharedPreviewPanelExists(),
                  QLPreviewPanel.shared().isVisible
            else { return }
            QLPreviewPanel.shared().reloadData()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Space opens the preview only when there is a file selected. In a text field
        // the space must stay a space, which is why this view never takes focus while
        // editing (SPEC §6.6, last bullet).
        guard event.charactersIgnoringModifiers == " ", !urls.isEmpty else {
            super.keyDown(with: event)
            return
        }
        togglePreviewPanel()
    }

    func togglePreviewPanel() {
        guard !urls.isEmpty else { return }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Responder-chain contract

    // The three `QLPreviewPanelController` methods are an informal category on `NSObject`
    // with no actor annotation, so an override is nonisolated by declaration whatever the
    // class is, and `@preconcurrency` on the two protocols above does not reach them (PG-103).
    // AppKit sends them on the main thread, from the responder chain, so each body assumes the
    // main actor once and touches `urls`, the panel and the focus record from there, instead
    // of reading main-actor state from a nonisolated context.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { !urls.isEmpty }
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
            // A no-op unless `claimFocusForPresentation()` recorded something (ADR-0070 §D4).
            handBackFocus()
        }
    }

    // MARK: PG-298, ADR-0070 §D4: focus claimed only to present (outcome A)

    /// What held first responder before `claimFocusForPresentation()` took it. Weak, so a
    /// view that has since left the window is never kept alive for a hand-back.
    private weak var focusBeforePresentation: NSResponder?

    /// Every presentation goes through here (PG-306); with `claimsFocus == false` (the
    /// timeline, ADR-0070 §D4) and in the editor, where a text view holds the keyboard, it
    /// is the only time the host holds first responder: it records the window's first responder,
    /// then takes it, since the panel finds its controller through the responder chain.
    /// Already first responder, it keeps the earlier record rather than recording itself.
    /// PG-307: when nobody held the keyboard (the window itself is first responder, which is
    /// what a click on a chip or a `List` row leaves behind) nothing is recorded, so the host
    /// keeps first responder after the panel closes and a bare space reopens it, as under the
    /// standing claim. It takes nothing from anyone: a row click still hands the `List` the
    /// keyboard through its `@FocusState` (ADR-0070 §D4, route F).
    func claimFocusForPresentation() {
        guard let window else { return }
        if window.firstResponder !== self {
            focusBeforePresentation = window.firstResponder === window
                ? nil : Self.handBackTarget(for: window.firstResponder)
        }
        window.makeFirstResponder(self)
    }

    /// The inverse of `claimFocusForPresentation()`, called when this host's control of the
    /// panel ends: gives first responder back to what was recorded, but only if that
    /// responder is still in the window and this host still holds first responder. A click
    /// elsewhere while the panel was open is never undone (ADR-0070 §D4).
    func handBackFocus() {
        let recorded = focusBeforePresentation
        focusBeforePresentation = nil
        guard let recorded, let window, window.firstResponder === self else { return }
        let isStillInWindow = (recorded as? NSView).map { $0.window === window } ?? (recorded === window)
        guard isStillInWindow else { return }
        window.makeFirstResponder(recorded)
    }

    /// A text field's first responder is the window's shared field editor, which leaves
    /// the view hierarchy as soon as the field stops editing - the field itself is what
    /// focus goes back to.
    private static func handBackTarget(for responder: NSResponder?) -> NSResponder? {
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView {
            return field
        }
        return responder
    }

    // MARK: Data source

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }

    /// Lets the panel forward arrow keys back here so the selection can follow it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        // Escape and space close the panel; the panel handles those itself.
        return false
    }
}

/// Puts a Quick Look host in the responder chain and keeps its file list current.
struct QuickLookTarget: NSViewRepresentable {
    /// Absolute URLs of the currently selected files. Empty disables the shortcut.
    let urls: [URL]
    /// Set to true to open the panel from a menu command rather than the spacebar.
    @Binding var isPresented: Bool
    /// PG-298, ADR-0070 §D4: whether this host claims first responder at appearance and on
    /// every update (`true`, today's behaviour on every surface) or only for the moment it
    /// presents the panel (`false`, the pratica timeline only: a claim there took the
    /// keyboard from the timeline's `List` for good, measured in ADR-0070's implementation
    /// notes). Either way a presentation takes first responder for as long as the panel is
    /// up (PG-306): only the standing claim differs.
    var claimsFocus: Bool = true

    /// PG-298, ADR-0070 §D4: the pure half of "claim now?" on `updateNSView`, so the default
    /// answer - today's behaviour - is pinned in-process rather than only by review
    /// (`Tests/QuickLookFocusTests.swift`). `hasURLs` is `!urls.isEmpty`,
    /// `firstResponderIsText` is `window.firstResponder is NSText`, `isFirstResponder` is
    /// `window.firstResponder === view`.
    static func claimsFocusOnUpdate(
        claimsFocus: Bool, hasURLs: Bool, firstResponderIsText: Bool, isFirstResponder: Bool
    ) -> Bool {
        claimsFocus && hasURLs && !firstResponderIsText && !isFirstResponder
    }

    func makeNSView(context: Context) -> QuickLookHostView {
        let view = QuickLookHostView()
        view.urls = urls
        // Taking focus on appearance is what makes the bare spacebar work without the
        // user having to click the board first.
        if claimsFocus {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ view: QuickLookHostView, context: Context) {
        view.urls = urls

        // Re-assert first responder whenever there is something to preview, unless a
        // text field holds focus: SPEC §6.6 is explicit that the space stays a space
        // while editing. Without this the bare spacebar stops working as soon as any
        // click moves focus elsewhere in the board.
        if let window = view.window,
           Self.claimsFocusOnUpdate(
               claimsFocus: claimsFocus, hasURLs: !urls.isEmpty,
               firstResponderIsText: window.firstResponder is NSText,
               isFirstResponder: window.firstResponder === view
           ) {
            window.makeFirstResponder(view)
        }

        if isPresented {
            // The panel finds its controller through the responder chain, and the host is
            // in it only while it is first responder: without the standing claim (the
            // timeline), and in the editor, where the note's text view holds the keyboard
            // and the standing claim steps aside for it, the panel would open empty. Take
            // focus for this presentation only; it goes back when the panel closes
            // (PG-306). On the board the host already holds it and this changes nothing.
            view.claimFocusForPresentation()
            view.togglePreviewPanel()
            DispatchQueue.main.async { isPresented = false }
        }
    }
}

extension View {
    /// Enables the spacebar preview for the given files while this view is on screen.
    ///
    /// PG-298, ADR-0070 §D4: `claimsFocus` defaults to `true`, today's behaviour on every
    /// surface (source-compatible with every existing call site). The pratica timeline
    /// passes `false`, so a Quick Look preview there no longer keeps the keyboard
    /// once the panel is gone (R-08); the Workspace board and the editor keep the default,
    /// since the board's bare-spacebar preview depends on the claim (ADR-0070 §D4). In the
    /// editor the claim always steps aside for the note's text view, so an embed preview
    /// reaches the panel through the presentation's own claim (PG-306).
    func quickLook(urls: [URL], isPresented: Binding<Bool>, claimsFocus: Bool = true) -> some View {
        background(
            QuickLookTarget(urls: urls, isPresented: isPresented, claimsFocus: claimsFocus)
                .frame(width: 0, height: 0)
        )
    }
}
