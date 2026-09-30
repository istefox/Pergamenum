import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D13, plan
// docs/plans/contenitore.md, Task 2 - R-26 (validation half).
//
// Under `Sources/Core/Contenitore` (globbed into `sharedSources`) for the reason
// `PraticheSettings` sits under `Sources/Core/Pratiche`: `VaultSettings` embeds it, and both
// connectors decode `VaultSettings`.

/// Settings › Contenitore, nested inside `VaultSettings.contenitore` (Task 6).
struct ContenitoreSettings: Codable, Equatable, Sendable {
    /// The drop folder, outside the vault, stored `~`-relative when it sits under the home
    /// folder, so it resolves on any Mac the vault syncs to.
    var dropFolder: String
    /// The Contenitore root, relative to the vault root.
    var root: String

    static let defaultDropFolder = "~/Pergamenum Drop"
    static let defaultRoot = "Contenitore"

    static let `default` = ContenitoreSettings(dropFolder: defaultDropFolder, root: defaultRoot)

    init(dropFolder: String = ContenitoreSettings.defaultDropFolder, root: String = ContenitoreSettings.defaultRoot) {
        self.dropFolder = dropFolder
        self.root = root
    }

    /// Decoded key by key like `PraticheSettings`, so a `settings.json` written before a key
    /// existed does not lose the whole nested value.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dropFolder = try container.decodeIfPresent(String.self, forKey: .dropFolder) ?? Self.defaultDropFolder
        root = try container.decodeIfPresent(String.self, forKey: .root) ?? Self.defaultRoot
    }

    // MARK: - The drop folder

    /// Why a drop folder was refused. Each case carries the one sentence the settings tab shows.
    enum DropFolderRefusal: Equatable, Sendable {
        case empty
        case notAbsolute
        case filesystemRoot
        case home
        case vault
        case insideVault
        case containsVault

        var sentence: String {
            switch self {
            case .empty: "Indica una cartella di deposito."
            case .notAbsolute: "Indica un percorso completo, che cominci con / oppure con ~."
            case .filesystemRoot: "La cartella di deposito non può essere la radice del disco."
            case .home: "La cartella di deposito non può essere la cartella Inizio."
            case .vault: "La cartella di deposito non può essere la vault."
            case .insideVault: "La cartella di deposito deve stare fuori dalla vault."
            case .containsVault: "La cartella di deposito non può contenere la vault."
            }
        }
    }

    /// Nil when `path` may be the drop folder: not the vault, not inside it, not an ancestor
    /// of it, not the home folder and not `/` (ADR-0071 §D13). Paths are compared with their
    /// symlinks resolved, so `/var` and `/private/var` agree.
    static func validateDropFolder(_ path: String, vaultRoot: URL, home: URL) -> DropFolderRefusal? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        guard let expanded = expandedURL(trimmed, home: home) else { return .notAbsolute }

        let drop = canonicalComponents(expanded)
        let vault = canonicalComponents(vaultRoot)
        if drop.count <= 1 { return .filesystemRoot }
        if drop == canonicalComponents(home) { return .home }
        if drop == vault { return .vault }
        if drop.starts(with: vault) { return .insideVault }
        if vault.starts(with: drop) { return .containsVault }
        return nil
    }

    /// The drop folder as a `URL`, with a leading `~` expanded to `home`. A value that is
    /// neither `~`-relative nor absolute resolves under `home`, so a hand-edited relative path
    /// never points inside the working directory of whatever process reads it.
    func resolvedDropFolder(home: URL) -> URL {
        let trimmed = dropFolder.trimmingCharacters(in: .whitespaces)
        if let expanded = Self.expandedURL(trimmed, home: home) { return expanded }
        return home.appending(path: trimmed, directoryHint: .isDirectory)
    }

    /// The stored form of a chosen folder: `~/…` when it sits under `home`, its absolute path
    /// otherwise.
    static func storedDropFolder(for url: URL, home: URL) -> String {
        let folder = url.standardizedFileURL.pathComponents
        let homeComponents = home.standardizedFileURL.pathComponents
        guard folder.starts(with: homeComponents) else { return url.standardizedFileURL.path(percentEncoded: false) }
        let rest = folder.dropFirst(homeComponents.count)
        return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
    }

    // MARK: - The root

    /// Why a Contenitore root was refused.
    enum RootRefusal: Equatable, Sendable {
        case empty
        case outsideVault
        case hidden
        case insidePratiche
        case containsPratiche

        var sentence: String {
            switch self {
            case .empty: "Indica la cartella del Contenitore."
            case .outsideVault: "La cartella del Contenitore deve stare dentro la vault."
            case .hidden: "La cartella del Contenitore non può essere nascosta."
            case .insidePratiche: "La cartella del Contenitore non può stare dentro la cartella delle Pratiche."
            case .containsPratiche: "La cartella del Contenitore non può contenere la cartella delle Pratiche."
            }
        }
    }

    /// Nil when `root` may be the Contenitore root: a strict vault subfolder, no component
    /// hidden, neither inside the Pratiche folder (or equal to it) nor containing it.
    static func validateRoot(_ root: String, praticheFolder: String) -> RootRefusal? {
        let trimmed = root.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") { return .outsideVault }
        let components = folderComponents(trimmed)
        guard !components.isEmpty else { return .empty }
        if components.contains("..") { return .outsideVault }
        if components.contains(where: { $0.hasPrefix(".") }) { return .hidden }

        let pratiche = folderComponents(praticheFolder)
        guard !pratiche.isEmpty else { return nil }
        if components.starts(with: pratiche) { return .insidePratiche }
        if pratiche.starts(with: components) { return .containsPratiche }
        return nil
    }

    // MARK: - Paths

    /// `~` or `~/…` expanded against `home`, an absolute path as it is, nil for anything else.
    private static func expandedURL(_ path: String, home: URL) -> URL? {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appending(path: String(path.dropFirst(2)), directoryHint: .isDirectory)
        }
        if path.hasPrefix("/") { return URL(filePath: path, directoryHint: .isDirectory) }
        return nil
    }

    /// The path's components with every existing ancestor's symlinks resolved through
    /// `realpath`, and the part that does not exist yet appended as written: a drop folder is
    /// validated before it is created.
    private static func canonicalComponents(_ url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)),
              existing.pathComponents.count > 1 {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.path(percentEncoded: false)
        if let real = realpath(resolved, nil) {
            resolved = String(cString: real)
            free(real)
        }
        return URL(filePath: resolved).pathComponents + missing
    }

    private static func folderComponents(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
    }
}
