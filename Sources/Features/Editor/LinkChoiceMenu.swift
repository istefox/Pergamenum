import AppKit

// ADR-0083 §D5, §D6 (PG-386, N3 session B).

/// Where the menu a click on a shared title puts up is shown. A seam because the real thing,
/// `NSMenu.popUp(positioning:at:in:)`, is modal tracking and never runs in a test.
@MainActor
protocol LinkChoiceMenuPresenting: AnyObject {
    func present(_ menu: NSMenu, at point: NSPoint, in view: NSView)
}

/// The production presenter, and the one place the choice becomes an `NSMenu`.
@MainActor
final class LinkChoiceMenu: LinkChoiceMenuPresenting {
    func present(_ menu: NSMenu, at point: NSPoint, in view: NSView) {
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// The choice at the click, as the approved mockup draws it: for a shared title a disabled
    /// header, «Più note si chiamano «X»», then one row per note labelled by its folder; for a
    /// dangling link the one row «Crea «X»». The rows are `LinkChoice.entries`, the catalogue
    /// `LinkChoiceSheet` draws too, so the two surfaces cannot differ.
    static func menu(
        title: String, choices: [LinkChoice], onChoose: @escaping (LinkChoice) -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if choices.contains(where: { if case .open = $0.action { true } else { false } }) {
            let header = NSMenuItem(title: "Più note si chiamano «\(title)»", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for choice in choices {
            let action = LinkChoiceMenuAction { onChoose(choice) }
            let item = NSMenuItem(
                title: choice.label, action: #selector(LinkChoiceMenuAction.choose(_:)), keyEquivalent: ""
            )
            // The item holds its action: `target` is weak, `representedObject` is not.
            item.target = action
            item.representedObject = action
            item.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }
}

extension LinkChoice {
    /// The SF Symbol a row is drawn with, on the menu and in the sheet alike.
    var symbol: String {
        switch action {
        case .open: "folder"
        case .create: "plus.square"
        }
    }
}

/// One menu row's action: an `NSMenuItem` reaches its target by selector, never by closure.
@MainActor
private final class LinkChoiceMenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    /// Not `perform(_:)`: that is `NSObject`'s `performSelector:` in Swift, and `#selector` picks it,
    /// so AppKit would send the menu item as a selector.
    @objc func choose(_ sender: Any?) {
        run()
    }
}
