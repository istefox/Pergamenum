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
            self = CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue)
                : .number(value.doubleValue)
        case is NSNull: self = .null
        case let value as [Any]: self = .array(value.compactMap(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.compactMapValues(JSONValue.init))
        default: return nil
        }
    }

    var rawValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
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
        if case .number(let value) = self { return value }
        return nil
    }
}
