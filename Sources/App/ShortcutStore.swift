import SwiftUI

/// The keyboard shortcuts in force, with the user's changes on top of the defaults.
///
/// A per-user preference rather than vault data, so it lives in `UserDefaults`: the
/// keys someone likes are a property of the person, not of the notes they are looking
/// at. The whole map is stored as one JSON string under a single key, which is what
/// makes a launch argument able to replace it wholesale in a UI test.
@MainActor
@Observable
final class ShortcutStore {
    /// Internal rather than private so a test can name the key it is asserting on.
    static let defaultsKey = "shortcutOverrides"

    /// Only the commands the user actually changed. A default binding is never
    /// written: the file then stays a record of decisions rather than a snapshot that
    /// would freeze today's defaults into next year's app.
    private(set) var overrides: [ShortcutCommand: KeyBinding] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    /// True when the map arrived on the command line, as `-shortcutOverrides "{…}"`.
    ///
    /// Same guard, and for the same reason, as `RecentVaults`: the argument domain
    /// outranks the persistent one, so an override is what the app reads for the whole
    /// session no matter what is written underneath it - and writing underneath it
    /// anyway would leave a UI test's throwaway bindings in the user's real settings.
    @ObservationIgnored private let isOverridden: Bool

    init(defaults: UserDefaults = .standard, isOverridden: Bool? = nil) {
        self.defaults = defaults
        // Injectable because the argument domain is process-wide: a test that set one
        // would be setting it for every other test in the same run.
        self.isOverridden = isOverridden
            ?? (defaults.volatileDomain(forName: UserDefaults.argumentDomain)[Self.defaultsKey] != nil)
        overrides = Self.decode(defaults.object(forKey: Self.defaultsKey))
    }

    // MARK: Reading

    /// The binding in force for a command.
    ///
    /// Never nil: a command the user cleared is stored as an empty binding, which is
    /// invalid and therefore produces no shortcut, rather than as a missing entry -
    /// which would be indistinguishable from "never changed" and would silently bring
    /// the default back.
    func binding(for command: ShortcutCommand) -> KeyBinding {
        overrides[command] ?? command.defaultBinding
    }

    func isCustomised(_ command: ShortcutCommand) -> Bool {
        overrides[command] != nil
    }

    /// The SwiftUI shortcut to hang on a menu item, or nil when the command has none.
    func shortcut(for command: ShortcutCommand) -> KeyboardShortcut? {
        binding(for: command).keyboardShortcut
    }

    /// Commands sharing a binding with `command`, which is what makes a shortcut fire
    /// the wrong thing or nothing at all.
    ///
    /// Reported rather than prevented: macOS itself lets two menu items share a key,
    /// and refusing the second one would leave the user unable to swap two shortcuts -
    /// the intermediate state is always a collision.
    func conflicts(with command: ShortcutCommand) -> [ShortcutCommand] {
        let binding = binding(for: command)
        guard binding.isValid else { return [] }
        return ShortcutCommand.allCases.filter { other in
            other != command && self.binding(for: other) == binding
        }
    }

    var hasConflicts: Bool {
        ShortcutCommand.allCases.contains { !conflicts(with: $0).isEmpty }
    }

    // MARK: Writing

    func set(_ binding: KeyBinding, for command: ShortcutCommand) {
        if binding == command.defaultBinding {
            overrides.removeValue(forKey: command)
        } else {
            overrides[command] = binding
        }
        persist()
    }

    /// Leaves the command with no shortcut at all.
    func clear(_ command: ShortcutCommand) {
        set(KeyBinding(""), for: command)
    }

    func reset(_ command: ShortcutCommand) {
        overrides.removeValue(forKey: command)
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    private func persist() {
        // A temporary override stays temporary: promoting it to permanent user data is
        // not something a command-line argument should be able to do.
        guard !isOverridden else { return }
        guard let data = try? JSONEncoder().encode(
            Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        ) else { return }
        guard let text = String(bytes: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.defaultsKey)
    }

    /// Reads the stored map, accepting both shapes the value can arrive in.
    ///
    /// Written by this app it is a JSON string. Handed in on the command line it is a
    /// dictionary: `UserDefaults` runs an argument whose value starts with `{` through
    /// the old-style property list reader, and a value that reader cannot parse is
    /// dropped entirely rather than kept as text - so a JSON literal never reaches the
    /// app at all, and the launch-argument form has to be the plist one.
    private static func decode(_ stored: Any?) -> [ShortcutCommand: KeyBinding] {
        let raw: [String: KeyBinding]
        switch stored {
        case let text as String:
            raw = (try? JSONDecoder().decode([String: KeyBinding].self, from: Data(text.utf8))) ?? [:]
        case let dictionary as [String: Any]:
            raw = dictionary.compactMapValues(binding(fromPropertyList:))
        default:
            return [:]
        }

        var result: [ShortcutCommand: KeyBinding] = [:]
        for (id, binding) in raw {
            // An unknown id is dropped rather than refused: it is what a shortcut
            // removed in a later version looks like, and one stale entry must not cost
            // the user every other binding in the file.
            guard let command = ShortcutCommand(rawValue: id) else { continue }
            result[command] = binding
        }
        return result
    }

    /// One binding out of a property list dictionary.
    ///
    /// The modifiers are read from a number *or* from its digits: an old-style plist
    /// has no number type, so everything the argument-domain reader produces is a
    /// string, and decoding that through `JSONDecoder` would fail on every entry.
    private static func binding(fromPropertyList value: Any) -> KeyBinding? {
        guard let fields = value as? [String: Any], let key = fields["key"] as? String
        else { return nil }
        let modifiers = (fields["modifiers"] as? Int)
            ?? (fields["modifiers"] as? String).flatMap { Int($0) }
            ?? 0
        return KeyBinding(key, KeyBinding.Modifiers(rawValue: modifiers))
    }
}

extension KeyBinding {
    /// The SwiftUI shortcut, or nil when the binding cannot be used.
    var keyboardShortcut: KeyboardShortcut? {
        guard isValid, let equivalent = keyEquivalent else { return nil }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "space": .space
        case "return": .return
        case "tab": .tab
        case "escape": .escape
        case "delete": .delete
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        case "home": .home
        case "end": .end
        case "pageUp": .pageUp
        case "pageDown": .pageDown
        // Spelled out rather than passed as `KeyEquivalent.init`: the type has several
        // initialisers taking a character-like value and the reference is ambiguous.
        default: key.count == 1 ? key.first.map { KeyEquivalent($0) } : nil
        }
    }
}
