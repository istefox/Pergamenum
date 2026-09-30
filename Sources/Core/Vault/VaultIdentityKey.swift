import Foundation

extension URL {
    /// The one spelling under which a vault root is compared and keyed: symlinks resolved and
    /// the path standardized, as text. `/tmp/v` and `/private/tmp/v`, or a link and its target,
    /// name the same vault and give the same key. `RecentVaults`, `OpenTabsStore`,
    /// `PinnedTagsStore`, `VaultSession`'s path-derived id and `VaultController.open(_:)`'s
    /// previous-vault mark all use it, so no two of them can disagree about which vault a URL is
    /// (PG-326: `standardizedFileURL` alone does not resolve links).
    var vaultKey: String {
        resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }
}
