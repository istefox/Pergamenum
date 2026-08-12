import Foundation
import Observation
import SwiftUI

/// Loads token files and publishes the theme the views should render with.
///
/// The engine owns two base themes, light and dark, both of which ship in the app
/// bundle and both of which are complete. Themes found in the vault's
/// `.pergamenum/themes/` directory are layered on top of the bundled base with the
/// matching appearance, so a user file may define three colours and inherit the
/// rest (ADR-0001 §D4).
@MainActor
@Observable
final class ThemeEngine {
    /// What the user picked in Settings, not what is currently on screen.
    enum Selection: Hashable, Sendable {
        case followSystem
        case light
        case dark
        /// A theme file from the vault, by id (its file name without extension).
        case named(String)
    }

    private(set) var themes: [Theme]
    /// Problems from the most recent load, for Settings to display. Empty is the
    /// normal case; a non-empty list means a token file was malformed and the
    /// affected tokens fell back rather than the app failing to render.
    private(set) var problems: [String]

    var selection: Selection {
        didSet { persistSelection() }
    }

    /// The system's current appearance, pushed in by the root view. Kept as state
    /// rather than read on demand because `current` must be a pure function of the
    /// engine's properties for `@Observable` to invalidate views correctly.
    var systemAppearance: ThemeAppearance = .light

    /// The theme to render with right now.
    var current: Theme {
        switch selection {
        case .followSystem:
            base(for: systemAppearance)
        case .light:
            base(for: .light)
        case .dark:
            base(for: .dark)
        case .named(let id):
            themes.first { $0.id == id } ?? base(for: systemAppearance)
        }
    }

    /// Themes a user can pick in Settings: the two bundled ones plus anything found
    /// in the vault. The emergency theme is deliberately not among them.
    var selectableThemes: [Theme] { themes }

    private let defaults: UserDefaults
    private static let selectionKey = "theme.selection"

    init(bundle: Bundle = .pergamenumResources, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = ThemeEngine.loadBundledThemes(from: bundle)
        themes = loaded.themes
        problems = loaded.problems
        selection = ThemeEngine.restoreSelection(from: defaults)
    }

    /// Adds or replaces themes from a vault directory. Each file inherits from the
    /// bundled theme whose appearance it declares, so a partial file is valid.
    /// Called when a vault opens; safe to call again when the directory changes.
    func loadUserThemes(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        var added: [Theme] = []
        var newProblems: [String] = []

        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.path < $1.path }) {
            let id = file.deletingPathExtension().lastPathComponent
            // A user file named like a bundled theme customises it rather than
            // shadowing it, which is why the bundled version is the inheritance base
            // instead of being dropped from the list.
            guard let data = try? Data(contentsOf: file) else {
                newProblems.append("\(id): could not be read")
                continue
            }
            do {
                let document = try DesignTokenDocument(data: data, fallbackName: id)
                let theme = Theme(document: document, id: id, inheriting: base(for: document.appearance))
                added.append(theme)
                newProblems.append(contentsOf: theme.problems.map { "\(id): \($0)" })
            } catch {
                newProblems.append("\(id): \(error)")
            }
        }

        let bundled = themes.filter { $0.id.hasPrefix("pergamenum-") }
        let userIDs = Set(added.map(\.id))
        themes = bundled.filter { !userIDs.contains($0.id) } + added
        problems = newProblems
    }

    // MARK: Bundled themes

    private func base(for appearance: ThemeAppearance) -> Theme {
        themes.first { $0.id == "pergamenum-\(appearance.rawValue)" }
            ?? themes.first { $0.appearance == appearance }
            ?? .emergency
    }

    private struct LoadResult {
        var themes: [Theme]
        var problems: [String]
    }

    private static func loadBundledThemes(from bundle: Bundle) -> LoadResult {
        var result = LoadResult(themes: [], problems: [])

        // Light loads first and seeds the inheritance chain: if the dark file is
        // damaged, dark falls back to a complete light theme rather than to the
        // emergency palette, which is the less jarring failure.
        for appearance in ThemeAppearance.allCases {
            let id = "pergamenum-\(appearance.rawValue)"
            guard let url = bundle.tokenFileURL(named: id) else {
                result.problems.append("\(id).json is missing from the app bundle")
                continue
            }
            do {
                let document = try DesignTokenDocument(data: try Data(contentsOf: url), fallbackName: id)
                let inherited = result.themes.first ?? .emergency
                let theme = Theme(document: document, id: id, inheriting: inherited)
                result.themes.append(theme)
                result.problems.append(contentsOf: theme.problems.map { "\(id): \($0)" })
                result.problems.append(contentsOf: theme.inheritedTokens.map { "\(id): missing token \($0)" })
            } catch {
                result.problems.append("\(id): \(error)")
            }
        }

        if result.themes.isEmpty {
            // Only reachable when the bundle has no readable theme at all, which
            // means a broken build rather than a user error. Rendering the emergency
            // theme keeps the window usable so the problem list can be read.
            result.themes = [.emergency]
        }
        return result
    }

    // MARK: Selection persistence

    private func persistSelection() {
        let encoded: String = switch selection {
        case .followSystem: "system"
        case .light: "light"
        case .dark: "dark"
        case .named(let id): "named:\(id)"
        }
        defaults.set(encoded, forKey: ThemeEngine.selectionKey)
    }

    private static func restoreSelection(from defaults: UserDefaults) -> Selection {
        switch defaults.string(forKey: selectionKey) {
        case "light": .light
        case "dark": .dark
        case .some(let value) where value.hasPrefix("named:"): .named(String(value.dropFirst(6)))
        default: .followSystem
        }
    }
}

// MARK: - Resource lookup

extension Bundle {
    /// The bundle that actually carries the theme files.
    ///
    /// Under `xcodebuild test` the tests run inside the app's bundle, but the test
    /// bundle is what `Bundle(for:)` resolves to for a `@testable` import, so both
    /// candidates are tried rather than assuming either one.
    static var pergamenumResources: Bundle {
        let candidates = [Bundle.main, Bundle(for: ResourceAnchor.self)]
        return candidates.first { $0.tokenFileURL(named: "pergamenum-light") != nil } ?? .main
    }

    /// Xcode's copy phase flattens resource folders, while a folder reference keeps
    /// them nested; looking in both places makes the lookup independent of which one
    /// the project generator produced.
    func tokenFileURL(named name: String) -> URL? {
        url(forResource: name, withExtension: "json", subdirectory: "Themes")
            ?? url(forResource: name, withExtension: "json")
    }
}

/// Anchors `Bundle(for:)` to whichever bundle this code was compiled into.
private final class ResourceAnchor {}
