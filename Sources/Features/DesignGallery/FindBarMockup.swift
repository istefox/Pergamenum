import SwiftUI

// MARK: - Trova e sostituisci (M8)

/// The find bar with the app's own appearance, before it exists.
///
/// Find and replace already work: `usesFindBar` gives AppKit's own bar, which brings
/// incremental search, replace-all, a count and a scope for free. What it cannot do is
/// search by regular expression - checked against MacOSX26.5.sdk rather than assumed:
/// `NSTextFinderMatchingType` has exactly four values, `Contains`, `StartsWith`,
/// `FullWord` and `EndsWith`. There is no fifth, and no option elsewhere in the class.
///
/// So the regex of SPEC §10 costs a find of our own, and a find of our own is a view -
/// which is why this exists before any of it is written (SPEC §11.1). Adopting a bar of
/// our own also means **re-earning what AppKit already gave**: the count, the scope, the
/// case option and the wrapping are not new features here, they are things that must not
/// be lost on the way. Every one of them is drawn in a scene below for that reason.
///
/// Seven scenes, because what has to be judged is not one screen:
///
/// - that the bar reads as belonging to the note rather than sitting on top of it;
/// - that a match and *the* match are told apart at a glance, which is the whole of
///   navigating results and the one thing a search does that nothing else does;
/// - that the second row appears without the first moving, since Cmd+F and Cmd+Alt+F are
///   the same bar in two sizes;
/// - what a capture group looks like on both sides, because `$1` in the replace field is
///   the only reason a regex find is worth the code;
/// - what a half-typed pattern says, which is the state a regex find gets wrong most
///   often: `(\d{4` is not an error the person made, it is a pattern they are still
///   writing, and a red box on every keystroke would make the feature unusable;
/// - that "nothing found" and "not a valid pattern" are distinguishable, since they occupy
///   the same corner and mean opposite things;
/// - that "only in the selection" says what it is scoped to, not merely that it is on.
///
/// **Two decisions to approve, not just a look.**
///
/// *The colour of a match.* No token names one today. This draws every match in
/// `accentMuted` and the current one in `accentPrimary` with `onAccent` text, so nothing
/// is added to the theme files. The alternative was `stickyYellow`, which reads like a
/// highlighter and is the obvious choice - and is a sticky note's colour borrowed for an
/// unrelated role, which is how a token set stops meaning anything. Say if you want the
/// yellow anyway; it is a one-line change here and a real one in two JSON files.
///
/// *Where the bar sits.* Under the editor header and above the text, full width, which is
/// where AppKit put it and where the hands already are. It pushes the text down rather
/// than floating over it: a bar that overlays hides the first line of the note, and the
/// first line is where a search that just wrapped is most likely to have landed.
struct FindBarMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene("Cmd+F, appena aperta: nessuna ricerca, nessun conteggio", .opened)
            scene("Mentre si scrive: la corrente si distingue dalle altre", .matching)
            scene("Cmd+Alt+F: la sostituzione è una seconda riga, la prima non si muove", .replacing)
            scene("Regex acceso, con i gruppi di cattura da una parte e dall'altra", .regex)
            scene("Un pattern ancora a metà: si dice, non si accusa", .incompletePattern)
            scene("Nessuna corrispondenza, che è un'altra cosa da un pattern non valido", .noMatches)
            scene("Solo nella selezione: l'ambito dice a che cosa", .inSelection)
        }
    }

    private func scene(_ caption: String, _ state: FindBarMock.State) -> some View {
        MockupScene(caption) {
            VStack(spacing: 0) {
                FindBarMock(state: state)
                Divider()
                SearchedNoteBackdrop(state: state)
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }
}

// MARK: - The bar

private struct FindBarMock: View {
    @Environment(\.theme) private var theme

    enum State {
        case opened, matching, replacing, regex, incompletePattern, noMatches, inSelection

        /// Whether the replace row is drawn. Cmd+Alt+F is the same bar with one row more,
        /// never a different bar - so the find row keeps its position and the note moves.
        var showsReplace: Bool {
            switch self {
            case .replacing, .regex: true
            default: false
            }
        }

        var isRegexOn: Bool {
            switch self {
            case .regex, .incompletePattern: true
            default: false
            }
        }

        var query: String {
            switch self {
            case .opened: ""
            case .regex: #"\b(\d{4})-(\d{2})-(\d{2})\b"#
            case .incompletePattern: #"\b(\d{4"#
            case .noMatches: "flangia"
            default: "trasmissibilità"
            }
        }

        /// What sits where the count goes. The same corner carries a number, a reason for
        /// having none, and a refusal to search - three states one line has to keep apart.
        var tally: String {
            switch self {
            case .opened: ""
            case .matching, .inSelection: "3 di 12"
            case .replacing: "3 di 12"
            case .regex: "1 di 4"
            case .incompletePattern: "pattern incompleto"
            case .noMatches: "nessuna corrispondenza"
            }
        }

        var tallyIsPlain: Bool {
            switch self {
            case .incompletePattern, .noMatches: false
            default: true
            }
        }
    }

    let state: State

    var body: some View {
        VStack(spacing: theme.spacing(.xs)) {
            findRow
            if state.showsReplace { replaceRow }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }

    private var findRow: some View {
        HStack(spacing: theme.spacing(.s)) {
            field(
                placeholder: "Trova",
                text: state.query,
                isMono: state.isRegexOn,
                trailing: AnyView(tally)
            )
            option(".*", isOn: state.isRegexOn, help: "Espressione regolare")
            option("Aa", isOn: false, help: "Distingui maiuscole")
            scopeControl
            stepper
            Text("Fine").themedText(.body, color: .accentPrimary)
        }
    }

    private var replaceRow: some View {
        HStack(spacing: theme.spacing(.s)) {
            field(
                placeholder: "Sostituisci",
                text: state == .regex ? "$1/$2/$3" : "trasmissione",
                isMono: state.isRegexOn,
                trailing: nil
            )
            Text("Sostituisci").themedText(.body, color: .accentPrimary)
            Text("Tutti").themedText(.body, color: .accentPrimary)
            // Balances the find row's stepper and «Fine» so the two fields keep the same
            // width: a replace field narrower than the find field above it reads as a
            // different control rather than the other half of one.
            Color.clear.frame(width: 96, height: 1)
        }
    }

    /// The count lives inside the field, at its trailing edge, and not beside it. Outside,
    /// it moves every time the number gains a digit and drags the buttons with it.
    private var tally: some View {
        Text(state.tally)
            .themedText(.caption, color: state.tallyIsPlain ? .textTertiary : .taskOverdue)
    }

    private func field(
        placeholder: String, text: String, isMono: Bool, trailing: AnyView?
    ) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            if text.isEmpty {
                Text(placeholder).themedText(.body, color: .textTertiary)
            } else {
                Text(text).themedText(isMono ? .mono : .body)
                Rectangle().fill(theme.color(.accentPrimary)).frame(width: 1, height: 15)
            }
            Spacer(minLength: theme.spacing(.s))
            if let trailing { trailing }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    /// A toggle labelled with what it does rather than with a word. `.*` is what a regex
    /// looks like and `Aa` is what case looks like; «Espressione regolare» spelled out
    /// would be the widest thing in the bar, and the bar has to leave room for the query.
    private func option(_ label: String, isOn: Bool, help: String) -> some View {
        Text(label)
            .themedText(.mono, color: isOn ? .onAccent : .textSecondary)
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 3)
            .background(isOn ? theme.color(.accentPrimary) : theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            .help(help)
    }

    /// Says what it is scoped to and not merely that it is on: «Selezione» on its own is a
    /// button whose state has to be inferred from its shading.
    private var scopeControl: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: state == .inSelection ? "text.viewfinder" : "doc.text")
            Text(state == .inSelection ? "Selezione" : "Nota")
                .themedText(.caption)
        }
        .foregroundStyle(theme.color(state == .inSelection ? .onAccent : .textSecondary))
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 3)
        .background(state == .inSelection ? theme.color(.accentPrimary) : theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .help("Cerca in tutta la nota o solo nella selezione")
    }

    private var stepper: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "chevron.up")
            Image(systemName: "chevron.down")
        }
        .foregroundStyle(theme.color(state.tally.isEmpty ? .textTertiary : .textSecondary))
    }
}

