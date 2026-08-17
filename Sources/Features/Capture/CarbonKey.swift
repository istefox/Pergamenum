import Carbon.HIToolbox
import Foundation

/// A `KeyBinding` said the way `RegisterEventHotKey` wants to hear it.
///
/// In `Features/` and not in `Core/`, deliberately. `Core` is compiled by `perg` and
/// `pergamenum-mcp` as well as by the app and depends on Foundation alone (ADR-0001
/// §D1); an `import Carbon` there would build fine and move the boundary for
/// convenience. Nothing headless needs a hot key.
///
/// Two things about Carbon that a conversion written from memory gets wrong, and both
/// were checked by running them:
///
/// - The modifier masks are **not** `NSEvent`'s. Carbon says `controlKey` 4096,
///   `cmdKey` 256, `optionKey` 2048, `shiftKey` 512.
/// - A virtual key code names a **position** on the keyboard, not a character. `kVK_ANSI_A`
///   is 0, and on a layout where that key is not `a` the shortcut fires on whatever key
///   sits there. That is how every Mac app has always done it and it is what the user
///   sees written on the keycap in front of them.
enum CarbonKey {
    /// The virtual key code for a binding's key, or nil when there is none.
    ///
    /// A closed table, like `KeyBinding.namedKeys` is closed. A key outside it means a
    /// shortcut that cannot be registered, said out loud - never a guessed code, which
    /// would register the panel on some other key and look like the feature is broken.
    static func virtualKeyCode(for key: String) -> UInt32? {
        if let named = namedKeys[key] { return UInt32(named) }
        guard key.count == 1, let letter = key.lowercased().first else { return nil }
        return characterKeys[letter].map(UInt32.init)
    }

    /// The Carbon modifier mask for a binding's modifiers.
    static func modifierMask(for modifiers: KeyBinding.Modifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.command) { mask |= cmdKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.control) { mask |= controlKey }
        return UInt32(mask)
    }

    /// Both halves at once, or nil when the key has no code.
    static func pair(for binding: KeyBinding) -> (code: UInt32, modifiers: UInt32)? {
        guard let code = virtualKeyCode(for: binding.key) else { return nil }
        return (code, modifierMask(for: binding.modifiers))
    }

    // MARK: The table

    /// The keys with no printable character. Every name here is one of
    /// `KeyBinding.namedKeys`, so a binding the recorder can produce is one this can
    /// translate.
    private static let namedKeys: [String: Int] = [
        "space": kVK_Space,
        "return": kVK_Return,
        "tab": kVK_Tab,
        "escape": kVK_Escape,
        "delete": kVK_Delete,
        "up": kVK_UpArrow,
        "down": kVK_DownArrow,
        "left": kVK_LeftArrow,
        "right": kVK_RightArrow,
        "home": kVK_Home,
        "end": kVK_End,
        "pageUp": kVK_PageUp,
        "pageDown": kVK_PageDown,
    ]

    /// Letters, digits and the punctuation the app's own shortcuts use, by the ANSI
    /// position each occupies.
    private static let characterKeys: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "\\": kVK_ANSI_Backslash,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "`": kVK_ANSI_Grave,
    ]
}
