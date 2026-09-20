import Foundation

extension PraticaSyncEngine {
    // MARK: - Paths and constants

    /// `email/` or `allegati/` under the pratica's own folder, refused when
    /// `praticaFolder` escapes the vault (ADR-0041 §D2). Every read and every write this
    /// engine performs under a pratica goes through here, so the refusal lands before the
    /// directory is listed rather than after something has been read out of it.
    ///
    /// Not `private`, on this member and every other one below: `PraticaSyncEngine+
    /// Folder.swift`'s `folderContext(of:)` and `PraticaSyncEngine+Messages.swift`'s
    /// `commit(_:request:folder:outcome:)`/`prepare(_:request:reader:folder:)` are
    /// extensions of this actor in separate files, and read them.
    func directory(_ name: String, of request: SyncRequest) throws -> URL {
        let folder = request.praticaFolder
        return try boundary.url(for: folder.isEmpty ? name : "\(folder)/\(name)")
    }

    /// `email/` or `allegati/` under a pratica that must **already** be one, created one level
    /// at a time (`withIntermediateDirectories: false`, the precedent
    /// `CanvasStore.createFolder` sets). Returned as is when it exists.
    ///
    /// PG-168: the message in flight when a pratica folder moves or is trashed is past this
    /// engine's cooperative cancellation boundary, and a write that creates its own parent
    /// chain brings the vacated folder back - a stray `email/` holding a valid message and no
    /// `pratica.md`, which nothing lists or repairs. A sync is not entitled to bring a pratica
    /// into existence, so this throws `VaultWriteRefusal.folderVanished` instead.
    ///
    /// Two preconditions at two layers, on purpose. `VaultSession.write`'s
    /// `requiringExistingFolder:` asks only "does the parent directory exist" and must not
    /// learn what a pratica is. This asks the domain question: does `pratica.md` still sit
    /// beside the folder, the marker `PraticheController.dossier(at:)` recognises a pratica
    /// by, so it is exactly the condition under which a directory made here is still part of
    /// a pratica rather than orphan garbage. It also catches a folder that survived but lost
    /// its dossier, which the generic check cannot. Checked on every call, not only when the
    /// leaf is missing: `email/` can outlive the `pratica.md` that justified it.
    ///
    /// A pratica's first sync is unaffected - `runExclusive` reads `pratica.md` before the
    /// engine is even built. An empty `praticaFolder` (tolerated by `directory(_:of:)`) has
    /// no marker to look for.
    func makeDirectory(_ name: String, of request: SyncRequest) throws -> URL {
        let url = try directory(name, of: request)
        if !request.praticaFolder.isEmpty {
            let marker = try boundary.url(for: PraticaNaming.praticaNotePath(of: request.praticaFolder))
            guard FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else {
                throw VaultWriteRefusal.folderVanished(request.praticaFolder)
            }
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw VaultWriteRefusal.folderVanished(request.praticaFolder)
        }
        return url
    }

    static func fileNames(in directory: URL) -> [String] {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        )
        // Sorted, so every decision derived from what is already on disk is a function
        // of the folder's contents rather than of the file system's listing order.
        return (names ?? []).sorted()
    }

    static let frontmatterSchemaVersion = 1
    static let unknownCounterpart = "Sconosciuto"
    static let unnamedAttachment = "allegato"
    static let pendingPlaceholder =
        "*Il corpo di questo messaggio non è ancora stato scaricato da Mail.*"

    static func thresholdBytes(_ settings: PraticheSettings) -> Int {
        settings.attachmentThresholdMB * 1024 * 1024
    }
}
