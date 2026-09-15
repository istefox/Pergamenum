import Foundation

// ADR-0045 §D2/PG-160: `PraticaFileOperations`'s attachment cluster, split out verbatim
// once it crossed `type_body_length`'s own warning line. Pure move, no behaviour change.

extension PraticaFileOperations {
    /// Not `private`: `PraticaFileOperations.swift`'s `moveFiles(of:to:)` and
    /// `copyFiles(of:to:)` are in a separate file, and both call this.
    @discardableResult
    func copyAttachments(
        of detail: PraticaRowDetail, to destination: String, patching mdURL: URL?
    ) -> [AttachmentRename] {
        guard !detail.attachments.isEmpty, let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.attachmentsDirectoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata: \(error.localizedDescription)")
            return []
        }
        let existingOnDisk = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        )
        // Every destination name reserved BEFORE any copy or rewrite happens, in one
        // planning pass - deciding a later attachment's unique name only after an
        // earlier one has already claimed (or been copied to) its own target is what
        // let two distinct attachments collide onto the same new name (:506).
        struct Plan { var attachment: PraticaAttachmentRef; var targetName: String; var reused: Bool }
        var claimed = existingOnDisk
        var plans: [Plan] = []
        // Two references sharing the same name are the SAME attachment (its `.name` is
        // its `Identifiable` id) referenced twice, not two distinct files that happen to
        // collide - planning a second `AttachmentRename` for a name already planned
        // would give `applyAttachmentRenames` a duplicate `from` key, which crashes
        // `Dictionary(uniqueKeysWithValues:)` AFTER the first copy already landed on
        // disk (:530). One plan per name; the single rename it produces already covers
        // every `[[name]]` occurrence in the note.
        var plannedNames: Set<String> = []
        for attachment in detail.attachments {
            guard plannedNames.insert(attachment.name).inserted else { continue }
            guard FileManager.default.fileExists(atPath: attachment.url.path(percentEncoded: false))
            else { continue }
            // The same name is the same attachment only when it is ALREADY on disk
            // (bytes to compare against) AND no earlier attachment in this same
            // batch has already claimed it as ITS OWN target - a name only reserved
            // so far, with nothing written yet, has no bytes this one could match.
            if existingOnDisk.contains(attachment.name), plans.allSatisfy({ $0.targetName != attachment.name }) {
                let target = folder.appending(path: attachment.name, directoryHint: .notDirectory)
                if Self.contentsMatch(attachment.url, target) {
                    plans.append(Plan(attachment: attachment, targetName: attachment.name, reused: true))
                    continue
                }
            }
            let targetName = claimed.contains(attachment.name)
                ? Self.reservedAttachmentName(attachment.name, avoiding: claimed)
                : attachment.name
            claimed.insert(targetName)
            plans.append(Plan(attachment: attachment, targetName: targetName, reused: false))
        }
        var renames: [AttachmentRename] = []
        for plan in plans where !plan.reused {
            let target = folder.appending(path: plan.targetName, directoryHint: .notDirectory)
            do {
                try FileManager.default.copyItem(at: plan.attachment.url, to: target)
                if plan.targetName != plan.attachment.name {
                    renames.append(AttachmentRename(from: plan.attachment.name, to: plan.targetName))
                }
            } catch {
                pratiche.report("«\(plan.attachment.name)» non è stato copiato: \(error.localizedDescription)")
            }
        }
        Self.applyAttachmentRenames(renames, toFileAt: mdURL)
        return renames
    }

    /// Renames every `[[oldName]]`/`![[oldName]]` reference to `attachment` inside the
    /// transferred message to `newName` - the other half of resolving a same-name,
    /// different-bytes collision (the file itself already got the new name).
    ///
    /// Not `private`: `PraticaFileOperations.swift`'s `reverseContentRewrites(_:
    /// notePath:)` is in a separate file, and is this member's only caller.
    static func renameAttachmentReference(in mdURL: URL?, from oldName: String, to newName: String) {
        applyAttachmentRenames([AttachmentRename(from: oldName, to: newName)], toFileAt: mdURL)
    }

    /// Every rename applied in ONE pass over the file's ORIGINAL text, keyed by the
    /// bracketed name each `[[...]]` token actually names - never as a sequence of
    /// `replacingOccurrences` calls. Two renames chained that way can cascade: once
    /// `quote.pdf` becomes `quote-2.pdf`, a SEPARATE `quote-2.pdf -> quote-2-2.pdf`
    /// pass would catch that just-rewritten text too, redirecting both attachments
    /// onto the same final name. Reading the map against the untouched original
    /// text is what keeps each token's rewrite independent of every other one's.
    private static func applyAttachmentRenames(_ renames: [AttachmentRename], toFileAt mdURL: URL?) {
        guard let mdURL, !renames.isEmpty, let text = try? String(contentsOf: mdURL, encoding: .utf8)
        else { return }
        let map = Dictionary(uniqueKeysWithValues: renames.map { ($0.from, $0.to) })
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return }
        let nsText = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let name = nsText.substring(with: match.range(at: 1))
            result += "[[\(map[name] ?? name)]]"
            lastEnd = match.range.location + match.range.length
        }
        result += nsText.substring(from: lastEnd)
        guard result != text else { return }
        try? result.write(to: mdURL, atomically: true, encoding: .utf8)
    }

    /// `ImportNaming.uniqueFileName`'s own rule (`-2`, `-3`, ...), but checked
    /// against a batch's in-flight reservations rather than the filesystem alone -
    /// the filesystem has nothing to check yet for a name this same call is about to
    /// claim for an earlier attachment.
    private static func reservedAttachmentName(_ proposed: String, avoiding reserved: Set<String>) -> String {
        let stem = (proposed as NSString).deletingPathExtension
        let ext = (proposed as NSString).pathExtension
        var suffix = 2
        var candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
        while reserved.contains(candidate) {
            suffix += 1
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
        }
        return candidate
    }

    /// Byte comparison, never a size/date *equality* shortcut: two attachments genuinely
    /// can share a size by coincidence, and this decides whether a destination file gets
    /// reused or renamed. Unequal sizes are the one thing a stat can settle, since they
    /// rule a match out outright.
    private static func contentsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        // Two files of different sizes cannot hold the same bytes, and a size is a stat
        // rather than a read of two attachments into memory. Every other case - equal
        // sizes, or a size that cannot be read at all - still goes to the byte comparison,
        // which stays the thing that decides.
        if let lhsSize = try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           let rhsSize = try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           lhsSize != rhsSize {
            return false
        }
        guard let a = try? Data(contentsOf: lhs), let b = try? Data(contentsOf: rhs) else { return false }
        return a == b
    }
}
