import Foundation

/// One keyboard shortcut, as the user sees it and as it is stored.
///
/// Its own type rather than SwiftUI's `KeyboardShortcut`: that one is not `Equatable`,
/// not `Codable` and not comparable, and all three are needed here - the settings pane
/// has to persist a binding, show it, and tell whether two commands ended up on the
/// same keys. The conversion to SwiftUI happens once, at the menu.
///
/// The modifier bits are this type's own, not `EventModifiers.rawValue`. What is
/// written to disk is then independent of a framework constant that is free to change
/// between releases.
struct KeyBinding: Hashable, Codable, Sendable {
    struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }

        // Written as a bare number rather than as the `{"rawValue": 1}` the compiler
        // would synthesise for a struct: the stored file is meant to be readable, and
        // an option set is a number in every other format that carries one.
        init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(Int.self)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// A single character for an ordinary key, or one of `Self.namedKeys` for a key
    /// with no printable character.
    ///
    /// Letters are stored lowercased: macOS shows `⌘N` whether or not shift is held,
    /// and storing `N` would make an unshifted binding compare unequal to itself after
    /// a round trip through the recorder.
    var key: String
    var modifiers: Modifiers

    init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    // MARK: Named keys

    /// The keys with no printable character that a shortcut may use.
    ///
    /// A closed set on purpose: a binding is stored as a string, and an open one would
    /// let a typo persist as a shortcut that can never fire.
    static let namedKeys = [
        "space", "return", "tab", "escape", "delete",
        "up", "down", "left", "right",
        "home", "end", "pageUp", "pageDown",
    ]

    var isNamedKey: Bool { Self.namedKeys.contains(key) }

    // MARK: Validity

    /// Why a binding cannot be used, or nil when it can.
    enum Problem: Equatable, Sendable {
        /// An ordinary character with neither Command nor Control held: it would fire
        /// while the user is typing that letter into a note.
        case needsCommandOrControl
        case unknownKey(String)
        case empty
    }

    var problem: Problem? {
        if key.isEmpty { return .empty }
        if isNamedKey { return nil }
        guard key.count == 1 else { return .unknownKey(key) }
        let holdsMenuModifier = modifiers.contains(.command) || modifiers.contains(.control)
        return holdsMenuModifier ? nil : .needsCommandOrControl
    }

    var isValid: Bool { problem == nil }

    // MARK: Display

    /// The shortcut written the way macOS writes it: modifiers in the system's order,
    /// then the key.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keySymbol
    }

    private var keySymbol: String {
        switch key {
        case "space": "␣"
        case "return": "↩"
        case "tab": "⇥"
        case "escape": "⎋"
        case "delete": "⌫"
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "home": "↖"
        case "end": "↘"
        case "pageUp": "⇞"
        case "pageDown": "⇟"
        default: key.uppercased()
        }
    }
}
