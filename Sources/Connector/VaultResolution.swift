import Foundation

/// Which vault a connector acts on, and how it opens it.
///
/// Shared by `perg` and by the MCP server: both are started by somebody who did not
/// necessarily say which vault they meant, and both should land on the same one.
enum VaultResolution {
    /// In order: `--vault`, `PERGAMENUM_VAULT`, then the vault the app opened last.
    ///
    /// The third is what makes the tool usable without arguments, and it costs nothing:
    /// `RecentVaults` keeps plain paths in `UserDefaults`, not security-scoped
    /// bookmarks, and takes its store by injection - so reading the app's own domain is
    /// two lines and no change to that type. A sandboxed process could not do this; the
    /// app is not sandboxed in v1 and neither is this (SPEC §2).
    static func root(from arguments: Arguments) throws -> URL {
        if let given = arguments["vault"] {
            return try directory(at: given, describedAs: "--vault")
        }
        if let environment = ProcessInfo.processInfo.environment["PERGAMENUM_VAULT"],
           !environment.isEmpty {
            return try directory(at: environment, describedAs: "PERGAMENUM_VAULT")
        }
        guard let defaults = UserDefaults(suiteName: AppInfo.bundleIdentifier),
              let recent = RecentVaults(defaults: defaults, isOverridden: false).mostRecent
        else {
            throw ConnectorError(
                """
                nessun vault: passa --vault <cartella>, imposta PERGAMENUM_VAULT, \
                oppure aprine uno in Pergamenum
                """,
                usage: true
            )
        }
        return recent
    }

    /// Opens a session on a vault and brings its index up to date.
    ///
    /// The bundled vocabulary is nil here and that is deliberate: a command-line tool
    /// has no resource bundle to carry `vocabolari.json` in. A vault the app has opened
    /// already holds its own replica in `.pergamenum/`, which is the copy that governs
    /// (SPEC §4.6, principle 5); a vault that has never been opened gets an empty
    /// vocabulary and says so, rather than being judged against tables it does not have.
    @MainActor
    static func session(at root: URL) async throws -> VaultSession {
        let stateBase: URL
        do {
            stateBase = try VaultState.applicationSupportBase()
        } catch {
            throw ConnectorError("Application Support non raggiungibile: \(error.localizedDescription)")
        }
        let session = VaultSession(root: root, stateBase: stateBase, bundledVocabulary: nil)
        await session.rescan()
        return session
    }

    private static func directory(at path: String, describedAs source: String) throws -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ConnectorError("\(source): «\(path)» non è una cartella", usage: true)
        }
        return URL(filePath: expanded, directoryHint: .isDirectory)
    }
}
