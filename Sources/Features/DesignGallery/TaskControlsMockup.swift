import SwiftUI

// MARK: - Controlli delle viste, rollover, nota evento (M12)

/// The three smaller screens of M12, which have one thing in common: each of them changes a
/// surface that already exists rather than adding one.
///
/// Five choices are put here for approval.
///
/// 1. **The controls are a menu, not a row of segments.** Three of them - grouping, sorting,
///    density - across a pane that is 320 points at its narrowest would leave no room for the
///    task list they act on. The menu's label says the current grouping, so the state is
///    readable without opening it.
/// 2. **They are remembered per view** (§D6). *Oggi* wants a flat list by hour and *Tutti* wants
///    grouping by note; one shared setting would make every switch between the two a
///    re-setting.
/// 3. **A rolled-over task carries the day it belongs to, in the overdue colour, and nothing
///    else changes.** No second date, no marker in the file, no row that could be mistaken for
///    an ordinary one - that mistake would be the silent move §7.3 refuses, drawn instead of
///    written.
/// 4. **Moving it is one key and it is offered on the row**, because a group of them is exactly
///    what the setting surfaces. `Cmd+0` is the existing "oggi" key from §7.3 and this adds no
///    second vocabulary.
/// 5. **The event note is created from the event, and the event says so afterwards.** A note
///    already made shows its title instead of the offer, or the second click would make a second
///    note - and the note is the sibling of that day's daily note (ADR-0013 §D2).
///
/// Everything here is literal. No EventKit, no vault, no writing.
struct TaskControlsMockup: View {
    @Environment(\.theme) private var theme

    /// The Attività pane at the width it actually has (min 320, ideal 380).
    private static let paneWidth: CGFloat = 380

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                controls
                rollover
                eventNote
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: MockupGalleryView.contentWidth, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func pane(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) { content() }
            .padding(theme.spacing(.s))
            .frame(width: Self.paneWidth, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    // MARK: I controlli

    private var controls: some View {
        scene("I controlli delle viste task: un menu solo, la cui etichetta dice già come è "
            + "raggruppata la lista. Ricordati per vista, non per app.") {
            pane {
                HStack(spacing: theme.spacing(.xs)) {
                    Text("TUTTI").themedText(.caption, color: .textTertiary)
                    Spacer()
                    menuLabel("Per nota", systemImage: "rectangle.3.group")
                    menuLabel("Compatta", systemImage: "arrow.up.and.down.text.horizontal")
                }
                group("Vibrofer")
                taskRow("Sopralluogo pressa 4", detail: "!10/09/2026", isOverdue: false)
                taskRow("Rivedere il capitolato", detail: nil, isOverdue: false)
                group("Presse idrauliche")
                taskRow("Disegno", detail: ">25/08/2026", isOverdue: false)
            }
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).themedText(.caption, color: .textTertiary)
            Text(title).themedText(.caption, color: .textSecondary)
            Image(systemName: "chevron.up.chevron.down").themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private func group(_ title: String) -> some View {
        Text(title)
            .themedText(.caption, color: .textTertiary)
            .padding(.top, theme.spacing(.xs))
    }

    // MARK: Il rollover

    private var rollover: some View {
        scene("Con il rollover acceso, la vista Oggi mostra anche i task pianificati e non "
            + "finiti dei giorni prima. Il marcatore dice **a quale giorno appartengono**: il "
            + "file non è cambiato, e senza quel marcatore la riga sembrerebbe lo spostamento "
            + "silenzioso che §7.3 rifiuta.") {
            pane {
                Text("OGGI, 20/08/2026").themedText(.caption, color: .textTertiary)
                taskRow("Chiamare Ceramiche", detail: ">20/08/2026", isOverdue: false)
                group("Rimandati")
                taskRow("Sopralluogo pressa 4", detail: "lunedì 17/08", isOverdue: true, showsMove: true)
                taskRow("Preventivo Nexion", detail: "martedì 18/08", isOverdue: true, showsMove: true)
                Text("Il rollover mostra, non sposta: «Porta a oggi» riscrive `>data` nella nota "
                    + "di origine, e nient'altro tocca i file.")
                    .themedText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func taskRow(
        _ text: String, detail: String?, isOverdue: Bool, showsMove: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: "square")
                .themedText(.caption, color: isOverdue ? .taskOverdue : .taskOpen)
            Text(text).themedText(.body).lineLimit(1)
            if let detail {
                Text(detail).themedText(.caption, color: isOverdue ? .taskOverdue : .textTertiary)
            }
            Spacer(minLength: 0)
            if showsMove {
                Text("Porta a oggi  ⌘0").themedText(.caption, color: .accentPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: La nota evento

    private var eventNote: some View {
        scene("Dalla timeline: un evento senza nota offre di crearla, uno che ce l'ha già mostra "
            + "il titolo invece dell'offerta - un secondo click farebbe una seconda nota. La "
            + "nota nasce accanto alla daily note di quel giorno.") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                pane {
                    Text("TIMELINE").themedText(.caption, color: .textTertiary)
                    eventRow(hour: "11:00", title: "Vibrofer, sopralluogo", note: nil)
                    eventRow(hour: "15:30", title: "Riunione tecnica", note: "20260820-riunione-tecnica")
                }
                .frame(width: 300)
                noteStub
            }
        }
    }

    private func eventRow(hour: String, title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(hour).themedText(.caption, color: .textTertiary)
                Text(title).themedText(.body).lineLimit(1)
                Spacer(minLength: 0)
            }
            if let note {
                Label(note, systemImage: "doc.text")
                    .themedText(.caption, color: .accentPrimary)
                    .lineLimit(1)
            } else {
                Label("Nota per questo evento", systemImage: "square.and.pencil")
                    .themedText(.caption, color: .accentPrimary)
            }
        }
        .padding(.vertical, 2)
    }

    /// What the gesture writes. The capture shape (`type-note` + `status-inbox`) is what keeps a
    /// stub out of the linter's way until somebody says what it is about (ADR-0013 §D3).
    private var noteStub: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Calendar/20260820-riunione-tecnica.md")
                .themedText(.caption, color: .textTertiary)
            ForEach([
                "---",
                "date: 2026-08-20",
                "tags:",
                "  - type-note",
                "  - status-inbox",
                "---",
                "",
                "15:30–16:30 · Riunione tecnica",
                "Con: Stefano Ferri, Anna Rossi",
                "",
                "Da [[20260820]]",
            ], id: \.self) { line in
                Text(line).themedText(.mono, color: .textSecondary)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}
