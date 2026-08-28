import Foundation

/// The Workspace card's own text-colour and text-alignment properties (ADR-0027 §D4), stored
/// as two prefixed keys on `CanvasNode.unknown` - never as an edit to
/// `Sources/Core/Canvas/JSONCanvas.swift` itself (C5). Modelled on `CanvasCrop.swift` line for
/// line: `CanvasNode.init?` already funnels an unrecognised key into `unknown` and `rawValue`
/// already re-emits it, so nothing here ever needs to mutate that dictionary to read from it -
/// a malformed or out-of-range value is read as absent, never corrected, never removed
/// (ADR-0020 §D2's own rule, which `CanvasCrop.read` documents the same way). `CardTextStyle`
/// itself carries no *write* method, matching `CanvasCrop`, which does not either - the write
/// happens inline, at the call site, the same way `WorkspaceController+Crop.swift:121-125`
/// writes `CanvasCrop.key` directly onto `node.unknown`.
struct CardTextStyle: Equatable, Sendable {
    /// The prefixed key `pergamenum-textColor` lives under, on `CanvasNode.unknown`. Its value
    /// is a `CanvasColor` raw value: `"1"`..."6"` for the JSON Canvas presets, or `"#RRGGBB"`
    /// (ADR-0027 §D4) - the same vocabulary a card's *background* colour already speaks, so a
    /// card's text colour and its background colour never invent a second encoding.
    static let colorKey = "pergamenum-textColor"

    /// The prefixed key `pergamenum-textAlign` lives under, on `CanvasNode.unknown`. Its value
    /// is one of `Alignment`'s four raw string values. Absent means natural alignment.
    static let alignKey = "pergamenum-textAlign"

    enum Alignment: String, Equatable, Sendable {
        case left, center, right, justify
    }

    var color: CanvasColor?
    var alignment: Alignment?

    // MARK: Reading

    /// The style written on `node`, reading each key independently: a node can carry a colour
    /// with no alignment, an alignment with no colour, both, or neither (R-07's whole content -
    /// no colour and no alignment set is exactly today's plain-text card). A key that is
    /// absent, malformed, or out of range reads as `nil` on the corresponding property; the
    /// dictionary passed in is never mutated to get there.
    static func read(from node: CanvasNode) -> CardTextStyle {
        CardTextStyle(
            color: raw(colorKey, on: node).flatMap { CanvasColor($0) },
            alignment: raw(alignKey, on: node).flatMap { Alignment(rawValue: $0) }
        )
    }

    /// The string written under `key`, or `nil` when the key is absent or holds something
    /// that is not a string - `CanvasCrop.read`'s own `guard case .string(let raw)?` shape,
    /// factored out only because this type reads two keys where that one reads one. A
    /// subscript read never mutates the dictionary, which is what keeps a malformed value
    /// on the node instead of correcting it away.
    private static func raw(_ key: String, on node: CanvasNode) -> String? {
        guard case .string(let value)? = node.unknown[key] else { return nil }
        return value
    }

    // MARK: Presets

    /// The six JSON Canvas presets as fixed sRGB values, preset `1` first: the Obsidian
    /// canvas palette (red, orange, yellow, green, cyan, purple), so a `.canvas` authored
    /// there colours its text the same way here whatever theme is loaded. Written as hex
    /// strings rather than components so `RGBA(hex:)` stays the only place in this
    /// repository that turns a colour string into channels.
    private static let presetHex = ["#E93147", "#EC7500", "#E0AC00", "#08B94E", "#00BFBC", "#7852EE"]

    /// `color`'s concrete sRGB value. A `.hex` case is parsed verbatim through `RGBA(hex:)`;
    /// each of the six JSON Canvas presets (`1...6`) is drawn from a fixed table declared on
    /// this type, never from a theme token (ADR-0027 §D4) - a canvas authored in Obsidian must
    /// render its colour coding the same way here as it does there, regardless of which theme
    /// is active, the same carve-out `StickyTextCard.stickyColor` already takes for a card's
    /// background. A preset outside `1...6` is out of range and, like a malformed hex string,
    /// reads as `nil` rather than a substituted default - the caller substitutes
    /// `theme.color(.textPrimary)` itself when this returns `nil`.
    static func rgba(for color: CanvasColor) -> RGBA? {
        switch color {
        case .hex(let value):
            return RGBA(hex: value)
        case .preset(let index):
            guard presetHex.indices.contains(index - 1) else { return nil }
            return RGBA(hex: presetHex[index - 1])
        }
    }
}
