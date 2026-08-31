import Foundation

/// The Link card's editable title (PG-073, SPEC §6.4 row 7 / §6.5 "titolo editabile"), stored
/// as the prefixed key `pergamenum-title` on `CanvasNode.unknown` - never as an edit to
/// `Sources/Core/Canvas/JSONCanvas.swift` itself, matching `CanvasCrop`/`CardTextStyle` exactly.
/// `CanvasNode.init?` already funnels an unrecognised key into `unknown` and `rawValue` already
/// re-emits it, so JSON Canvas round-trip and Obsidian compatibility (CLAUDE.md principle 4)
/// need nothing further here.
enum LinkCardTitle {
    static let key = "pergamenum-title"

    /// The title stored on `node`, or `nil` when absent, empty, or not a string - read as
    /// absent rather than corrected or removed, the same rule `CanvasCrop.read`/
    /// `CardTextStyle.read` already document for their own keys.
    static func read(from node: CanvasNode) -> String? {
        guard case .string(let value)? = node.unknown[key], !value.isEmpty else { return nil }
        return value
    }
}
