import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D6, plan
// docs/plans/contenitore.md, Task 3. Split out of `NoteFileOperations.swift` in ADR-0045's
// `Type+Aspect` shape; shared with `perg` and `pergamenum-mcp` through `sharedSources`.

// MARK: - Document pairs (ADR-0071 §D6)

extension NoteFileOperations {
    /// What a Contenitore pair rename or move would change: both destinations, the notes and
    /// boards rewritten (the title rewrite and the file-name rewrite composed into one change per
    /// file), and anything skipped or unreadable along the way.
    struct PairPlan: Equatable, Sendable {
        var newPath: String
        /// The file's destination, nil for a scheda whose file is missing.
        var companionNewPath: String?
        var noteChanges: [VaultFileChange] = []
        var boardChanges: [VaultFileChange] = []
        var failures: [String] = []
    }

    /// A pair rename: the scheda and its file both take `newStem`, in their own folder (R-21).
    /// Both new names must be free, or both files are refused.
    func pairRenamePlan(
        scheda: String, companion: String?, newStem: String, knownPaths: [String]
    ) throws -> PairPlan {
        try pairPlan(
            scheda: scheda, companion: companion,
            folder: (scheda as NSString).deletingLastPathComponent,
            newStem: newStem, knownPaths: knownPaths
        )
    }

    /// A pair move into `folder`, keeping the stem, or taking `newStem` when the caller passes
    /// one - a collision `VaultSession.moveDocument` resolved in the same plan. A move alone
    /// rewrites no note: a bare-name file link resolves anywhere (ADR-0071 Context 6).
    func pairMovePlan(
        scheda: String, companion: String?, toFolder folder: String, renamingTo newStem: String?,
        knownPaths: [String]
    ) throws -> PairPlan {
        let stem = NoteName.title(fromFileName: (scheda as NSString).lastPathComponent)
        return try pairPlan(
            scheda: scheda, companion: companion, folder: folder, newStem: newStem ?? stem,
            knownPaths: knownPaths
        )
    }

    /// The file's extension, read off its name against the scheda's stem rather than with
    /// `pathExtension`: `20260929 fattura 2026.01` with no extension would otherwise read `01`.
    static func companionExtension(stem: String, fileName: String) -> String {
        guard fileName.count > stem.count, fileName.lowercased().hasPrefix(stem.lowercased() + ".") else {
            return fileName.count == stem.count ? "" : (fileName as NSString).pathExtension
        }
        return String(fileName.dropFirst(stem.count + 1))
    }

    private func pairPlan(
        scheda: String, companion: String?, folder: String, newStem: String, knownPaths: [String]
    ) throws -> PairPlan {
        let names = try checkedPairNames(scheda: scheda, companion: companion, folder: folder, newStem: newStem)
        return pairChanges(names, knownPaths: knownPaths)
    }

    /// Where both halves of a pair are and where they would go.
    private struct PairNames {
        let scheda: String
        let companion: String?
        let oldStem: String
        let newStem: String
        let newScheda: String
        let oldFileName: String?
        let newFileName: String?
        let newCompanion: String?

        /// Whether the file's own name changes, which the scheda's file key has to follow.
        var renamesFile: Bool { oldFileName != nil && oldFileName != newFileName }
    }

    /// The pair's new names, refused when the stem is invalid, either half is missing, or
    /// either destination is taken.
    private func checkedPairNames(
        scheda: String, companion: String?, folder: String, newStem: String
    ) throws -> PairNames {
        let oldStem = NoteName.title(fromFileName: (scheda as NSString).lastPathComponent)
        if newStem != oldStem {
            let violations = NoteName.validate(newStem)
            guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }
        }
        func joined(_ name: String) -> String { folder.isEmpty ? name : "\(folder)/\(name)" }

        let oldFileName = companion.map { ($0 as NSString).lastPathComponent }
        let newFileName = oldFileName.map {
            ContenitoreNaming.fileName(stem: newStem, extension: Self.companionExtension(stem: oldStem, fileName: $0))
        }
        let newScheda = joined(NoteName.fileName(for: newStem))
        let newCompanion = newFileName.map(joined)

