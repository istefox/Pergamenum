import SwiftUI

// MARK: - I template (M9)

/// The other half of ADR-0011: a note under `Templates/` used as the starting text of a
/// new one, chosen while the note is being named (D5-D7).
///
/// The architecture is settled and is not what this mockup is for. `Templates/` is a
/// folder and not a tag, because SPEC §4.4's namespace is harness-owned and closed; the
/// choice happens at creation time, in `NewNoteComposer`; and v1 substitutes `{{date}}`
/// and `{{title}}` and nothing else. What is open is smaller and entirely visual:
///
/// 1. **What the composer shows when `Templates/` does not exist** - which is every
///    vault today, including Stefano's. A control that hides itself is invisible to
///    someone who has never made a template, and a control that is permanently there
///    and permanently empty is noise for someone who never will. Three answers below.
/// 2. **Whether the chosen template's body is shown before «Crea»** - the composer owns
///    the whole editor column and most of it is empty space, so the room exists. The
///    question is whether filling it helps or just makes the pane busy.
///
/// Everything is literal. Nothing reads `Templates/`, which no vault has yet.
struct TemplateMockup: View {
    @Environment(\.theme) private var theme

    /// Three cells across, inside `MockupGalleryView.contentWidth`:
    /// 3 × (208 + 16 of padding) + 2 × 16 of spacing = 704, under the 720 available.
    private static let tripleWidth: CGFloat = 208
    /// Two across, with the room the first row does not need: 2 × (320 + 16) + 16 = 688.
    private static let doubleWidth: CGFloat = 320

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                scene(
                    "Il composer, template scelto, con l'anteprima del corpo",
                    ComposerScene(showsPreview: true)
                )
                scene(
                    "Lo stesso, senza anteprima: resta lo spazio vuoto di oggi",
                    ComposerScene(showsPreview: false)
                )
                emptyStates
                placeholders
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: MockupGalleryView.contentWidth, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
            content
        }
    }

    /// The decision this mockup exists for. Every vault is in this state right now.
    private var emptyStates: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Quando la cartella Templates/ non esiste")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("A. Il controllo non c'è", Self.tripleWidth, AbsentControl())
                labelled("B. C'è, disattivato", Self.tripleWidth, DisabledControl())
                labelled("C. C'è, e spiega", Self.tripleWidth, TeachingControl())
            }
        }
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("I due segnaposto, prima e dopo")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("Templates/Riunione.md", Self.doubleWidth, TextBlock(lines: TemplateText.before))
                labelled("La nota creata", Self.doubleWidth, TextBlock(lines: TemplateText.after))
            }
        }
    }

    private func labelled(_ title: String, _ width: CGFloat, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textSecondary)
            content
                .frame(width: width, alignment: .leading)
                .padding(theme.spacing(.s))
                .background(theme.color(.backgroundSecondary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }
}

// MARK: - Il composer

private struct ComposerScene: View {
    @Environment(\.theme) private var theme
    let showsPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            HStack {
                Text("Nuova nota").themedText(.caption, color: .textTertiary)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            Text("Riunione con Rossi").themedText(.title)
            controls
            if showsPreview {
                preview
            }
            Spacer()
            footer
        }
        .padding(theme.spacing(.l))
        .frame(height: 380)
        .background(theme.color(.backgroundPrimary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .stroke(theme.color(.borderSubtle))
        )
    }

    /// The template menu joins the row the folder and topic already share, rather than
    /// taking a line of its own: all three answer "what kind of note is this", and the
    /// composer's own restraint is the thing worth not spending.
    private var controls: some View {
        HStack(spacing: theme.spacing(.s)) {
            pill("folder", "01 Progetti")
            pill("doc.text", "Riunione")
            Text("topic-… (facoltativo)")
                .themedText(.body, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                        .stroke(theme.color(.borderSubtle))
                )
        }
    }

    private func pill(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: symbol)
            Text(label)
            Image(systemName: "chevron.down").themedText(.caption, color: .textTertiary)
        }
        .themedText(.body, color: .textPrimary)
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    /// The body the note will start with, greyed and unreadable-as-editable on purpose:
    /// it answers "what am I about to get" in the space the composer already wastes.
    private var preview: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("DAL TEMPLATE").themedText(.caption, color: .textTertiary)
            TextBlock(lines: TemplateText.after)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Il titolo è il nome del file: niente / \\ : * ? \" < > | # ^ [ ].")
                .themedText(.caption, color: .textTertiary)
            HStack {
                Text("Annulla").themedText(.body, color: .textSecondary)
                Text("Crea")
                    .themedText(.body, color: .textInverted)
                    .padding(.horizontal, theme.spacing(.m))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(theme.color(.accentPrimary))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            }
        }
    }
}

// MARK: - I tre modi di non avere template

/// A: the control is simply not rendered. Nothing to explain, nothing to discover
/// either - a person who has never made a template has no way to learn one is possible.
private struct AbsentControl: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("01 Progetti  ·  topic-…").themedText(.body, color: .textSecondary)
            Text("La riga è quella di oggi, invariata.")
                .themedText(.caption, color: .textTertiary)
        }
    }
}

/// B: always there, greyed when there is nothing to choose. Discoverable, and a small
/// permanent tax on everyone who never uses templates.
private struct DisabledControl: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "doc.text")
                Text("Nessun template")
            }
            .themedText(.body, color: .textTertiary)
            Text("Visibile sempre, cliccabile mai.")
                .themedText(.caption, color: .textTertiary)
        }
    }
}

/// C: always there, and the menu's one item says how to fill it. Discoverable and
/// self-teaching, at the cost of nothing that B does not already spend.
private struct TeachingControl: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "doc.text")
                Text("Template")
                Image(systemName: "chevron.down").themedText(.caption, color: .textTertiary)
            }
            .themedText(.body, color: .textSecondary)
            Text("Una nota in Templates/ diventa un modello.")
                .themedText(.caption, color: .accentPrimary)
                .padding(theme.spacing(.xs))
                .background(theme.color(.backgroundTertiary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
    }
}

// MARK: - Blocchi di testo

private struct TextBlock: View {
    @Environment(\.theme) private var theme
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .themedText(line.hasPrefix("#") ? .heading : .body,
                                color: line.contains("{{") ? .accentPrimary : .textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum TemplateText {
    /// The template as it sits on disk. Its own frontmatter is discarded rather than
    /// copied: the new note gets a conformant four-key block from `createNote` exactly
    /// as it does today (ADR-0011 D6), so only what follows is the template.
    static let before = [
        "# {{title}}",
        "",
        "Data: {{date}}",
        "",
        "## Presenti",
        "",
        "## Decisioni",
        "",
        "## Da fare",
    ]

    static let after = [
        "# Riunione con Rossi",
        "",
        "Data: 2026-08-18",
        "",
        "## Presenti",
        "",
        "## Decisioni",
        "",
        "## Da fare",
    ]
}
