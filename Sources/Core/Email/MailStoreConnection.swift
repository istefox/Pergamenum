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
// is dead before `sqlite3_step` runs. `SQLITE_OPEN_CREATE` must never be passed to
// `sqlite3_open_v2`: a missing copy has to fail loudly, not silently become an empty,
// permanently-`.storeMissing`-hiding database.
final class MailStoreConnection {
    /// What can go wrong opening or querying the published copy.
    enum ConnectionError: Error, Equatable, Sendable, CustomStringConvertible {
        case fileMissing
        case openFailed(code: Int32, message: String)
        case prepareFailed(code: Int32, message: String)
        case integrityCheckFailed(detail: String)
        /// Tester-declared boundary (ADR-0155): thrown unconditionally by every
        /// not-yet-implemented method below, so a call through this stub is always
        /// distinguishable from a real SQLite failure.
        case unimplemented

        var description: String {
            switch self {
            case .fileMissing: "il file dell'indice non esiste"
            case let .openFailed(code, message): "apertura dell'indice fallita (\(code)): \(message)"
            case let .prepareFailed(code, message): "preparazione della query fallita (\(code)): \(message)"
            case let .integrityCheckFailed(detail): "controllo di integrità fallito: \(detail)"
            case .unimplemented: "MailStoreConnection non è ancora implementata"
            }
        }
    }

    private var handle: OpaquePointer?

    private init(handle: OpaquePointer?) {
        self.handle = handle
    }

    deinit {
        // Real teardown is the coder's job (ADR §D1); nothing is ever opened by the
        // stub `open(at:readOnly:)` below, so `handle` is always nil here today.
        if let handle {
            sqlite3_close(handle)
        }
    }

    /// Opens `url` (the copy's own `Envelope Index`, never Mail's live file) without
    /// `SQLITE_OPEN_CREATE` - a missing copy must throw, never mint an empty database.
    ///
    /// Stub: tester-declared boundary (ADR-0155). Always throws `.unimplemented`,
    /// which is what makes every query built on top of a `MailStoreReader`
    /// (`Tests/MailStoreReaderTests.swift`) fail at construction until the coder
    /// implements the real open sequence.
    static func open(at url: URL, readOnly: Bool) throws -> MailStoreConnection {
        throw ConnectionError.unimplemented
    }

    /// `PRAGMA quick_check` + `SELECT count(*) FROM messages` (ADR §D2 step 3): a
    /// torn copy surfaces here as `SQLITE_CORRUPT`/`SQLITE_NOTADB`, never as missing
    /// messages discovered later.
    func quickCheck() throws {
        throw ConnectionError.unimplemented
    }

    /// Prepares one statement; the caller binds, steps and finalizes it.
    func prepare(_ sql: String) throws -> OpaquePointer {
        throw ConnectionError.unimplemented
    }

    /// Binds a `TEXT` parameter with the transient destructor (`SQLITE_TRANSIENT`'s
    /// macro is invisible to the Swift importer) - binding without it hands SQLite a
    /// pointer that is dead before `sqlite3_step` runs.
    func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        fatalError("MailStoreConnection.bindText is unreachable: open(at:readOnly:) always throws until implemented")
    }

    func bindInt(_ statement: OpaquePointer, _ index: Int32, _ value: Int) {
        fatalError("MailStoreConnection.bindInt is unreachable: open(at:readOnly:) always throws until implemented")
    }

    /// Steps once; `true` while a row is available, `false` at `SQLITE_DONE`.
    func step(_ statement: OpaquePointer) throws -> Bool {
        throw ConnectionError.unimplemented
    }

    func finalize(_ statement: OpaquePointer) {
        fatalError("MailStoreConnection.finalize is unreachable: open(at:readOnly:) always throws until implemented")
    }

    /// A `TEXT` column, or `nil` when the column is SQL `NULL`.
    func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        fatalError("MailStoreConnection.columnText is unreachable: open(at:readOnly:) always throws until implemented")
    }

    /// An `INTEGER` column, or `nil` when the column is SQL `NULL`.
    func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        fatalError("MailStoreConnection.columnInt is unreachable: open(at:readOnly:) always throws until implemented")
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }
}
