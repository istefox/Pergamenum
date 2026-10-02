import Foundation

/// How `CanvasNode.init?` reads a JSON Canvas 1.0 required key: `x`, `y`, `width`, `height` on
/// every node, and `text`, `file` or `url` on its own kind (ADR-0065 §D5.4, closing §D13.4, PG-277).
///
/// Three outcomes, and only three:
/// - absent: the default. Nothing is on disk for a save to overwrite, and a generated canvas that
///   omits geometry still opens drawn.
/// - present with the expected JSON type: the value. Geometry takes any JSON number, fractional or
///   negative included, since this app's own boards write fractional geometry.
/// - present with any other type, `null` included: `nil`, so the element is kept opaque beside its
///   readable neighbours (its index only as a fallback, PG-281) and written back verbatim. Never
///   coerced: `"12"` is not 12 and `true` is not 1, because either guess would change the value's
///   JSON type on the next save.
///
/// The type is judged through `JSONValue(_:)`, which already tells a `CFBoolean` from a number.
enum CanvasRequiredKey {
    static func number(_ key: String, in object: [String: Any], absent fallback: Double) -> Double? {
        read(key, in: object, absent: fallback, as: \.doubleValue)
    }

    /// A node's own required payload, read by the same rule: `text` on a text node, `file` on a
    /// file node, `url` on a link node. `""` for a kind that has none - `group`, and any type this
    /// app does not know, which checks geometry only. Another kind's payload key is never read here:
    /// it stays in `unknown`, whatever its type (§D5.1).
    static func payload(ofType type: String, in object: [String: Any]) -> String? {
        switch type {
        case "text": read("text", in: object, absent: "", as: \.stringValue)
        case "file": read("file", in: object, absent: "", as: \.stringValue)
        case "link": read("url", in: object, absent: "", as: \.stringValue)
        default: ""
        }
    }

    private static func read<Value>(
        _ key: String, in object: [String: Any], absent fallback: Value, as expected: (JSONValue) -> Value?
    ) -> Value? {
        guard let raw = object[key] else { return fallback }
        return JSONValue(raw).flatMap(expected)
    }
}
