import SwiftUI

/// Every token the app defines, rendered from the active theme.
///
/// This is the acceptance surface for M0: switching the theme repaints this view
/// with no relaunch, and anything that fails to load shows up in the problems
/// section instead of silently rendering a wrong colour.
struct DesignGalleryView: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var engine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                header
                if !engine.problems.isEmpty { problems }
                colorSection("Sfondi", [
                    (.backgroundPrimary, "background.primary"),
                    (.backgroundSecondary, "background.secondary"),
                    (.backgroundTertiary, "background.tertiary"),
                    (.surfaceCard, "surface.card"),
                    (.surfaceRaised, "surface.raised"),
                    (.surfaceSunken, "surface.sunken"),
                ])
                colorSection("Testo e bordi", [
                    (.textPrimary, "text.primary"),
                    (.textSecondary, "text.secondary"),
                    (.textTertiary, "text.tertiary"),
                    (.textInverted, "text.inverted"),
                    (.borderSubtle, "border.subtle"),
                    (.borderStrong, "border.strong"),
                ])
                colorSection("Accento", [
                    (.accentPrimary, "accent.primary"),
                    (.accentMuted, "accent.muted"),
                    (.onAccent, "accent.onAccent"),
                ])
                colorSection("Workspace", [
                    (.canvasBackground, "canvas.background"),
                    (.canvasGrid, "canvas.grid"),
                    (.canvasSelection, "canvas.selection"),
                ])
                colorSection("Task", [
                    (.taskOpen, "task.open"),
                    (.taskScheduled, "task.scheduled"),
                    (.taskOverdue, "task.overdue"),
                    (.taskDone, "task.done"),
                    (.taskCancelled, "task.cancelled"),
                ])
                colorSection("Note adesive", [
                    (.stickyYellow, "sticky.yellow"),
                    (.stickyGreen, "sticky.green"),
                    (.stickyBlue, "sticky.blue"),
                    (.stickyPink, "sticky.pink"),
                    (.stickyGrey, "sticky.grey"),
                ])
                typography
                metrics
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(theme.name)
                .themedText(.title)
            Text("\(ColorToken.allCases.count) colori · \(FontToken.allCases.count) stili di testo · \(SpacingToken.allCases.count) spaziature · \(RadiusToken.allCases.count) raggi · \(ShadowToken.allCases.count) ombre")
                .themedText(.caption, color: .textSecondary)
        }
    }

    private var problems: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Label("Problemi nei file token", systemImage: "exclamationmark.triangle")
                    .themedText(.heading, color: .taskOverdue)
                ForEach(engine.problems, id: \.self) { problem in
                    Text(problem).themedText(.caption, color: .textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorSection(_ title: String, _ entries: [(ColorToken, String)]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title).themedText(.heading)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: theme.spacing(.s))],
                alignment: .leading,
                spacing: theme.spacing(.s)
            ) {
                ForEach(entries, id: \.1) { token, label in
                    swatch(token, label)
                }
            }
        }
    }

    private func swatch(_ token: ColorToken, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(token))
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                        .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
                )
            Text(label).themedText(.caption, color: .textSecondary)
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Tipografia").themedText(.heading)
            ThemedCard {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    specimen(.title, "font.title", "Trasmissibilità e rapporto di frequenza")
                    specimen(.heading, "font.heading", "Note correlate")
                    specimen(.body, "font.body", "Il vault resta leggibile su disco: se Pergamenum sparisse, i dati restano usabili.")
                    specimen(.caption, "font.caption", "modificata 5 minuti fa · 3 backlink")
                    specimen(.mono, "font.mono", "- [ ] Rivedere la curva >2026-08-15")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func specimen(_ token: FontToken, _ label: String, _ sample: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).themedText(.caption, color: .textTertiary)
            Text(sample).themedText(token)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Spaziature, raggi, ombre").themedText(.heading)
            ThemedCard {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    HStack(alignment: .bottom, spacing: theme.spacing(.m)) {
                        ForEach(SpacingToken.allCases, id: \.self) { token in
                            VStack(spacing: theme.spacing(.xs)) {
                                Rectangle()
                                    .fill(theme.color(.accentPrimary))
                                    .frame(width: theme.spacing(token), height: theme.spacing(token))
                                Text(token.rawValue.replacingOccurrences(of: "spacing.", with: ""))
                                    .themedText(.caption, color: .textTertiary)
                            }
                        }
                    }
                    HStack(spacing: theme.spacing(.m)) {
                        ForEach(RadiusToken.allCases, id: \.self) { token in
                            VStack(spacing: theme.spacing(.xs)) {
                                RoundedRectangle(cornerRadius: theme.radius(token), style: .continuous)
                                    .fill(theme.color(.accentMuted))
                                    .frame(width: 56, height: 40)
                                Text(token.rawValue.replacingOccurrences(of: "radius.", with: ""))
                                    .themedText(.caption, color: .textTertiary)
                            }
                        }
                        ForEach(ShadowToken.allCases, id: \.self) { token in
                            VStack(spacing: theme.spacing(.xs)) {
                                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                                    .fill(theme.color(.surfaceCard))
                                    .frame(width: 56, height: 40)
                                    .themedShadow(token)
                                Text(token.rawValue.replacingOccurrences(of: "shadow.", with: ""))
                                    .themedText(.caption, color: .textTertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
