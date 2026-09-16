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

    var description: String {
        switch self {
        case .movedOn(let path):
            "«\(path)» è cambiato da quando questa scrittura è partita, non lo tocco"
        }
    }
}
