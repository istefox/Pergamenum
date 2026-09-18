import CryptoKit
import Foundation

extension PraticaSyncEngine {
    // MARK: - Attachment placement (R-10)

    /// Same name, different content: `-2`, `-3`, … before the extension (SPEC
    /// "Attachment file name"). Reached only after the SHA-256 check above, so a
    /// second copy of the same bytes never gets here.
    ///
    /// Not `private`: `PraticaSyncEngine+Messages.swift`'s `place(_:named:date:
    /// nameByDigest:taken:)` is an extension of this actor in a separate file, and
    /// is this member's only caller.
    static func uniqueAttachmentName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        let stem = (base as NSString).deletingPathExtension
        let suffix = (base as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = suffix.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(suffix)"
            if !taken.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Where an over-threshold attachment actually lives, for the chip that opens it
    /// «if still there» (SPEC "Edge cases"): Mail's own extracted copy when it exists,
    /// and otherwise the `.emlx` container that really holds those bytes. Never a path
    /// this app has not looked at.
    ///
    /// `part` is Mail's own IMAP-style body-part number (`MIMEPart.partNumber`,
    /// ADR-0048) - a string because it can be `"1.2"`, not a flat array index.
    ///
    /// Not `private`: `PraticaSyncEngine+Messages.swift`'s `prepare(_:request:reader:
    /// folder:)` is an extension of this actor in a separate file, and is this
    /// member's only caller.
    static func storePath(of name: String, at emlxURL: URL, rowID: Int, part: String) -> String {
        let extracted = EMLXReader
            .attachmentsDirectory(forMessageAt: emlxURL, rowID: rowID, part: part)
            .appending(path: name, directoryHint: .notDirectory)
        let path = extracted.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) ? path : emlxURL.path(percentEncoded: false)
    }

    /// Not `private`: `PraticaSyncEngine+Messages.swift`'s `place(...)` and
    /// `PraticaSyncEngine+Folder.swift`'s `folderContext(of:)` are both extensions of
    /// this actor in separate files, and both read this.
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
