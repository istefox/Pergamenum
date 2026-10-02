import Foundation

/// A JSON value, used to carry properties this app does not understand.
///
/// SPEC §6.2 requires that extra properties written by other apps survive a
/// round-trip through Pergamenum. That is the same rule the frontmatter parser
/// follows for foreign keys, and it needs a value type that can hold anything JSON
/// can express while staying `Sendable` and `Equatable`.
enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    /// An integer a `Double` cannot hold exactly (beyond 2^53 in magnitude). `JSONSerialization`
    /// reads such a value as an exact `Int64`, and holding it as a `Double` rounded it on the
    /// next encode (PG-279): a foreign id written by another app came back changed. Every
    /// integer a `Double` does hold exactly stays `.number`, so `.number(3)` keeps reading `3`.
    case integer(Int64)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init?(_ any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            // NSNumber does not distinguish bool from number by type, only by the
            // ObjC type encoding, and getting this wrong writes `1` where the file
            // had `true`.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if Self.isIntegral(value), Int64(exactly: value.doubleValue) != value.int64Value {
                self = .integer(value.int64Value)
            } else {
                self = .number(value.doubleValue)
            }
        case is NSNull: self = .null
        case let value as [Any]: self = .array(value.compactMap(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.compactMapValues(JSONValue.init))
        default: return nil
        }
    }

    /// Whether `JSONSerialization` read the number as an integer type (`c`/`s`/`i`/`l`/`q` and
    /// their unsigned forms), not as a `double` or a decimal.
    private static func isIntegral(_ value: NSNumber) -> Bool {
        switch String(cString: value.objCType) {
        case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q": true
        default: false
        }
    }

    var rawValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .integer(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let values): values.map(\.rawValue)
        case .object(let values): values.mapValues(\.rawValue)
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }
}
