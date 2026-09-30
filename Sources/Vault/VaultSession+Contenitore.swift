import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D6, plan
// docs/plans/contenitore.md, Task 3 - R-20, R-21, R-22, R-23.
//
// In `sharedSources` (`Project.swift`): `renameNote`, `moveNote` and `trashNote`
// (`VaultSession+Files.swift`, shared) route a scheda through the pair performers here, and
// both connectors call those three doors. No connector gains a command from it (§D14).

/// A document pair's operations at the session's note doors (ADR-0071 §D6).
///
/// The rules that decide what changes are `NoteFileOperations.pairRenamePlan`/`pairMovePlan`;
/// what performs them is here, in one `transaction` per gesture, so both files and every
/// rewritten link carry one operation id and `isDryRun` stops all of it at once.
extension VaultSession {
    private var pairOperations: NoteFileOperations { NoteFileOperations(store: store) }

    /// This vault's extracted text, beside the vault (ADR-0071 §D8). Search reads it (§D9); the
    /// app's extraction queue writes it.
    var extractedTexts: ExtractedTextStore { ExtractedTextStore(directory: state.extractedText) }

    /// The companion file beside the scheda at `path`, when the note is a scheda whose file is
    /// present: the target of its `pergamenum-contenitore-file` key, in the scheda's own folder,
    /// with the scheda's own stem. Nil for any other note, and for a scheda whose file is
    /// missing, which is then operated on alone (§D6).
    ///
    /// The stem check is a guard, not a formality: a key edited by hand to name some other file
    /// must not make a rename of the scheda rename that file too.
    func companion(ofScheda path: String) -> String? {
        guard let facts = index.note(at: path)?.contenitore else { return nil }
        let fileName = facts.fileName
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }

        let stem = NoteName.title(fromFileName: (path as NSString).lastPathComponent).lowercased()
        let lowered = fileName.lowercased()
        guard lowered == stem || lowered.hasPrefix(stem + "."), !lowered.hasSuffix(".md") else { return nil }

