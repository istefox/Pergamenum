import Foundation

/// Which notes were open in which order, per vault, so a relaunch finds the desk as it was
/// (ADR-0012 D10).
///
/// **In `UserDefaults` and not under `.pergamenum/`, unlike the starred notes.** The vault is
/// meant to travel through iCloud Drive (principle 6), and which notes are open *on this Mac*
/// is not something the other one should inherit - a star is a fact about the note, an open tab
/// is a fact about a desk. The key carries the vault's path, so two vaults do not overwrite
/// each other's session.
///
/// Losing the file loses the arrangement and nothing else, which is the same promise every
/// other store in this app makes.
struct OpenTabsStore {
    /// One tab as it survives a relaunch: which note, and whether it was the transient
    /// preview. Not the buffer - unsaved text is not something to keep in `UserDefaults`,
    /// and a tab is closed only after the question ADR-0012 D3 asks.
    struct Entry: Codable, Equatable, Sendable {
        var path: String
        var isPreview: Bool
    }

    /// One column of the editor: its tabs and the one that was in front.
    struct Column: Codable, Equatable, Sendable {
        var entries: [Entry] = []
        /// The path that was in front, rather than an index: a note deleted while the app was
        /// closed shifts every index and would silently focus a different note.
        var activePath: String?
    }

    /// The whole desk: one column, or two after a split (ADR-0012 D4).
    ///
    /// **This shape replaced a flat list of entries, and the old blob no longer decodes.** A
    /// version written before the split reads back as an empty session, which costs the tab
    /// arrangement once and nothing else - the notes are on disk and none of this is content.
    /// A migration for a `UserDefaults` blob that describes where windows were is more machinery
    /// than the thing is worth.
    struct Session: Codable, Equatable, Sendable {
        var columns: [Column] = []
        var focusedColumn = 0
    }

    private let defaults: UserDefaults

    /// A store backed by a throwaway suite, for tests. Running the suite must not rearrange
    /// the tabs of the app the person is using - the same reason `RecentVaults.volatile()`
    /// exists, and the same mistake it was written to stop.
    static func volatile() -> OpenTabsStore {
        OpenTabsStore(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())") ?? .standard)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for root: URL) -> String {
        "openTabs:" + root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }

    func session(for root: URL) -> Session {
        guard let data = defaults.data(forKey: Self.key(for: root)),
              let session = try? JSONDecoder().decode(Session.self, from: data)
        else { return Session() }
        return session
    }

    func remember(_ session: Session, for root: URL) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.key(for: root))
    }

    func forget(_ root: URL) {
        defaults.removeObject(forKey: Self.key(for: root))
    }
}
