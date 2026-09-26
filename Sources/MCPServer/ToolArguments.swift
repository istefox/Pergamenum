import Foundation
import MCP

/// The arguments of a tool call, read leniently.
///
/// A schema says a field is a string and a model sends the number 3 anyway, or sends
/// `"true"` where a boolean was asked for. Refusing that is technically correct and
/// practically useless: the intent is unambiguous, and a round trip spent on a type
/// error is a round trip the person waiting does not get back. So the readers accept
/// the near misses and refuse only what genuinely says nothing.
struct ToolArguments {
    private let values: [String: Value]

    init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    /// A string that has to be there.
    func required(_ name: String) throws -> String {
        guard let text = string(name), !text.isEmpty else {
            throw ConnectorError("«\(name)» è obbligatorio", usage: true)
        }
        return text
    }

    /// A string, or nil when it was absent or empty. Empty and absent are one case on
    /// purpose: a model filling in `""` for a folder means "no folder".
    func string(_ name: String) -> String? {
        guard let value = values[name] else { return nil }
        let text: String?
        switch value {
        case .string(let raw): text = raw
        case .int(let number): text = String(number)
        case .double(let number): text = String(number)
        case .bool(let flag): text = String(flag)
        default: text = nil
        }
        return (text?.isEmpty ?? true) ? nil : text
    }

    func int(_ name: String) -> Int? {
        guard let value = values[name] else { return nil }
        switch value {
        case .int(let number): return number
        case .double(let number): return Self.truncated(number)
        case .string(let raw): return Int(raw)
        default: return nil
        }
    }

    /// An integer that keeps «absent» apart from «unreadable» (ADR-0063 §D1.4), for a
    /// `limit`: a bad number is refused with the shared sentence rather than read as «no
    /// limit given», which is the leniency the rest of this file allows elsewhere.
    func checkedInt(_ name: String) throws -> Int? {
        guard let value = values[name] else { return nil }
        switch value {
        case .null: return nil
        case .int(let number): return number
        // The refusals go through the text rule so the sentence is the shared one. An
        // out-of-range double prints in exponent form and a bool, array, object or data
        // value never prints as an integer, so none of them can read as a number there.
        case .double(let number):
            guard let whole = Self.truncated(number) else {
                return try VaultAPI.limit(parsing: String(number), named: name)
            }
            return whole
        case .string(let raw): return try VaultAPI.limit(parsing: raw, named: name)
        default: return try VaultAPI.limit(parsing: "\(value)", named: name)
        }
    }

    /// A JSON number toward zero, or nil when it has no `Int` to land on. `Int(_:)` on a
    /// `Double` traps outside `Int`'s range, and `1e300` is valid JSON (ADR-0063 §D1.5).
    private static func truncated(_ number: Double) -> Int? {
        Int(exactly: number.rounded(.towardZero))
    }

    /// A boolean, falling back to what the tool declared as its default.
    ///
    /// The fallback matters more here than anywhere else in this file: `dryRun` defaults
    /// to true, so a model that omits it, or sends something unreadable in its place,
    /// gets a diff rather than a change (ADR-0007 §D6).
    func bool(_ name: String, default fallback: Bool) -> Bool {
        guard let value = values[name] else { return fallback }
        switch value {
        case .bool(let flag): return flag
        case .string(let raw):
            switch raw.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return fallback
            }
        case .int(let number): return number != 0
        default: return fallback
        }
    }
}
