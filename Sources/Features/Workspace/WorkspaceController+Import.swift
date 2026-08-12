import CoreGraphics
import Foundation

/// Bringing files into the board's folder (SPEC §6.1, §4.2).
extension WorkspaceController {
    /// Copies files into the board's folder and places a card for each.
    ///
    /// `.eml` files go through the assisted rename of SPEC §4.2: the proposal comes
    /// from the message's own headers, and the caller confirms it. Everything else
    /// keeps its name, deduplicated so an import never overwrites an earlier one.
    @discardableResult
    func importFiles(_ urls: [URL], at point: CGPoint) -> [ImportProposal] {
        guard let store else { return [] }
        let directory = folder.isEmpty
            ? store.root
            : store.root.appending(path: folder, directoryHint: .isDirectory)

        var proposals: [ImportProposal] = []
        for (index, url) in urls.enumerated() {
            let original = url.lastPathComponent
            var proposed = original

            if url.pathExtension.lowercased() == "eml",
               let data = try? Data(contentsOf: url) {
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                proposed = ImportNaming.proposedEmailFileName(
                    headers: EmailHeaderParser.parse(text),
                    currentFileName: original,
                    today: .today
                )
            }
            proposals.append(ImportProposal(
                source: url,
                originalName: original,
                proposedName: ImportNaming.uniqueFileName(proposed, in: directory),
                // Cascaded so several files dropped at once do not land on top of
                // each other.
                point: CGPoint(x: point.x + CGFloat(index) * 24, y: point.y + CGFloat(index) * 24)
            ))
        }
        return proposals
    }

    struct ImportProposal: Identifiable, Sendable {
        let id = UUID()
        var source: URL
        var originalName: String
        /// Editable by the user before the copy happens.
        var proposedName: String
        var point: CGPoint
    }

    /// Performs a confirmed import: copies the file in and places its card.
    @discardableResult
    func commitImport(_ proposal: ImportProposal) -> String? {
        guard let store else { return nil }
        let directory = folder.isEmpty
            ? store.root
            : store.root.appending(path: folder, directoryHint: .isDirectory)
        let destination = directory.appending(path: proposal.proposedName, directoryHint: .notDirectory)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Copy rather than move: the source may be outside the vault, and moving a
            // file out of someone's Downloads folder is not what "import" promises.
            try FileManager.default.copyItem(at: proposal.source, to: destination)
        } catch {
            recordProblem("import di \(proposal.originalName): \(error.localizedDescription)")
            return nil
        }

        let relativePath = folder.isEmpty
            ? proposal.proposedName
            : "\(folder)/\(proposal.proposedName)"
        let id = placeFile(relativePath, at: proposal.point, creatingOnDisk: relativePath)
        refreshContents()
        return id
    }
}
