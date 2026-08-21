import CryptoKit
import Foundation

/// Resolving `VaultSession.init`'s vault id, split out of `VaultSession.swift` itself
/// on the same convention as the rest of `VaultSession+*.swift`: a static, pure-ish
/// set of helpers `init` calls before any stored property is assigned, which is why
/// they live as `extension` members rather than as free functions - `VaultLayout` and
/// `VaultState` are what they're really about (ADR-0017 §D2).
extension VaultSession {
    /// What `resolveIdentity` hands back: the settings `init` should keep (unchanged,
    /// or carrying a freshly minted and persisted id), the id `state` is built from,
    /// and any problems worth reporting. A named type rather than a three-member
    /// tuple, which is also what SwiftLint's `large_tuple` rule is telling you.
    struct IdentityResolution {
        let settings: VaultSettings
        let id: String
        let problems: [String]
    }

    /// Reads `settings.json`, defaulting silently when the file is absent and
    /// defaulting with a reported problem when it exists but will not decode.
    ///
    /// Static, and called before any stored property is assigned: the vault id lives
    /// in these settings and `state` needs it before `history` and the other stores
    /// can be built (ADR-0017). The file is not overwritten on a decode failure, so
    /// the user can repair it by hand - the same contract the old instance method kept.
    static func readSettings(in root: URL) -> (settings: VaultSettings, problems: [String]) {
        let url = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.settingsFile, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url) else {
            return (.default, [])
        }
        do {
            return (try JSONDecoder().decode(VaultSettings.self, from: data), [])
        } catch {
            return (.default, ["\(VaultLayout.settingsFile): \(error.localizedDescription); using defaults"])
        }
    }

    /// Resolves the id `state` is built from, minting and persisting one when
    /// `settings` has none yet.
    ///
    /// The common case: mint a UUID, persist it via `writeSettings`, done. When that
    /// write fails - a read-only vault - the minted UUID is discarded rather than kept
    /// in memory only: keeping it would mint a fresh one on every launch, since nothing
    /// on disk remembers it, and orphan a new state directory each time. A
    /// deterministic id derived from the resolved root stands in instead - the exact
    /// path-hash identity ADR-0017 §D2 rejects for the general case, because a Finder
    /// rename orphans it silently - accepted here only as a fallback for a vault
    /// nothing can be written to, and reported so the tradeoff is never silent either.
    static func resolveIdentity(settings: VaultSettings, root: URL) -> IdentityResolution {
        if let existing = settings.vaultID {
            return IdentityResolution(settings: settings, id: existing, problems: [])
        }

        var minted = settings
        let candidate = UUID().uuidString
        minted.vaultID = candidate
        if writeSettings(minted, in: root) {
            return IdentityResolution(settings: minted, id: candidate, problems: [])
        }

        let fallback = pathDerivedID(for: root)
        return IdentityResolution(settings: settings, id: fallback, problems: [
            "\(VaultLayout.settingsFile): impossibile scrivere l'identificativo del vault; "
                + "uso un identificativo derivato dal percorso, stabile solo finché il vault "
                + "non viene rinominato o spostato"
        ])
    }

    /// Writes `settings.json` atomically, creating the private directory if needed.
    /// Static so a candidate id can be persisted before `self` exists (`resolveIdentity`
    /// runs ahead of every stored property). Returns whether the write succeeded;
    /// `updateSettings` keeps its own instance-side error reporting for every other
    /// caller.
    private static func writeSettings(_ settings: VaultSettings, in root: URL) -> Bool {
        let privateDirectory = root.appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings)
                .write(to: privateDirectory.appending(path: VaultLayout.settingsFile), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A deterministic id from the resolved root path, used only by `resolveIdentity`
    /// when `settings.json` cannot be written. Shaped like a UUID purely so it is
    /// interchangeable everywhere an id names a directory; nothing parses it as one.
    private static func pathDerivedID(for root: URL) -> String {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let hex = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let chars = Array(hex.prefix(32))
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
            .map { String(chars[$0]) }
            .joined(separator: "-")
    }
}
