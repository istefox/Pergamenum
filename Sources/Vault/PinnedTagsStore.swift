import Foundation

/// Which tags this machine keeps at the top of the tag browser (ADR-0012, slice 3).
///
/// **In `UserDefaults` and not under `.pergamenum/`, on the same reasoning as the open tabs
/// (D10) and the opposite of the starred notes (D6).** A star says a note matters, which is a
/// fact about the vault and should follow it through iCloud Drive; a pinned tag says *this*
/// desk keeps reaching for `client-nexion` this month, which the other machine has no reason to
/// inherit. The key carries the vault's path, so two vaults do not overwrite each other.
///
/// Losing it loses the order of a list and nothing else.
struct PinnedTagsStore {
    private let defaults: UserDefaults

    /// A store backed by a throwaway suite, for tests: running the suite must not rearrange the
    /// browser of the app the person is using. The same reason `OpenTabsStore.volatile` exists.
    static func volatile() -> PinnedTagsStore {
        PinnedTagsStore(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())") ?? .standard)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for root: URL) -> String {
        "pinnedTags:" + root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }

    /// The pinned tags, in the order they were pinned, skipping anything that no longer parses
    /// as a tag - the grammar of SPEC §4.4 is closed and this file is not where it is widened.
    func tags(for root: URL) -> [Tag] {
        (defaults.stringArray(forKey: Self.key(for: root)) ?? []).compactMap(Tag.init)
    }

    func remember(_ tags: [Tag], for root: URL) {
        defaults.set(tags.map(\.description), forKey: Self.key(for: root))
    }
}
