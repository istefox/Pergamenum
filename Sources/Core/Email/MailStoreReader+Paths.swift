import Foundation

// ADR-0045 §D3/§D7 (PG-143 structure refactor): the `.emlx` path derivation, split out
// of `MailStoreReader.swift` for its own file-length warning - moved verbatim,
// Foundation only, no SwiftUI or AppKit, so both connectors keep compiling it.

extension MailStoreReader {
    /// The `.emlx` path predicted for a row from its mailbox url + ROWID (R-03,
    /// PROBE 2 / ADR §D4), measured on three real rows in three mailboxes of two
    /// accounts on 2026-09-09:
    ///
    ///     <root>/<account>/<Folder>.mbox[/<Sub>.mbox…]/<store-uuid>/Data/<fan>/Messages/<ROWID>.emlx
    ///
    /// - the account is the mailbox url's host, the folders are its path components
    ///   percent-decoded, one `.mbox` directory each, nested;
    /// - `<store-uuid>` is one UUID directory inside the `.mbox`, identical for every
    ///   mailbox of every account in this store - it is *not* in the index, so it is
    ///   read from the directory rather than derived;
    /// - `<fan>` is `ROWID / 1000` written one digit per directory **in reverse**, and
    ///   is empty for a ROWID below 1000 (measured: `146053` → `6/4/1`, `83970` →
    ///   `3/8`, `8900` → `8`, `169` → none).
    ///
    /// Predicted, never verified: whether that file exists, whether Mail parked a
    /// headers-only `<ROWID>.partial.emlx` there instead (PROBE 2 found 723 of them in
    /// one mailbox - R-15's «corpo non ancora scaricato», never R-16's «non più in
    /// Mail»), and the bounded enumeration that repairs a drifted rule are ADR §D4's
    /// `EMLXLocator`, Task 2.
    func emlxPath(forRow row: MailMessageRow) -> URL? {
        guard let mailbox = Self.mailboxDirectory(for: row.mailbox.url, under: mailRoot) else { return nil }
        var directory = Self.storeDirectory(in: mailbox).appending(path: "Data", directoryHint: .isDirectory)
        for digit in Self.fanOut(forRowID: row.rowID) {
            directory = directory.appending(path: digit, directoryHint: .isDirectory)
        }
        return directory
            .appending(path: "Messages", directoryHint: .isDirectory)
            .appending(path: "\(row.rowID).emlx", directoryHint: .notDirectory)
    }

    // MARK: - Paths

    /// The fixture store and the published copy are told apart by the one directory
    /// name Mail's own layout guarantees: `<root>/MailData/Envelope Index`. A store
    /// opened anywhere else is a published generation (`<state>/gen-…/Envelope Index`),
    /// whose `.emlx` files live in the *live* tree, not beside the copy.
    ///
    /// Not `private`: `MailStoreReader.swift`'s `init(storeURL:)` is the struct's own
    /// declaration in a separate file, and is this member's only caller.
    static func mailRoot(forStoreAt storeURL: URL) -> URL {
        let container = storeURL.deletingLastPathComponent()
        if container.lastPathComponent == "MailData" {
            return container.deletingLastPathComponent()
        }
        return MailStoreLocation.resolve()
    }

    private static func mailboxDirectory(for mailboxURL: String, under root: URL) -> URL? {
        // Decoded on both halves: `pathComponents` already decodes, and `host()`
        // defaults to the *encoded* form, which would spell a directory name Mail
        // never wrote if an account identifier ever stopped being a bare UUID.
        guard let parsed = URL(string: mailboxURL),
              let account = parsed.host(percentEncoded: false)
        else { return nil }
        var directory = root.appending(path: account, directoryHint: .isDirectory)
        for component in parsed.pathComponents where component != "/" {
            directory = directory.appending(path: "\(component).mbox", directoryHint: .isDirectory)
        }
        return directory
    }

    /// The UUID directory inside a `.mbox`, when there is one. Read rather than
    /// derived: PROBE 2 measured it identical across both accounts and all three
    /// mailboxes, but nothing in the index carries it, so guessing it would be
    /// guessing.
    private static func storeDirectory(in mailbox: URL) -> URL {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: mailbox, includingPropertiesForKeys: nil
        ) else { return mailbox }

        guard let store = entries.first(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
            return mailbox
        }
        return mailbox.appending(path: store.lastPathComponent, directoryHint: .isDirectory)
    }

    /// `146053` → `["6", "4", "1"]`; `8900` → `["8"]`; `169` → `[]` (PROBE 2).
    private static func fanOut(forRowID rowID: Int) -> [String] {
        let quotient = rowID / 1000
        guard quotient > 0 else { return [] }
        return String(quotient).reversed().map(String.init)
    }
}
