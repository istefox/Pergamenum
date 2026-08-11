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

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !urls.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
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

    func makeNSView(context: Context) -> QuickLookHostView {
        let view = QuickLookHostView()
        view.urls = urls
        // Taking focus on appearance is what makes the bare spacebar work without the
        // user having to click the board first.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: QuickLookHostView, context: Context) {
        view.urls = urls

        // Re-assert first responder whenever there is something to preview, unless a
        // text field holds focus: SPEC §6.6 is explicit that the space stays a space
        // while editing. Without this the bare spacebar stops working as soon as any
        // click moves focus elsewhere in the board.
        if !urls.isEmpty, let window = view.window,
           !(window.firstResponder is NSText), window.firstResponder !== view {
            window.makeFirstResponder(view)
        }

        if isPresented {
            view.togglePreviewPanel()
            DispatchQueue.main.async { isPresented = false }
        }
    }
}

extension View {
    /// Enables the spacebar preview for the given files while this view is on screen.
    func quickLook(urls: [URL], isPresented: Binding<Bool>) -> some View {
        background(QuickLookTarget(urls: urls, isPresented: isPresented).frame(width: 0, height: 0))
    }
}
