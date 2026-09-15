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
