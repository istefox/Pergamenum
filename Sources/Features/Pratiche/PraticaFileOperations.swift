import Foundation

// ADR-0045 §D2 (PG-143 structure refactor): `PraticaCommandActions`'s struct body
// mixed command dispatch with filesystem plumbing - a genuine second responsibility,
// not a size accident. Split out verbatim; `PraticaCommandActions.exclude`, `.move`,
// `.alsoAdd` and `.confirmRegeneration` now reach it through the computed `files`
// property instead of calling these directly.

/// The filesystem half of what «Escludi», «Sposta in…», «Aggiungi anche a…» and
/// «Rigenera…» do: trash, move, copy and restore a message's own files, with the
/// content rewrites a same-name collision forces. Two stored properties are enough -
/// `vault.root` and `pratiche.report(_:)` are the only things this block ever reached
/// for on `PraticaCommandActions` itself.
@MainActor
struct PraticaFileOperations {
    let vault: VaultController
    let pratiche: PraticheController

    // MARK: - Files

    /// One file the Trash is holding, and where it came from - what makes «Escludi»
    /// undoable rather than confirmed (UX-BLUEPRINT).
    struct TrashedFile: Equatable, Sendable {
        var original: URL
        var inTrash: URL
        var relativePath: String
    }

    /// One file this batch moved, both ends, for the inverse.
    struct MovedFile: Equatable, Sendable {
        var from: URL
        var to: URL
    }

