import Foundation

/// Which token a Contenitore colour is drawn with (ADR-0071 §D1, R-17).
///
/// Here rather than on `ContenitoreColour`, for the reason `DiaryColour+Token.swift` gives: the
/// colour is data the scheda carries, the token is a design-system answer.
extension ContenitoreColour {
    /// The sticky card's own token for the same preset number.
    var token: ColorToken {
        StickyPreset.token(for: canvasPreset)
    }
}
