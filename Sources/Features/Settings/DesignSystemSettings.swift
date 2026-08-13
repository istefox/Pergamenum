import AppKit
import SwiftUI

/// The design system, where the rest of the preferences are (SPEC §11, §12).
///
/// It used to be a pane in the sidebar, beside Vault and Workspace, which put a
/// developer's reference view in the same list as the app's actual work. It is a
/// setting: it says what the app looks like and it is where the look is changed.
///
/// Every colour here is editable, and editing one writes a real token file into the
/// vault's `.pergamenum/themes/`. Nothing is kept in memory only, so a customisation
/// survives a relaunch, travels with the vault, and can be read or edited by hand.
struct DesignSystemSettings: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var engine
    @State private var isShowingAllTokens = false

    /// The groups of the gallery, kept in the same order so the two views describe
    /// the palette the same way.
    private static let groups: [(title: String, tokens: [ColorToken])] = [
        ("Sfondi", [.backgroundPrimary, .backgroundSecondary, .backgroundTertiary,
                    .surfaceCard, .surfaceRaised, .surfaceSunken]),
        ("Testo e bordi", [.textPrimary, .textSecondary, .textTertiary, .textInverted,
                           .borderSubtle, .borderStrong]),
        ("Accento", [.accentPrimary, .accentMuted, .onAccent]),
        ("Workspace", [.canvasBackground, .canvasGrid, .canvasSelection]),
        ("Task", [.taskOpen, .taskScheduled, .taskOverdue, .taskDone, .taskCancelled]),
        ("Note adesive", [.stickyYellow, .stickyGreen, .stickyBlue, .stickyPink, .stickyGrey]),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("Tema attivo") {
                    Text(theme.name).themedText(.body, color: .textSecondary)
                }
                if engine.userThemesDirectory == nil {
                    Label(
                        "Apri una cartella note per poter salvare i colori: un tema vive lì, non nell'app.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .themedText(.caption, color: .taskOverdue)
                } else if let customization = engine.customization {
                    LabeledContent("Personalizzazione") {
                        Text("\(customization.colors.count) colori su \(appearanceName(customization.appearance))")
                            .themedText(.caption, color: .textSecondary)
                    }
                    HStack {
                        Button("Riparti dal tema attuale") {
                            engine.rebaseCustomization(on: theme.appearance)
                        }
                        Button("Ripristina", role: .destructive) { engine.resetCustomization() }
                    }
                } else {
                    Text("Scegli un colore qui sotto e viene salvato come tema della cartella note.")
                        .themedText(.caption, color: .textTertiary)
                }
                if let problem = engine.customizationProblem {
                    Text(problem).themedText(.caption, color: .taskOverdue)
                }
            }

            ForEach(Self.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.tokens, id: \.self) { token in
                        row(token)
                    }
                }
            }

            Section {
                Button("Mostra tutti i token…") { isShowingAllTokens = true }
            } footer: {
                Text("Tipografia, spaziature, raggi e ombre restano definiti dal file del tema.")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingAllTokens) {
            VStack(spacing: 0) {
                HStack {
                    Text("Token del tema").themedText(.heading)
                    Spacer()
                    Button("Chiudi") { isShowingAllTokens = false }
                }
                .padding(theme.spacing(.m))
                Divider()
                DesignGalleryView()
            }
            .frame(width: 720, height: 620)
            .background(theme.color(.backgroundSecondary))
        }
    }

    private func row(_ token: ColorToken) -> some View {
        let isCustom = engine.customization?.colors[token] != nil
        return LabeledContent {
            HStack(spacing: theme.spacing(.s)) {
                if isCustom {
                    Button {
                        engine.clearCustomColor(token)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Torna al valore del tema di base")
                }
                Text(engine.customizableColor(token).hexString)
                    .themedText(.mono, color: .textTertiary)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { engine.customizableColor(token).asColor },
                        set: { engine.setCustomColor(token, to: RGBA($0)) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(token.path).themedText(.body)
                if isCustom {
                    Text("personalizzato").themedText(.caption, color: .accentPrimary)
                }
            }
        }
    }

    private func appearanceName(_ appearance: ThemeAppearance) -> String {
        appearance == .dark ? "tema scuro" : "tema chiaro"
    }
}

extension RGBA {
    var asColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Reads a colour back out of the picker.
    ///
    /// Converted through sRGB on purpose: the well hands back whatever space the
    /// system picker was in, and a value in Display P3 written as hex would come back
    /// a different colour the next time the file is read.
    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }
}
