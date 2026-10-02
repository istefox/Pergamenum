import AppKit

/// Gives the foreground back after a batch of `pergamenum://` links that must not raise
/// the app (PG-132, SPEC §9).
///
/// Opening a URL scheme activates the target app before `application(_:open:)` runs:
/// Launch Services does it, not this code, so a `capture` link appended its text and left
/// Pergamenum in front of whatever the person was doing. `PergamenumRoute.raisesApp` said
/// a capture must not do that and nothing consulted it. This type records which app was
/// in front before this one, through the workspace's own activation notifications, and
/// hands activation back to it once every route of an all-capture batch has been handled -
/// the cooperative `activate(from:options:)`, never `activate(ignoringOtherApps:)`, which
/// is the call the AppKit guidance warns against on a non-user-triggered path.
@MainActor
final class ForegroundHandBack {
    /// The last app other than this one that became active, or nil when none has since
    /// launch (the first link ever handled, from the Finder, before any switch).
    private(set) var previousApplication: NSRunningApplication?
    /// Never removed: the one instance is the app delegate's and lives as long as the
    /// process, and a `deinit` touching main-actor state is what Swift 6 refuses.
    private var observer: (any NSObjectProtocol)?

    init(workspace: NSWorkspace = .shared) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = workspace.frontmostApplication, frontmost.processIdentifier != currentPID {
            previousApplication = frontmost
        }
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication, activated.processIdentifier != currentPID
            else { return }
            MainActor.assumeIsolated { self?.previousApplication = activated }
        }
    }

    /// True when the batch is made only of routes that must not raise the app
    /// (`PergamenumRoute.raisesApp` false for every one): a batch mixing a capture with a
    /// link that opens a note or a day is a batch the person wants to look at.
    nonisolated static func handsBackActivation(after routes: [PergamenumRoute]) -> Bool {
        !routes.isEmpty && routes.allSatisfy { !$0.raisesApp }
    }

    /// Activates the app that was in front before this one, when there is one and this app
    /// is the active one - the two conditions under which the hand-back means anything.
    /// Returns whether an activation was asked for.
    @discardableResult
    func handBack() -> Bool {
        guard NSApp.isActive, let previous = previousApplication, !previous.isTerminated else { return false }
        return previous.activate(from: .current, options: [])
    }
}
