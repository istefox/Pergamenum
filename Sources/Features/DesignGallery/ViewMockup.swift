import SwiftUI

// MARK: - Le viste (M11)

/// The screen for ADR-0009: a view is a saved query living in a fenced block, and this is what
/// the block looks like once something runs it.
///
/// Four choices are put here for approval, plus one per renderer in `ViewMockupRenderers`.
///
/// 1. **A view is drawn in Lettura and stays source in Modifica.** The Obsidian source/preview
///    split, and the reason is not only habit: a board with drop targets inside an `NSTextView`
///    would need ADR-0010's line-fragment machinery built a second time, for content that can be
///    dragged. In Modifica the fence is a code block like any other, which is also exactly what
///    Obsidian shows a reader who cannot run it (§D1).
/// 2. **Every rendered view carries one header line**: what it is, how many rows it found, and
///    a refresh. §D7 has a view evaluate on open, on an explicit refresh and on a debounced
///    watcher change - "explicit refresh" needs somewhere to be, and the row count is what tells
///    a person the difference between a view that found nothing and a view that has not run.
/// 3. **Nothing matched and did not parse look nothing alike.** §D1 refuses an empty result for
///    a broken block, and the reverse matters as much: a view that legitimately found nothing
///    says so in its own words, and never with the red an error gets.
/// 4. **The error names the line and shows the block.** Not a badge, not a console: the block is
///    four lines away in the same file, and the reader is the person who wrote it.
///
/// Everything here is literal. No query is parsed, no index is read, no vault is opened.
struct ViewMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            modes
            states
            renderers
        }
    }

    // MARK: Le due modalità

    private var modes: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            MockupScene("In Modifica il blocco resta quello che è: un fence, con la sua sintassi in chiaro.") {
                sourceBlock
            }
            MockupScene("In Lettura, al suo posto, la vista. Stessa nota, stesso file, un click di distanza.") {
                framed {
                    viewHeader(renderer: "tabella", count: 3)
                    ViewTableMockup()
                }
            }
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            fenceLine("```pergamenum-view", color: .textTertiary)
            fenceLine("from: path(\"Clienti\")")
            fenceLine("where: tag(\"client-*\") and not tag(\"status-chiuso\")")
            fenceLine("sort: modified desc")
            fenceLine("render: table")
            fenceLine("columns: [title, tags, modified, tasks.open, deadline.next]")
            fenceLine("```", color: .textTertiary)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private func fenceLine(_ text: String, color: ColorToken = .textSecondary) -> some View {
        Text(text).themedText(.mono, color: color)
    }

    /// The one line above every rendered view: what it is, what it found, and how to run it
    /// again. Without the count, a view that found nothing is indistinguishable from a view
    /// that has not been evaluated.
    private func viewHeader(renderer: String, count: Int) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(renderer.uppercased()).themedText(.caption, color: .textTertiary)
            Text("·").themedText(.caption, color: .textTertiary)
            Text(count == 1 ? "1 nota" : "\(count) note").themedText(.caption, color: .textTertiary)
            Spacer()
            Image(systemName: "arrow.clockwise").themedText(.caption, color: .textTertiary)
        }
        .padding(.bottom, theme.spacing(.xs))
    }

    private func framed(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(theme.spacing(.m))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
            )
    }

    // MARK: Vuoto e rotto

    private var states: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            MockupScene("Nessuna nota risponde: lo dice con parole sue, e resta una vista.") {
                framed {
                    viewHeader(renderer: "tabella", count: 0)
                    Text("Nessuna nota in «Clienti» ha un tag client- senza essere chiusa.")
                        .themedText(.body, color: .textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            MockupScene("Il blocco non si legge: la riga, il motivo, e il blocco così com'è scritto. "
                + "Mai una lista vuota, che sarebbe indistinguibile da un vault che ha perso le note.") {
                framed { errorBody }
            }
        }
    }

    private var errorBody: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "exclamationmark.triangle").themedText(.caption, color: .taskOverdue)
                Text("riga 4: una board è fatta di colonne: aggiungi «group», per esempio "
                    + "group: tag(\"status-*\")")
                    .themedText(.caption, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 1) {
                fenceLine("from: path(\"Clienti\")")
                fenceLine("where: tag(\"client-*\")")
                fenceLine("sort: modified desc")
                fenceLine("render: board", color: .taskOverdue)
            }
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
    }

    // MARK: I cinque renderer

    private var renderers: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            MockupScene("Board. L'unico renderer che scrive: trascinare una card fra due colonne "
                + "riscrive il tag status- nella nota. «Senza stato» sta per primo perché è "
                + "l'unico modo di togliere uno stato con un gesto, e «Presse idrauliche» "
                + "compare due volte perché il file dichiara davvero due stati (§D5).") {
                framed {
                    viewHeader(renderer: "board", count: 3)
                    ViewBoardMockup()
                }
            }
            MockupScene("Gallery. Le miniature vengono da embedTargets. Una nota che non allega niente "
                + "resta comunque una card: toglierla farebbe dire alla gallery meno di quanto "
                + "la query ha trovato.") {
                framed {
                    viewHeader(renderer: "gallery", count: 4)
                    ViewGalleryMockup()
                }
            }
            MockupScene("Calendario. Il giorno è il primo campo di tipo data fra le columns "
                + "(date, modified, deadline.next, scheduled.next), e date quando non ce n'è "
                + "nessuno: una chiave in più solo per questo non serve.") {
                framed {
                    viewHeader(renderer: "calendario", count: 4)
                    ViewCalendarMockup()
                }
            }
            MockupScene("Lista. Per una vista incorporata in una nota che parla d'altro: una riga "
                + "ciascuna, le colonne dopo il titolo piegate in una didascalia sola.") {
                framed {
                    viewHeader(renderer: "lista", count: 3)
                    ViewListMockup()
                }
            }
        }
    }
}
