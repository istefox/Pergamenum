import AppKit
import SwiftUI

// ADR-0069 (the attachment chip's context menu is an AppKit menu, because the `List` row's own
// `.contextMenu` takes every right-click inside the row), plan
// docs/plans/pg-285-attachment-chip-context-menu.md - R-01, R-02, R-04.
//
// The chip sits in a `PraticaTimelineView` row that carries the message menu. A SwiftUI
// `.contextMenu` on the chip never opened there (PG-285): the row's menu took the right-click.
// This view, laid over the chip, takes the context click at `hitTest` instead - before SwiftUI
// resolves any menu - and shows the chip's own `NSMenu`, built from
// `AttachmentChipModel.menuEntries` when it opens (§D1, §D2). Every other event finds no view
// here, so a click, a double-click, a hover or a scroll reaches the chip and the row as before.
//
// The shape of `EmbedResizeOverlay`'s `hitTest` (a pass-through overlay) and of
// `FormattingTextView.rightMouseDown` (`menu(for:)` shown through `popUpContextMenu`).

/// The chip's context click, answered by AppKit (ADR-0069 §D1, §D2).
@MainActor
final class AttachmentChipMenuView: NSView {
    /// Read when the menu opens, not when the chip renders: enablement reflects the file on
    /// disk at the moment of the right-click.
    var entries: () -> [AttachmentChipModel.MenuEntry] = { [] }
    var perform: (AttachmentChipModel.Command) -> Void = { _ in }

    /// One item per entry, in order, enabled by the catalogue alone: `autoenablesItems` is off,
    /// so AppKit's responder validation never overrides it.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries() {
            let item = NSMenuItem(title: entry.title, action: #selector(performEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.command.rawValue
            item.identifier = NSUserInterfaceItemIdentifier(entry.command.identifier)
            item.isEnabled = entry.isEnabled
            menu.addItem(item)
        }
        return menu
    }

    @objc private func performEntry(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = AttachmentChipModel.Command(rawValue: raw)
        else { return }
        perform(command)
    }

    /// Whether an event is the context click this view exists for: a right mouse-down, or a
    /// left mouse-down with Control held. Everything else passes through (§D2).
    nonisolated static func claimsContextClick(
        type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch type {
        case .rightMouseDown: true
        case .leftMouseDown: modifierFlags.contains(.control)
        default: false
        }
    }

    /// Present only for the context click. With no current event, or any other one, the chip
    /// and the row underneath see no overlay at all.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              Self.claimsContextClick(type: event.type, modifierFlags: event.modifierFlags)
        else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(for: event)
    }

    /// Control-click is a context click; any other left click would not have reached this view
    /// (`hitTest`), and goes to `super` if it somehow does.
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else { return super.mouseDown(with: event) }
        showMenu(for: event)
    }

    private func showMenu(for event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// The chip itself carries the label, the identifier and the actions (§D5).
    override func isAccessibilityElement() -> Bool { false }
}

/// Places `AttachmentChipMenuView` over the chip (ADR-0069 §D1). It must stay the chip's last
/// modifier: see the header of `AttachmentChip.swift`.
struct AttachmentChipMenuHost: NSViewRepresentable {
    let entries: () -> [AttachmentChipModel.MenuEntry]
    let perform: (AttachmentChipModel.Command) -> Void

    func makeNSView(context: Context) -> AttachmentChipMenuView {
        let view = AttachmentChipMenuView()
        view.entries = entries
        view.perform = perform
        return view
    }

    func updateNSView(_ view: AttachmentChipMenuView, context: Context) {
        view.entries = entries
        view.perform = perform
    }
}
