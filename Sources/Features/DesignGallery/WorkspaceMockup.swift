import SwiftUI

// Static compositions of the screens M1 to M5 will build for real. They render from
// the same tokens as production code, so approving one here is approving its look,
// not a picture of it. None of them touch a vault, an index or EventKit.
// One file per screen since PG-148 (ADR-0051); they shared nothing but this note.

// MARK: - Workspace (M2, M3)

struct WorkspaceMockup: View {
    @Environment(\.theme) private var theme

    private static let tools: [(String, String, String)] = [
        ("cursorarrow", "Seleziona", "V"),
        ("note.text", "Nota", "N"),
        ("textformat", "Testo", "T"),
        ("folder", "Cartella", "F"),
        ("photo", "Immagine", "I"),
        ("doc.text", "Documento", "D"),
        ("link", "Link", "L"),
        ("checklist", "To Do", "K"),
        ("rectangle.on.rectangle.slash", "Moduli (v2)", ""),
        ("pencil.tip", "Disegno", "P"),
        ("arrow.up.right", "Freccia", "A"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            HStack(spacing: 0) {
                toolbar
                Divider()
                board
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: theme.spacing(.s)) {
            Circle().fill(theme.color(.accentPrimary)).frame(width: 8, height: 8)
            Text("Labs").themedText(.body)
            ForEach(["Workspace", "01 Progetti", "vibrofer-emea"], id: \.self) { segment in
                Text("›").themedText(.body, color: .textTertiary)
                Text(segment).themedText(.body, color: segment == "vibrofer-emea" ? .textPrimary : .textSecondary)
            }
            Spacer()
            Label("Salvato", systemImage: "checkmark.circle")
                .themedText(.caption, color: .textSecondary)
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textSecondary))
            Image(systemName: "gearshape").foregroundStyle(theme.color(.textSecondary))
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .background(theme.color(.backgroundPrimary))
    }

    private var toolbar: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(Array(Self.tools.enumerated()), id: \.offset) { index, tool in
                let selected = index == 0
                let excluded = tool.2.isEmpty
                Image(systemName: tool.0)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(theme.color(excluded ? .textTertiary : (selected ? .onAccent : .textSecondary)))
                    .background(selected ? theme.color(.accentPrimary) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .opacity(excluded ? 0.4 : 1)
                    .help(tool.2.isEmpty ? tool.1 : "\(tool.1) (\(tool.2))")
            }
            Spacer()
        }
        .padding(theme.spacing(.xs))
        .frame(width: 44)
        .background(theme.color(.backgroundPrimary))
    }

    private var board: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.color(.canvasBackground)
            grid
            cards
            zoomControls.padding(theme.spacing(.m))
        }
    }

    private var grid: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var path = Path()
            for x in stride(from: 0, through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(theme.color(.canvasGrid)), lineWidth: 1)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                folderCard("02 Rilievi", count: 14)
                documentCard("Trasmissibilità e rapporto di frequenza", words: 812)
                stickyCard("Chiedere a Marco i dati di targa del ventilatore", color: .stickyYellow)
            }
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                pdfCard("Datasheet supporto AV-45", pages: 6)
                emailCard()
                linkCard()
            }
        }
        .padding(theme.spacing(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func folderCard(_ name: String, count: Int) -> some View {
        ThemedCard(padding: .s) {
            HStack(spacing: theme.spacing(.s)) {
                Image(systemName: "folder.fill").foregroundStyle(theme.color(.accentPrimary))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).themedText(.body)
                    Text("\(count) elementi").themedText(.caption, color: .textTertiary)
                }
            }
        }
        .frame(width: 190)
    }

    private func documentCard(_ title: String, words: Int) -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Label(title, systemImage: "doc.text").themedText(.body).lineLimit(2)
                Text("\(words) parole").themedText(.caption, color: .textTertiary)
            }
        }
        .frame(width: 210)
    }

    private func stickyCard(_ text: String, color: ColorToken) -> some View {
        Text(text)
            .themedText(.body)
            .padding(theme.spacing(.s))
            .frame(width: 170, alignment: .topLeading)
            .background(theme.color(color))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
            .themedShadow(.card)
    }

    private func pdfCard(_ title: String, pages: Int) -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
                    .frame(width: 174, height: 110)
                    .overlay(Image(systemName: "doc.richtext").foregroundStyle(theme.color(.textTertiary)))
                HStack {
                    Text(title).themedText(.caption).lineLimit(1)
                    Spacer()
                    Text("\(pages)p").themedText(.caption, color: .textTertiary)
                }
                .frame(width: 174)
            }
        }
    }

    private func emailCard() -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Rossi Impianti", systemImage: "envelope").themedText(.body)
                Text("Richiesta offerta supporti").themedText(.caption, color: .textSecondary)
                Text("4 ago 2026").themedText(.caption, color: .textTertiary)
            }
        }
        .frame(width: 190)
    }

    private func linkCard() -> some View {
        ThemedCard(padding: .s) {
            HStack(spacing: theme.spacing(.s)) {
                Image(systemName: "link").foregroundStyle(theme.color(.accentPrimary))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Scheda in DEVONthink").themedText(.body).lineLimit(1)
                    Text("x-devonthink-item://").themedText(.caption, color: .textTertiary)
                }
            }
        }
        .frame(width: 210)
    }

    private var zoomControls: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "minus")
            Text("100%").themedText(.caption)
            Image(systemName: "plus")
            Divider().frame(height: 12)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}
