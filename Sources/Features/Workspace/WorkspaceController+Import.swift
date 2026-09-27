import CoreGraphics
import Foundation

/// Bringing files into the board's folder (SPEC §6.1, §4.2).
extension WorkspaceController {
    /// Copies files into the board's folder and places a card for each.
    ///
    /// `.eml` files go through the assisted rename of SPEC §4.2: the proposal comes
    /// from the message's own headers, and the caller confirms it. Everything else
    /// keeps its name, sanitized against `NoteName.forbiddenCharacters` (PG-134/#234 -
    /// a dropped name carrying `#`/`[`/`]`/… would otherwise break a future `[[…]]`
    /// embed of the file) and deduplicated so an import never overwrites an earlier one -
    /// against disk and against the names this same drop has already minted (#569 point 8),
    /// since nothing is copied until every proposal is confirmed.
    @discardableResult
    func importFiles(_ urls: [URL], at point: CGPoint) -> [ImportProposal] {
        guard let store else { return [] }
        let directory: URL
        do {
            directory = try boardFolderURL(in: store)
        } catch {
            recordProblem("import: \(error)")
            return []
        }

        var proposals: [ImportProposal] = []
        var minted: Set<String> = []
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
            } else {
                proposed = ImportNaming.sanitizedFileName(original)
            }
            let unique = ImportNaming.uniqueFileName(proposed, in: directory, reserved: minted)
            minted.insert(unique)
            proposals.append(ImportProposal(
                source: url,
                originalName: original,
                proposedName: unique,
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
    ///
    /// The destination goes through the store's boundary (ADR-0041 §D2, #569 point 5):
    /// `proposedName` is editable text, and a name spelled to climb out of the folder must
    /// not climb out of the vault.
    @discardableResult
    func commitImport(_ proposal: ImportProposal) -> String? {
        guard let store else { return nil }
        let relativePath = folder.isEmpty
            ? proposal.proposedName
            : "\(folder)/\(proposal.proposedName)"

        do {
            let destination = try store.boundary.url(for: relativePath)
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Copy rather than move: the source may be outside the vault, and moving a
            // file out of someone's Downloads folder is not what "import" promises.
            try FileManager.default.copyItem(at: proposal.source, to: destination)
        } catch {
            // A boundary refusal names the path as spelled; its `localizedDescription` is
            // the generic Cocoa sentence, which says nothing to the person reading it.
            let reason = (error as? VaultBoundary.Violation)?.description ?? error.localizedDescription
            recordProblem("import di \(proposal.originalName): \(reason)")
            return nil
        }

        let id = placeFile(relativePath, at: proposal.point, creatingOnDisk: relativePath)
        refreshContents()
        return id
    }
}