        let folder = (path as NSString).deletingLastPathComponent
        let companion = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        return exists(companion) ? companion : nil
    }

    /// Moves a document into `<container>/<YYYY>`, where YYYY is the year of the scheda's
    /// `date` (R-20), creating the year folder. A collision there gives the pair one unique stem,
    /// applied to both files in the same plan and the same transaction; a free name moves the
    /// pair unchanged, since a bare-name file link needs no rewrite for a move (ADR-0071
    /// Context 6). A scheda whose file is missing moves alone.
    func moveDocument(at schedaPath: String, toContainer container: String) async throws -> NoteFileOperations.Outcome {
        guard let record = index.note(at: schedaPath) else { throw FileOperationError.missing(schedaPath) }
        let date = record.frontmatter.date
            ?? CalendarDate(compact: String(record.title.prefix(8)))
            ?? CalendarDate(Date())
        let folder = ContenitoreNaming.yearFolder(for: date, in: container)
        guard folder != (schedaPath as NSString).deletingLastPathComponent else {
            return NoteFileOperations.Outcome(newPath: schedaPath)
        }

        let companion = companion(ofScheda: schedaPath)
        let listing = Set(fileNames(inFolder: folder).map { $0.lowercased() })
        let schedaName = (schedaPath as NSString).lastPathComponent
        let companionName = companion.map { ($0 as NSString).lastPathComponent }
        var newStem: String?
        let companionTaken = companionName.map { listing.contains($0.lowercased()) } == true
        if listing.contains(schedaName.lowercased()) || companionTaken {
            let ext = companionName.map {
                NoteFileOperations.companionExtension(stem: record.title, fileName: $0)
            } ?? ""
            newStem = ContenitoreNaming.uniquePairStem(
                record.title, extension: ext,
                takenFileNames: listing,
                takenTitles: Set(index.allNotes.map(\.title))
            )
        }

        let plan = try pairOperations.pairMovePlan(
            scheda: schedaPath, companion: companion, toFolder: folder, renamingTo: newStem,
            knownPaths: index.allNotes.map(\.relativePath)
        )
        return try await performPair(plan, scheda: schedaPath, companion: companion, command: "note move")
    }

    /// Trashes a document's scheda and its file together, in one gesture (R-22), and returns
    /// the notes left linking to either beside where the Finder's trash put each file. A scheda
    /// whose file is missing is trashed alone.
    ///
    /// The file goes first: if the scheda then cannot be trashed, the file is brought back from
    /// the trash, so the pair goes whole or not at all, and the scheda's note id - which
    /// `trashFile` forgets - is never forgotten for a trash that did not happen. The file comes
    /// back through `restoreFromOutside`, which never reads a binary's bytes (§D3); a restore
    /// that fails too is named in the thrown error, never swallowed.
    func trashDocument(at schedaPath: String) async throws -> (orphaned: [String], trashURLs: [URL]) {
        let companion = companion(ofScheda: schedaPath)
        let knownPaths = index.allNotes.map(\.relativePath)
        var trashURLs: [URL] = []

        try await transaction("note trash") {
            var companionURL: URL?
            if let companion {
                companionURL = try await trashFile(at: companion)
                if let companionURL { trashURLs.append(companionURL) }
            }
            do {
                if let url = try await trashFile(at: schedaPath) { trashURLs.append(url) }
            } catch {
                guard let companion else { throw error }
                // The Trash gave no URL back, so there is nothing to restore from: the pair is
                // split and the error must say so rather than pass for a clean refusal.
                guard let companionURL else {
                    throw FileOperationError.failed(
                        "\(error); \(companion) è rimasto nel Cestino e non è stato possibile ripristinarlo"
                    )
                }
                do {
                    try await restoreFromOutside(companionURL, to: companion)
                } catch let restoreError {
                    throw FileOperationError.failed(
                        "\(error); \(companion) è rimasto nel Cestino: \(restoreError)"
                    )
                }
                throw error
            }
        }

        let orphaned = pairDanglingLinks(scheda: schedaPath, companion: companion, knownPaths: knownPaths)
        if !isDryRun {
            forgetStar(schedaPath)
            if let companion { forgetStar(companion) }
        }
        return (orphaned, trashURLs)
    }

    /// The notes left pointing at either half of a trashed pair, each named once.
    private func pairDanglingLinks(scheda: String, companion: String?, knownPaths: [String]) -> [String] {
        var orphaned = pairOperations.danglingLinks(for: scheda, knownPaths: knownPaths)
        guard let companion else { return orphaned }
        for path in pairOperations.danglingLinks(for: companion, knownPaths: knownPaths)
        where !orphaned.contains(path) {
            orphaned.append(path)
        }
        return orphaned
    }

    // MARK: - Performers the note doors call

    /// `renameNote` for a scheda with its file beside it: both files take `newStem` (R-21).
    func renameDocumentPair(
        scheda: String, companion: String, to newStem: String
    ) async throws -> NoteFileOperations.Outcome {
        let plan = try pairOperations.pairRenamePlan(
            scheda: scheda, companion: companion, newStem: newStem,
            knownPaths: index.allNotes.map(\.relativePath)
        )
        return try await performPair(plan, scheda: scheda, companion: companion, command: "note rename")
    }

    /// `moveNote` for a scheda with its file beside it: both files move, or a collision refuses
    /// both (§D6: the session's `moveNote` passes no new stem).
    func moveDocumentPair(
        scheda: String, companion: String, toFolder folder: String
    ) async throws -> NoteFileOperations.Outcome {
        let plan = try pairOperations.pairMovePlan(
            scheda: scheda, companion: companion, toFolder: folder, renamingTo: nil,
            knownPaths: index.allNotes.map(\.relativePath)
        )
        return try await performPair(plan, scheda: scheda, companion: companion, command: "note move")
    }

    /// One transaction: the scheda's move, the file's move, then every composed note and board
    /// rewrite through the guarded writers (ADR-0046 §D1). The id and the star follow through
    /// `moveFile`. If the file cannot move after the scheda did, the scheda is moved back, so a
    /// pair never ends split across two folders; a move back that fails too is named in the
    /// thrown error, never swallowed.
    private func performPair(
        _ plan: NoteFileOperations.PairPlan, scheda: String, companion: String?, command: String
    ) async throws -> NoteFileOperations.Outcome {
        var outcome = NoteFileOperations.Outcome(newPath: plan.newPath, failures: plan.failures)
        guard plan.newPath != scheda || plan.companionNewPath != companion else { return outcome }

        try await transaction(command) {
            if plan.newPath != scheda {
                try await moveFile(from: scheda, to: plan.newPath)
            }
            if let companion, let target = plan.companionNewPath, target != companion {
                do {
                    try await moveFile(from: companion, to: target)
                } catch {
                    guard plan.newPath != scheda else { throw error }
                    do {
                        try await moveFile(from: plan.newPath, to: scheda)
                    } catch let rollbackError {
                        throw FileOperationError.failed(
                            "\(error); \(plan.newPath) non è tornata in \(scheda): \(rollbackError)"
                        )
                    }
                    throw error
                }
            }
            let notes = await VaultPlanApplication.apply(plan.noteChanges, writing: writeGuarded)
            let boards = await VaultPlanApplication.apply(plan.boardChanges, writing: writeFileGuarded)
            outcome.rewrittenPaths.append(contentsOf: notes.rewrittenPaths + boards.rewrittenPaths)
            outcome.failures.append(contentsOf: notes.failures + boards.failures)
            outcome.refusals.append(contentsOf: notes.refusals + boards.refusals)
        }
        return outcome
    }

    /// The names directly inside a vault folder, or none when it does not exist yet.
    private func fileNames(inFolder folder: String) -> [String] {
        guard let url = try? store.url(for: folder) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
    }
}
