import Foundation
import Observation

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

    /// Where the vault keeps its themes, once one is open. Nil means no vault, and
    /// with no vault there is nowhere to save a customisation to: a colour picked
    /// then would have nowhere to live and would vanish on the next launch, so
    /// Settings says so rather than pretending.
    private(set) var userThemesDirectory: URL?

    /// The colours Settings has written, and the appearance they build on.
    private(set) var customization: ThemeCustomization.Draft?

    /// Anything that went wrong writing a customisation, shown next to the wells.
    private(set) var customizationProblem: String?

    private let defaults: UserDefaults
    private static let selectionKey = "theme.selection"

    init(bundle: Bundle = .pergamenumResources, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = ThemeEngine.loadBundledThemes(from: bundle)
        themes = loaded.themes
        problems = loaded.problems
        selection = ThemeEngine.restoreSelection(from: defaults)
    }

    /// Points the engine at a vault and loads whatever themes it holds.
    ///
    /// Until this was called from the app, `loadUserThemes` was reachable only from
    /// the test suite: the vault's `themes` directory was read by nobody, so a theme
    /// file dropped into a vault did nothing and the Settings picker could only ever
    /// list the two bundled themes.
    func attach(vaultRoot: URL) {
        let directory = vaultRoot
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.themesDirectory, directoryHint: .isDirectory)
        userThemesDirectory = directory
        loadUserThemes(in: directory)
        customization = ThemeCustomization.load(from: directory)
        customizationProblem = nil
        dropSelectionIfItsThemeIsGone()
    }

    /// A remembered theme that this vault does not have is not a theme.
    ///
    /// The selection is a per-user preference and the themes come from the vault, so
    /// the two can disagree: open vault A, pick its theme, open vault B, and the
    /// preference still names a file that is not there. `current` already fell back
    /// to the system appearance, but the picker showed no selection at all, which
    /// reads as a broken control rather than as a theme that moved.
    private func dropSelectionIfItsThemeIsGone() {
        guard case .named(let id) = selection, !themes.contains(where: { $0.id == id }) else { return }
        selection = .followSystem
    }

    /// Forgets the vault's themes when it closes, so a theme from the vault just
    /// closed cannot stay on screen over the next one.
    func detachVault() {
        userThemesDirectory = nil
        customization = nil
        customizationProblem = nil
        themes = themes.filter { $0.id.hasPrefix("pergamenum-") }
        if case .named = selection { selection = .followSystem }
    }

    // MARK: Colour customisation

    /// The value a colour well should open on: what the user chose, or what the
    /// theme underneath currently renders.
    func customizableColor(_ token: ColorToken) -> RGBA {
        customization?.colors[token] ?? current.rawColor(token)
    }

    /// What a *new* write to the customisation should declare, independent of
    /// whatever a `personalizzato.json` already on disk happens to say.
    ///
    /// `current.appearance` is not safe for this once the customisation is already
    /// selected (`selection == .named(ThemeCustomization.id)`): it would just read
    /// back the very file a stale write is about to perpetuate, which is how a font
    /// or colour picked while looking at dark could silently keep re-saving a light
    /// file left over from an earlier session. For every other selection - explicit
    /// light/dark, or following the system - the intended appearance is exactly what
    /// `current` already resolves to, since there is no customisation to be circular
    /// about yet.
    private var intendedAppearance: ThemeAppearance {
        switch selection {
        case .followSystem: systemAppearance
        case .light: .light
        case .dark: .dark
        case .named: systemAppearance
        }
    }

    /// Corrects a draft's appearance to match `intendedAppearance` before a write,
    /// so a customisation file left over from a different appearance never silently
    /// carries a new colour or font choice into the wrong theme. Surfaces what
    /// happened next to the wells the same way any other customisation problem
    /// does, rather than reconciling in total silence.
    private func reconciled(_ draft: ThemeCustomization.Draft) -> ThemeCustomization.Draft {
        var draft = draft
        guard draft.appearance != intendedAppearance else { return draft }
        customizationProblem =
            "il tema personalizzato era per \(appearanceName(draft.appearance)), riportato a \(appearanceName(intendedAppearance))"
        draft.appearance = intendedAppearance
        return draft
    }

    private func appearanceName(_ appearance: ThemeAppearance) -> String {
        appearance == .dark ? "scuro" : "chiaro"
    }

    /// Writes one colour into the vault's customisation file and switches to it.
    ///
    /// The write happens first and the selection follows it: selecting a theme whose
    /// file failed to appear would leave the app pointing at a theme that is not
    /// there, and `current` would silently fall back to the system appearance while
    /// Settings claimed the customisation was active.
    func setCustomColor(_ token: ColorToken, to value: RGBA) {
        guard let directory = userThemesDirectory else {
            customizationProblem = "nessuna cartella note aperta: non c'è dove salvare il tema"
            return
        }
        var draft = reconciled(customization ?? ThemeCustomization.Draft(appearance: intendedAppearance, colors: [:]))
        draft.colors[token] = value
        apply(draft, in: directory)
    }

    /// Drops one colour back to the theme underneath.
    func clearCustomColor(_ token: ColorToken) {
        guard let directory = userThemesDirectory, var draft = customization else { return }
        draft.colors.removeValue(forKey: token)
        if draft.isEmpty {
            resetCustomization()
            return
        }
        apply(draft, in: directory)
    }

    // MARK: Font customisation (ADR-0030 §D9)

    /// Writes one prose font token into the vault's customisation file and switches
    /// to it. Mirrors `setCustomColor`'s write-then-select ordering and its
    /// "no vault, no save" guard exactly — `Draft.fonts` is `colors`' sibling, not a
    /// second mechanism.
    func setCustomFont(_ token: FontToken, to value: TypographyValue) {
        guard let directory = userThemesDirectory else {
            customizationProblem = "nessuna cartella note aperta: non c'è dove salvare il carattere"
            return
        }
        var draft = reconciled(customization ?? ThemeCustomization.Draft(appearance: intendedAppearance, colors: [:]))
        draft.fonts[token] = value
        apply(draft, in: directory)
    }

    /// Drops both prose font overrides (`.prose` and `.proseTitle` together — Settings
    /// never offers one without the other) back to the theme underneath, removing the
    /// file when no colour override is left either, mirroring `clearCustomColor`
    /// through `resetCustomization()` (R-12).
    ///
    /// Unlike `clearCustomColor` it falls back to reading the file when the in-memory
    /// copy is nil: the file is the customisation (CLAUDE.md principle 1) and it can
    /// be there without this engine having written it — a vault attached after a font
    /// was chosen by hand, or written while this window was open. Refusing then would
    /// leave a reset button that does nothing on a file that plainly exists.
    func clearCustomFonts() {
        guard let directory = userThemesDirectory,
              var draft = customization ?? ThemeCustomization.load(from: directory) else { return }
        for token in ThemeCustomization.customizableFonts {
            draft.fonts.removeValue(forKey: token)
        }
        if draft.isEmpty {
            resetCustomization()
            return
        }
        apply(draft, in: directory)
    }

    /// Rebuilds the customisation on the appearance showing right now, keeping the
    /// colours already chosen. This is what makes a light customisation usable as a
    /// starting point for a dark one instead of a dead end.
    func rebaseCustomization(on appearance: ThemeAppearance) {
        guard let directory = userThemesDirectory else { return }
        var draft = customization ?? ThemeCustomization.Draft(appearance: appearance, colors: [:])
        draft.appearance = appearance
        apply(draft, in: directory)
    }

    /// Deletes the file and goes back to the theme that was underneath.
    func resetCustomization() {
        guard let directory = userThemesDirectory else { return }
        do {
            try ThemeCustomization.remove(from: directory)
            customization = nil
            customizationProblem = nil
            if selection == .named(ThemeCustomization.id) { selection = .followSystem }
            loadUserThemes(in: directory)
        } catch {
            customizationProblem = "\(error)"
        }
    }

    private func apply(_ draft: ThemeCustomization.Draft, in directory: URL) {
        do {
            try ThemeCustomization.write(draft, to: directory)
            customization = draft
            customizationProblem = nil
            loadUserThemes(in: directory)
            selection = .named(ThemeCustomization.id)
        } catch {
            customizationProblem = "\(error)"
        }
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
