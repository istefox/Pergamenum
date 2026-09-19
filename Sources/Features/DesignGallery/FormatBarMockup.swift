import SwiftUI

// MARK: - La barra di formattazione (M8)

/// The bar that appears over a selection, before it exists. M8's last slice.
///
/// The editor has no way to make a word bold today. `/` writes markdown **at the caret** -
/// `EditorCommand.Action.insert` is the whole of what it can do - so every entry in that
/// catalogue starts a new thing and none of them wraps something already written. Selecting
/// a word and making it bold has no gesture at all, which is what this closes, together with
/// «surround selection» from the same roadmap line.
///
/// Six scenes, because what has to be judged is not one strip of icons:
///
/// - that the bar reads as belonging to the selection rather than hovering over the note;
/// - that a button already applied is visibly *on*, since pressing it again has to remove
///   the markers and not add a second pair;
/// - where it goes when the selection is at the very top of the pane and there is no room
///   above it - the same problem `CompletionPanel` solved by flipping, and it should flip
///   the same way rather than invent a second rule;
/// - that a selection crossing several lines is a case, not an accident, and that it is the
///   case which decides the anchor;
/// - that it stays away from a code fence, where `**` would be two asterisks in a program;
/// - what the two link buttons do differently, since `[[ ]]` and `[ ]( )` look alike and
///   lead to different places.
///
/// **Four decisions to approve, not just a look.**
///
/// *Which buttons, and why not more.* Bold, italic, strikethrough, inline code, then the two
/// links. **No headings and no lists**, though they are the obvious things to want: those are
/// line operations, and a bar that appeared over a selection and then acted on the whole line
/// would be doing something other than what is selected. They stay on `/`, which writes at
/// the caret and is honest about it. The line is «this bar wraps the selection, nothing else».
///
/// *Strikethrough costs a small fix elsewhere.* `MarkdownInlineParser` already renders
/// `~~testo~~` in Lettura, and `MarkdownStyler` has no `.strikethrough` span, so the editor
/// leaves it plain. Offering the button without closing that gap would produce text that
/// looks styled on one surface and unstyled on the other. Either the span is added with this
/// slice or the button goes - and the span is four lines beside the ones for `**` and `*`.
///
/// *Toggling, not stacking.* A lit button removes its own markers. Pressing bold twice must
/// give back the word, not `****parola****`, and that is the whole reason the buttons need a
/// lit state at all.
///
/// *Not inside a fence.* No bar over a selection inside ``` ``` ```: there `**` is two
/// asterisks in a program, and the app already knows where fences are - `CodeFence.regions`
/// is what keeps `#` from being a tag in there.
///
/// **Amended on 2026-08-18, after looking at the built thing.** The bar was anchored to the
/// *first* line of the selection, above it. Dragging from a heading down through a paragraph
/// put it at the top of the note, centimetres from where the mouse had stopped - and covering
/// the frontmatter. It now hangs off the **last** line, which is where the hand is, and the
/// side follows from the shape of the selection: above it when the selection is one line,
/// below it when the selection spans several, because above the last line of a long selection
/// is the middle of what is selected. The multi-line scene below draws that.
///
/// The other thing that looked wrong built and right drawn: the capsule had a one-pixel
/// border. SPEC §11.2 asks for hierarchy from weight and space «più che da linee e riquadri»,
/// and a bordered capsule over a note reads as a frame drawn *on* the text rather than as
/// something resting above it. The raised shadow carries it alone now, and this mockup does
/// the same so the two cannot drift.
struct FormatBarMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene("Su una selezione di poche parole: sei bottoni e due gruppi", .plain)
            scene("Su testo già in grassetto: il bottone è acceso, e premerlo toglie", .alreadyBold)
            scene(
                "Selezione in cima al riquadro: la barra si ribalta sotto, come il pannello di completamento",
                .flipped
            )
            scene(
                "Selezione su più righe: la barra sta sotto l'ultima riga, dov'è finito il mouse",
                .multiline
            )
            scene("Dentro un blocco di codice: nessuna barra", .insideFence)
            scene("I due link non sono lo stesso link", .links)
        }
    }

    private func scene(_ caption: String, _ state: FormatBarMock.State) -> some View {
        MockupScene(caption) {
            SelectedNoteBackdrop(state: state)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }
}

// MARK: - The bar

private struct FormatBarMock: View {
    @Environment(\.theme) private var theme

    enum State {
        case plain, alreadyBold, flipped, multiline, insideFence, links

        /// Which buttons are lit, meaning «this selection already has it, and pressing me
        /// takes it away».
        var applied: Set<String> {
            switch self {
            case .alreadyBold: ["bold"]
            default: []
            }
        }

        /// Whether the bar sits below the selection instead of above it. Not a taste: at the
        /// top of the pane there is no room above, and the panel of PG-023 already learnt
        /// that a control which clamps itself onto the line being worked on is worse than one
        /// that moves to the other side.
        /// Below the anchor rather than above it. Two reasons and they are different: at the
        /// top of the pane there is no room above, and a selection spanning several lines has
        /// its last line in the middle of itself.
        var isBelow: Bool { self == .flipped || self == .multiline }
    }

    let state: State

    /// One button, named rather than a three-member tuple: `button.2` says nothing about what
    /// it holds, which is the objection `TasksMockup.MockTask` already carries in this folder.
    struct Button: Identifiable {
        var id: String
        var symbol: String
        var help: String
    }

