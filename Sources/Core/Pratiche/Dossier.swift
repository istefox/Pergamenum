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
        // Flattened rather than looked up key by key: `FrontmatterParser` groups a key
        // with its continuation lines, but a `pratica.md` a person hand-edited may have
        // them apart, and reading the whole block costs nothing.
        let lines = foreignKeys.flatMap(\.lines)
        guard let schemaVersion = DossierYAML.scalarInt(key: keyRoot, lines: lines) else { return nil }
        return Dossier(
            schemaVersion: schemaVersion,
            counterparts: DossierYAML.stringList(key: counterpartsKey, lines: lines),
            conversations: DossierYAML.inlineIntList(key: conversationsKey, lines: lines),
            keywords: DossierYAML.stringList(key: keywordsKey, lines: lines),
            included: DossierYAML.stringList(key: includedKey, lines: lines),
            excluded: DossierYAML.stringList(key: excludedKey, lines: lines),
            ignored: DossierYAML.inlineIntList(key: ignoredKey, lines: lines)
        )
    }

    /// Renders the seven keys as `Frontmatter.ForeignKey` lines, in the SPEC's own
    /// order (ADR §D12). A key whose list is empty is omitted, matching
    /// `FrontmatterSerializer`'s own "no empty list key" rule.
    ///
    /// Protected interface (`.claude/protected-interfaces`): a shape change here
    /// silently unmakes every pratica already on disk, since a folder is recognised
    /// as a pratica by this key set.
    static func render(_ dossier: Dossier) -> [Frontmatter.ForeignKey] {
        // Counterparts are addresses and need no quoting; a keyword, a message id and
        // anything else a person types can carry a `:` or a `#`, which unquoted would
        // change the line's YAML meaning.
        let rendered: [(String, [String])] = [
            (keyRoot, DossierYAML.renderScalarInt(key: keyRoot, value: dossier.schemaVersion)),
            (counterpartsKey, DossierYAML.renderStringList(
                key: counterpartsKey, values: dossier.counterparts, quoted: false
            )),
            (conversationsKey, DossierYAML.renderInlineIntList(
                key: conversationsKey, values: dossier.conversations
            )),
            (keywordsKey, DossierYAML.renderStringList(
                key: keywordsKey, values: dossier.keywords, quoted: true
            )),
            (includedKey, DossierYAML.renderStringList(
                key: includedKey, values: dossier.included, quoted: true
            )),
            (excludedKey, DossierYAML.renderStringList(
                key: excludedKey, values: dossier.excluded, quoted: true
            )),
            (ignoredKey, DossierYAML.renderInlineIntList(key: ignoredKey, values: dossier.ignored)),
        ]
        return rendered
            .filter { !$0.1.isEmpty }
            .map { Frontmatter.ForeignKey(name: $0.0, lines: $0.1) }
    }

    /// Replaces this dossier's own key lines inside `foreignKeys`, **in place** -
    /// every other key, including one this app did not write, stays at its original
    /// position and byte-for-byte unchanged (ADR §D12, C4). A dossier with no prior
    /// representation in `foreignKeys` has its keys appended at the end.
    static func merging(_ dossier: Dossier, into foreignKeys: [Frontmatter.ForeignKey]) -> [Frontmatter.ForeignKey] {
        var pending: [String: Frontmatter.ForeignKey] = [:]
        for key in render(dossier) { pending[key.name] = key }

        var merged: [Frontmatter.ForeignKey] = []
        let owned = Set(ownedKeys)
        for existing in foreignKeys {
            guard owned.contains(existing.name) else {
                // Somebody else's key: kept where it is, byte for byte (C4).
                merged.append(existing)
                continue
            }
            // An owned key whose list is now empty disappears rather than staying
            // behind with stale values `render` deliberately omits.
            if let replacement = pending.removeValue(forKey: existing.name) {
                merged.append(replacement)
            }
        }
        // Anything this dossier gained since the file was written goes at the end, in
        // the SPEC's own key order, never interleaved among keys it does not own.
        for name in ownedKeys {
            if let addition = pending.removeValue(forKey: name) { merged.append(addition) }
        }
        return merged
    }
}
