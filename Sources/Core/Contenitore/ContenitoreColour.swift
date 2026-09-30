import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D1, plan
// docs/plans/contenitore.md, Task 2 - R-17.

/// A document's colour: one of the six JSON Canvas presets, stored in the scheda by name,
/// never as a hex (SPEC "Colour").
///
/// The case order is the preset order, so `canvasPreset` is the case's position plus one and
/// the board and the pane draw the same colour for the same number
/// (`Sources/DesignSystem/StickyPreset+Token.swift`).
enum ContenitoreColour: String, CaseIterable, Sendable, Codable {
    case rosso
    case arancio
    case giallo
    case verde
    case ciano
    case viola

    /// The JSON Canvas preset number, 1 through 6.
    var canvasPreset: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// The colour for a JSON Canvas preset number, or nil outside 1...6.
    init?(canvasPreset: Int) {
        guard Self.allCases.indices.contains(canvasPreset - 1) else { return nil }
        self = Self.allCases[canvasPreset - 1]
    }

    /// The name the interface shows, the one the Workspace colour menu already uses.
    var displayName: String {
        switch self {
        case .rosso: "Rosso"
        case .arancio: "Arancio"
        case .giallo: "Giallo"
        case .verde: "Verde"
        case .ciano: "Ciano"
        case .viola: "Viola"
        }
    }
}
