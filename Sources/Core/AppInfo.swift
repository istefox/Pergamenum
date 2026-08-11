import Foundation

/// Static identity of the app, in one place so views, tests and the about panel
/// read the same values.
enum AppInfo {
    static let name = "Pergamenum"
    static let tagline = "Bootstrap - under active development"
    /// Reverse-DNS identifier, lowercase by specification (SPEC §2).
    static let bundleIdentifier = "it.stefer.pergamenum"
    /// Custom URL scheme registered in the Info.plist (SPEC §9).
    static let urlScheme = "pergamenum"
}
