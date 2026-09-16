import Foundation

/// The vault's whole category tree, plus a format version (SPEC "Data model —
/// Registry"). Loaded with the vault, saved atomically on every change; an absent
/// file means an empty registry, and a malformed one is reported and never
/// overwritten (ADR-0047 §D2, `CategoryRegistryStore`).
struct CategoryRegistry: Codable, Equatable, Sendable {
    /// Bumped only if this on-disk shape itself changes (this type is a proposed
    /// protected interface, ADR-0047 "Protected-interface proposal"). A version the
    /// store does not recognise reads back as malformed, the same as bytes it cannot
    /// decode at all - never silently reinterpreted.
    static let currentVersion = 1

    var version: Int
    var entries: [Category]

    static let empty = CategoryRegistry(version: currentVersion, entries: [])

    /// Why a mutation was refused, before anything was written (ADR-0047 §D3).
    enum RefusalReason: Error, Equatable, Sendable {
        case malformedSlug(String)
        case duplicateSlug(String)
        case unknownParent(String)
        case parentNotTopLevel(String)
        case parentIsSelf(String)
        /// The on-disk file could not be read (ADR-0047 §D2): every mutation refuses
        /// while this holds, rather than risk replacing a hand-edited registry with an
        /// empty one. Raised by `VaultSession+Categories.swift`, not by `validating`
        /// itself, which never sees the file.
        case registryUnreadable
    }

    /// The one pure door every mutation goes through (ADR-0047 §D3): given the
    /// registry's prospective new entry list, refuses before anything is written. Not
    /// an `assert`-shaped checker a call site can forget - it is the only way to
    /// obtain a `CategoryRegistry` `CategoryRegistryStore.save` will accept, so a new
    /// mutation inherits the check instead of remembering it (ADR-0041's rule, applied
    /// again).
    ///
    /// Validates the whole candidate list rather than one entry at a time: uniqueness
    /// and "parent must be top-level" are both facts about the registry as a whole, and
    /// checking them against a list that already contains the edit (or omits the
    /// deletion) is what makes an update of an unchanged slug validate cleanly against
    /// itself.
    static func validating(
        _ entries: [Category], version: Int = currentVersion
    ) -> Result<CategoryRegistry, RefusalReason> {
        for entry in entries where !Tag.isWellFormedValue(entry.slug) {
            return .failure(.malformedSlug(entry.slug))
        }

        let slugs = entries.map(\.slug)
        for slug in Set(slugs) where slugs.filter({ $0 == slug }).count > 1 {
            return .failure(.duplicateSlug(slug))
        }

        let bySlug = Dictionary(uniqueKeysWithValues: entries.map { ($0.slug, $0) })
        for entry in entries {
            guard let parentSlug = entry.parent else { continue }
            guard parentSlug != entry.slug else { return .failure(.parentIsSelf(entry.slug)) }
            guard let parent = bySlug[parentSlug] else { return .failure(.unknownParent(parentSlug)) }
            guard parent.parent == nil else { return .failure(.parentNotTopLevel(parentSlug)) }
        }

        return .success(CategoryRegistry(version: version, entries: entries))
    }

    /// The direct children of a top-level category (depth is at most two, so this is
    /// the whole of "below" it).
    func children(of parentSlug: String) -> [Category] {
        entries.filter { $0.parent == parentSlug }
    }

    /// `slug` plus its children, for a rollup or an archive cascade (ADR-0047 §D4/SPEC
    /// "Rollup"). A child has no children of its own, so this never walks deeper than
    /// one level.
    func subtreeSlugs(of slug: String) -> Set<String> {
        Set([slug] + children(of: slug).map(\.slug))
    }
}
