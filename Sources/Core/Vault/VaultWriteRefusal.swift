import Foundation

/// Thrown by `VaultSession.write(_:to:expecting:)` and `writeFile(_:to:expecting:)` when the
/// caller's `expecting` hash no longer matches the file's current bytes: the read that produced
/// `text` straddled a suspension, somebody else wrote in between, and this write refuses rather
/// than silently discarding that edit.
///
/// Moved out of `VaultSession` (ADR-0046 §D4) so `VaultPlanApplication.apply`, which lives in
/// `Sources/Core` and cannot catch a type declared in `Sources/Vault`, can classify it as its own
/// outcome channel rather than an ordinary failure. `VaultSession.WriteRefusal` stays as an
/// unqualified typealias so all fifteen existing references keep compiling.
enum VaultWriteRefusal: Error, CustomStringConvertible, Equatable {
    case movedOn(String)
    /// The directory a write was about to land in does not exist, and the write was asked not
    /// to create it (`requiringExistingFolder:`, PG-168). Carries the *folder*, not the file,
    /// unlike `movedOn`: the folder is the actionable thing, since the file was never going to
    /// be the problem, the vacated parent was. The two answers differ on purpose, `movedOn`
    /// says somebody changed the contents (re-read and retry), this one says somebody removed
    /// the container (act at its new location, or not at all).
    case folderVanished(String)

    var description: String {
        switch self {
        case .movedOn(let path):
            "«\(path)» è cambiato da quando questa scrittura è partita, non lo tocco"
        case .folderVanished(let path):
            "«\(path)» non esiste più, non la ricreo per scriverci dentro"
        }
    }
}