    /// The message's own `.md` and its `.eml` sidecar - see `exclude(_:detail:)` for
    /// why the attachments stay where they are.
    ///
    /// Not `private`: `PraticaCommandActions.swift`'s `exclude(_:detail:)` and
    /// `confirmRegeneration(_:)` are in a separate file, and both call this.
    func trash(filesOf notePath: String) -> [TrashedFile] {
        guard let root = vault.root else { return [] }
        var trashed: [TrashedFile] = []
        for relativePath in Self.messageFilePaths(of: notePath) {
            let url = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            var landed: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            } catch {
                pratiche.report("«\(relativePath)» non è stato eliminato: \(error.localizedDescription)")
                continue
            }
            guard let inTrash = landed as URL? else { continue }
            trashed.append(TrashedFile(original: url, inTrash: inTrash, relativePath: relativePath))
        }
        return trashed
    }

    /// The inverse of `trash(filesOf:)`: back out of the Trash, to exactly where each
    /// file was.
    ///
    /// Not `private`: `PraticaCommandActions.swift`'s `exclude(_:detail:)` and
    /// `confirmRegeneration(_:)` are in a separate file, and both call this.
    func restore(_ files: [TrashedFile]) {
        for file in files {
            do {
                try FileManager.default.moveItem(at: file.inTrash, to: file.original)
            } catch {
                pratiche.report("«\(file.relativePath)» non è tornato al suo posto: \(error.localizedDescription)")
            }
        }
    }

    /// One `[[oldName]] -> [[newName]]` attachment-link rewrite made inside a moved/
    /// copied `.md`, so `moveBack` can put it back in the reverse direction.
    ///
    /// Not `private`: `ContentRewrites.attachmentRenames` below stores an array of
    /// these, and `ContentRewrites` widens to `internal` for `PraticaCommandActions
    /// .swift` (a stored property cannot be less accessible than its own type).
    struct AttachmentRename {
        var from: String
        var to: String
    }

    /// Everything a transfer's undo needs beyond the file paths themselves: the
    /// collision-driven content rewrites `moveFiles` and `copyAttachments` made
    /// *inside* the moved `.md` - restoring paths alone would leave the restored
    /// message pointing at a sidecar/attachment name that only made sense at the
    /// destination it was forced to collide at.
    ///
    /// Not `private`: `PraticaCommandActions.swift`'s `move(_:detail:to:)` holds the
    /// value `moveFiles` returns and hands it back to `reverseContentRewrites(_:
    /// notePath:)` from its undo block, both in a separate file.
    struct ContentRewrites {
        var originalBaseName: String
        /// `nil` when no `.md`/`.eml` collision happened at all.
        var renamedBaseName: String?
        var attachmentRenames: [AttachmentRename] = []
    }

    /// Not `private`: `PraticaCommandActions.swift`'s `move(_:detail:to:)` is in a
    /// separate file, and is this member's only caller.
    func moveFiles(
        of detail: PraticaRowDetail, to destination: String
    ) -> (files: [MovedFile], rewrites: ContentRewrites) {
        let originalBaseName = (detail.notePath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
        var rewrites = ContentRewrites(originalBaseName: originalBaseName, renamedBaseName: nil)
        guard let root = vault.root else { return ([], rewrites) }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata.")
            return ([], rewrites)
        }
        // Reserved once, for BOTH the `.md` and its `.eml` sidecar: a collision on
        // either extension alone would otherwise rename just that one file, leaving
        // `pergamenum-mail-original` pointing at a sidecar name that no longer exists.
        let baseName = Self.reservedBaseName(for: detail.notePath, in: folder)
        var moved: [MovedFile] = []
        var movedMD: URL?
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let ext = (relativePath as NSString).pathExtension
            let target = folder.appending(path: "\(baseName).\(ext)", directoryHint: .notDirectory)
            do {
                try FileManager.default.moveItem(at: source, to: target)
                moved.append(MovedFile(from: source, to: target))
                if ext == "md" { movedMD = target }
            } catch {
                pratiche.report("«\(relativePath)» non è stato spostato: \(error.localizedDescription)")
            }
        }
        if let movedMD, baseName != originalBaseName {
            Self.updateOriginalReference(at: movedMD, to: "\(baseName).eml")
            rewrites.renamedBaseName = baseName
        }
        // The attachments are copied rather than moved for the same reason «Escludi»
        // leaves them alone: one file in `allegati/` can be several messages'
        // attachment, and this one is only taking its own copy with it.
        rewrites.attachmentRenames = copyAttachments(of: detail, to: destination, patching: movedMD)
        return (moved, rewrites)
    }

    /// The inverse of `moveFiles`'s `rewrites`: put the moved `.md`'s OWN text back
    /// to what it said before the transfer, once `moveBack` has put the files back
    /// at their original paths. Order matters no more than `moveFiles`'s own two
    /// independent rewrites did - the sidecar reference and each attachment link are
    /// disjoint pieces of text.
    ///
    /// Not `private`: `PraticaCommandActions.swift`'s `move(_:detail:to:)` is in a
    /// separate file, and is this member's only caller.
    func reverseContentRewrites(_ rewrites: ContentRewrites, notePath: String) {
        guard let root = vault.root else { return }
        let mdURL = root.appending(path: notePath, directoryHint: .notDirectory)
        if rewrites.renamedBaseName != nil {
            Self.updateOriginalReference(at: mdURL, to: "\(rewrites.originalBaseName).eml")
        }
        for rename in rewrites.attachmentRenames {
            Self.renameAttachmentReference(in: mdURL, from: rename.to, to: rename.from)
        }
    }

    /// Not `private`: `PraticaCommandActions.swift`'s `alsoAdd(_:detail:to:)` is in a
    /// separate file, and is this member's only caller.
    func copyFiles(of detail: PraticaRowDetail, to destination: String) -> [URL] {
        guard let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata.")
            return []
        }
        let baseName = Self.reservedBaseName(for: detail.notePath, in: folder)
        var copied: [URL] = []
        var copiedMD: URL?
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let ext = (relativePath as NSString).pathExtension
            let target = folder.appending(path: "\(baseName).\(ext)", directoryHint: .notDirectory)
            do {
                try FileManager.default.copyItem(at: source, to: target)
                copied.append(target)
                if ext == "md" { copiedMD = target }
            } catch {
                pratiche.report("«\(relativePath)» non è stato copiato: \(error.localizedDescription)")
            }
        }
        if let copiedMD, baseName != (detail.notePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "") {
            Self.updateOriginalReference(at: copiedMD, to: "\(baseName).eml")
        }
        copyAttachments(of: detail, to: destination, patching: copiedMD)
        return copied
    }

    /// One free basename for BOTH extensions, checked together - `ImportNaming
    /// .uniqueFileName` only ever frees one file's own name, which is exactly the gap
    /// `moveFiles`/`copyFiles` used to fall into when only the `.md` or only the
    /// `.eml` collided.
    private static func reservedBaseName(for notePath: String, in folder: URL) -> String {
        let stem = (notePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        var candidate = stem
        var suffix = 2
        func taken(_ ext: String) -> Bool {
            FileManager.default.fileExists(
                atPath: folder.appending(path: "\(candidate).\(ext)", directoryHint: .notDirectory)
                    .path(percentEncoded: false)
            )
        }
        while taken("md") || taken("eml") {
            candidate = "\(stem)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// A byte-preserving patch of one scalar line, the same discipline
    /// `Dossier.merging` already applies to keys it does not own - re-rendering the
    /// whole document through `MessageDocument.render` would need the note's `tags`/
    /// `related`/`aliases` this function never had a reason to load.
    private static func updateOriginalReference(at mdURL: URL, to emlFileName: String) {
        guard var text = try? String(contentsOf: mdURL, encoding: .utf8) else { return }
        guard let range = text.range(
            of: #"pergamenum-mail-original:\s*"[^"]*""#, options: .regularExpression
        ) else { return }
        text.replaceSubrange(range, with: "pergamenum-mail-original: \"\(emlFileName)\"")
        try? text.write(to: mdURL, atomically: true, encoding: .utf8)
    }

    /// Returns the `from` URL of every file actually restored - the caller must not
    /// rewrite content back into a path whose restore failed, since that path may by
    /// now hold an unrelated note that merely reused the same name.
    ///
    /// Not `private`: `PraticaCommandActions.swift`'s `move(_:detail:to:)` is in a
    /// separate file, and is this member's only caller.
    @discardableResult
    func moveBack(_ files: [MovedFile]) -> Set<URL> {
        var restored: Set<URL> = []
        for file in files {
            do {
                try FileManager.default.moveItem(at: file.to, to: file.from)
                restored.insert(file.from)
            } catch {
                pratiche.report(
                    "«\(file.to.lastPathComponent)» non è tornato al suo posto: \(error.localizedDescription)"
                )
            }
        }
        return restored
    }

    /// The message's `.md` and the `.eml` beside it (R-09's sidecar), vault-relative.
    private static func messageFilePaths(of notePath: String) -> [String] {
        [notePath, (notePath as NSString).deletingPathExtension + ".eml"]
    }
}