// MARK: - The note behind it

/// The note the bar searches, with the matches drawn.
///
/// Every scene draws the bar over text rather than on a plain background, for the reason
/// `SlashMenuMockup` does: what has to be judged is whether it belongs to the note.
private struct SearchedNoteBackdrop: View {
    @Environment(\.theme) private var theme

    let state: FindBarMock.State

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Curva di trasmissibilità").themedText(.heading)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                line.view(theme: theme, isSelected: isSelectionScene && (1...2).contains(index))
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.m))
        .frame(height: 190)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }

    private var isSelectionScene: Bool { state == .inSelection }

    /// One line of the note, as the pieces a match splits it into.
    private struct Line {
        var pieces: [(text: String, mark: Mark)]

        enum Mark { case none, other, current }

        @MainActor
        func view(theme: Theme, isSelected: Bool) -> some View {
            HStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Text(piece.text)
                        .themedText(.body, color: piece.mark == .current ? .onAccent : .textSecondary)
                        .padding(.horizontal, piece.mark == .none ? 0 : 2)
                        .background(background(piece.mark, theme: theme))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .background(isSelected ? theme.color(.canvasSelection) : .clear)
        }

        @MainActor
        private func background(_ mark: Mark, theme: Theme) -> Color {
            switch mark {
            case .none: .clear
            case .other: theme.color(.accentMuted)
            case .current: theme.color(.accentPrimary)
            }
        }
    }

    private var lines: [Line] {
        switch state {
        case .opened:
            plain
        case .noMatches:
            plain
        case .incompletePattern:
            // Nothing is highlighted while the pattern is half-typed. A find that kept the
            // previous pattern's matches on screen would be showing an answer to a question
            // nobody is asking any more.
            plain
        case .regex:
            [
                Line(pieces: [("Misure del ", .none), ("2026-08-04", .current), (", pressa 4.", .none)]),
                Line(pieces: [("Confronto con il ", .none), ("2025-11-12", .other), (".", .none)]),
                Line(pieces: [("Prossima verifica ", .none), ("2026-09-01", .other), (".", .none)]),
                Line(pieces: [("Nessuna data in questa riga.", .none)]),
            ]
        default:
            [
                Line(pieces: [("La ", .none), ("trasmissibilità", .other), (" sotto radice di due.", .none)]),
                Line(pieces: [("Curva di ", .none), ("trasmissibilità", .current), (" a 4 Hz.", .none)]),
                Line(pieces: [("La ", .none), ("trasmissibilità", .other), (" cresce con lo smorzamento.", .none)]),
                Line(pieces: [("Dati di targa del ventilatore.", .none)]),
            ]
        }
    }

    private var plain: [Line] {
        [
            Line(pieces: [("La trasmissibilità sotto radice di due.", .none)]),
            Line(pieces: [("Curva di trasmissibilità a 4 Hz.", .none)]),
            Line(pieces: [("La trasmissibilità cresce con lo smorzamento.", .none)]),
            Line(pieces: [("Dati di targa del ventilatore.", .none)]),
        ]
    }
}
