import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// §D12.

/// `pratica.md`'s own frontmatter, the seven `pergamenum-dossier-*` keys (ADR §D12).
/// A folder whose `pratica.md` parses to a non-`nil` `Dossier` is a pratica (R-01).
struct Dossier: Equatable, Sendable {
    /// `pergamenum-dossier` - the schema version of the keys below, `1` today.
    var schemaVersion: Int
    /// `pergamenum-dossier-counterparts` - addresses of the other side, lowercase.
    var counterparts: [String]
    /// `pergamenum-dossier-conversations` - Mail `conversation_id`s followed.
    var conversations: [Int]
    /// `pergamenum-dossier-keywords` - optional; a subject match auto-admits.
    var keywords: [String]
    /// `pergamenum-dossier-included` - `Message-ID`s added by hand outside any
    /// followed conversation.
    var included: [String]
    /// `pergamenum-dossier-excluded` - `Message-ID`s removed by hand; never
    /// re-imported.
    var excluded: [String]
    /// `pergamenum-dossier-ignored` - conversation ids dismissed from the tray, for
    /// this pratica only.
    var ignored: [Int]

    static let keyRoot = "pergamenum-dossier"
    static let counterpartsKey = "pergamenum-dossier-counterparts"
    static let conversationsKey = "pergamenum-dossier-conversations"
    static let keywordsKey = "pergamenum-dossier-keywords"
    static let includedKey = "pergamenum-dossier-included"
    static let excludedKey = "pergamenum-dossier-excluded"
    static let ignoredKey = "pergamenum-dossier-ignored"

    /// The seven key names, in the SPEC's own order - the order `render(_:)` never
    /// deviates from and `merging(_:into:)` never reshuffles other keys around.
    static let ownedKeys = [
        keyRoot, counterpartsKey, conversationsKey, keywordsKey, includedKey, excludedKey, ignoredKey,
    ]

    /// Parses the seven keys out of a note's foreign keys. `nil` when
    /// `pergamenum-dossier` is absent - the folder is then not a pratica (R-01).
    static func parse(_ foreignKeys: [Frontmatter.ForeignKey]) -> Dossier? {
        // Coder-owned.
        nil
    }

    /// Renders the seven keys as `Frontmatter.ForeignKey` lines, in the SPEC's own
    /// order (ADR §D12). A key whose list is empty is omitted, matching
    /// `FrontmatterSerializer`'s own "no empty list key" rule.
    ///
    /// Protected interface (`.claude/protected-interfaces`): a shape change here
    /// silently unmakes every pratica already on disk, since a folder is recognised
    /// as a pratica by this key set.
    static func render(_ dossier: Dossier) -> [Frontmatter.ForeignKey] {
        // Coder-owned. Stubbed empty, which also keeps `merging(_:into:)`'s identity
        // stub self-consistent (nothing to remove, nothing to insert) until both are
        // implemented together.
        []
    }

    /// Replaces this dossier's own key lines inside `foreignKeys`, **in place** -
    /// every other key, including one this app did not write, stays at its original
    /// position and byte-for-byte unchanged (ADR §D12, C4). A dossier with no prior
    /// representation in `foreignKeys` has its keys appended at the end.
    static func merging(_ dossier: Dossier, into foreignKeys: [Frontmatter.ForeignKey]) -> [Frontmatter.ForeignKey] {
        // Coder-owned. Stubbed as the identity: leaves `foreignKeys` untouched, which
        // is correct only when `dossier`'s keys are already absent from it and empty
        // (the render stub's own output) - every other case is red until implemented.
        foreignKeys
    }
}
