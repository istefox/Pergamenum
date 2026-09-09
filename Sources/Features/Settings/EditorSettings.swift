import AppKit
import SwiftUI

/// The editor tab of the settings window (SPEC §12).
///
/// Its own type for the reason `TaskSettings` is: `SettingsView` is one tab away from the
/// size SwiftLint stops at, and a tab is a self-contained piece of it.
struct EditorSettings: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ThemeEngine.self) private var engine

    /// The languages the system has dictionaries for, in the user's preference order.
    /// Read once: `NSSpellChecker` does not gain a language while the window is open.
    private let availableLanguages = NSSpellChecker.shared.availableLanguages

    /// Every font family installed right now, read once for the same reason the
    /// languages are: it is a couple of hundred entries and it does not change while
    /// this window is open, so rebuilding it on every redraw of the picker is work
    /// nobody asked for.
    private let availableFamilies = NSFontManager.shared.availableFontFamilies

    /// The system face as the picker's own entry: `TypographyValue.Family`'s keyword
    /// for it, used as the tag so the selection is one `String` and there is no second
    /// enum to keep in step with the token file's own vocabulary.
    private static let systemFamily = TypographyValue.Family.system.rawValue

    private static let sizeRange: ClosedRange<CGFloat> = 12...24

    /// The weights and line heights the two page tokens are written with.
    ///
    /// The controls choose a family and a body size; everything else stays what the
    /// design system declares (ADR-0030 §D2). `Theme` hands back a resolved `NSFont`
    /// and never the token's own `fontWeight`/`lineHeight`, so these cannot be read off
    /// the theme underneath: writing them as constants is what keeps a customised file
    /// the same shape as the bundled one.
    private static let bodyWeight = 400
    private static let titleWeight = 700
    private static let bodyLineHeight = 1.4
    private static let titleLineHeight = 1.2

    /// The title follows the body at the ratio the bundled themes carry, 24 over 16
    /// (ADR-0030 §D9): one control writes two tokens, and a page whose title can never
    /// end up smaller than its prose.
    private static let titleRatio: CGFloat = 24.0 / 16.0

    var body: some View {
        Form {
            Section("Carattere della nota") {
                Picker("Famiglia", selection: Binding(
                    get: { selectedFamily },
                    set: { family in applyProse(family: family, size: proseSize) }
                )) {
                    Text("Sistema").tag(Self.systemFamily)
                    ForEach(availableFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .accessibilityIdentifier("settings-prose-font-family")

                Stepper(
                    value: Binding(
                        get: { proseSize },
                        set: { size in applyProse(family: selectedFamily, size: size) }
                    ),
                    in: Self.sizeRange,
                    step: 1
                ) {
                    LabeledContent("Corpo") {
                        Text("\(Int(proseSize)) pt").themedText(.body, color: .textSecondary)
                    }
                }
                .accessibilityIdentifier("settings-prose-font-size")

                Button("Ripristina carattere") { engine.clearCustomFonts() }
                    .accessibilityIdentifier("settings-prose-font-reset")
                    .disabled(!hasProseOverride)

                Text("Vale per la nota, non per l'interfaccia. Il titolo segue il corpo, "
                     + "una volta e mezza la sua misura. La scelta è un tema della cartella "
                     + "note, scritto in `.pergamenum/themes/personalizzato.json`: viaggia con "
                     + "le note e si annulla cancellando il file.")
                    .themedText(.caption, color: .textTertiary)

                if let problem = engine.customizationProblem {
                    Text(problem).themedText(.caption, color: .taskOverdue)
                }
            }

            Toggle("Nascondi i marcatori mentre scrivi", isOn: Binding(
                get: { vault.settings.hidesMarkup },
                set: { value in vault.updateSettings { $0.hidesMarkup = value } }
            ))
            .accessibilityIdentifier("settings-hides-markup")

            Text("I `#` di un titolo e i `*` di un'enfasi non vengono disegnati, e ricompaiono "
                 + "quando il cursore entra nel paragrafo. Un'immagine o un PDF incorporato viene "
                 + "disegnato al posto della sintassi che lo nomina, anche quando il cursore è "
                 + "sulla stessa riga. Il file non cambia: i caratteri ci sono sempre, anche "
                 + "quando non si vedono.")
                .themedText(.caption, color: .textTertiary)

            Toggle("Rivela solo la parola sotto il cursore", isOn: Binding(
                get: { vault.settings.revealsInlineSpans },
                set: { value in vault.updateSettings { $0.revealsInlineSpans = value } }
            ))
            .accessibilityIdentifier("settings-reveals-inline-spans")
            .disabled(!vault.settings.hidesMarkup)

            Text("Grassetto, corsivo, barrato e collegamenti mostrano la loro sintassi "
                 + "solo dove si trova il cursore, invece che in tutto il paragrafo. "
                 + "Titoli, elenchi, citazioni e tabelle non cambiano.")
                .themedText(.caption, color: .textTertiary)

            Toggle("Larghezza di lettura", isOn: Binding(
                get: { vault.settings.readableWidth },
                set: { value in vault.updateSettings { $0.readableWidth = value } }
            ))
            .accessibilityIdentifier("settings-readable-width")

            Text("La colonna di testo resta larga quanto una pagina e si centra da sola in una "
                 + "finestra ampia, invece di allargarsi da un bordo all'altro. Su una finestra "
                 + "stretta non cambia nulla: il testo occupa già tutto lo spazio che c'è.")
                .themedText(.caption, color: .textTertiary)

            Toggle("Correttore ortografico", isOn: Binding(
                get: { vault.settings.spellCheck.isEnabled },
                set: { isOn in
                    vault.updateSettings { $0.spellCheck = isOn ? .automatic : .off }
                }
            ))
            .accessibilityIdentifier("settings-spell-check")

            if vault.settings.spellCheck.isEnabled {
                Picker("Lingua", selection: Binding(
                    get: { vault.settings.spellCheck },
                    set: { value in vault.updateSettings { $0.spellCheck = value } }
                )) {
                    Text("Automatica").tag(SpellCheck.automatic)
                    ForEach(availableLanguages, id: \.self) { identifier in
                        Text(name(of: identifier)).tag(SpellCheck.language(identifier))
                    }
                }
                .accessibilityIdentifier("settings-spell-check-language")
                Text("«Automatica» riconosce la lingua di ogni passaggio, "
                     + "quindi una citazione in inglese dentro una nota italiana non viene sottolineata.")
                    .themedText(.caption, color: .textTertiary)
            }

            Text("Sottolinea, non corregge: nessuna parola viene mai riscritta da sola. "
                 + "Blocchi di codice, wikilink, tag, date e frontmatter non vengono controllati.")
                .themedText(.caption, color: .textTertiary)
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }

    /// `it_IT` read as a person would say it, falling back to the identifier itself when
    /// the system has no name for it - a dictionary with no label is still selectable.
    private func name(of identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    // MARK: The note's face (ADR-0030 §D9)

    private var proseOverride: TypographyValue? { engine.customization?.fonts[.prose] }

    private var hasProseOverride: Bool {
        ThemeCustomization.customizableFonts.contains { engine.customization?.fonts[$0] != nil }
    }

    /// What the family picker opens on.
    ///
    /// With no override it is the family the theme underneath actually draws with, so
    /// the control says what is on screen rather than resetting to «Sistema» every time
    /// the pane appears. A family that is not among the installed ones - the system UI
    /// font, whose family name is dot-prefixed and unpickable, or a face named by a file
    /// this Mac has not got - reads as «Sistema», which is the face `Theme.nsFont(_:)`
    /// falls back to in exactly those cases (ADR-0030 §D3).
    private var selectedFamily: String {
        let declared: String
        if let override = proseOverride {
            guard case .named(let family) = override.family else { return Self.systemFamily }
            declared = family
        } else {
            declared = theme.nsFont(.prose).familyName ?? Self.systemFamily
        }
        return availableFamilies.contains(declared) ? declared : Self.systemFamily
    }

    /// The body size the page is drawn at: the override when there is one, otherwise
    /// the resolved size of the theme's own `font.prose`.
    private var proseSize: CGFloat { proseOverride?.size ?? theme.nsFont(.prose).pointSize }

    /// Writes both page tokens, never one: a title left at the base theme's face beside
    /// a customised body is a page in two typefaces, which is not a state either control
    /// offers a way back from. The open editor re-styles on its own, because what
    /// `updateNSView` watches is `ThemeEngine.current` changing.
    private func applyProse(family: String, size: CGFloat) {
        let resolved = TypographyValue.Family(rawValue: family)
        engine.setCustomFont(.prose, to: TypographyValue(
            family: resolved,
            size: size,
            weight: Self.bodyWeight,
            lineHeight: Self.bodyLineHeight
        ))
        engine.setCustomFont(.proseTitle, to: TypographyValue(
            family: resolved,
            size: (size * Self.titleRatio).rounded(),
            weight: Self.titleWeight,
            lineHeight: Self.titleLineHeight
        ))
    }
}
