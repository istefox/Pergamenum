import Foundation

/// The kill switch for the incremental restyle (ADR-0091 §D8): `-editorFullRestyle YES` on the
/// command line, or the same key in the defaults, makes every styling a full restyle.
///
/// Read once per editor, by `NoteTextView.Coordinator.init`; no surface sets it and Impostazioni
/// does not show it.
enum EditorRestyleSwitch {
    static let key = "editorFullRestyle"

    /// Whether the switch is on: the argument pair `-editorFullRestyle <bool>` in `arguments`, which
    /// is what the arguments domain puts in `UserDefaults.standard`, or the key in `defaults`.
    /// Read from both because a defaults suite of its own never sees the launch arguments.
    static func forcesFullRestyle(arguments: [String], defaults: UserDefaults) -> Bool {
        if let flag = arguments.firstIndex(of: "-\(key)"), flag + 1 < arguments.count {
            return isOn(arguments[flag + 1])
        }
        return defaults.bool(forKey: key)
    }

    /// The spellings the arguments domain reads as true.
    private static func isOn(_ value: String) -> Bool {
        ["yes", "true", "1"].contains(value.lowercased())
    }
}
