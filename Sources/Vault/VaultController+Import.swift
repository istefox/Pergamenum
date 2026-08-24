import Foundation

/// A file chosen from outside the vault, proposed a name and waiting for confirmation
/// (SPEC §10, File → "Importa file…").
struct FileImportProposal: Identifiable, Sendable {
    let id = UUID()
    let source: URL
    let originalName: String
    /// Editable by the user before the copy happens.
    var proposedName: String
}

/// The vault-wide counterpart of `WorkspaceController.importFiles`/`commitImport`
/// (`Sources/Features/Workspace/WorkspaceController+Import.swift`): same naming-assist
/// logic (`ImportNaming`, `EmailHeaderParser`), reached from the File menu rather than
/// from a drag onto an open board, so it lands in the Inbox rather than on a card.
extension VaultController {
    /// Proposes names for files chosen from outside the vault. Only `.eml` gets the
    /// naming.md rename assist (§4.2/7.3); everything else keeps its name, uniquified
    /// against the Inbox.
    func proposeImport(_ urls: [URL]) -> [FileImportProposal] {
        guard let root else { return [] }
        let directory = root.appending(
            path: VaultAPI.CaptureDestination.defaultFolder, directoryHint: .isDirectory
        )
        return urls.map { url in
            let original = url.lastPathComponent
            var proposed = original
            if url.pathExtension.lowercased() == "eml",
               let data = try? Data(contentsOf: url) {
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) ?? ""
                proposed = ImportNaming.proposedEmailFileName(
                    headers: EmailHeaderParser.parse(text),
                    currentFileName: original,
                    today: .today
                )
            }
            return FileImportProposal(
                source: url,
                originalName: original,
                proposedName: ImportNaming.uniqueFileName(proposed, in: directory)
            )
        }
    }

    /// Copies a confirmed proposal into the Inbox. Copy, not move: the source may be
    /// outside the vault (`WorkspaceController+Import.swift`'s own `commitImport`
    /// carries the same reasoning).
    @discardableResult
    func commitImport(_ proposal: FileImportProposal) -> String? {
        guard let root else { return nil }
        let directory = root.appending(
            path: VaultAPI.CaptureDestination.defaultFolder, directoryHint: .isDirectory
        )
        let destination = directory.appending(
            path: proposal.proposedName, directoryHint: .notDirectory
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: proposal.source, to: destination)
        } catch {
            recordProblem("import di \(proposal.originalName): \(error.localizedDescription)")
            return nil
        }
        return "\(VaultAPI.CaptureDestination.defaultFolder)/\(proposal.proposedName)"
    }
}
