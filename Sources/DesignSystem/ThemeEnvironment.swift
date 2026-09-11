import SwiftUI

extension EnvironmentValues {
    /// The active theme. Defaults to the emergency palette so that a preview or a
    /// detached view still renders; the app always injects a real one at the root.
    @Entry var theme: Theme = .emergency
}

extension View {
    /// Injects the theme and keeps the engine's notion of the system appearance in
    /// sync with the environment's, which is what makes "follow system" switch
    /// instantly instead of at the next launch.
    func themed(by engine: ThemeEngine) -> some View {
        modifier(ThemeInjection(engine: engine))
    }
}

private struct ThemeInjection: ViewModifier {
    @Bindable var engine: ThemeEngine
    @Environment(\.colorScheme) private var colorScheme

    /// Forcing a scheme makes the system-drawn chrome (sidebar material, title bar,
    /// controls) match the tokens; without it, choosing "Chiaro" under a dark system
    /// left a dark sidebar beside a light document.
    ///
    /// Deliberately nil while following the system: `preferredColorScheme` also
    /// rewrites `\.colorScheme` further down, and reading that value back into
    /// `systemAppearance` would pin the app to whatever it last rendered instead of
    /// tracking the real system setting.
    private var forcedScheme: ColorScheme? {
        guard engine.selection != .followSystem else { return nil }
        return engine.current.appearance == .dark ? .dark : .light
    }

    func body(content: Content) -> some View {
        content
            .environment(\.theme, engine.current)
            .background(engine.current.color(.backgroundPrimary))
            .preferredColorScheme(forcedScheme)
            .onAppear { syncSystemAppearance(colorScheme) }
            .onChange(of: colorScheme) { _, new in syncSystemAppearance(new) }
    }

    private func syncSystemAppearance(_ scheme: ColorScheme) {
        guard engine.selection == .followSystem else { return }
        engine.systemAppearance = scheme == .dark ? .dark : .light
    }
}

// MARK: - Token-driven building blocks

/// A card surface. Exists so the card radius, border and shadow are decided once
/// here rather than re-derived in every feature that needs a card.
struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: SpacingToken = .m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(theme.spacing(padding))
            .background(theme.color(.surfaceCard))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
            )
            .themedShadow(.card)
    }
}

extension View {
    /// Applies a shadow token. SwiftUI takes a radius where CSS-style tokens carry a
    /// blur, and the two differ by a factor of two.
    func themedShadow(_ token: ShadowToken) -> some View {
        modifier(ThemedShadow(token: token))
    }

    /// Body text with the line spacing the token asks for, which `\.font` alone does
    /// not carry.
    func themedText(_ token: FontToken, color: ColorToken = .textPrimary) -> some View {
        modifier(ThemedText(token: token, color: color))
    }
}

private struct ThemedShadow: ViewModifier {
    @Environment(\.theme) private var theme
    let token: ShadowToken

    func body(content: Content) -> some View {
        let shadow = theme.shadow(token)
        let color = Color(
            .sRGB,
            red: shadow.color.red,
            green: shadow.color.green,
            blue: shadow.color.blue,
            opacity: shadow.color.alpha
        )
        return content.shadow(color: color, radius: shadow.blur / 2, x: shadow.offsetX, y: shadow.offsetY)
    }
}

private struct ThemedText: ViewModifier {
    @Environment(\.theme) private var theme
    let token: FontToken
    let color: ColorToken

    func body(content: Content) -> some View {
        content
            .font(theme.font(token))
            .foregroundStyle(theme.color(color))
            .lineSpacing(theme.lineSpacing(token))
    }
}
