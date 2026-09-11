import Foundation
import SQLite3

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02,
// R-03.
//
// The only file in this repository allowed to say `sqlite3_` for the Mail-store
// family (ADR §D1) - `Sources/Index/IndexCache.swift` is a separate, pre-existing
// SQLite user for a different store (the app's own cache) and is outside this rule.
// `MailStoreReader` and everything above it talks to this type, never to the C API
// directly; `Tests/MailStoreReaderTests.swift` asserts that no other file under
// `Sources/Core/Email/` contains the string `sqlite3_`.
//
// Every value bound to a statement must use the transient destructor
// (`unsafeBitCast(-1, to: sqlite3_destructor_type.self)`, `SQLITE_TRANSIENT`'s macro
// is invisible to the Swift importer) - a `String` bound without it is a pointer that
// is dead before `sqlite3_step` runs. `SQLITE_OPEN_CREATE` is never passed to
// `sqlite3_open_v2`: a missing copy has to fail loudly, not silently become an empty,
// permanently-`.storeMissing`-hiding database.
final class MailStoreConnection {
    /// What can go wrong opening or querying the published copy.
    ///
    /// `prepareFailed` covers a failing `sqlite3_step` as well as a failing
    /// `sqlite3_prepare_v2`: both carry the same `(code, message)` pair, and the
    /// callers - `MailStoreCopy`, which treats any throw as "torn copy, retry", and
    /// `MailStoreReader`, which answers an empty result - never branch on which of
    /// the two failed.
    enum ConnectionError: Error, Equatable, Sendable, CustomStringConvertible {
        case fileMissing
        case openFailed(code: Int32, message: String)
        case prepareFailed(code: Int32, message: String)
        case integrityCheckFailed(detail: String)

        var description: String {
            switch self {
            case .fileMissing: "il file dell'indice non esiste"
            case let .openFailed(code, message): "apertura dell'indice fallita (\(code)): \(message)"
            case let .prepareFailed(code, message): "preparazione della query fallita (\(code)): \(message)"
            case let .integrityCheckFailed(detail): "controllo di integrità fallito: \(detail)"
            }
        }
    }

    /// `SQLITE_TRANSIENT`: the macro the Swift importer cannot see, spelled the way
    /// `IndexCache` already spells it. Without it SQLite keeps the pointer a bridged
    /// Swift `String` hands over for the duration of the call only, and reads freed
    /// memory at `sqlite3_step` - intermittently wrong rows, never a crash.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var handle: OpaquePointer?

    private init(handle: OpaquePointer?) {
        self.handle = handle
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    /// Opens `url` (the copy's own `Envelope Index`, never Mail's live file) without
    /// `SQLITE_OPEN_CREATE` - a missing copy must throw, never mint an empty database.
    ///
    /// `readOnly: false` is the recovery open of ADR §D2 step 2: writing to *our own
    /// copy* is what makes SQLite replay the `-wal` into it. Mail's own file is never
    /// passed here, by either caller.
    static func open(at url: URL, readOnly: Bool) throws -> MailStoreConnection {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConnectionError.fileMissing
        }

        var database: OpaquePointer?
        // Never `SQLITE_OPEN_CREATE`, in either branch (ADR §D1).
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        let code = sqlite3_open_v2(path, &database, flags, nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? String(cString: sqlite3_errstr(code))
            if let database {
                sqlite3_close(database)
            }
            throw ConnectionError.openFailed(code: code, message: message)
        }
        return MailStoreConnection(handle: database)
    }

    /// `PRAGMA quick_check` + `SELECT count(*) FROM messages` (ADR §D2 step 3): a
    /// torn copy surfaces here as `SQLITE_CORRUPT`/`SQLITE_NOTADB`, never as missing
    /// messages discovered later.
    ///
    /// The count is not asserted to be non-zero: an empty store is a legitimate,
    /// visible state ("nessun messaggio"), and the query's job is to prove the
    /// `messages` table exists and its pages are readable - a truncated copy fails to
    /// prepare it at all.
    func quickCheck() throws {
        let check = try prepare("PRAGMA quick_check;")
        defer { finalize(check) }
        guard try step(check), let result = columnText(check, 0) else {
            throw ConnectionError.integrityCheckFailed(detail: "PRAGMA quick_check non ha risposto")
        }
        guard result == "ok" else {
            throw ConnectionError.integrityCheckFailed(detail: result)
        }

        let count = try prepare("SELECT count(*) FROM messages;")
        defer { finalize(count) }
        guard try step(count), columnInt(count, 0) != nil else {
            throw ConnectionError.integrityCheckFailed(detail: "la tabella messages non è leggibile")
        }
    }

    /// Prepares one statement; the caller binds, steps and finalizes it.
    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else {
            throw ConnectionError.prepareFailed(code: SQLITE_MISUSE, message: "connessione già chiusa")
        }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(handle))
            if let statement {
                sqlite3_finalize(statement)
            }
            throw ConnectionError.prepareFailed(code: code, message: message)
        }
        return statement
    }

    /// Binds a `TEXT` parameter with the transient destructor (`SQLITE_TRANSIENT`'s
    /// macro is invisible to the Swift importer) - binding without it hands SQLite a
    /// pointer that is dead before `sqlite3_step` runs.
    func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    func bindInt(_ statement: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    /// Steps once; `true` while a row is available, `false` at `SQLITE_DONE`.
    func step(_ statement: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? String(cString: sqlite3_errstr(code))
            throw ConnectionError.prepareFailed(code: code, message: message)
        }
    }

    func finalize(_ statement: OpaquePointer) {
        sqlite3_finalize(statement)
    }

    /// A `TEXT` column, or `nil` when the column is SQL `NULL`.
    func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: text)
    }

    /// An `INTEGER` column, or `nil` when the column is SQL `NULL`.
    func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }
}
