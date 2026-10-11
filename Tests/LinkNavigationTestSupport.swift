import Foundation
@testable import Pergamenum

/// The scaffolding the link-navigation suites of N3 session B share (ADR-0083): a note's text with
/// valid frontmatter, and a `CommandActions` built over a throwaway vault the way
/// `OpenLinkUnresolvedTests` builds one. In a file of its own for the reason `DayTestSupport` is:
/// five suites need it, and a copy in each is a copy that drifts (ADR-0051).
@MainActor
enum LinkFixtures {
    /// A note with the frontmatter the conventions require and `body` after it.
    static func note(_ body: String = "Testo.") -> String {
        "---\ndate: 2026-10-01\ntags:\n  - type-note\n---\n\n\(body)\n"
    }

    /// A vault controller over `root`, with nothing persisted anywhere but the temporary vault.
    static func controller(root: URL) async -> VaultController {
        let vault = VaultController(recents: .volatile(), openTabs: .volatile())
        await vault.open(root)
        return vault
    }

    /// The window's command layer over a vault opened on `root`.
    static func actions(root: URL) async -> CommandActions {
        let vault = await controller(root: root)
        let calendarStore = EventKitStore()
        let capture = CaptureController()
        return CommandActions(
            navigation: Navigation(),
            vault: vault,
            day: DayController(store: calendarStore, vault: vault),
            calendar: calendarStore,
            capturePanel: CapturePanel(
                controller: capture,
                session: { vault.session },
                theme: { ThemeEngine().current },
                shortcutCaption: { nil }
            ),
            history: NavigationHistory(),
            pasteboard: .volatile()
        )
    }

    /// Two notes called «Riunione» in two folders, one called «Unica», and a source note, the
    /// vault every choice test starts from.
    static func writeSharedTitleVault(in vault: borrowing TemporaryVault) throws {
        try vault.write(note("Prima."), to: "Clienti/Riunione.md")
        try vault.write(note("Seconda."), to: "Progetti/Riunione.md")
        try vault.write(note("Unica."), to: "Unica.md")
        try vault.write(note("Sorgente."), to: "Progetti/Sorgente.md")
    }

    /// The URL the styler writes on a wikilink to `title` (what the editor reports at the caret).
    static func url(for title: String) -> URL { MarkdownAttributedText.noteURL(for: title) }
}

import AppKit

/// What `links.follow`, `links.choose`, `links.onCaretLinkChanged` and `links.offerCreation` were
/// called with, and the outcome `follow` answers. One spy for the four so a hosted suite wires an
/// editor with one line.
@MainActor
final class LinkInputsSpy {
    private(set) var requests: [LinkRequest] = []
    private(set) var chosen: [(choice: LinkChoice, how: LinkOpening)] = []
    private(set) var caretReports: [URL?] = []
    private(set) var offered: [String] = []
    var outcome: LinkFollowOutcome = .done

    func install(on coordinator: NoteTextView.Coordinator) {
        coordinator.parent.links.follow = { [self] request in
            requests.append(request)
            return outcome
        }
        coordinator.parent.links.choose = { [self] choice, how in chosen.append((choice, how)) }
        coordinator.parent.links.onCaretLinkChanged = { [self] url in caretReports.append(url) }
        coordinator.parent.links.offerCreation = { [self] title in offered.append(title) }
    }
}

/// Stands in for the menu the click puts up, which in production runs modal tracking.
@MainActor
final class LinkChoiceMenuSpy: LinkChoiceMenuPresenting {
    private(set) var presented: [(menu: NSMenu, point: NSPoint, view: NSView)] = []

    func present(_ menu: NSMenu, at point: NSPoint, in view: NSView) {
        presented.append((menu, point, view))
    }

    /// The rows that are not the header and not a separator.
    var itemTitles: [String] {
        guard let menu = presented.last?.menu else { return [] }
        return rows(of: menu).map(\.title)
    }

    func rows(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.dropFirst().filter { !$0.isSeparatorItem }
    }

    /// Invokes the `index`th row the way the menu would.
    func invoke(row index: Int) {
        guard let menu = presented.last?.menu else { return }
        let items = rows(of: menu)
        guard items.indices.contains(index), let action = items[index].action else { return }
        NSApp.sendAction(action, to: items[index].target, from: items[index])
    }
}

/// A manual clock and scheduler: `schedule` records the callback, `advance(by:)` moves the clock
/// and fires what came due, in order.
@MainActor
final class LinkPreviewClock {
    private(set) var time: TimeInterval = 100
    private var pending: [(due: TimeInterval, fire: @MainActor () -> Void)] = []
    private(set) var scheduledDelays: [TimeInterval] = []

    func now() -> TimeInterval { time }

    func schedule(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        pending.append((time + delay, fire))
    }

    func advance(by interval: TimeInterval) {
        time += interval
        let due = pending.filter { $0.due <= time }.sorted { $0.due < $1.due }
        pending.removeAll { $0.due <= time }
        for entry in due { entry.fire() }
    }
}

/// Stands in for the popover: records what it was asked to show, answers whether it could.
@MainActor
final class LinkPreviewPresenterSpy: LinkPreviewPresenting {
    private(set) var shown: [(content: LinkPreviewContent, rect: NSRect, view: NSTextView)] = []
    private(set) var hideCount = 0
    private(set) var isShowing = false
    /// What `show` answers; false leaves the preview hidden.
    var canShow = true
    /// Runs inside `show`, for sampling state while the preview is being presented.
    var duringShow: (() -> Void)?

    @discardableResult
    func show(_ content: LinkPreviewContent, anchoredTo rect: NSRect, in view: NSTextView) -> Bool {
        shown.append((content, rect, view))
        duringShow?()
        isShowing = canShow
        return canShow
    }

    func hide() {
        hideCount += 1
        isShowing = false
    }
}

extension NSTextView {
    /// The centre of the character range `range` in this view's own coordinates, the point a
    /// pointer over it would carry. Zero when layout has not reached the range.
    func pointOver(_ range: NSRange) -> NSPoint {
        guard let manager = textLayoutManager else { return .zero }
        manager.ensureLayout(for: manager.documentRange)
        let screen = firstRect(forCharacterRange: NSRange(location: range.location + range.length / 2, length: 1), actualRange: nil)
        guard let window, !screen.isEmpty else { return .zero }
        let inWindow = window.convertFromScreen(screen)
        let local = convert(inWindow, from: nil)
        return NSPoint(x: local.midX, y: local.midY)
    }
}