        guard exists(scheda) else { throw FileOperationError.missing(scheda) }
        if let companion, !exists(companion) { throw FileOperationError.missing(companion) }
        guard newScheda == scheda || !exists(newScheda) else { throw FileOperationError.alreadyExists(newScheda) }
        if let companion, let newCompanion, newCompanion != companion, exists(newCompanion) {
            throw FileOperationError.alreadyExists(newCompanion)
        }
        return PairNames(
            scheda: scheda, companion: companion, oldStem: oldStem, newStem: newStem, newScheda: newScheda,
            oldFileName: oldFileName, newFileName: newFileName, newCompanion: newCompanion
        )
    }

    /// Every note and board change the pair's new names call for.
    private func pairChanges(_ names: PairNames, knownPaths: [String]) -> PairPlan {
        var plan = PairPlan(newPath: names.newScheda, companionNewPath: names.newCompanion)
        let titles = pairTitleChanges(names)
        plan.failures = titles.failures

        let notes = pairNoteChanges(names, titleChanges: titles.changes, knownPaths: knownPaths)
        plan.noteChanges = notes.changes
        plan.failures.append(contentsOf: notes.failures)

        var repoints: [(from: String, to: String)] = []
        if names.newScheda != names.scheda { repoints.append((from: names.scheda, to: names.newScheda)) }
        if let companion = names.companion, let newCompanion = names.newCompanion, newCompanion != companion {
            repoints.append((from: companion, to: newCompanion))
        }
        if !repoints.isEmpty || !titles.changes.isEmpty {
            let boards = repointBoardsPlan(repoints: repoints, titleChanges: titles.changes)
            plan.boardChanges = boards.changes
            plan.failures.append(contentsOf: boards.failures)
        }
        return plan
    }

    /// The link targets to rewrite: the stem, when it changes, and the file name, when it changes
    /// and answers to this file alone.
    private func pairTitleChanges(
        _ names: PairNames
    ) -> (changes: [(old: String, new: String)], failures: [String]) {
        var changes: [(old: String, new: String)] = []
        var failures: [String] = []
        if names.newStem != names.oldStem { changes.append((old: names.oldStem, new: names.newStem)) }
        if let companion = names.companion, let oldFileName = names.oldFileName,
           let newFileName = names.newFileName, oldFileName != newFileName {
            // ADR-0022's ambiguity rule: another file answering to the same name elsewhere in
            // the vault would make every `[[<old name>]]` a guess, so none is rewritten.
            if filePaths(named: oldFileName).contains(where: { $0.lowercased() != companion.lowercased() }) {
                failures.append(
                    "«\(oldFileName)»: nome non univoco nella vault, i collegamenti al file non sono aggiornati"
                )
            } else {
                changes.append((old: oldFileName, new: newFileName))
            }
        }
        return (changes, failures)
    }

    /// The note text changes: every link rewrite, plus the scheda's own file key.
    private func pairNoteChanges(
        _ names: PairNames, titleChanges: [(old: String, new: String)], knownPaths: [String]
    ) -> (changes: [VaultFileChange], failures: [String]) {
        var changes: [VaultFileChange] = []
        var failures: [String] = []
        for path in knownPaths where !titleChanges.isEmpty || (names.renamesFile && path == names.scheda) {
            // The scheda is read where it still is and written where the performer moves it.
            let writePath = path == names.scheda ? names.newScheda : path
            guard let text = try? store.text(path) else {
                failures.append("\(path): non leggibile")
                continue
            }
            var updated = text
            for change in titleChanges {
                if let rewritten = NoteRename.rewritingLinks(in: updated, from: change.old, to: change.new) {
                    updated = rewritten
                }
            }
            // The scheda's own key names its companion by definition, not by a guess, so it
            // follows the rename even when the old file name is ambiguous elsewhere.
            if path == names.scheda, names.renamesFile, let newFileName = names.newFileName {
                updated = ContenitoreScheda.settingFileName(newFileName, in: updated)
            }
            guard updated != text else { continue }
            changes.append(VaultFileChange(path: writePath, before: text, after: updated))
        }
        return (changes, failures)
    }

    /// Every file in the vault whose name is `name`, case-insensitively, by vault-relative path:
    /// a walk rather than the index, which holds notes only. The one vault walk (ADR-0041 §D3),
    /// so the excluded directories are never entered.
    private func filePaths(named name: String) -> [String] {
        let wanted = name.lowercased()
        guard let walk = try? VaultWalk(boundary: VaultBoundary(root: store.root)) else { return [] }

        var paths: [String] = []
        walk.forEach { file in
            guard !file.isDirectory, file.name.lowercased() == wanted else { return }
            paths.append(file.relativePath)
        }
        return paths
    }
}
