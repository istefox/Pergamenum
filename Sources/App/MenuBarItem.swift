import AppKit

/// The icon in the menu bar (ADR-0008 §D7).
///
/// The panel needs Pergamenum to be running, and an app with its window closed behind
/// twenty others is one nobody remembers is running. This is the thing that makes it
/// visible, and the way in when the hot key was refused by the system.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: that one is a `Scene`, and the
/// commands here have to reach the same panel and vault the main window uses. It also
/// has to be removable at run time, which a scene is not.
@MainActor
final class MenuBarItem {
    private var item: NSStatusItem?

    private let onCapture: () -> Void
    private let onToday: () -> Void
    private let onInbox: () -> Void

    init(
        onCapture: @escaping () -> Void,
        onToday: @escaping () -> Void,
        onInbox: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.onToday = onToday
        self.onInbox = onInbox
    }

    var isShown: Bool { item != nil }

    /// Adds or removes the icon, for the setting that turns it off.
    func setShown(_ shown: Bool) {
        if shown {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A template image so it inverts with the menu bar instead of staying dark on a
        // dark bar.
        item.button?.image = NSImage(
            systemSymbolName: "text.badge.plus", accessibilityDescription: "Pergamenum"
        )
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
        self.item = item
    }

    private func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(entry("Cattura rapida", #selector(Target.capture)))
        menu.addItem(.separator())
        menu.addItem(entry("Oggi", #selector(Target.today)))
        menu.addItem(entry("Inbox", #selector(Target.inbox)))
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Esci da Pergamenum",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private func entry(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        // The target is retained by the menu item, and this object by the target: the
        // closures have to outlive this method, and an unretained target here is a
        // menu whose entries silently do nothing.
        item.target = target
        return item
    }

    private lazy var target = Target(owner: self)

    /// `NSMenuItem` wants an Objective-C selector, which a Swift closure is not.
    @MainActor
    private final class Target: NSObject {
        private unowned let owner: MenuBarItem
        init(owner: MenuBarItem) { self.owner = owner }

        @objc func capture() { owner.onCapture() }
        @objc func today() { owner.onToday() }
        @objc func inbox() { owner.onInbox() }
    }
}
