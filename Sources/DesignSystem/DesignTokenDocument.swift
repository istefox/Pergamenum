import CoreGraphics
import Foundation

/// A parsed W3C DTCG token file, flattened to dotted paths.
///
/// Parsing is deliberately lenient about *which* tokens a file contains and strict
/// about the shape of the ones it does: a user theme in `.pergamenum/themes/` may
/// define three colours and inherit the rest, but a malformed colour is a reported
/// problem rather than a silent black (ADR-0001 §D4).
struct DesignTokenDocument: Sendable {
    /// Human-readable theme name from `meta.name`, or the file name if absent.
    let name: String
    /// Appearance declared by `meta.appearance`; drives light/dark selection.
    let appearance: ThemeAppearance
    let tokens: [String: TokenValue]
    /// Non-fatal issues: a malformed value, an unknown type, a token that is not a
    /// token. Surfaced to the user rather than swallowed.
    let problems: [String]

    enum ParseError: Error, CustomStringConvertible {
        case notAnObject
        case unreadable(underlying: String)

        var description: String {
            switch self {
            case .notAnObject:
                "the token file's root is not a JSON object"
            case .unreadable(let underlying):
                "the token file could not be read: \(underlying)"
            }
        }
    }

    init(data: Data, fallbackName: String) throws {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ParseError.unreadable(underlying: error.localizedDescription)
        }
        guard let object = root as? [String: Any] else { throw ParseError.notAnObject }

        var collector = Collector()
        collector.walk(object, path: [], inheritedType: nil)

        tokens = collector.tokens
        problems = collector.problems

        if case .string(let declared)? = collector.tokens["meta.name"], !declared.isEmpty {
            name = declared
        } else {
            name = fallbackName
        }
        if case .string(let declared)? = collector.tokens["meta.appearance"] {
            appearance = ThemeAppearance(rawValue: declared) ?? .light
        } else {
            appearance = .light
        }
    }
}

enum ThemeAppearance: String, Sendable, CaseIterable {
    case light
    case dark
}

// MARK: - Tree walking

private struct Collector {
    var tokens: [String: TokenValue] = [:]
    var problems: [String] = []

    /// A DTCG node is a token when it carries `$value`; anything else with non-`$`
    /// children is a group whose `$type` is inherited by everything below it.
    mutating func walk(_ node: [String: Any], path: [String], inheritedType: String?) {
        let type = node["$type"] as? String ?? inheritedType

        if let value = node["$value"] {
            let dotted = path.joined(separator: ".")
            switch Self.convert(value, declaredType: type) {
            case .success(let token):
                tokens[dotted] = token
            case .failure(let reason):
                problems.append("\(dotted): \(reason)")
            }
            return
        }

        for (key, child) in node where !key.hasPrefix("$") {
            guard let childObject = child as? [String: Any] else {
                problems.append("\((path + [key]).joined(separator: ".")): expected a token or a group")
                continue
            }
            walk(childObject, path: path + [key], inheritedType: type)
        }
    }

    private enum Conversion {
        case success(TokenValue)
        case failure(String)
    }

    private static func convert(_ value: Any, declaredType: String?) -> Conversion {
        switch declaredType {
        case "color": return color(value)
        case "dimension": return dimension(value)
        case "typography": return typography(value)
        case "shadow": return shadow(value)
        case "string": return string(value)
        case .some(let unknown): return .failure("unknown token type '\(unknown)'")
        case nil: return infer(value)
        }
    }

    /// Used only when a file omits `$type`. The bundled themes always declare it;
    /// this exists so a hand-written user theme is usable rather than rejected.
    private static func infer(_ value: Any) -> Conversion {
        if let text = value as? String {
            return text.hasPrefix("#") ? color(value) : string(value)
        }
        if value is NSNumber { return dimension(value) }
        if let object = value as? [String: Any] {
            if object["fontSize"] != nil { return typography(value) }
            if object["blur"] != nil || object["offsetY"] != nil { return shadow(value) }
            if object["value"] != nil { return dimension(value) }
        }
        return .failure("no $type declared and the value's shape is not recognised")
    }

    private static func color(_ value: Any) -> Conversion {
        guard let text = value as? String else { return .failure("a colour must be a hex string") }
        guard let rgba = RGBA(hex: text) else { return .failure("'\(text)' is not a valid hex colour") }
        return .success(.color(rgba))
    }

    /// Accepts `8`, `"8"`, `"8px"` and `{"value": 8, "unit": "px"}`. Points and
    /// pixels are treated as the same unit: on macOS the token authoring tools emit
    /// `px` and SwiftUI consumes points, and rescaling here would double-apply the
    /// backing scale factor.
    private static func dimension(_ value: Any) -> Conversion {
        if let number = value as? NSNumber { return .success(.dimension(CGFloat(number.doubleValue))) }
        if let text = value as? String {
            let stripped = text.replacingOccurrences(of: "px", with: "")
                .replacingOccurrences(of: "pt", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let number = Double(stripped) else { return .failure("'\(text)' is not a dimension") }
            return .success(.dimension(CGFloat(number)))
        }
        if let object = value as? [String: Any], let number = object["value"] as? NSNumber {
            return .success(.dimension(CGFloat(number.doubleValue)))
        }
        return .failure("a dimension must be a number, a string or a {value, unit} object")
    }

    private static func typography(_ value: Any) -> Conversion {
        guard let object = value as? [String: Any] else {
            return .failure("typography must be an object")
        }
        guard let size = (object["fontSize"] as? NSNumber).map({ CGFloat($0.doubleValue) }) else {
            return .failure("typography is missing fontSize")
        }
        let family = TypographyValue.Family(rawValue: object["fontFamily"] as? String ?? "system") ?? .system
        let weight = (object["fontWeight"] as? NSNumber)?.intValue ?? 400
        let lineHeight = (object["lineHeight"] as? NSNumber)?.doubleValue ?? 1.4
        return .success(.typography(TypographyValue(
            family: family, size: size, weight: weight, lineHeight: lineHeight
        )))
    }

    private static func shadow(_ value: Any) -> Conversion {
        // DTCG allows a list of layered shadows; the design system uses one layer,
        // so a list collapses to its first entry rather than being rejected.
        let candidate = (value as? [Any])?.first ?? value
        guard let object = candidate as? [String: Any] else {
            return .failure("a shadow must be an object")
        }
        guard let hex = object["color"] as? String, let color = RGBA(hex: hex) else {
            return .failure("a shadow needs a valid hex colour")
        }
        func number(_ key: String) -> CGFloat {
            CGFloat((object[key] as? NSNumber)?.doubleValue ?? 0)
        }
        return .success(.shadow(ShadowValue(
            color: color,
            offsetX: number("offsetX"),
            offsetY: number("offsetY"),
            blur: number("blur"),
            spread: number("spread")
        )))
    }

    private static func string(_ value: Any) -> Conversion {
        guard let text = value as? String else { return .failure("expected a string") }
        return .success(.string(text))
    }
}