    /// The catalogue, as data. Two groups with a divider: what changes the letters, then what
    /// makes them lead somewhere.
    private static let buttons = [
        Button(id: "bold", symbol: "bold", help: "Grassetto"),
        Button(id: "italic", symbol: "italic", help: "Corsivo"),
        Button(id: "strikethrough", symbol: "strikethrough", help: "Barrato"),
        Button(id: "code", symbol: "chevron.left.forwardslash.chevron.right", help: "Codice"),
    ]

    private static let links = [
        Button(id: "wikilink", symbol: "doc.text", help: "Collega a una nota del vault"),
        Button(id: "link", symbol: "link", help: "Collega a un indirizzo"),
    ]

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(Self.buttons) { button in
                icon(button.symbol, isOn: state.applied.contains(button.id), help: button.help)
            }
            Divider().frame(height: 16).padding(.horizontal, 2)
            ForEach(Self.links) { button in
                icon(button.symbol, isOn: false, help: button.help)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 4)
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        // No stroke: see the amendment in this file's header.
        .themedShadow(.raised)
    }

    private func icon(_ symbol: String, isOn: Bool, help: String) -> some View {
        Image(systemName: symbol)
            .frame(width: 26, height: 22)
            .foregroundStyle(theme.color(isOn ? .onAccent : .textSecondary))
            .background(isOn ? theme.color(.accentPrimary) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            .help(help)
    }
}

// MARK: - The note under it

/// The note the bar floats over, with the selection drawn.
///
/// Every scene draws it over real text for the reason `SlashMenuMockup` and `FindBarMockup`
/// do: what has to be judged is whether the bar belongs to what is selected.
private struct SelectedNoteBackdrop: View {
    @Environment(\.theme) private var theme

    let state: FormatBarMock.State

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            if state == .flipped { bar.padding(.leading, 40) }
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    if barSitsAbove(line: index) { bar.padding(.leading, 40) }
                    line.view(theme: theme)
                    if barSitsBelow(line: index) { bar.padding(.leading, 40) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.m))
        .frame(height: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }

    private var bar: some View { FormatBarMock(state: state) }

    /// The bar hangs off the **last** selected line: that is where the mouse stopped. Above it
    /// for a one-line selection, below it when the selection spans several.
    private func barSitsAbove(line index: Int) -> Bool {
        guard !state.isBelow, state != .insideFence else { return false }
        return index == lastSelectedLine
    }

    private func barSitsBelow(line index: Int) -> Bool {
        guard state == .multiline else { return false }
        return index == lastSelectedLine
    }

    private var lastSelectedLine: Int {
        switch state {
        case .flipped: 0
        case .multiline: 2
        default: 1
        }
    }

    private struct Line {
        var pieces: [(text: String, kind: Kind)]

        enum Kind { case plain, selected, code, syntax }

        @MainActor
        func view(theme: Theme) -> some View {
            HStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Text(piece.text)
                        .themedText(piece.kind == .code ? .mono : .body, color: colour(piece.kind))
                        .padding(.horizontal, piece.kind == .selected ? 1 : 0)
                        .background(piece.kind == .selected ? theme.color(.canvasSelection) : .clear)
                }
                Spacer(minLength: 0)
            }
        }

        private func colour(_ kind: Kind) -> ColorToken {
            switch kind {
            case .plain: .textSecondary
            case .selected: .textPrimary
            case .code: .codeString
            case .syntax: .textTertiary
            }
        }
    }

    private var lines: [Line] {
        switch state {
        case .alreadyBold:
            [
                Line(pieces: [("Il rapporto fra le due frequenze decide tutto.", .plain)]),
                Line(pieces: [
                    ("Sotto radice di due l'isolatore ", .plain),
                    ("**", .syntax), ("amplifica", .selected), ("**", .syntax),
                    (" invece di attenuare.", .plain),
                ]),
                Line(pieces: [("Misure in reparto il 4 agosto.", .plain)]),
            ]
        case .multiline:
            [
                Line(pieces: [("Il rapporto fra le due frequenze decide tutto.", .plain)]),
                Line(pieces: [("Sotto radice di due l'isolatore amplifica", .selected)]),
                Line(pieces: [("invece di attenuare, e il solaio lo sente.", .selected)]),
                Line(pieces: [("Misure in reparto il 4 agosto.", .plain)]),
            ]
        case .insideFence:
            [
                Line(pieces: [("```sh", .syntax)]),
                Line(pieces: [("grep --recursive ", .code), ("trasmissibilità", .selected), (" .", .code)]),
                Line(pieces: [("```", .syntax)]),
                Line(pieces: [("Nessuna barra: qui ", .plain), ("**", .syntax), (" sono due asterischi.", .plain)]),
            ]
        case .links:
            [
                Line(pieces: [("Il rapporto fra le due frequenze decide tutto.", .plain)]),
                Line(pieces: [
                    ("Vedi la ", .plain), ("curva di trasmissibilità", .selected),
                    (" per i dati.", .plain),
                ]),
                Line(pieces: [
                    ("Il primo bottone scrive ", .plain), ("[[ ]]", .syntax),
                    (" e resta nel vault; il secondo ", .plain), ("[ ]( )", .syntax),
                    (" e apre fuori.", .plain),
                ]),
            ]
        default:
            [
                Line(pieces: [("Il rapporto fra le due frequenze decide tutto.", .plain)]),
                Line(pieces: [
                    ("Sotto radice di due l'isolatore ", .plain), ("amplifica", .selected),
                    (" invece di attenuare.", .plain),
                ]),
                Line(pieces: [("Misure in reparto il 4 agosto.", .plain)]),
            ]
        }
    }
}
