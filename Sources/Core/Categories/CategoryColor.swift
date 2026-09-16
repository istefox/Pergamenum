import Foundation

/// The fixed, small palette `Category.color` is chosen from (SPEC "Data model": "`color`
/// (a name from a small fixed palette, not a hex)"). A closed list of theme tokens rather
/// than a free colour, the same reasoning `DiaryColour` already carries for the diary
/// entry's five: a category that could pick any colour stops matching the app the first
/// time the theme changes.
///
/// `Category.color` stores this enum's raw value as a plain `String`, never this type
/// itself - the registry file (ADR-0047 §D2) is meant to be hand-editable, and a value
/// this narrow costs nothing to keep as a string there. `CategoryColor(rawValue:)` parses
/// it back; a value the palette does not recognise (a hand-edited typo, or a future
/// version's wider palette) reads as `nil`, and the caller falls back to a neutral token
/// rather than refusing to render the category at all (`CategoryColor+Token.swift`).
///
/// Reuses the same five hues `DiaryColour` already names rather than widening
/// `ColorToken`'s palette with new cases: SPEC "Not yet specified" leaves the exact
/// palette to implementation, and every token this app can draw already lives in exactly
/// two theme files (`Resources/Themes/pergamenum-*.json`) - five names is a small fixed
/// palette either way, and reusing them costs no new token, no new theme entry in either
/// file, and no new emergency-palette fallback to keep in step.
enum CategoryColor: String, CaseIterable, Identifiable, Sendable {
    case giallo, verde, blu, rosa, grigio

    var id: String { rawValue }

    /// The label in the picker, in the UI's language.
    var label: String { rawValue.capitalized }
}
