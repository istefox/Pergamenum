import AppKit
import SwiftUI

/// The editor tab of the settings window (SPEC §12).
///
/// Its own type for the reason `TaskSettings` is: `SettingsView` is one tab away from the
/// size SwiftLint stops at, and a tab is a self-contained piece of it.
struct EditorSettings: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// The languages the system has dictionaries for, in the user's preference order.
    /// Read once: `NSSpellChecker` does not gain a language while the window is open.
    private let availableLanguages = NSSpellChecker.shared.availableLanguages

    var body: some View {
        Form {
            Toggle("Nascondi i marcatori mentre scrivi", isOn: Binding(
                get: { vault.settings.hidesMarkup },
                set: { value in vault.updateSettings { $0.hidesMarkup = value } }
            ))
            .accessibilityIdentifier("settings-hides-markup")

            Text("I `#` di un titolo e i `*` di un'enfasi non vengono disegnati, e ricompaiono "
                 + "quando il cursore entra nel paragrafo. Il file non cambia: i caratteri ci sono "
                 + "sempre, anche quando non si vedono.")
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
}
